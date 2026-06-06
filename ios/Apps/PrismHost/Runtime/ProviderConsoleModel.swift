import Foundation
import PrismAI
import PrismModels
import PrismRuntime
import PrismWatchModels

@MainActor
final class ProviderConsoleModel: ObservableObject {
    @Published private(set) var oracle = OracleEngine()
    @Published private(set) var vision = VisionEngine()
    @Published private(set) var babel = BabelEngine()
    @Published var oraclePrompt = ""
    @Published var babelText = ""
    @Published var babelSourceLanguage = "ja"
    @Published var babelTargetLanguage = "en"
    var oracleDidChange: (@MainActor (OracleEngine) -> Void)?
    var babelDidChange: (@MainActor (BabelEngine) -> Void)?
    var visionDidChange: (@MainActor (VisionEngine) -> Void)?

    private let aiClient: any AIClient
    private let speechClient: any SpeechClient
    private let visionProcessor: any VisionProcessor
    private let translationClient: any TranslationClient
    private let services: ServiceConsoleModel?

    init(
        aiClient: any AIClient = EchoAIClient(providerName: "mock"),
        speechClient: any SpeechClient = MockSpeechClient(),
        visionProcessor: any VisionProcessor = MockVisionProcessor(),
        translationClient: any TranslationClient = MockTranslationClient(),
        services: ServiceConsoleModel? = nil
    ) {
        self.aiClient = aiClient
        self.speechClient = speechClient
        self.visionProcessor = visionProcessor
        self.translationClient = translationClient
        self.services = services
    }

    var oracleRows: [String] {
        switch oracle.state {
        case .ready:
            [
                "Ready",
                oracle.density.displayTitle,
                oracle.historyCount == 0 ? "NO HISTORY" : "\(oracle.historyCount) HISTORY"
            ]
        case .listening:
            ["Listening", oracle.currentPrompt ?? "MIC OPEN"]
        case let .asking(_, prompt):
            ["Thinking", prompt]
        case let .answer(answer):
            [
                answer.text,
                answer.saved ? "KEPT" : "OPEN",
                "\(oracle.currentPageTitle) \(oracle.density.displayTitle)"
            ]
        case .cancelled:
            ["Cancelled", oracle.historyCount == 0 ? "READY" : "\(oracle.historyCount) HISTORY"]
        case let .error(code):
            [code]
        }
    }

    var visionRows: [String] {
        switch vision.state {
        case .ready:
            ["\(vision.mode.displayName)", "Ready"]
        case .waitingImage:
            ["Capture pending"]
        case .analyzing:
            ["Analyzing"]
        case let .result(result):
            [result.summary]
        case let .saved(result):
            ["SAVED", result.summary]
        case let .error(code):
            [code]
        }
    }

    var babelRows: [String] {
        let header = "\(babel.sourceLanguage.uppercased())->\(babel.targetLanguage.uppercased())"
        let state = babel.frozen ? "FROZEN" : babel.currentRequestID == nil ? "READY" : "PENDING"
        let saved = babel.savedTranscripts.isEmpty ? "NO SAVES" : "\(babel.savedTranscripts.count) SAVED"
        return [header, state, saved] + babel.lines.suffix(3).map(\.text)
    }

    private func notifyBabelDidChange() {
        babelDidChange?(babel)
    }

    private func notifyVisionDidChange() {
        visionDidChange?(vision)
    }

    private func notifyOracleDidChange() {
        oracleDidChange?(oracle)
    }

    func askOracle() {
        Task {
            await askOracleNow()
        }
    }

    func askOracleNow() async {
        let effect = oracle.submitTypedPrompt(oraclePrompt)
        notifyOracleDidChange()
        guard let effect else {
            oraclePrompt = ""
            return
        }
        if case let .callOracle(prompt, requestID) = effect {
            await completeOraclePrompt(prompt, requestID: requestID, source: "typed")
        }
        oraclePrompt = ""
    }

    func startOracleVoiceMock() {
        Task {
            await startOracleVoiceNow()
        }
    }

    func startOracleVoiceNow() async {
        let effect = oracle.startVoiceAsk()
        notifyOracleDidChange()
        guard case let .captureAudio(_, requestID) = effect else { return }
        do {
            let transcript = try await currentSpeechClient().transcribe(
                TranscriptionInput(requestID: requestID, pcm16MonoLittleEndian: Data([0, 0, 1, 0]), sampleRate: 8000)
            )
            if let call = oracle.receiveTranscript(transcript.text, requestID: requestID),
               case let .callOracle(prompt, providerID) = call {
                notifyOracleDidChange()
                await completeOraclePrompt(prompt, requestID: providerID, source: "audio")
            } else {
                notifyOracleDidChange()
            }
        } catch {
            oracle.fail("OFFLINE")
            notifyOracleDidChange()
        }
    }

    func cancelOracle() {
        oracle.cancel()
        notifyOracleDidChange()
    }

    func captureVisionMock() {
        Task {
            await captureVisionNow()
        }
    }

    func captureVisionNow() async {
        let effect = vision.capture()
        notifyVisionDidChange()
        if case let .captureImage(_, requestID) = effect {
            _ = vision.receiveImage(Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9]), requestID: requestID)
            notifyVisionDidChange()
            do {
                let result = try await currentVisionProcessor().recognizeText(
                    in: VisionInput(requestID: requestID, jpegData: Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9]))
                )
                _ = vision.receiveAnalysis(
                    summary: vision.mode == .readText ? "TEXT FOUND" : result.text,
                    ocrText: result.text,
                    requestID: result.requestID
                )
                notifyVisionDidChange()
            } catch {
                vision.fail("VISION OFFLINE")
                notifyVisionDidChange()
            }
        }
    }

    func toggleVisionMode() {
        vision.toggleMode()
        notifyVisionDidChange()
    }

    @discardableResult
    func saveVisionNote() -> Bool {
        let saved = vision.saveCurrentResult() != nil
        if saved {
            notifyVisionDidChange()
        }
        return saved
    }

    @discardableResult
    func cancelVisionCapture() -> Bool {
        let cancelled = vision.cancel()
        if cancelled {
            notifyVisionDidChange()
        }
        return cancelled
    }

    func translateBabelText() {
        Task {
            await translateBabelTextNow()
        }
    }

    func translateBabelTextNow() async {
        guard let effect = babel.translateHostText(babelText) else {
            notifyBabelDidChange()
            return
        }
        notifyBabelDidChange()
        if case let .translateText(text, _, _, requestID) = effect {
            await completeBabelTranslation(text, requestID: requestID)
        }
        babelText = ""
    }

    func captureBabelAudioMock() {
        Task {
            await captureBabelAudioNow()
        }
    }

    func captureBabelAudioNow() async {
        guard let effect = babel.captureAudio() else {
            notifyBabelDidChange()
            return
        }
        notifyBabelDidChange()
        if case let .captureAudio(_, requestID) = effect,
           let transcript = try? await currentSpeechClient().transcribe(
               TranscriptionInput(
                   requestID: requestID,
                   pcm16MonoLittleEndian: Data([0, 0, 1, 0]),
                   sampleRate: 8000,
                   language: babel.sourceLanguage
               )
           ),
           let translate = babel.receiveTranscript(transcript.text, requestID: requestID),
           case let .translateText(_, _, _, translationID) = translate {
            await completeBabelTranslation(transcript.text, requestID: translationID)
        }
    }

    func toggleBabelFreeze() {
        babel.toggleFreeze()
        notifyBabelDidChange()
    }

    func swapBabelLanguages() {
        babel.swapLanguages()
        babelSourceLanguage = babel.sourceLanguage
        babelTargetLanguage = babel.targetLanguage
        notifyBabelDidChange()
    }

    func applyBabelLanguages() {
        babel.setLanguages(source: babelSourceLanguage, target: babelTargetLanguage)
        babelSourceLanguage = babel.sourceLanguage
        babelTargetLanguage = babel.targetLanguage
        notifyBabelDidChange()
    }

    func applyBabelPreset(_ preset: WatchBabelPreset) {
        babel.setLanguages(source: preset.sourceLanguage, target: preset.targetLanguage)
        babelSourceLanguage = babel.sourceLanguage
        babelTargetLanguage = babel.targetLanguage
        notifyBabelDidChange()
    }

    @discardableResult
    func saveBabelTranscript() -> Bool {
        let saved = babel.saveTranscript()
        notifyBabelDidChange()
        return saved
    }

    @discardableResult
    func clearBabelTranscript() -> Bool {
        let cleared = babel.clearTranscript()
        notifyBabelDidChange()
        return cleared
    }

    @discardableResult
    func repeatBabelLast() -> Bool {
        guard let effect = babel.repeatLast() else {
            notifyBabelDidChange()
            return false
        }
        notifyBabelDidChange()
        if case let .translateText(text, _, _, requestID) = effect {
            Task {
                await completeBabelTranslation(text, requestID: requestID)
            }
        }
        return true
    }

    func saveAndClearBabel() {
        babel.saveAndClear()
        notifyBabelDidChange()
    }

    private func completeOraclePrompt(_ prompt: String, requestID: PrismRequestID, source: String) async {
        do {
            let response = try await currentAIClient().respond(
                to: AIRequest(
                    id: requestID,
                    appID: .oracle,
                    prompt: prompt,
                    requiresCloudApproval: services?.requireCloudApproval ?? false
                )
            )
            _ = oracle.receiveAnswer(response.text, requestID: response.requestID, source: source)
        } catch {
            oracle.fail("OFFLINE")
        }
        notifyOracleDidChange()
    }

    private func completeBabelTranslation(_ text: String, requestID: PrismRequestID) async {
        do {
            let result = try await currentTranslationClient().translate(
                TranslationRequest(requestID: requestID, text: text, sourceLanguage: babel.sourceLanguage, targetLanguage: babel.targetLanguage)
            )
            _ = babel.receiveTranslation(result.text, requestID: result.requestID)
        } catch {
            babel.fail("TRANSLATE OFFLINE")
        }
        notifyBabelDidChange()
    }

    private func currentAIClient() -> any AIClient {
        guard let services else {
            return aiClient
        }
        switch services.providerMode {
        case .offline:
            return OfflineAIClient()
        case .openAI:
            let key = (try? services.readProviderKey()) ?? ""
            return OpenAIResponsesClient(
                configuration: services.openAIConfiguration(),
                apiKeyProvider: { key },
                userApprovedCloudProcessing: { true }
            )
        case .appleOnDevice:
            return aiClient
        }
    }

    private func currentSpeechClient() -> any SpeechClient {
        guard let services else {
            return speechClient
        }
        switch services.transcriptionMode {
        case .offline:
            return OfflineSpeechClient()
        case .openAI:
            let key = (try? services.readProviderKey()) ?? ""
            let configuration = services.openAIConfiguration()
            if configuration.usesRealtimeTranscription {
                return OpenAIRealtimeWhisperTranscriptionClient(
                    configuration: configuration,
                    apiKeyProvider: { key },
                    userApprovedCloudProcessing: { true }
                )
            } else {
                return OpenAIAudioTranscriptionClient(
                    configuration: configuration,
                    apiKeyProvider: { key },
                    userApprovedCloudProcessing: { true }
                )
            }
        case .appleOnDevice:
            return speechClient
        }
    }

    private func currentVisionProcessor() -> any VisionProcessor {
        guard let services else {
            return visionProcessor
        }
        switch services.visionMode {
        case .offline:
            return OfflineVisionProcessor()
        case .openAI:
            let key = (try? services.readProviderKey()) ?? ""
            return OpenAIVisionProcessor(
                configuration: services.openAIConfiguration(),
                apiKeyProvider: { key },
                userApprovedCloudProcessing: { true }
            )
        case .appleOnDevice:
            return visionProcessor
        }
    }

    private func currentTranslationClient() -> any TranslationClient {
        guard let services else {
            return translationClient
        }
        switch services.translationMode {
        case .offline:
            return OfflineTranslationClient()
        case .openAI:
            let key = (try? services.readProviderKey()) ?? ""
            return OpenAITranslationClient(
                configuration: services.openAIConfiguration(),
                apiKeyProvider: { key },
                userApprovedCloudProcessing: { true }
            )
        case .appleOnDevice:
            return translationClient
        }
    }
}

private struct MockSpeechClient: SpeechClient {
    func transcribe(_ audio: TranscriptionInput) async throws -> TranscriptionResult {
        TranscriptionResult(requestID: audio.requestID, text: "bonjour")
    }
}

private struct MockVisionProcessor: VisionProcessor {
    func recognizeText(in image: VisionInput) async throws -> VisionTextResult {
        VisionTextResult(requestID: image.requestID, text: "ESP32 board", confidence: 0.82)
    }
}

private struct MockTranslationClient: TranslationClient {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let output = request.text.localizedCaseInsensitiveContains("bonjour") ? "hello" : "translation mock"
        return TranslationResult(requestID: request.requestID, text: output)
    }
}

private struct OfflineSpeechClient: SpeechClient {
    func transcribe(_ audio: TranscriptionInput) async throws -> TranscriptionResult {
        throw ProviderError.offline
    }
}

private struct OfflineVisionProcessor: VisionProcessor {
    func recognizeText(in image: VisionInput) async throws -> VisionTextResult {
        throw ProviderError.offline
    }
}

private struct OfflineTranslationClient: TranslationClient {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        throw ProviderError.offline
    }
}
