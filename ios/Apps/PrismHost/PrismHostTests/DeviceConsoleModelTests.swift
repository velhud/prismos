import XCTest
import PrismAI
import PrismModels
import PrismRuntime
import PrismWatchModels
@testable import PrismHost

@MainActor
final class DeviceConsoleModelTests: XCTestCase {
    func testScanRequiresExplicitCandidateSelectionBeforeConnect() {
        let model = DeviceConsoleModel(
            transport: MockMonocleTransport(),
            identityStore: InMemoryDeviceIdentityStore()
        )

        model.startScan()

        XCTAssertEqual(model.connectionState, .selected)
        XCTAssertEqual(model.candidates.count, 1)
        XCTAssertNil(model.selectedDevice)
    }

    func testSelectedRawDataDeviceConnectsAndAllowsDraw() {
        let store = InMemoryDeviceIdentityStore()
        let model = DeviceConsoleModel(transport: MockMonocleTransport(maxWriteLength: 64), identityStore: store)
        model.startScan()
        model.select(model.candidates[0])
        model.connectSelected()
        model.sendStaticDraw()

        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertTrue(model.rawDataAvailable)
        XCTAssertEqual(store.knownDeviceID, model.selectedDevice?.id)
        XCTAssertEqual(model.diagnostics.first?.category, "DRAW")
        XCTAssertTrue(model.diagnostics.first?.message.contains("Queued") == true)
    }

    func testRecoveryOnlyDeviceDisablesDraw() {
        let recovery = KnownDevice(
            id: UUID(),
            displayName: "Recovery inAi glasses",
            advertisedName: "Monocle",
            rawDataServiceSeen: false,
            nusServiceSeen: true
        )
        let model = DeviceConsoleModel(
            transport: RecoveryTransport(device: recovery),
            identityStore: InMemoryDeviceIdentityStore()
        )

        model.startScan()
        model.select(recovery)
        model.connectSelected()
        model.sendStaticDraw()

        XCTAssertEqual(model.connectionState, .recoveryOnly)
        XCTAssertFalse(model.rawDataAvailable)
        XCTAssertTrue(model.nusAvailable)
        XCTAssertEqual(model.diagnostics.first?.message, "Static DRAW blocked by connection state")
    }

    func testLifecycleAndRecoveryStateRemainUserVisible() {
        let recovery = KnownDevice(
            id: UUID(),
            displayName: "Recovery inAi glasses",
            advertisedName: "Monocle",
            rawDataServiceSeen: false,
            nusServiceSeen: true
        )
        let model = DeviceConsoleModel(
            transport: RecoveryTransport(device: recovery),
            identityStore: InMemoryDeviceIdentityStore()
        )

        model.startScan()
        model.select(recovery)
        model.connectSelected()

        XCTAssertEqual(model.recoveryState, .safeModeLikely)
        XCTAssertTrue(model.recoveryState.disablesNormalControls)
        XCTAssertTrue(model.reconnectMessage.contains("recovery-only"))

        model.recordLifecycle(.forceQuitLimited)

        XCTAssertEqual(model.lifecycleState, .forceQuitLimited)
        XCTAssertTrue(model.reconnectMessage.contains("force quit"))
        XCTAssertEqual(model.diagnostics.first?.category, "Lifecycle")
    }

    func testStoredIdentityReconnectsOnlyWhenDeviceIDIsUniquelyVisible() {
        let deviceID = UUID()
        let store = InMemoryDeviceIdentityStore()
        store.knownDeviceID = deviceID
        let device = KnownDevice(
            id: deviceID,
            displayName: "Stored inAi glasses",
            advertisedName: "Monocle",
            rawDataServiceSeen: true,
            nusServiceSeen: false
        )
        let model = DeviceConsoleModel(
            transport: MockMonocleTransport(devices: [device], maxWriteLength: 64),
            identityStore: store
        )

        model.reconnectStoredDevice()

        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertEqual(model.selectedDevice, device)
    }

    func testStoredIdentityMismatchBecomesWrongDeviceRisk() {
        let store = InMemoryDeviceIdentityStore()
        store.knownDeviceID = UUID()
        let visible = KnownDevice(
            id: UUID(),
            displayName: "Different inAi glasses",
            advertisedName: "Monocle",
            rawDataServiceSeen: true,
            nusServiceSeen: false
        )
        let model = DeviceConsoleModel(
            transport: MockMonocleTransport(devices: [visible], maxWriteLength: 64),
            identityStore: store
        )

        model.reconnectStoredDevice()

        XCTAssertEqual(model.connectionState, .wrongDeviceRisk)
    }

    func testRawDataAndNUSServicesAreClassifiedSeparately() {
        let classifier = MonocleServiceClassifier()

        XCTAssertEqual(classifier.role(for: MonocleBLEUUIDs.rawDataService), .runtimeRawData)
        XCTAssertEqual(classifier.role(for: MonocleBLEUUIDs.nusService), .recoveryNUS)
        XCTAssertEqual(classifier.role(for: "00000000-0000-0000-0000-000000000000"), .unrelated)
    }

    func testCoreBluetoothRestorationIdentifierIsStable() {
        XCTAssertEqual(MonocleBLERestoration.centralManagerIdentifier, "com.prismos.PrismOS.monocle.central")
        #if canImport(CoreBluetooth)
        XCTAssertFalse(MonocleBLERestoration.centralManagerOptions.isEmpty)
        #endif
    }

    func testStaticDrawUsesFramedRawDataPayloadWithWriteLengthSplitting() throws {
        let message = MonocleOutboundMessage.staticTextDraw(text: "PrismOS")

        let frames = try message.frames(maxWriteLength: 20)

        XCTAssertGreaterThan(frames.count, 1)
        XCTAssertEqual(Array(frames[0].prefix(5)), [0x50, 0x4D, 1, 0x05, 0x01])
        XCTAssertEqual(frames.last?[4], 0x02)
    }

    func testInboundControlNotificationsDecodeButtonAndMediaEvents() throws {
        let button = try Self.controlFrame(payload: #"{"event":"BTN","id":"R","gesture":"TAP","app":"vision","ts":1,"dur":92}"#)
        let media = try Self.controlFrame(payload: #"{"event":"MEDIA","kind":"AUDIO","status":"END","detail":"2","ts":2}"#)
        let model = DeviceConsoleModel(
            transport: MockMonocleTransport(),
            identityStore: InMemoryDeviceIdentityStore()
        )

        model.receiveNotification(button)
        model.receiveNotification(media)

        XCTAssertEqual(model.diagnostics[0].category, "MEDIA")
        XCTAssertEqual(model.diagnostics[1].category, "BTN")
    }

    func testInboundControlNotificationsStillAcceptLegacyTypeKey() throws {
        let button = try Self.controlFrame(payload: #"{"type":"BTN","button":"A"}"#)
        let media = try Self.controlFrame(payload: #"{"type":"MEDIA","state":"play"}"#)
        let model = DeviceConsoleModel(
            transport: MockMonocleTransport(),
            identityStore: InMemoryDeviceIdentityStore()
        )

        model.receiveNotification(button)
        model.receiveNotification(media)

        XCTAssertEqual(model.diagnostics[0].category, "MEDIA")
        XCTAssertEqual(model.diagnostics[1].category, "BTN")
    }

    private static func controlFrame(payload: String) throws -> Data {
        let message = MonocleOutboundMessage(kind: 0x01, messageID: 22, payload: Data(payload.utf8))
        return try XCTUnwrap(message.frames(maxWriteLength: 128).first)
    }
}

@MainActor
final class RuntimeConsoleModelTests: XCTestCase {
    func testRuntimeModelStartsInOrbitWithSixActiveApps() {
        let model = RuntimeConsoleModel()

        XCTAssertEqual(model.activeAppLabel, "Orbit")
        XCTAssertEqual(model.activeAppRows.map(\.appID), PrismAppID.allCases)
    }

    func testRuntimeModelFocusesAppAndInterceptsReservedGesture() {
        let model = RuntimeConsoleModel()

        model.focus(.oracle)
        model.sendReservedGesture()

        XCTAssertEqual(model.activeAppLabel, "Oracle")
        XCTAssertEqual(model.snapshot.diagnostics.first?.redactedMessage, "Reserved gesture intercepted")
    }

    func testRuntimePreviewUsesLatestHostDraw() {
        let model = RuntimeConsoleModel()

        XCTAssertEqual(model.previewViewport.appID, "orbit")

        model.focus(.vision)

        XCTAssertEqual(model.activeAppLabel, "Vision")
        XCTAssertEqual(model.previewViewport.appID, "vision")
        XCTAssertEqual(model.previewViewport, model.snapshot.latestDraw)

        model.exitToOrbit()

        XCTAssertEqual(model.previewViewport.appID, "orbit")
    }

    func testRuntimeModelPublishesHostChangesAndAcceptsWatchFocusWithoutEcho() {
        let model = RuntimeConsoleModel()
        var observedSurfaces: [RuntimeSurface] = []

        model.runtimeDidChange = { snapshot in
            observedSurfaces.append(snapshot.surface)
        }

        model.focus(.signal)

        XCTAssertEqual(model.activeAppLabel, "Signal")
        XCTAssertEqual(observedSurfaces, [.focused(.signal)])

        model.syncFromWatchSnapshot(
            WatchSnapshot.sample(
                activeSurface: .app(.vision),
                activeApp: .vision
            )
        )

        XCTAssertEqual(model.activeAppLabel, "Vision")
        XCTAssertEqual(model.previewViewport.appID, "vision")
        XCTAssertEqual(observedSurfaces, [.focused(.signal)])

        model.syncFromWatchSnapshot(
            WatchSnapshot.sample(
                activeSurface: .orbit,
                activeApp: .vision
            )
        )

        XCTAssertEqual(model.activeAppLabel, "Orbit")
        XCTAssertEqual(model.previewViewport.appID, "orbit")
        XCTAssertEqual(observedSurfaces, [.focused(.signal)])
    }
}

@MainActor
final class LocalConsoleModelTests: XCTestCase {
    func testLocalConsoleManagesChronosTeleprompterSignalAndClear() {
        let model = LocalConsoleModel()

        model.startChronos()
        model.nextScriptLine()
        model.toggleSignalPrivacy()
        model.teleprompterDraftTitle = "Launch"
        model.teleprompterDraftBody = "First line second line third line"
        model.setTeleprompterWordsPerMinute(200)
        model.importTeleprompterDraft()
        model.toggleScriptAuto()
        model.tickTeleprompter(now: Date().addingTimeInterval(2))
        model.signalDraftTitle = "Deploy"
        model.signalDraftBody = "Review build"
        model.signalDraftPriority = .important
        model.addSignalDraft()

        XCTAssertEqual(model.chronos.state.runState, .running)
        XCTAssertEqual(model.teleprompter.script.title, "Launch")
        XCTAssertEqual(model.teleprompter.script.wordsPerMinute, 200)
        XCTAssertGreaterThanOrEqual(model.teleprompter.script.currentIndex, 0)
        XCTAssertTrue(model.signal.privacyMode)
        XCTAssertTrue(model.signal.visibleCards.contains { $0.title == "Deploy" })

        model.clearLocalArtifacts()

        XCTAssertEqual(model.chronos.state.runState, .setup)
        XCTAssertTrue(model.teleprompter.script.chunks.isEmpty)
        XCTAssertTrue(model.signal.visibleCards.isEmpty)
    }

    func testLocalConsoleSyncHelpersMirrorHostState() {
        let model = LocalConsoleModel()
        let chronos = ChronosEngine(
            state: ChronosState(
                mode: .stopwatch,
                totalSeconds: 420,
                startedAt: Date().addingTimeInterval(-12),
                accumulatedSeconds: 42,
                runState: .running,
                pinned: true
            )
        )
        let teleprompter = TeleprompterEngine(
            script: TeleprompterEngine.importScript(
                title: "Interview",
                body: "Lead with the result, then the evidence, then the follow-up."
            )
        )

        model.updateChronos(chronos)
        model.updateTeleprompter(teleprompter)

        XCTAssertEqual(model.chronos.state.mode, .stopwatch)
        XCTAssertEqual(model.chronos.state.totalSeconds, 420)
        XCTAssertEqual(model.teleprompter.script.title, "Interview")
        XCTAssertTrue(model.sessionRows.joined(separator: " ").contains("Interview"))
    }

    func testLocalConsoleNotifiesHostSyncCallbacks() {
        let model = LocalConsoleModel()
        var chronosDidChange = false
        var teleprompterDidChange = false
        var signalDidChange = false

        model.chronosDidChange = { _ in
            chronosDidChange = true
        }
        model.teleprompterDidChange = { _ in
            teleprompterDidChange = true
        }
        model.signalDidChange = { _ in
            signalDidChange = true
        }

        model.toggleChronosPinned()
        model.nextScriptLine()
        model.toggleSignalPrivacy()

        XCTAssertTrue(chronosDidChange)
        XCTAssertTrue(teleprompterDidChange)
        XCTAssertTrue(signalDidChange)
    }

    func testLocalConsolePublishesChronosAlarmBoundary() {
        let model = LocalConsoleModel()

        model.startChronos()
        model.tickChronos(now: Date().addingTimeInterval(301))

        XCTAssertEqual(model.chronos.state.runState, .alarm)
        XCTAssertEqual(model.lastChronosAlert?.delivery, .notificationAndHaptic)
    }
}

@MainActor
final class ProviderConsoleModelTests: XCTestCase {
    func testProviderConsoleRunsOracleVisionAndBabelServiceFlows() async {
        let model = ProviderConsoleModel(aiClient: TestAIClient())

        model.oraclePrompt = "55 foot pounds"
        await model.askOracleNow()
        await model.captureVisionNow()
        model.babelText = "bonjour"
        await model.translateBabelTextNow()

        XCTAssertTrue(model.oracleRows.joined(separator: " ").contains("74.57"))
        XCTAssertTrue(model.visionRows.joined(separator: " ").contains("ESP32") || model.visionRows.joined(separator: " ").contains("TEXT"))
        XCTAssertTrue(model.babelRows.joined(separator: " ").contains("hello"))
    }

    func testProviderConsoleKeepsSaveAndControlActionsExplicit() async {
        let model = ProviderConsoleModel(aiClient: TestAIClient())

        await model.captureVisionNow()
        _ = model.saveVisionNote()
        await model.captureBabelAudioNow()
        model.toggleBabelFreeze()
        model.babelSourceLanguage = "es"
        model.babelTargetLanguage = "en"
        model.applyBabelLanguages()
        model.swapBabelLanguages()
        model.saveAndClearBabel()

        XCTAssertTrue(model.visionRows.joined(separator: " ").contains("SAVED"))
        XCTAssertTrue(model.babelRows.joined(separator: " ").contains("SAVED"))
    }

    func testProviderConsoleNotifiesVisionDidChange() async {
        let model = ProviderConsoleModel(aiClient: TestAIClient())
        var didChangeCount = 0

        model.visionDidChange = { _ in
            didChangeCount += 1
        }

        model.toggleVisionMode()
        await model.captureVisionNow()
        _ = model.saveVisionNote()
        _ = model.cancelVisionCapture()

        XCTAssertGreaterThan(didChangeCount, 0)
    }

    func testProviderConsoleOracleDidChangeFiresOnAskAndCancel() async {
        let model = ProviderConsoleModel(aiClient: TestAIClient())
        var didChangeCount = 0

        model.oracleDidChange = { _ in
            didChangeCount += 1
        }

        model.oraclePrompt = "What is tungsten?"
        await model.askOracleNow()

        XCTAssertGreaterThan(didChangeCount, 0)
        XCTAssertNotEqual(model.oracleRows.first, "Ready")

        model.cancelOracle()

        XCTAssertEqual(model.oracleRows.first, "Cancelled")
        XCTAssertGreaterThan(didChangeCount, 1)
    }
}

private struct TestAIClient: AIClient {
    func respond(to request: AIRequest) async throws -> AIResponse {
        let text = request.prompt.localizedCaseInsensitiveContains("55 foot") ? "74.57 Nm." : "Provider answer."
        return AIResponse(requestID: request.id, text: text, providerName: "test")
    }
}

@MainActor
final class ServiceConsoleModelTests: XCTestCase {
    func testInMemorySecretStoreBehavesLikeSecretStoreBoundary() throws {
        let store = InMemorySecretStore()

        try store.save("sk-test", for: "openai.api_key")

        XCTAssertEqual(try store.read("openai.api_key"), "sk-test")
        try store.delete("openai.api_key")
        XCTAssertThrowsError(try store.read("openai.api_key"))
    }

    func testKeychainSecretStoreWrapperStoresReadsAndDeletesAPIKey() throws {
        let store = KeychainSecretStore(
            service: "com.prismos.PrismOSTests.\(UUID().uuidString)",
            client: FakeKeychainClient()
        )
        let key = "openai.api_key"

        try store.save("sk-test", for: key)
        XCTAssertEqual(try store.read(key), "sk-test")
        try store.delete(key)
        XCTAssertThrowsError(try store.read(key))
    }

    func testServiceConsoleDoesNotExposeSecretsInDiagnosticsPreview() {
        let model = ServiceConsoleModel(secretStore: InMemorySecretStore())

        model.saveProviderKey("sk-secret")

        XCTAssertEqual(model.providerKeyStatus, .stored)
        XCTAssertTrue(model.diagnosticsPreview.joined(separator: "\n").contains("[REDACTED]"))
        XCTAssertFalse(model.diagnosticsPreview.joined(separator: "\n").contains("sk-secret"))
    }

    func testServiceConsoleCreatesRedactedDiagnosticsExport() {
        let model = ServiceConsoleModel(secretStore: InMemorySecretStore())

        model.createRedactedDiagnosticsExport()

        XCTAssertEqual(model.diagnosticsExportSummary, "Redacted export ready: 2 event(s)")
        XCTAssertTrue(model.diagnosticsPreview.joined(separator: "\n").contains("[REDACTED]"))
        XCTAssertFalse(model.diagnosticsPreview.joined(separator: "\n").contains("sk-preview"))
        XCTAssertFalse(model.diagnosticsRawMode)
    }

    func testServiceConsoleBuildsSanitizedOpenAIConfiguration() {
        let model = ServiceConsoleModel(secretStore: InMemorySecretStore())

        model.openAITextModelID = "  "
        model.openAIVisionModelID = "gpt-vision-test"
        model.openAITranslationModelID = "gpt-translate-test"
        model.openAITranscriptionModelID = "gpt-transcribe-test"
        model.openAIRealtimeSessionModelID = "gpt-realtime-test"
        model.openAIRealtimeTranscriptionDelay = "medium"
        model.openAIReasoningEffort = "minimal"
        model.openAITextVerbosity = "medium"
        model.openAIStoreResponses = true

        let configuration = model.openAIConfiguration()

        XCTAssertEqual(configuration.textModel, "gpt-5.5")
        XCTAssertEqual(configuration.visionModel, "gpt-vision-test")
        XCTAssertEqual(configuration.translationModel, "gpt-translate-test")
        XCTAssertEqual(configuration.transcriptionModel, "gpt-transcribe-test")
        XCTAssertEqual(configuration.realtimeSessionModel, "gpt-realtime-test")
        XCTAssertEqual(configuration.realtimeTranscriptionDelay, "medium")
        XCTAssertEqual(configuration.reasoningEffort, "minimal")
        XCTAssertEqual(configuration.textVerbosity, "medium")
        XCTAssertTrue(configuration.storeResponses)
    }

    func testOpenAIResponsesClientRequiresCloudApproval() async {
        let client = OpenAIResponsesClient(
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { false },
            transport: FakeHTTPTransport(
                data: #"{"output_text":"unreachable"}"#.data(using: .utf8)!,
                statusCode: 200
            )
        )

        do {
            _ = try await client.respond(to: AIRequest(prompt: "Summarize", requiresCloudApproval: true))
            XCTFail("Expected cloud approval failure")
        } catch {
            XCTAssertEqual(error as? ProviderError, .missingApproval)
        }
    }

    func testOpenAIResponsesClientRequiresStoredSecret() async {
        let client = OpenAIResponsesClient(
            apiKeyProvider: { "" },
            userApprovedCloudProcessing: { true },
            transport: FakeHTTPTransport(
                data: #"{"output_text":"unreachable"}"#.data(using: .utf8)!,
                statusCode: 200
            )
        )

        do {
            _ = try await client.respond(to: AIRequest(prompt: "Summarize"))
            XCTFail("Expected missing secret failure")
        } catch {
            XCTAssertEqual(error as? ProviderError, .missingSecret)
        }
    }

    func testOpenAIResponsesClientSendsResponsesRequestAndPreservesRequestID() async throws {
        let requestID = PrismRequestID()
        let transport = FakeHTTPTransport(
            data: #"{"output":[{"content":[{"type":"output_text","text":"Provider answer"}]}]}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = OpenAIResponsesClient(
            model: "gpt-test",
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            transport: transport
        )

        let response = try await client.respond(to: AIRequest(id: requestID, prompt: "Answer privately"))

        XCTAssertEqual(response.requestID, requestID)
        XCTAssertEqual(response.text, "Provider answer")
        XCTAssertEqual(response.providerName, "openai:gpt-test")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest?.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(transport.decodedBody?["model"] as? String, "gpt-test")
        XCTAssertEqual(transport.decodedBody?["input"] as? String, "Answer privately")
        XCTAssertEqual(transport.decodedBody?["store"] as? Bool, false)
        XCTAssertEqual((transport.decodedBody?["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual((transport.decodedBody?["text"] as? [String: Any])?["verbosity"] as? String, "low")
    }

    func testOpenAIResponsesClientMapsTimeoutAndOfflineFailures() async {
        let timedOut = OpenAIResponsesClient(
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            transport: FakeHTTPTransport(error: URLError(.timedOut))
        )
        let offline = OpenAIResponsesClient(
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            transport: FakeHTTPTransport(error: URLError(.notConnectedToInternet))
        )

        do {
            _ = try await timedOut.respond(to: AIRequest(prompt: "Summarize"))
            XCTFail("Expected timeout failure")
        } catch {
            XCTAssertEqual(error as? ProviderError, .timeout)
        }

        do {
            _ = try await offline.respond(to: AIRequest(prompt: "Summarize"))
            XCTFail("Expected offline failure")
        } catch {
            XCTAssertEqual(error as? ProviderError, .offline)
        }
    }

    func testOpenAIResponsesClientRejectsEmptyAndNonSuccessResponses() async {
        let empty = OpenAIResponsesClient(
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            transport: FakeHTTPTransport(
                data: #"{"output_text":""}"#.data(using: .utf8)!,
                statusCode: 200
            )
        )
        let rejected = OpenAIResponsesClient(
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            transport: FakeHTTPTransport(
                data: #"{"error":{"message":"bad request"}}"#.data(using: .utf8)!,
                statusCode: 400
            )
        )

        do {
            _ = try await empty.respond(to: AIRequest(prompt: "Summarize"))
            XCTFail("Expected provider rejection")
        } catch {
            XCTAssertEqual(error as? ProviderError, .providerRejected)
        }

        do {
            _ = try await rejected.respond(to: AIRequest(prompt: "Summarize"))
            XCTFail("Expected provider rejection")
        } catch {
            XCTAssertEqual(error as? ProviderError, .providerRejected)
        }
    }

    func testOpenAITranslationClientUsesResponsesWithTranslationModel() async throws {
        let requestID = PrismRequestID()
        let transport = FakeHTTPTransport(
            data: #"{"output_text":"hello"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = OpenAITranslationClient(
            configuration: OpenAIServiceConfiguration(translationModel: "gpt-translate-test"),
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            transport: transport
        )

        let result = try await client.translate(
            TranslationRequest(
                requestID: requestID,
                text: "bonjour",
                sourceLanguage: "fr",
                targetLanguage: "en"
            )
        )

        XCTAssertEqual(result.requestID, requestID)
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(transport.decodedBody?["model"] as? String, "gpt-translate-test")
        XCTAssertTrue((transport.decodedBody?["input"] as? String)?.contains("bonjour") == true)
    }

    func testOpenAIVisionProcessorSendsImageInput() async throws {
        let requestID = PrismRequestID()
        let transport = FakeHTTPTransport(
            data: #"{"output_text":"ESP32 status board"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let processor = OpenAIVisionProcessor(
            configuration: OpenAIServiceConfiguration(visionModel: "gpt-vision-test"),
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            transport: transport
        )

        let result = try await processor.recognizeText(
            in: VisionInput(requestID: requestID, jpegData: Data([0xff, 0xd8, 0xff, 0xd9]))
        )

        XCTAssertEqual(result.requestID, requestID)
        XCTAssertEqual(result.text, "ESP32 status board")
        XCTAssertEqual(result.confidence, 1)
        XCTAssertEqual(transport.decodedBody?["model"] as? String, "gpt-vision-test")
        let input = try XCTUnwrap(transport.decodedBody?["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertEqual(content.last?["type"] as? String, "input_image")
        XCTAssertTrue((content.last?["image_url"] as? String)?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    func testOpenAIAudioTranscriptionClientSendsMultipartWAV() async throws {
        let requestID = PrismRequestID()
        let transport = FakeHTTPTransport(
            data: #"{"text":"test transcript"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = OpenAIAudioTranscriptionClient(
            configuration: OpenAIServiceConfiguration(transcriptionModel: "gpt-transcribe-test"),
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            transport: transport
        )

        let result = try await client.transcribe(
            TranscriptionInput(requestID: requestID, pcm16MonoLittleEndian: Data([0, 0, 1, 0]), sampleRate: 16_000)
        )

        XCTAssertEqual(result.requestID, requestID)
        XCTAssertEqual(result.text, "test transcript")
        XCTAssertEqual(transport.lastRequest?.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertTrue(transport.lastRequest?.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
        XCTAssertNotNil(transport.bodyData.range(of: Data("name=\"model\"\r\n\r\ngpt-transcribe-test".utf8)))
        XCTAssertNotNil(transport.bodyData.range(of: Data("Content-Type: audio/wav".utf8)))
        XCTAssertNotNil(transport.bodyData.range(of: Data("RIFF".utf8)))
    }

    func testOpenAIAudioTranscriptionClientRejectsRealtimeModel() async throws {
        let client = OpenAIAudioTranscriptionClient(
            configuration: OpenAIServiceConfiguration(transcriptionModel: "gpt-realtime-whisper"),
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            transport: FakeHTTPTransport(
                data: #"{"text":"unreachable"}"#.data(using: .utf8)!,
                statusCode: 200
            )
        )

        do {
            _ = try await client.transcribe(
                TranscriptionInput(pcm16MonoLittleEndian: Data([0, 0, 1, 0]), sampleRate: 16_000)
            )
            XCTFail("Expected realtime model to be rejected by the Audio API client")
        } catch {
            XCTAssertEqual(error as? ProviderError, .unsupportedMode)
        }
    }

    func testOpenAIRealtimeWhisperTranscriptionClientStreamsSessionEvents() async throws {
        let requestID = PrismRequestID()
        let socket = FakeRealtimeWebSocket(receiveMessages: [
            #"{"type":"session.updated"}"#,
            #"{"type":"conversation.item.input_audio_transcription.delta","delta":"bonjour"}"#,
            #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"bonjour le monde"}"#
        ])
        let factory = FakeRealtimeWebSocketFactory(socket: socket)
        let client = OpenAIRealtimeWhisperTranscriptionClient(
            configuration: OpenAIServiceConfiguration(
                transcriptionModel: "gpt-realtime-whisper",
                realtimeSessionModel: "gpt-realtime-2",
                realtimeTranscriptionDelay: "minimal"
            ),
            timeout: 1,
            apiKeyProvider: { "sk-test" },
            userApprovedCloudProcessing: { true },
            webSocketFactory: factory
        )

        let result = try await client.transcribe(
            TranscriptionInput(
                requestID: requestID,
                pcm16MonoLittleEndian: Data([0, 0, 1, 0]),
                sampleRate: 8_000,
                language: "fr"
            )
        )

        XCTAssertEqual(result.requestID, requestID)
        XCTAssertEqual(result.text, "bonjour le monde")
        XCTAssertEqual(factory.lastRequest?.url?.absoluteString, "wss://api.openai.com/v1/realtime?model=gpt-realtime-2")
        XCTAssertEqual(factory.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(factory.lastRequest?.value(forHTTPHeaderField: "OpenAI-Safety-Identifier"), "prismos-ios-babel")

        let sentEvents = socket.sentBodies.compactMap { body in
            try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        }
        XCTAssertEqual(sentEvents.count, 3)
        XCTAssertEqual(sentEvents[0]["type"] as? String, "session.update")
        let session = try XCTUnwrap(sentEvents[0]["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "realtime")
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24_000)
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-realtime-whisper")
        XCTAssertEqual(transcription["language"] as? String, "fr")
        XCTAssertEqual(transcription["delay"] as? String, "minimal")

        XCTAssertEqual(sentEvents[1]["type"] as? String, "input_audio_buffer.append")
        let audioBase64 = try XCTUnwrap(sentEvents[1]["audio"] as? String)
        XCTAssertEqual(Data(base64Encoded: audioBase64)?.count, 12)
        XCTAssertEqual(sentEvents[2]["type"] as? String, "input_audio_buffer.commit")
    }
}

private struct RecoveryTransport: MonocleTransport {
    var device: KnownDevice

    func scanForRawDataDevices(knownDeviceID: UUID?) -> [KnownDevice] {
        [device]
    }

    func connect(to device: KnownDevice) -> MonocleConnectionResult {
        MonocleConnectionResult(
            state: .recoveryOnly,
            rawDataAvailable: false,
            nusAvailable: true,
            maxWriteLength: 64,
            message: "NUS recovery visible; normal runtime disabled"
        )
    }

    func send(_ message: MonocleOutboundMessage, maxWriteLength: Int) throws -> MonocleWriteResult {
        throw MonocleTransportError.writeInProgress
    }

    func ingestNotification(_ data: Data) throws -> MonocleInboundEvent? {
        nil
    }
}

private final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let data: Data
    private let statusCode: Int
    private let error: Error?
    private(set) var lastRequest: URLRequest?
    private(set) var decodedBody: [String: Any]?
    private(set) var bodyData = Data()

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
        self.error = nil
    }

    init(error: Error) {
        self.data = Data()
        self.statusCode = 0
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error {
            throw error
        }
        lastRequest = request
        if let httpBody = request.httpBody {
            bodyData = httpBody
            decodedBody = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private final class FakeRealtimeWebSocket: RealtimeWebSocket, @unchecked Sendable {
    private let queue = DispatchQueue(label: "FakeRealtimeWebSocket")
    private var receiveMessages: [String]
    private var storedSentBodies: [String] = []
    private var storedDidCancel = false

    var sentBodies: [String] {
        queue.sync {
            storedSentBodies
        }
    }

    var didCancel: Bool {
        queue.sync {
            storedDidCancel
        }
    }

    init(receiveMessages: [String]) {
        self.receiveMessages = receiveMessages
    }

    func sendString(_ text: String) async throws {
        queue.sync {
            storedSentBodies.append(text)
        }
    }

    func receiveString() async throws -> String {
        try queue.sync {
            guard !receiveMessages.isEmpty else {
                throw ProviderError.providerRejected
            }
            return receiveMessages.removeFirst()
        }
    }

    func cancel() {
        queue.sync {
            storedDidCancel = true
        }
    }
}

private final class FakeRealtimeWebSocketFactory: RealtimeWebSocketFactory, @unchecked Sendable {
    private let socket: FakeRealtimeWebSocket
    private(set) var lastRequest: URLRequest?

    init(socket: FakeRealtimeWebSocket) {
        self.socket = socket
    }

    func makeWebSocket(request: URLRequest) -> RealtimeWebSocket {
        lastRequest = request
        return socket
    }
}
