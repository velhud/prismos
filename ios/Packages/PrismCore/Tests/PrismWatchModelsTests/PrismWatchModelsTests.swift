import XCTest
import PrismWatchModels

final class PrismWatchModelsTests: XCTestCase {
    func testCommandRoundTripsWithTypedValue() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_123)
        let command = WatchCommand(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            snapshotVersion: 13,
            kind: .togglePrivacy,
            value: .flag(true),
            createdAt: createdAt
        )

        XCTAssertEqual(try roundTrip(command), command)
        XCTAssertEqual(WatchSignalPriority.important.displayTitle, "IMPORTANT")
    }

    func testSnapshotRoundTripsWithAllActiveAppIDs() throws {
        let acknowledgement = WatchAcknowledgement(
            commandID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            status: .queued,
            reason: "queued for host",
            snapshotVersion: 21,
            displayText: "QUEUED"
        )
        let snapshot = WatchSnapshot(
            version: 21,
            activeSurface: .app(.vision),
            connection: .phone,
            privacyMode: true,
            captureActive: false,
            wrongDeviceRisk: true,
            widgets: PrismAppID.allCases.map { appID in
                WatchAppWidget(appID: appID, isFocused: appID == .vision)
            },
            activeApp: WatchAppSummary(
                appID: .vision,
                primaryActionTitle: "Capture",
                secondaryActionTitle: "Retake",
                isPrivacySensitive: true
            ),
            lastAcknowledgement: acknowledgement
        )

        let decoded = try roundTrip(snapshot)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.widgets.map(\.appID), PrismAppID.allCases)
        XCTAssertEqual(decoded.activeApp?.appID, .vision)
        XCTAssertEqual(decoded.lastAcknowledgement?.status, .queued)
        XCTAssertTrue(decoded.wrongDeviceRisk)
    }

    func testSnapshotRoundTripsWithChronosState() throws {
        let chronos = WatchChronosState(
            mode: .stopwatch,
            runState: .running,
            totalSeconds: 300,
            remainingSeconds: 112,
            elapsedSeconds: 188,
            isPinned: true,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_400)
        )
        let snapshot = WatchSnapshot(
            version: 32,
            activeSurface: .app(.chronos),
            connection: .phone,
            privacyMode: false,
            captureActive: false,
            widgets: PrismAppID.allCases.map { appID in
                WatchAppWidget(appID: appID, isFocused: appID == .chronos)
            },
            activeApp: WatchAppSummary(
                appID: .chronos,
                subtitle: chronos.compactTitle,
                primaryActionTitle: chronos.primaryActionTitle,
                secondaryActionTitle: chronos.secondaryActionTitle,
                isPrivacySensitive: false
            ),
            chronos: chronos
        )

        let decoded = try roundTrip(snapshot)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.chronos?.runState, .running)
        XCTAssertEqual(decoded.activeApp?.subtitle, "STOPWATCH 03:08")
    }

    func testSnapshotRoundTripsWithTeleprompterState() throws {
        let teleprompter = WatchTeleprompterState(
            title: "Launch",
            mode: .auto,
            currentIndex: 2,
            totalChunks: 5,
            wordsPerMinute: 160,
            bookmarkIndex: 2,
            currentLine: "KEEP EYE CONTACT",
            nextLine: "ADVANCE CONCISE CHUNKS",
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_700)
        )
        let snapshot = WatchSnapshot(
            version: 33,
            activeSurface: .app(.teleprompter),
            connection: .phone,
            privacyMode: false,
            captureActive: false,
            widgets: PrismAppID.allCases.map { appID in
                WatchAppWidget(appID: appID, isFocused: appID == .teleprompter)
            },
            activeApp: WatchAppSummary(
                appID: .teleprompter,
                subtitle: teleprompter.compactTitle,
                primaryActionTitle: teleprompter.primaryActionTitle,
                secondaryActionTitle: teleprompter.secondaryActionTitle,
                isPrivacySensitive: true
            ),
            teleprompter: teleprompter
        )

        let decoded = try roundTrip(snapshot)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.teleprompter?.mode, .auto)
        XCTAssertEqual(decoded.activeApp?.subtitle, "3/5 AUTO 160 WPM")
    }

    func testSnapshotRoundTripsWithSignalState() throws {
        let signal = WatchSignalState(
            privacyMode: true,
            visibleCardCount: 2,
            currentIndex: 1,
            currentCard: WatchSignalCard(
                id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
                source: "PRISM",
                title: "Sync",
                body: nil,
                priority: .important,
                handoffURL: "https://example.com/signal"
            ),
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_900)
        )
        let snapshot = WatchSnapshot(
            version: 34,
            activeSurface: .app(.signal),
            connection: .phone,
            privacyMode: false,
            captureActive: false,
            widgets: PrismAppID.allCases.map { appID in
                WatchAppWidget(appID: appID, isFocused: appID == .signal)
            },
            activeApp: WatchAppSummary(
                appID: .signal,
                subtitle: signal.titleLine,
                primaryActionTitle: signal.primaryActionTitle,
                secondaryActionTitle: signal.secondaryActionTitle,
                isPrivacySensitive: true
            ),
            signal: signal
        )

        let decoded = try roundTrip(snapshot)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.signal, signal)
        XCTAssertEqual(decoded.activeApp?.appID, .signal)
        XCTAssertEqual(decoded.activeApp?.subtitle, "PRIVATE")
        XCTAssertEqual(decoded.signal?.titleLine, "PRIVATE")
        XCTAssertEqual(decoded.signal?.bodyLine, "OPEN PHONE")
    }

    func testSnapshotRoundTripsWithBabelState() throws {
        let babel = WatchBabelState(
            sourceLanguage: "ja",
            targetLanguage: "en",
            phase: .translating,
            audioLevel: 0.75,
            lines: [
                WatchBabelLine(kind: .system, text: "LISTENING"),
                WatchBabelLine(kind: .raw, text: "konnichiwa"),
                WatchBabelLine(kind: .final, text: "hello")
            ],
            savedTranscriptCount: 2,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_001_200)
        )
        let snapshot = WatchSnapshot(
            version: 35,
            activeSurface: .app(.babel),
            connection: .phone,
            privacyMode: true,
            captureActive: false,
            widgets: PrismAppID.allCases.map { appID in
                WatchAppWidget(
                    appID: appID,
                    subtitle: appID == .babel ? babel.compactTitle : nil,
                    isFocused: appID == .babel
                )
            },
            activeApp: WatchAppSummary(
                appID: .babel,
                subtitle: babel.compactTitle,
                primaryActionTitle: babel.primaryActionTitle,
                secondaryActionTitle: babel.secondaryActionTitle,
                isPrivacySensitive: true
            ),
            babel: babel
        )

        let decoded = try roundTrip(snapshot)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.babel?.phase, .translating)
        XCTAssertEqual(decoded.activeApp?.subtitle, "JA -> EN • TRANSLATING")
        XCTAssertEqual(decoded.widgets.first(where: { $0.appID == .babel })?.subtitle, "JA -> EN • TRANSLATING")
    }

    func testSnapshotRoundTripsWithVisionState() throws {
        let vision = WatchVisionState(
            mode: .readText,
            phase: .saved,
            summary: "ESP32 BOARD ONLINE",
            ocrText: "PRESS TOP BUTTON",
            savedNoteCount: 2,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_001_500)
        )
        let snapshot = WatchSnapshot(
            version: 36,
            activeSurface: .app(.vision),
            connection: .phone,
            privacyMode: false,
            captureActive: false,
            widgets: PrismAppID.allCases.map { appID in
                WatchAppWidget(
                    appID: appID,
                    subtitle: appID == .vision ? vision.compactTitle : nil,
                    isFocused: appID == .vision
                )
            },
            activeApp: WatchAppSummary(
                appID: .vision,
                subtitle: vision.compactTitle,
                primaryActionTitle: vision.primaryActionTitle,
                secondaryActionTitle: vision.secondaryActionTitle,
                isPrivacySensitive: true
            ),
            vision: vision
        )

        let decoded = try roundTrip(snapshot)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.vision, vision)
        XCTAssertEqual(decoded.activeApp?.subtitle, "SAVED • ESP32 BOARD ONLINE")
        XCTAssertEqual(decoded.vision?.detailTitle, "PRESS TOP BUTTON")
    }

    func testChronosStateAndActionRoundTrip() throws {
        let chronos = WatchChronosState(
            mode: .timer,
            runState: .paused,
            totalSeconds: 420,
            remainingSeconds: 127,
            elapsedSeconds: 293,
            isPinned: false,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )
        let command = WatchCommand(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            snapshotVersion: 13,
            kind: .chronos,
            appID: .chronos,
            value: .chronos(.addTime(30)),
            createdAt: Date(timeIntervalSince1970: 1_700_000_456)
        )

        XCTAssertEqual(try roundTrip(chronos), chronos)
        XCTAssertEqual(try roundTrip(command), command)
        XCTAssertEqual(WatchChronosMode.timer.displayTitle, "TIMER")
        XCTAssertEqual(WatchChronosRunState.alarm.displayTitle, "ALARM")
        XCTAssertEqual(chronos.statusTitle, "PAUSED")
        XCTAssertEqual(chronos.primaryActionTitle, "RESUME")
        XCTAssertEqual(chronos.pinActionTitle, "PIN")
    }

    func testTeleprompterStateAndActionRoundTrip() throws {
        let teleprompter = WatchTeleprompterState(
            title: "Launch",
            mode: .manual,
            currentIndex: 1,
            totalChunks: 4,
            wordsPerMinute: 140,
            bookmarkIndex: 1,
            currentLine: "KEEP EYE CONTACT",
            nextLine: "ADVANCE CONCISE CHUNKS",
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_456)
        )
        let command = WatchCommand(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            snapshotVersion: 13,
            kind: .teleprompter,
            appID: .teleprompter,
            value: .teleprompter(.adjustWordsPerMinute(2)),
            createdAt: Date(timeIntervalSince1970: 1_700_000_789)
        )

        XCTAssertEqual(try roundTrip(teleprompter), teleprompter)
        XCTAssertEqual(try roundTrip(command), command)
        XCTAssertEqual(WatchTeleprompterMode.manual.displayTitle, "MANUAL")
        XCTAssertEqual(teleprompter.compactTitle, "2/4 MANUAL 140 WPM")
        XCTAssertEqual(teleprompter.primaryActionTitle, "PLAY")
        XCTAssertEqual(teleprompter.secondaryActionTitle, "BOOKMARK")
        XCTAssertEqual(teleprompter.bookmarkStatusTitle, "BOOKMARKED")
    }

    func testSignalStateAndActionRoundTrip() throws {
        let signal = WatchSignalState(
            privacyMode: false,
            visibleCardCount: 2,
            currentIndex: 0,
            currentCard: WatchSignalCard(
                id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                source: "SYS",
                title: "Battery",
                body: "Low",
                priority: .critical,
                handoffURL: nil
            ),
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_456)
        )
        let command = WatchCommand(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            snapshotVersion: 13,
            kind: .signal,
            appID: .signal,
            value: .signal(.openHandoff),
            createdAt: Date(timeIntervalSince1970: 1_700_001_111)
        )

        XCTAssertEqual(try roundTrip(signal), signal)
        XCTAssertEqual(try roundTrip(command), command)
        XCTAssertEqual(WatchSignalAction.openHandoff, .openHandoff)
        XCTAssertEqual(signal.positionTitle, "1/2")
        XCTAssertEqual(signal.priorityTitle, "CRITICAL")
        XCTAssertEqual(signal.primaryActionTitle, "DISMISS")
        XCTAssertEqual(signal.secondaryActionTitle, "NEXT")
        XCTAssertEqual(signal.bodyLine, "Low")
    }

    func testBabelStateAndActionRoundTrip() throws {
        let babel = WatchBabelState(
            sourceLanguage: "es",
            targetLanguage: "en",
            phase: .frozen,
            audioLevel: 0,
            lines: [
                WatchBabelLine(kind: .system, text: "FROZEN"),
                WatchBabelLine(kind: .raw, text: "hola"),
                WatchBabelLine(kind: .final, text: "hello")
            ],
            savedTranscriptCount: 3,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_001_250)
        )
        let command = WatchCommand(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            snapshotVersion: 13,
            kind: .babel,
            appID: .babel,
            value: .babel(.selectPreset(.esToEn)),
            createdAt: Date(timeIntervalSince1970: 1_700_001_260)
        )

        XCTAssertEqual(try roundTrip(babel), babel)
        XCTAssertEqual(try roundTrip(command), command)
        XCTAssertEqual(WatchBabelPhase.frozen.displayTitle, "FROZEN")
        XCTAssertEqual(WatchBabelPreset.esToEn.displayTitle, "ES -> EN")
        XCTAssertEqual(babel.pairTitle, "ES -> EN")
        XCTAssertEqual(babel.primaryActionTitle, "RESUME")
        XCTAssertEqual(babel.savedTranscriptTitle, "3 SAVED")
        XCTAssertEqual(babel.resolvedPreset, .esToEn)
        XCTAssertEqual(babel.displayLines(masked: true).compactMap(\.text), ["FROZEN", "PRIVATE", "PRIVATE"])
    }

    func testVisionStateAndActionRoundTrip() throws {
        let vision = WatchVisionState(
            mode: .identify,
            phase: .result,
            summary: "ESP32 BOARD ONLINE",
            ocrText: "PRESS TOP BUTTON",
            savedNoteCount: 1,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_001_260)
        )
        let command = WatchCommand(
            id: UUID(uuidString: "AAAAAAAA-CCCC-DDDD-EEEE-111111111111")!,
            snapshotVersion: 13,
            kind: .vision,
            appID: .vision,
            value: .vision(.askOracle),
            createdAt: Date(timeIntervalSince1970: 1_700_001_265)
        )

        XCTAssertEqual(try roundTrip(vision), vision)
        XCTAssertEqual(try roundTrip(command), command)
        XCTAssertEqual(WatchVisionMode.readText.displayTitle, "READ TEXT")
        XCTAssertEqual(WatchVisionPhase.analyzing.displayTitle, "ANALYZING")
        XCTAssertEqual(vision.statusTitle, "RESULT")
        XCTAssertEqual(vision.primaryActionTitle, "RETAKE")
        XCTAssertEqual(vision.secondaryActionTitle, "SAVE")
        XCTAssertEqual(vision.modeActionTitle, "READ TEXT")
        XCTAssertEqual(vision.savedNoteTitle, "1 SAVED")
        XCTAssertEqual(vision.detailTitle, "ESP32 BOARD ONLINE")
    }

    func testOracleStateAndActionRoundTrip() throws {
        let oracle = WatchOracleState(
            phase: .answer,
            density: .balanced,
            pageIndex: 0,
            pageCount: 2,
            historyCount: 3,
            isKept: true,
            promptText: "WHAT IS TUNGSTEN?",
            pageText: "3422 C (6192 F).",
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_001_300)
        )
        let command = WatchCommand(
            id: UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!,
            snapshotVersion: 13,
            kind: .oracle,
            appID: .oracle,
            value: .oracle(.toggleKeep),
            createdAt: Date(timeIntervalSince1970: 1_700_001_301)
        )

        XCTAssertEqual(try roundTrip(oracle), oracle)
        XCTAssertEqual(try roundTrip(command), command)
        XCTAssertEqual(WatchOraclePhase.thinking.displayTitle, "THINKING")
        XCTAssertEqual(WatchOracleDensity.moreDetail.displayTitle, "DETAIL")
        XCTAssertEqual(oracle.statusTitle, "ANSWER")
        XCTAssertEqual(oracle.pageTitle, "1/2")
        XCTAssertEqual(oracle.historyTitle, "3 HISTORY")
        XCTAssertEqual(oracle.densityTitle, "BALANCED")
        XCTAssertEqual(oracle.keepTitle, "KEPT")
        XCTAssertEqual(oracle.primaryActionTitle, "FOLLOW UP")
        XCTAssertEqual(oracle.secondaryActionTitle, "UNKEEP")
        XCTAssertEqual(oracle.clearActionTitle, "CLEAR")
        XCTAssertEqual(oracle.copyActionTitle, "COPY")
        XCTAssertEqual(oracle.shorterActionTitle, "SHORTER")
        XCTAssertEqual(oracle.moreDetailActionTitle, "MORE")
        XCTAssertEqual(oracle.crownHintTitle, "PAGE")
        XCTAssertEqual(oracle.compactTitle, "1/2 KEPT")
        XCTAssertEqual(oracle.detailTitle, "3422 C (6192 F).")
        XCTAssertTrue(oracle.canKeep)
        XCTAssertTrue(oracle.canCopy)
        XCTAssertTrue(oracle.canAdjustPage)
        XCTAssertTrue(oracle.canShorten)
        XCTAssertTrue(oracle.canExpand)
    }

    func testSnapshotRoundTripsWithOracleState() throws {
        let oracle = WatchOracleState(
            phase: .answer,
            density: .balanced,
            pageIndex: 0,
            pageCount: 2,
            historyCount: 3,
            isKept: true,
            promptText: "WHAT IS TUNGSTEN?",
            pageText: "3422 C (6192 F).",
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_001_310)
        )
        let snapshot = WatchSnapshot(
            version: 37,
            activeSurface: .app(.oracle),
            connection: .phone,
            privacyMode: false,
            captureActive: false,
            widgets: PrismAppID.allCases.map { appID in
                WatchAppWidget(
                    appID: appID,
                    subtitle: appID == .oracle ? oracle.compactTitle : nil,
                    isFocused: appID == .oracle
                )
            },
            activeApp: WatchAppSummary(
                appID: .oracle,
                subtitle: oracle.compactTitle,
                primaryActionTitle: oracle.primaryActionTitle,
                secondaryActionTitle: oracle.secondaryActionTitle,
                isPrivacySensitive: true
            ),
            oracle: oracle
        )

        let decoded = try roundTrip(snapshot)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.oracle, oracle)
        XCTAssertEqual(decoded.activeApp?.appID, .oracle)
        XCTAssertEqual(decoded.activeApp?.subtitle, "1/2 KEPT")
        XCTAssertEqual(decoded.widgets.first(where: { $0.appID == .oracle })?.subtitle, "1/2 KEPT")
    }

    func testReducerBuildsVisionCommand() throws {
        var reducer = WatchCommandReducer()
        let snapshot = WatchSnapshot.sample(version: 44, activeApp: .vision)

        let command = try XCTUnwrap(try reducer.reduce(.vision(.askOracle), against: snapshot))

        XCTAssertEqual(command.kind, .vision)
        XCTAssertEqual(command.appID, .vision)
        XCTAssertEqual(command.value, .vision(.askOracle))
    }

    func testReducerBuildsOracleCommand() throws {
        var reducer = WatchCommandReducer()
        let snapshot = WatchSnapshot.sample(version: 45, activeApp: .oracle)

        let ask = try XCTUnwrap(try reducer.reduce(.oracle(.ask), against: snapshot))
        let copy = try XCTUnwrap(try reducer.reduce(.oracle(.copy), against: snapshot))

        XCTAssertEqual(ask.kind, .oracle)
        XCTAssertEqual(ask.appID, .oracle)
        XCTAssertEqual(ask.value, .oracle(.ask))
        XCTAssertEqual(copy.kind, .oracle)
        XCTAssertEqual(copy.appID, .oracle)
        XCTAssertEqual(copy.value, .oracle(.copy))
    }

    func testWireCodecRoundTripsSnapshotCommandAndAcknowledgement() throws {
        let snapshot = WatchSnapshot.sample(version: 31, connection: .monocle, wrongDeviceRisk: true)
        let command = WatchCommand(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            snapshotVersion: 31,
            kind: .save,
            createdAt: Date(timeIntervalSince1970: 1_700_001_000)
        )
        let acknowledgement = WatchAcknowledgement(
            commandID: command.id,
            status: .queued,
            reason: "queued",
            snapshotVersion: 31
        )

        XCTAssertEqual(try WatchBridgeWireCodec.decodeSnapshot(try WatchBridgeWireCodec.encodeSnapshot(snapshot)), snapshot)
        XCTAssertEqual(try WatchBridgeWireCodec.decodeCommand(try WatchBridgeWireCodec.encodeCommand(command)), command)
        XCTAssertEqual(
            try WatchBridgeWireCodec.decodeAcknowledgement(try WatchBridgeWireCodec.encodeAcknowledgement(acknowledgement)),
            acknowledgement
        )
    }

    func testStatusMapsToDisplayTextAndHaptics() {
        XCTAssertEqual(WatchCommandStatus.applied.displayText, "APPLIED")
        XCTAssertEqual(WatchCommandStatus.applied.hapticHint, .success)
        XCTAssertEqual(WatchCommandStatus.rejected.hapticHint, .failure)
        XCTAssertEqual(WatchCommandStatus.queued.hapticHint, .warning)
        XCTAssertEqual(WatchCommandStatus.stale.hapticHint, .retry)
    }

    func testValidatorRejectsStaleHostFacingCommandsAndAllowsLocalDeckSelection() throws {
        let snapshot = WatchSnapshot.sample(version: 42, connection: .stale)
        let validator = WatchCommandValidator()

        let localDeckCommand = WatchCommand(
            snapshotVersion: 7,
            kind: .selectDeck,
            value: .deck(.privacy)
        )
        XCTAssertNoThrow(try validator.validate(localDeckCommand, against: snapshot))

        let hostFacingCommand = WatchCommand(
            snapshotVersion: 7,
            kind: .focusApp,
            appID: .oracle
        )
        XCTAssertThrowsError(try validator.validate(hostFacingCommand, against: snapshot)) { error in
            XCTAssertEqual(
                error as? WatchCommandValidationError,
                .staleSnapshot(expected: 42, actual: 7)
            )
        }

        let freshSnapshot = WatchSnapshot.sample(version: 42, connection: .stale)
        let staleBlockingCommand = WatchCommand(
            snapshotVersion: 42,
            kind: .primaryAction,
            appID: .oracle
        )
        XCTAssertThrowsError(try validator.validate(staleBlockingCommand, against: freshSnapshot)) { error in
            XCTAssertEqual(
                error as? WatchCommandValidationError,
                .unreachablePhone(command: .primaryAction)
            )
        }

        let refreshSnapshotCommand = WatchCommand(
            snapshotVersion: 7,
            kind: .refreshSnapshot
        )
        XCTAssertNoThrow(try validator.validate(refreshSnapshotCommand, against: snapshot))

        let chronosCommand = WatchCommand(
            snapshotVersion: 42,
            kind: .chronos,
            appID: .chronos,
            value: .chronos(.adjustDuration(-30))
        )
        XCTAssertThrowsError(try validator.validate(chronosCommand, against: snapshot)) { error in
            XCTAssertEqual(
                error as? WatchCommandValidationError,
                .unreachablePhone(command: .chronos)
            )
        }

        let missingChronosPayload = WatchCommand(
            snapshotVersion: 42,
            kind: .chronos,
            appID: .chronos
        )
        XCTAssertThrowsError(try validator.validate(missingChronosPayload, against: snapshot)) { error in
            XCTAssertEqual(
                error as? WatchCommandValidationError,
                .missingPayload(command: .chronos)
            )
        }

        let teleprompterCommand = WatchCommand(
            snapshotVersion: 42,
            kind: .teleprompter,
            appID: .teleprompter,
            value: .teleprompter(.bookmark)
        )
        XCTAssertThrowsError(try validator.validate(teleprompterCommand, against: snapshot)) { error in
            XCTAssertEqual(
                error as? WatchCommandValidationError,
                .unreachablePhone(command: .teleprompter)
            )
        }

        let visionCommand = WatchCommand(
            snapshotVersion: 42,
            kind: .vision,
            appID: .vision,
            value: .vision(.capture)
        )
        XCTAssertThrowsError(try validator.validate(visionCommand, against: snapshot)) { error in
            XCTAssertEqual(
                error as? WatchCommandValidationError,
                .unreachablePhone(command: .vision)
            )
        }
    }

    func testReducerCoalescesCrownDeltaAndResetsAfterSnapshotChange() throws {
        var reducer = WatchCommandReducer()
        let liveSnapshot = WatchSnapshot.sample(version: 9, connection: .phone)

        XCTAssertNil(try reducer.reduce(.crownDelta(1), against: liveSnapshot))
        XCTAssertNil(try reducer.reduce(.crownDelta(2), against: liveSnapshot))

        let command = try XCTUnwrap(try reducer.reduce(.commitCrown, against: liveSnapshot))
        XCTAssertEqual(command.kind, .crownDelta)
        XCTAssertEqual(command.value, .delta(3))
        XCTAssertEqual(command.snapshotVersion, 9)

        let newSnapshot = WatchSnapshot.sample(version: 10, connection: .phone)
        XCTAssertNil(try reducer.reduce(.crownDelta(4), against: newSnapshot))
        let localDeckCommand = try XCTUnwrap(try reducer.reduce(.selectDeck(.handoff), against: newSnapshot))
        XCTAssertEqual(localDeckCommand.kind, .selectDeck)
        XCTAssertEqual(localDeckCommand.value, .deck(.handoff))
        XCTAssertNil(try reducer.reduce(.commitCrown, against: newSnapshot))
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }
}
