import XCTest
import PrismModels
import PrismRuntime
import PrismWatchModels
@testable import PrismHost

@MainActor
final class WatchBridgeTests: XCTestCase {
    func testPublishingSnapshotWritesApplicationContextAndRetainsSixApps() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)

        let snapshot = try bridge.publishSnapshot()

        XCTAssertEqual(snapshot.widgets.map(\.appID), PrismAppID.allCases)
        XCTAssertEqual(snapshot.activeSurface, .orbit)
        XCTAssertEqual(snapshot.chronos?.mode, .timer)
        XCTAssertEqual(snapshot.widgets.first(where: { $0.appID == .chronos })?.subtitle, "TIMER 05:00")
        XCTAssertEqual(snapshot.widgets.first(where: { $0.appID == .teleprompter })?.subtitle, "1/4 MANUAL 140 WPM")
        XCTAssertEqual(snapshot.widgets.first(where: { $0.appID == .signal })?.subtitle, "Battery")
        XCTAssertEqual(snapshot.widgets.first(where: { $0.appID == .babel })?.subtitle, "JA -> EN • READY")
        XCTAssertEqual(snapshot.widgets.first(where: { $0.appID == .vision })?.subtitle, "IDENTIFY READY")
        XCTAssertEqual(snapshot.oracle?.statusTitle, "READY")
        XCTAssertEqual(snapshot.widgets.first(where: { $0.appID == .oracle })?.subtitle, "ASK READY")
        XCTAssertEqual(snapshot.signal?.currentCard?.title, "Battery")
        XCTAssertEqual(snapshot.signal?.titleLine, "Battery")
        XCTAssertEqual(snapshot.teleprompter?.title, "Demo Script")
        XCTAssertEqual(snapshot.teleprompter?.primaryActionTitle, "PLAY")
        XCTAssertEqual(snapshot.vision?.statusTitle, "READY")
        XCTAssertEqual(session.applicationContexts.count, 2)
        XCTAssertEqual(try WatchBridgeWireCodec.decodeSnapshot(session.applicationContexts.last!), snapshot)
    }

    func testChronosPresetAndRunCommandsUpdateHostSnapshot() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)

        let focus = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .focusApp,
            appID: .chronos
        )
        _ = try bridge.receiveReachableCommand(focus)

        let preset = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .chronos,
            appID: .chronos,
            value: .chronos(.applyPreset(420))
        )
        let presetAck = try bridge.receiveReachableCommand(preset)
        XCTAssertEqual(presetAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.activeApp?.appID, .chronos)
        XCTAssertEqual(bridge.latestSnapshot.chronos?.totalSeconds, 420)
        XCTAssertEqual(bridge.latestSnapshot.activeApp?.subtitle, "TIMER 07:00")

        let start = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .chronos,
            appID: .chronos,
            value: .chronos(.startPauseResume)
        )
        let startAck = try bridge.receiveReachableCommand(start)
        XCTAssertEqual(startAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.chronos?.runState, .running)

        let pause = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .chronos,
            appID: .chronos,
            value: .chronos(.startPauseResume)
        )
        let pauseAck = try bridge.receiveReachableCommand(pause)
        XCTAssertEqual(pauseAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.chronos?.runState, .paused)
    }

    func testReachableFocusCommandAppliesAndRepliesApplied() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)
        let command = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .focusApp,
            appID: .oracle
        )
        var reply: [String: Any]?

        let acknowledgement = try bridge.receiveReachableCommand(command) { reply = $0 }

        XCTAssertEqual(acknowledgement.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.activeSurface, .app(.oracle))
        XCTAssertEqual(bridge.latestSnapshot.activeApp?.appID, .oracle)
        XCTAssertEqual(session.applicationContexts.count, 2)
        XCTAssertEqual(try WatchBridgeWireCodec.decodeAcknowledgement(try XCTUnwrap(reply)), acknowledgement)
        XCTAssertEqual(try WatchBridgeWireCodec.decodeSnapshot(session.applicationContexts.last!), bridge.latestSnapshot)
    }

    func testHostRuntimeSurfacePublishesIntoWatchSnapshot() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)

        try bridge.updateRuntimeSurface(.focused(.vision))

        XCTAssertEqual(bridge.latestSnapshot.activeSurface, .app(.vision))
        XCTAssertEqual(bridge.latestSnapshot.activeApp?.appID, .vision)
        XCTAssertEqual(try WatchBridgeWireCodec.decodeSnapshot(try XCTUnwrap(session.applicationContexts.last)), bridge.latestSnapshot)

        try bridge.updateRuntimeSurface(.orbit)

        XCTAssertEqual(bridge.latestSnapshot.activeSurface, .orbit)
        XCTAssertNil(bridge.latestSnapshot.activeApp)
        XCTAssertEqual(try WatchBridgeWireCodec.decodeSnapshot(try XCTUnwrap(session.applicationContexts.last)), bridge.latestSnapshot)
    }

    func testQueuedBookmarkUsesTransferUserInfoAndDrainsLater() throws {
        let session = FakeWatchBridgeSession(isReachable: false)
        let bridge = PhoneWatchBridge(session: session)
        let command = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .bookmark
        )

        let queued = try bridge.receiveQueuedCommand(command)

        XCTAssertEqual(queued.status, .queued)
        XCTAssertEqual(session.transferredUserInfos.count, 1)
        XCTAssertEqual(try WatchBridgeWireCodec.decodeQueuedCommand(session.transferredUserInfos[0]), command)
        XCTAssertEqual(bridge.pendingQueuedCommands.map(\.id), [command.id])
        XCTAssertEqual(bridge.latestSnapshot.lastAcknowledgement?.status, .queued)

        session.isReachable = true
        let drained = try bridge.drainQueuedCommands()

        XCTAssertEqual(drained.map(\.status), [.applied])
        XCTAssertTrue(bridge.pendingQueuedCommands.isEmpty)
        XCTAssertEqual(bridge.latestSnapshot.lastAcknowledgement?.status, .applied)
    }

    func testStaleCommandIsRejected() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)
        let command = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version + 1,
            kind: .focusApp,
            appID: .vision
        )

        let acknowledgement = try bridge.receiveReachableCommand(command)

        XCTAssertEqual(acknowledgement.status, .stale)
        XCTAssertTrue(acknowledgement.reason?.contains("Stale") == true)
    }

    func testPrivacyModeRejectsPrimaryAction() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)
        try bridge.updatePrivacyMode(true)
        let command = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .primaryAction,
            appID: .oracle
        )

        let acknowledgement = try bridge.receiveReachableCommand(command)

        XCTAssertEqual(acknowledgement.status, .rejected)
        XCTAssertTrue(acknowledgement.reason?.contains("Privacy") == true)
    }

    func testRecoveryOnlyRejectsFocusedCommand() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)
        try bridge.updateConnection(.recovery)
        let command = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .focusApp,
            appID: .babel
        )

        let acknowledgement = try bridge.receiveReachableCommand(command)

        XCTAssertEqual(acknowledgement.status, .rejected)
        XCTAssertTrue(acknowledgement.reason?.contains("Recovery") == true)
    }

    func testWrongDeviceRiskRejectsFocusedCommand() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)
        try bridge.updateWrongDeviceRisk(true)
        let command = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .focusApp,
            appID: .chronos
        )

        let acknowledgement = try bridge.receiveReachableCommand(command)

        XCTAssertEqual(acknowledgement.status, .rejected)
        XCTAssertTrue(acknowledgement.reason?.contains("Wrong device") == true)
    }

    func testWrongDeviceRiskDisablesPublishedWidgetsAndSnapshot() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)

        try bridge.updateWrongDeviceRisk(true)

        let snapshot = try bridge.publishSnapshot()

        XCTAssertTrue(bridge.latestSnapshot.wrongDeviceRisk)
        XCTAssertTrue(snapshot.wrongDeviceRisk)
        XCTAssertTrue(snapshot.widgets.allSatisfy(\.isDisabled))
    }

    func testDuplicateCommandIDReturnsCachedAcknowledgement() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)
        let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let command = WatchCommand(
            id: id,
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .focusApp,
            appID: .signal
        )

        let first = try bridge.receiveReachableCommand(command)
        let second = try bridge.receiveReachableCommand(command)

        XCTAssertEqual(first, second)
        XCTAssertEqual(session.applicationContexts.count, 2)
    }

    func testChronosAlarmPublishesAlarmAcknowledgementAndKeepsItStable() throws {
        let session = FakeWatchBridgeSession()
        let seededChronos = ChronosEngine(
            state: ChronosState(
                mode: .timer,
                totalSeconds: 1,
                startedAt: Date().addingTimeInterval(-2),
                accumulatedSeconds: 0,
                runState: .running,
                pinned: true
            )
        )
        let bridge = PhoneWatchBridge(session: session, chronos: seededChronos)

        XCTAssertEqual(bridge.latestSnapshot.chronos?.runState, .alarm)
        XCTAssertEqual(bridge.latestSnapshot.lastAcknowledgement?.haptic, .alarm)

        let firstAlarmID = try XCTUnwrap(bridge.latestSnapshot.lastAcknowledgement?.commandID)
        let refreshed = try bridge.publishSnapshot()

        XCTAssertEqual(refreshed.lastAcknowledgement?.commandID, firstAlarmID)
        XCTAssertEqual(refreshed.lastAcknowledgement?.haptic, .alarm)
    }

    func testOracleCommandsUpdateHostStateAndEmitRuntimeEffects() throws {
        let session = FakeWatchBridgeSession()
        var emittedEffects: [RuntimeEffect] = []
        let bridge = PhoneWatchBridge(
            session: session,
            runtimeEffectHandler: { effect in
                emittedEffects.append(effect)
            }
        )

        let focus = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .focusApp,
            appID: .oracle
        )
        _ = try bridge.receiveReachableCommand(focus)
        XCTAssertEqual(bridge.latestSnapshot.activeApp?.appID, .oracle)

        let ask = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .oracle,
            appID: .oracle,
            value: .oracle(.ask)
        )
        let askAck = try bridge.receiveReachableCommand(ask)
        XCTAssertEqual(askAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.oracle?.phase, .listening)
        XCTAssertTrue(bridge.latestSnapshot.captureActive)
        if case let .captureAudio(appID, _) = try XCTUnwrap(emittedEffects.last) {
            XCTAssertEqual(appID, .oracle)
        } else {
            XCTFail("Expected Oracle audio capture effect")
        }

        let answerID = PrismRequestID(rawValue: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!)
        let answer = OracleAnswer(
            id: answerID,
            prompt: "WHAT IS TUNGSTEN?",
            text: "3422 C (6192 F).",
            source: "typed",
            createdAt: Int(Date().timeIntervalSince1970)
        )
        try bridge.updateOracle(OracleEngine(state: .answer(answer), history: [answer]))

        let keep = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .oracle,
            appID: .oracle,
            value: .oracle(.toggleKeep)
        )
        let keepAck = try bridge.receiveReachableCommand(keep)
        XCTAssertEqual(keepAck.status, .applied)
        XCTAssertTrue(bridge.latestSnapshot.oracle?.isKept == true)

        let copy = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .oracle,
            appID: .oracle,
            value: .oracle(.copy)
        )
        let copyAck = try bridge.receiveReachableCommand(copy)
        XCTAssertEqual(copyAck.status, .applied)
        XCTAssertEqual(emittedEffects.last, .copyToClipboard(text: "3422 C (6192 F)."))

        let clear = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .oracle,
            appID: .oracle,
            value: .oracle(.clear)
        )
        let clearAck = try bridge.receiveReachableCommand(clear)
        XCTAssertEqual(clearAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.oracle?.phase, .ready)
    }

    func testTeleprompterCommandsUpdateLineBookmarkModeSpeedResetAndPrivacy() throws {
        let session = FakeWatchBridgeSession()
        let bridge = PhoneWatchBridge(session: session)

        let focus = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .focusApp,
            appID: .teleprompter
        )
        _ = try bridge.receiveReachableCommand(focus)

        let nextLine = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .teleprompter,
            appID: .teleprompter,
            value: .teleprompter(.nextLine)
        )
        let nextAck = try bridge.receiveReachableCommand(nextLine)
        XCTAssertEqual(nextAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.teleprompter?.currentIndex, 1)
        XCTAssertEqual(bridge.latestSnapshot.teleprompter?.lineProgressTitle, "2/4")

        let bookmark = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .teleprompter,
            appID: .teleprompter,
            value: .teleprompter(.bookmark)
        )
        let bookmarkAck = try bridge.receiveReachableCommand(bookmark)
        XCTAssertEqual(bookmarkAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.teleprompter?.bookmarkIndex, 1)

        let play = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .teleprompter,
            appID: .teleprompter,
            value: .teleprompter(.togglePlayPause)
        )
        let playAck = try bridge.receiveReachableCommand(play)
        XCTAssertEqual(playAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.teleprompter?.mode, .auto)

        let speed = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .teleprompter,
            appID: .teleprompter,
            value: .teleprompter(.adjustWordsPerMinute(2))
        )
        let speedAck = try bridge.receiveReachableCommand(speed)
        XCTAssertEqual(speedAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.teleprompter?.wordsPerMinute, 160)

        let reset = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .teleprompter,
            appID: .teleprompter,
            value: .teleprompter(.startOver)
        )
        let resetAck = try bridge.receiveReachableCommand(reset)
        XCTAssertEqual(resetAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.teleprompter?.currentIndex, 0)

        try bridge.updatePrivacyMode(true)

        XCTAssertTrue(bridge.latestSnapshot.privacyMode)
        XCTAssertNil(bridge.latestSnapshot.teleprompter?.currentLine)
        XCTAssertNil(bridge.latestSnapshot.teleprompter?.nextLine)
        XCTAssertEqual(bridge.latestSnapshot.teleprompter?.title, "PRIVATE")
    }

    func testSignalCommandsUpdateSelectionPrivacyHandoffAndReload() throws {
        let session = FakeWatchBridgeSession()
        let signal = SignalStack(
            cards: [
                SignalCard(source: "PRISM", title: "Sync", body: "Done", priority: .info, handoffURL: "https://example.com/signal"),
                SignalCard(source: "SYS", title: "Battery", body: "Low", priority: .critical)
            ]
        )
        var openedURLs: [String] = []
        let bridge = PhoneWatchBridge(
            session: session,
            signal: signal,
            runtimeEffectHandler: { effect in
                if case let .openHandoff(urlString) = effect {
                    openedURLs.append(urlString)
                }
            }
        )

        XCTAssertEqual(bridge.latestSnapshot.signal?.currentCard?.title, "Battery")
        XCTAssertEqual(bridge.latestSnapshot.signal?.positionTitle, "1/2")

        let focus = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .focusApp,
            appID: .signal
        )
        _ = try bridge.receiveReachableCommand(focus)

        let next = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .signal,
            appID: .signal,
            value: .signal(.next)
        )
        let nextAck = try bridge.receiveReachableCommand(next)
        XCTAssertEqual(nextAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.signal?.currentCard?.title, "Sync")
        XCTAssertEqual(bridge.latestSnapshot.signal?.positionTitle, "2/2")

        let open = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .signal,
            appID: .signal,
            value: .signal(.openHandoff)
        )
        let openAck = try bridge.receiveReachableCommand(open)
        XCTAssertEqual(openAck.status, .applied)
        XCTAssertEqual(openedURLs, ["https://example.com/signal"])

        let privacy = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .signal,
            appID: .signal,
            value: .signal(.togglePrivacy)
        )
        let privacyAck = try bridge.receiveReachableCommand(privacy)
        XCTAssertEqual(privacyAck.status, .applied)
        XCTAssertTrue(bridge.latestSnapshot.signal?.privacyMode == true)
        XCTAssertNil(bridge.latestSnapshot.signal?.currentCard?.body)
        XCTAssertEqual(bridge.latestSnapshot.signal?.titleLine, "PRIVATE")

        let dismiss = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .signal,
            appID: .signal,
            value: .signal(.dismiss)
        )
        let dismissAck = try bridge.receiveReachableCommand(dismiss)
        XCTAssertEqual(dismissAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.signal?.currentCard?.title, "Battery")

        let secondDismiss = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .signal,
            appID: .signal,
            value: .signal(.dismiss)
        )
        let secondDismissAck = try bridge.receiveReachableCommand(secondDismiss)
        XCTAssertEqual(secondDismissAck.status, .applied)
        XCTAssertTrue(bridge.latestSnapshot.signal?.isEmpty == true)

        let reload = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .signal,
            appID: .signal,
            value: .signal(.reload)
        )
        let reloadAck = try bridge.receiveReachableCommand(reload)
        XCTAssertEqual(reloadAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.signal?.currentCard?.title, "Battery")
        XCTAssertEqual(bridge.latestSnapshot.signal?.visibleCardCount, 2)
    }

    func testBabelCommandsUpdateLanguagesFreezeSaveClearAndRepeatLast() throws {
        let session = FakeWatchBridgeSession()
        var babel = BabelEngine(sourceLanguage: "ja", targetLanguage: "en")
        if case let .translateText(_, _, _, requestID)? = babel.translateHostText("konnichiwa") {
            _ = babel.receiveTranslation("hello", requestID: requestID)
        }

        let bridge = PhoneWatchBridge(
            session: session,
            babel: babel,
            babelCommandHandler: { action in
                switch action {
                case .toggleFreeze:
                    babel.toggleFreeze()
                    return BabelCommandResult(status: .applied, reason: babel.frozen ? "Frozen" : "Resumed", babel: babel)
                case .swapLanguages:
                    babel.swapLanguages()
                    return BabelCommandResult(
                        status: .applied,
                        reason: "\(babel.sourceLanguage.uppercased()) -> \(babel.targetLanguage.uppercased())",
                        babel: babel
                    )
                case let .selectPreset(preset):
                    babel.setLanguages(source: preset.sourceLanguage, target: preset.targetLanguage)
                    return BabelCommandResult(status: .applied, reason: preset.displayTitle, babel: babel)
                case .clearTranscript:
                    _ = babel.clearTranscript()
                    return BabelCommandResult(status: .applied, reason: "Cleared", babel: babel)
                case .saveTranscript:
                    let saved = babel.saveTranscript()
                    return BabelCommandResult(status: saved ? .applied : .rejected, reason: saved ? "Saved" : "Empty transcript", babel: babel)
                case .repeatLast:
                    let repeated = babel.repeatLast()
                    return BabelCommandResult(status: repeated == nil ? .rejected : .applied, reason: repeated == nil ? "No history" : "Repeat last", babel: babel)
                }
            }
        )

        let preset = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .babel,
            appID: .babel,
            value: .babel(.selectPreset(.frToEn))
        )
        let presetAck = try bridge.receiveReachableCommand(preset)
        XCTAssertEqual(presetAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.babel?.sourceLanguage, "fr")
        XCTAssertEqual(bridge.latestSnapshot.babel?.targetLanguage, "en")

        let freeze = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .babel,
            appID: .babel,
            value: .babel(.toggleFreeze)
        )
        let freezeAck = try bridge.receiveReachableCommand(freeze)
        XCTAssertEqual(freezeAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.babel?.phase, .frozen)

        let save = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .babel,
            appID: .babel,
            value: .babel(.saveTranscript)
        )
        let saveAck = try bridge.receiveReachableCommand(save)
        XCTAssertEqual(saveAck.status, .applied)
        XCTAssertGreaterThan(bridge.latestSnapshot.babel?.savedTranscriptCount ?? 0, 0)

        let clear = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .babel,
            appID: .babel,
            value: .babel(.clearTranscript)
        )
        let clearAck = try bridge.receiveReachableCommand(clear)
        XCTAssertEqual(clearAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.babel?.lines.first?.text, "CLEARED")

        let repeatLast = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .babel,
            appID: .babel,
            value: .babel(.repeatLast)
        )
        let repeatAck = try bridge.receiveReachableCommand(repeatLast)
        XCTAssertEqual(repeatAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.babel?.phase, .frozen)
        XCTAssertEqual(bridge.latestSnapshot.babel?.lines.last?.kind, .raw)
    }

    func testVisionCommandsUpdateHostStateAndEmitRuntimeEffects() throws {
        let session = FakeWatchBridgeSession()
        var emittedEffects: [RuntimeEffect] = []
        let bridge = PhoneWatchBridge(
            session: session,
            runtimeEffectHandler: { effect in
                emittedEffects.append(effect)
            }
        )

        let capture = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .vision,
            appID: .vision,
            value: .vision(.capture)
        )
        let captureAck = try bridge.receiveReachableCommand(capture)
        XCTAssertEqual(captureAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.vision?.phase, .waitingImage)
        XCTAssertTrue(bridge.latestSnapshot.captureActive)
        if case let .captureImage(appID, _) = try XCTUnwrap(emittedEffects.last) {
            XCTAssertEqual(appID, .vision)
        } else {
            XCTFail("Expected captureImage effect")
        }

        var vision = VisionEngine()
        if case let .captureImage(_, requestID) = vision.capture() {
            _ = vision.receiveImage(Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9]), requestID: requestID)
            _ = vision.receiveAnalysis(summary: "ESP32 BOARD ONLINE", ocrText: "PRESS TOP BUTTON", requestID: requestID)
        }
        try bridge.updateVision(vision)

        let save = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .vision,
            appID: .vision,
            value: .vision(.saveNote)
        )
        let saveAck = try bridge.receiveReachableCommand(save)
        XCTAssertEqual(saveAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.vision?.phase, .saved)
        XCTAssertEqual(bridge.latestSnapshot.vision?.savedNoteTitle, "1 SAVED")
        if case let .saveVisionNote(text, _) = try XCTUnwrap(emittedEffects.last) {
            XCTAssertEqual(text, "ESP32 BOARD ONLINE")
        } else {
            XCTFail("Expected saveVisionNote effect")
        }

        let oracle = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .vision,
            appID: .vision,
            value: .vision(.askOracle)
        )
        let oracleAck = try bridge.receiveReachableCommand(oracle)
        XCTAssertEqual(oracleAck.status, .applied)
        XCTAssertEqual(bridge.latestSnapshot.vision?.phase, .saved)
        if case let .callOracle(prompt, _) = try XCTUnwrap(emittedEffects.last) {
            XCTAssertTrue(prompt.contains("ESP32 BOARD ONLINE"))
        } else {
            XCTFail("Expected callOracle effect")
        }
    }

    func testVisionStateMasksResultContentInPrivacyMode() throws {
        var vision = VisionEngine()
        if case let .captureImage(_, requestID) = vision.capture() {
            _ = vision.receiveImage(Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9]), requestID: requestID)
            _ = vision.receiveAnalysis(summary: "ESP32 BOARD ONLINE", ocrText: "PRESS TOP BUTTON", requestID: requestID)
        }

        let masked = PhoneWatchBridge.watchVisionState(for: vision, now: Date(), privacyMode: true)

        XCTAssertEqual(masked.phase, .result)
        XCTAssertNil(masked.summary)
        XCTAssertNil(masked.ocrText)
        XCTAssertEqual(masked.compactTitle, "RESULT")
        XCTAssertEqual(masked.detailTitle, "RESULT HIDDEN")
    }

    func testBridgeStateChangesMirrorIntoHostSessionsModel() throws {
        let session = FakeWatchBridgeSession()
        let localModel = LocalConsoleModel()
        let bridge = PhoneWatchBridge(
            session: session,
            stateDidChange: { chronos, teleprompter, signal in
                localModel.updateChronos(chronos)
                localModel.updateTeleprompter(teleprompter)
                localModel.updateSignal(signal)
            }
        )

        let command = WatchCommand(
            snapshotVersion: bridge.latestSnapshot.version,
            kind: .teleprompter,
            appID: .teleprompter,
            value: .teleprompter(.nextLine)
        )

        _ = try bridge.receiveReachableCommand(command)

        XCTAssertEqual(localModel.teleprompter.script.currentIndex, 1)
        XCTAssertEqual(localModel.teleprompter.script.title, "Demo Script")
        XCTAssertEqual(localModel.signal.currentCard?.title, "Battery")
        XCTAssertEqual(localModel.sessionRows[1], "Teleprompter: Demo Script")
    }
}

private final class FakeWatchBridgeSession: WatchBridgeSessioning {
    var isReachable: Bool
    var applicationContexts: [[String: Any]] = []
    var transferredUserInfos: [[String: Any]] = []

    init(isReachable: Bool = true) {
        self.isReachable = isReachable
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        applicationContexts.append(applicationContext)
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        transferredUserInfos.append(userInfo)
    }
}
