import XCTest
import PrismDraw
import PrismModels
@testable import PrismRuntime

final class ProviderAppsTests: XCTestCase {
    func testTextPolicyRemovesMarkdownAndBoundsLength() {
        let policy = MonocleTextPolicy(maxCharacters: 32)

        let output = policy.conciseHUDText("**74.57 Nm**\n`value` #tag extra words that should not fit")

        XCTAssertFalse(output.contains("**"))
        XCTAssertFalse(output.contains("`"))
        XCTAssertLessThanOrEqual(output.count, 32)
    }

    func testMediaCommandsUseDocumentedPayloadShape() {
        let command = MediaRequestCommand(appID: .oracle, kind: .captureAudio, timeoutSeconds: 4, sampleRate: 8000, bitDepth: 8)

        XCTAssertEqual(command.effect, .captureAudio(appID: .oracle, requestID: command.requestID))
        XCTAssertTrue(command.controlJSON.contains(#""cmd":"CAPTURE_AUDIO""#))
        XCTAssertTrue(command.controlJSON.contains(#""app":"oracle""#))
        XCTAssertTrue(command.controlJSON.contains(#""sample_rate":8000"#))
    }

    func testOracleVoiceTypedAnswerCancelCopyAndStaleProtection() throws {
        var oracle = OracleEngine(outputPolicy: MonocleTextPolicy(maxCharacters: 64))

        let effect = oracle.startVoiceAsk()
        guard case let .captureAudio(appID, audioID) = effect else {
            return XCTFail("Expected audio capture")
        }
        XCTAssertEqual(appID, .oracle)
        XCTAssertEqual(oracle.receiveTranscript("  ", requestID: audioID), nil)
        XCTAssertEqual(oracle.state, .error("???"))

        let call = try XCTUnwrap(oracle.submitTypedPrompt("Melting point tungsten"))
        guard case let .callOracle(prompt, requestID) = call else {
            return XCTFail("Expected Oracle call")
        }
        XCTAssertTrue(prompt.contains("Answer completely"))
        oracle.cancel()
        XCTAssertFalse(oracle.receiveAnswer("3422 C", requestID: requestID))

        let fresh = try XCTUnwrap(oracle.submitTypedPrompt("55 ft lb to Nm"))
        guard case let .callOracle(_, freshID) = fresh else {
            return XCTFail("Expected Oracle call")
        }
        XCTAssertTrue(oracle.receiveAnswer("**74.57 Nm.**", requestID: freshID))
        XCTAssertEqual(oracle.history.first?.text, "**74.57 Nm.**")
        XCTAssertEqual(oracle.copyAnswer(), .copyToClipboard(text: "**74.57 Nm.**"))
        XCTAssertLessThanOrEqual(try PrismDrawPacker.pack(oracle.render()).count, PrismDrawConstants.maxPayloadBytes)
    }

    func testOracleKeepDensityFollowUpAndClearUpdateHostState() throws {
        var oracle = OracleEngine(outputPolicy: MonocleTextPolicy(maxCharacters: 96))

        guard case let .callOracle(prompt, requestID)? = oracle.submitTypedPrompt("What is tungsten?") else {
            return XCTFail("Expected Oracle call")
        }

        XCTAssertTrue(prompt.contains("Answer completely"))
        XCTAssertTrue(oracle.receiveAnswer("3422 C (6192 F).", requestID: requestID))
        XCTAssertFalse(oracle.isCurrentAnswerKept)

        XCTAssertTrue(oracle.toggleKeep())
        XCTAssertTrue(oracle.isCurrentAnswerKept)

        oracle.moreDetail()
        XCTAssertEqual(oracle.density, .moreDetail)
        XCTAssertEqual(oracle.currentPageCount, 1)

        guard case let .callOracle(followUpPrompt, followUpID)? = oracle.followUp() else {
            return XCTFail("Expected follow-up call")
        }
        XCTAssertTrue(followUpPrompt.contains("follow-up"))
        XCTAssertTrue(followUpID.isCurrent(comparedTo: oracle.currentRequestID))

        oracle.clear()
        XCTAssertEqual(oracle.state, .cancelled)
        XCTAssertNil(oracle.currentRequestID)
    }

    func testVisionCaptureAnalysisSaveCopyAndStaleProtection() throws {
        var vision = VisionEngine(mode: .readText)
        let effect = vision.capture()
        guard case let .captureImage(appID, imageID) = effect else {
            return XCTFail("Expected image capture")
        }
        XCTAssertEqual(appID, .vision)

        XCTAssertFalse(vision.receiveImage(Data([0x00, 0x01, 0x02]), requestID: imageID))
        XCTAssertEqual(vision.state, .error("BAD JPEG"))

        let freshEffect = vision.capture()
        guard case let .captureImage(_, freshID) = freshEffect else {
            return XCTFail("Expected image capture")
        }
        XCTAssertFalse(vision.receiveAnalysis(summary: "late", requestID: imageID))
        XCTAssertTrue(vision.receiveImage(Data([0xFF, 0xD8, 0x00, 0xFF, 0xD9]), requestID: freshID))
        XCTAssertTrue(vision.receiveAnalysis(summary: "Menu", ocrText: "Grilled eel", requestID: freshID))
        XCTAssertEqual(vision.copyOCRText(), .copyToClipboard(text: "Grilled eel"))
        XCTAssertEqual(vision.saveCurrentResult(), .saveVisionNote(text: "Menu", requestID: freshID))
        XCTAssertEqual(vision.notes.count, 1)
        XCTAssertLessThanOrEqual(try PrismDrawPacker.pack(vision.render()).count, PrismDrawConstants.maxPayloadBytes)
    }

    func testBabelBackpressureFreezeSwapSaveAndStaleProtection() throws {
        var babel = BabelEngine(sourceLanguage: "fr", targetLanguage: "en")
        let effect = try XCTUnwrap(babel.captureAudio())
        guard case let .captureAudio(appID, audioID) = effect else {
            return XCTFail("Expected audio capture")
        }
        XCTAssertEqual(appID, .babel)
        XCTAssertNil(babel.captureAudio())
        XCTAssertTrue(babel.lines.contains { $0.text == "BUSY DROP" })

        let translate = try XCTUnwrap(babel.receiveTranscript("bonjour", requestID: audioID))
        guard case let .translateText(text, from, to, translationID) = translate else {
            return XCTFail("Expected translation")
        }
        XCTAssertEqual(text, "bonjour")
        XCTAssertEqual(from, "fr")
        XCTAssertEqual(to, "en")
        XCTAssertFalse(babel.receiveTranslation("late", requestID: PrismRequestID()))
        XCTAssertTrue(babel.receiveTranslation("hello", requestID: translationID))

        babel.toggleFreeze()
        babel.swapLanguages()
        babel.saveAndClear()

        XCTAssertTrue(babel.frozen)
        XCTAssertEqual(babel.sourceLanguage, "en")
        XCTAssertEqual(babel.targetLanguage, "fr")
        XCTAssertEqual(babel.savedTranscripts.count, 1)
        XCTAssertLessThanOrEqual(try PrismDrawPacker.pack(babel.render()).count, PrismDrawConstants.maxPayloadBytes)
    }

    func testBabelSaveClearAndRepeatLastUseTranscriptHistory() throws {
        var babel = BabelEngine(sourceLanguage: "fr", targetLanguage: "en")
        let effect = try XCTUnwrap(babel.translateHostText("bonjour"))
        guard case let .translateText(_, _, _, requestID) = effect else {
            return XCTFail("Expected translation request")
        }
        XCTAssertTrue(babel.receiveTranslation("hello", requestID: requestID))

        XCTAssertTrue(babel.saveTranscript())
        XCTAssertTrue(babel.clearTranscript())

        let repeatEffect = try XCTUnwrap(babel.repeatLast())
        guard case let .translateText(text, from, to, repeatID) = repeatEffect else {
            return XCTFail("Expected repeat translation request")
        }

        XCTAssertEqual(text, "bonjour")
        XCTAssertEqual(from, "fr")
        XCTAssertEqual(to, "en")
        XCTAssertEqual(babel.lastInputText, "bonjour")
        XCTAssertTrue(repeatID.isCurrent(comparedTo: babel.currentRequestID))
    }
}

extension ProviderAppsTests {
    func testCanonicalLongAnswersOCRTranslationsAndPagingKeepTheirTails() throws {
        let complete = String(repeating: "Full details must remain available. ", count: 300) + "FINAL CONCLUSION"
        var oracle = OracleEngine()
        guard case let .callOracle(_,id)? = oracle.submitTypedPrompt("Explain in full") else { return XCTFail("Expected call") }
        XCTAssertTrue(oracle.receiveAnswer(complete,requestID:id))
        XCTAssertEqual(oracle.history.first?.text,complete)
        XCTAssertEqual(oracle.copyAnswer(),.copyToClipboard(text:complete))
        XCTAssertGreaterThan(oracle.currentPageCount,1)
        let pages = MonocleTextPolicy().pages(for:complete)
        XCTAssertTrue(pages.joined(separator:" ").contains("FINAL CONCLUSION"))
        let longWord = String(repeating:"x",count:300)
        XCTAssertEqual(MonocleTextPolicy().pages(for:longWord).joined().replacingOccurrences(of:"\n",with:""),longWord)
        var vision = VisionEngine(mode:.readText)
        guard case let .captureImage(_,imageID) = vision.capture() else { return XCTFail("Expected capture") }
        XCTAssertTrue(vision.receiveImage(Data([255,216,0,255,217]),requestID:imageID))
        XCTAssertTrue(vision.receiveAnalysis(summary:complete,ocrText:complete,requestID:imageID))
        XCTAssertEqual(vision.copyOCRText(),.copyToClipboard(text:complete))
        var babel = BabelEngine()
        for _ in 0..<30 {
            guard case let .translateText(_,_,_,rid)? = babel.translateHostText(complete) else { return XCTFail("Expected translation") }
            XCTAssertTrue(babel.receiveTranslation(complete,requestID:rid))
        }
        XCTAssertTrue(babel.saveTranscript())
        XCTAssertEqual(babel.savedTranscripts[0].components(separatedBy:"FINAL CONCLUSION").count - 1,60)
        let script = TeleprompterEngine.importScript(title:"Complete script",body:longWord + "\n\nFinal paragraph")
        XCTAssertEqual(script.sourceText,longWord + "\n\nFinal paragraph")
        XCTAssertTrue(script.chunks.joined().hasPrefix(longWord))
    }
}
