import SwiftUI
import Combine
import WatchConnectivity
import PrismShell
import PrismAI

@MainActor
final class ShellHostModel: ObservableObject {
    let preferences: UserDefaults
    let link: CoreBluetoothMonocleAdapter
    let native: EventKitShellTools
    let voice: NativeShellVoice
    let timerNotifications = NativeTimerNotifications()
    @Published private(set) var engine: AssistantOrchestrator?
    @Published private(set) var startupError: String?
    private var watch: ShellPhoneWatchBridge?
    private var timer: Timer?
    private var linkObservation: AnyCancellable?
    private var lastContextRefresh = Date.distantPast
    private var refreshing = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let secrets = KeychainSecretStore()
    init() {
        #if DEBUG
        let acceptance = ShellAcceptanceConfiguration.fromEnvironment()
        preferences = acceptance?.preferences ?? .standard
        #else
        preferences = .standard
        #endif
        link = CoreBluetoothMonocleAdapter(defaults: preferences); native = EventKitShellTools(); voice = NativeShellVoice()
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            var libraryURL = directory.appendingPathComponent("PrismShell/library-v1.json")
            #if DEBUG
            if acceptance != nil { timerNotifications.enabled = false }
            if let acceptance { libraryURL = directory.appendingPathComponent("PrismAcceptance/" + acceptance.id.uuidString + "/library-v1.json") }
            #endif
            let repository = FileShellRepository(url: libraryURL)
            let secretStore = secrets
            var model = ResponsesExperienceModel(model: OpenAIServiceConfiguration.defaultTextModel, apiKey: { try secretStore.read("openai.api_key") })
            var effects: any NativeToolBoundary = native
            var output: any ShellVoiceOutput = voice
            #if DEBUG
            if let acceptance {
                model = ResponsesExperienceModel(model: "acceptance-fixture", apiKey: { "fixture-not-a-credential" }, transport: ShellAcceptanceHTTP(plans: acceptance.plans))
                effects = ShellAcceptanceOS(); output = ShellAcceptanceVoice()
            }
            #endif
            let runtime = try AssistantOrchestrator(repository: repository, model: model, native: effects, link: link, voice: output)
            engine = runtime
            Task { await timerNotifications.synchronize(runtime.archive.timer) }
            watch = ShellPhoneWatchBridge(engine: runtime)
            runtime.onChange = { [weak self] in
                self?.objectWillChange.send(); self?.watch?.publish(); self?.syncBackgroundLease()
                if let self { Task { await self.timerNotifications.synchronize(self.engine?.archive.timer) } }
            }
            link.onConnection = { [weak runtime] connected in runtime?.setConnection(connected) }
            link.onGesture = { [weak self] side, gesture in self?.gesture(side: side, gesture: gesture) }
            link.onAudio = { [weak self] id, bytes in
                guard let self, let runtime = self.engine else { return }
                // The current bounded production path uses file transcription, not a subscription session.
                let secretStore = self.secrets
                let transcription = OpenAIAudioTranscriptionClient(
                    configuration: OpenAIServiceConfiguration(transcriptionModel: "gpt-transcribe"),
                    apiKeyProvider: { try secretStore.read("openai.api_key") }, userApprovedCloudProcessing: { true })
                runtime.receiveAudio(bytes, requestID: id, speech: transcription)
            }
            link.onError = { [weak runtime] error in runtime?.clear(); runtime?.showError(error) }
            voice.onChange = { [weak self] in self?.objectWillChange.send() }
            voice.onInterrupted = { [weak self] in self?.objectWillChange.send() }
            linkObservation = link.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }; self.engine?.tick(); self.syncBackgroundLease()
                    if Date().timeIntervalSince(self.lastContextRefresh) >= 60 && UIApplication.shared.applicationState == .active {
                        await self.refreshSources()
                    }
                }
            }
        } catch {
            // Do not replace corrupt/inaccessible canonical storage with an empty Library.
            startupError = "The Library could not be opened. Its original file has been preserved. \(error.localizedDescription)"
        }
    }
    func refreshSources() async {
        guard !refreshing, let engine else { return }
        refreshing = true; defer { refreshing = false }
        lastContextRefresh = Date(); await engine.refreshContext(); await engine.considerProactivity()
    }
    func gesture(side: String, gesture: String) {
        guard let engine else { return }
        perform { try await engine.handleGesture(side: side, gesture: gesture) }
    }

    func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation() } catch { engine?.showError(error) }; syncBackgroundLease() }
    }
    private func syncBackgroundLease() {
        let busy = engine?.activeRequestID != nil || engine?.isExecutingAction == true
        if busy && backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Prism user interaction") { [weak self] in
                Task { @MainActor in
                    self?.engine?.clear()
                    if let self, self.backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(self.backgroundTask); self.backgroundTask = .invalid }
                }
            }
        } else if !busy && backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid
        }
    }
    func setPrivacy(_ edit: (inout PrivacySettings) -> Void) {
        guard let engine else { return }; var p = engine.archive.privacy; edit(&p)
        do { try engine.updatePrivacy(p) } catch { engine.showError(error) }
    }
    func saveKey(_ key: String) -> Bool {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { engine?.showError(ShellError.invalid("Enter a non-empty API key")); return false }
        do { try secrets.save(value, for: "openai.api_key"); return true } catch { engine?.showError(error); return false }
    }
    func removeKey() { do { try secrets.delete("openai.api_key") } catch { engine?.showError(error) } }
    func configureAgent(endpoint: String, token: String) throws {
        guard let url = URL(string: endpoint), url.scheme == "https", url.user == nil, url.password == nil else { throw ShellError.invalid("Use an HTTPS gateway address without embedded credentials") }
        try secrets.save(token, for: "prism.agent.token"); UserDefaults.standard.set(endpoint, forKey: "prism.agent.endpoint"); native.agentEndpoint = url
    }
}

@MainActor
final class ShellPhoneWatchBridge: NSObject, WCSessionDelegate {
    private weak var engine: AssistantOrchestrator?
    private let session = WCSession.default
    init(engine: AssistantOrchestrator, activate: Bool = true) {
        self.engine = engine; super.init()
        if activate && WCSession.isSupported() { session.delegate = self; session.activate() }
    }
    func publish() {
        guard session.activationState == .activated, let engine,
              let data = try? ShellJSON.encoder().encode(engine.watchSnapshot) else { return }
        do { try session.updateApplicationContext(["prism.shell.snapshot": data]) } catch { /* Latest state is resent on reachability/activation. */ }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.publish() } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["prism.shell.refresh"] as? Bool == true {
            Task { @MainActor in
                if let engine = self.engine, let data = try? ShellJSON.encoder().encode(engine.watchSnapshot) { replyHandler(["prism.shell.snapshot": data]) }
                else { replyHandler(["error": "Phone state unavailable"]) }
            }; return
        }
        guard let data = message["prism.shell.command"] as? Data, data.count <= 8192 else { replyHandler(["error": "Invalid command"]); return }
        Task { @MainActor in
            do {
                guard let engine = self.engine else { throw ShellError.unavailable("Phone is unavailable") }
                let command = try ShellJSON.decoder().decode(ShellWatchCommand.self, from: data)
                try await engine.processWatch(command)
                replyHandler(["prism.shell.snapshot": try ShellJSON.encoder().encode(engine.watchSnapshot)])
            } catch { replyHandler(["error": error.localizedDescription]); self.publish() }
        }
    }
}
