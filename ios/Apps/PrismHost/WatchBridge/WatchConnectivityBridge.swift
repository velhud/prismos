import Foundation
import UIKit
import WatchConnectivity
import PrismRuntime
import PrismWatchModels

private final class WatchConnectivitySessionAdapter: WatchBridgeSessioning {
    private let session: WCSession

    init(session: WCSession) {
        self.session = session
    }

    var isReachable: Bool {
        session.isReachable
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        try session.updateApplicationContext(applicationContext)
    }

    func transferUserInfo(_ userInfo: [String : Any]) {
        _ = session.transferUserInfo(userInfo)
    }
}

@MainActor
final class WatchConnectivityBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var lastErrorMessage: String?

    private let session: WCSession
    private let bridge: PhoneWatchBridge
    private weak var runtimeModel: RuntimeConsoleModel?
    private weak var providerModel: ProviderConsoleModel?

    init(
        runtimeModel: RuntimeConsoleModel? = nil,
        localModel: LocalConsoleModel? = nil,
        providerModel: ProviderConsoleModel? = nil,
        coordinator: AppCoordinatorCore = AppCoordinatorCore(),
        state: WatchBridgeState = WatchBridgeState()
    ) {
        let session = WCSession.default
        let sessionAdapter = WatchConnectivitySessionAdapter(session: session)
        var bridgeState = state
        self.runtimeModel = runtimeModel
        self.providerModel = providerModel
        if let providerModel {
            bridgeState.babel = PhoneWatchBridge.watchBabelState(
                for: providerModel.babel,
                now: Date(),
                privacyMode: state.privacyMode
            )
            bridgeState.vision = PhoneWatchBridge.watchVisionState(
                for: providerModel.vision,
                now: Date(),
                privacyMode: state.privacyMode
            )
            bridgeState.oracle = PhoneWatchBridge.watchOracleState(
                for: providerModel.oracle,
                now: Date(),
                privacyMode: state.privacyMode
            )
            bridgeState.captureActive = bridgeState.vision?.isBusy == true || bridgeState.oracle?.phase.isBusy == true
        }
        self.session = session
        self.bridge = PhoneWatchBridge(
            session: sessionAdapter,
            coordinator: coordinator,
            state: bridgeState,
            chronos: localModel.map { $0.chronos } ?? ChronosEngine(),
            teleprompter: localModel.map { $0.teleprompter } ?? TeleprompterEngine(
                script: TeleprompterEngine.importScript(
                    title: "Demo Script",
                    body: "Welcome to PrismOS. Keep eye contact while the Host advances concise chunks."
                )
            ),
            signal: localModel.map { $0.signal } ?? SignalStack(
                cards: [
                    SignalCard(source: "PRISM", title: "Prism", body: "Sync Done", priority: .info),
                    SignalCard(source: "SYS", title: "Battery", body: "Low", priority: .critical)
                ]
            ),
            babel: providerModel?.babel ?? BabelEngine(),
            vision: providerModel?.vision ?? VisionEngine(),
            oracle: providerModel?.oracle ?? OracleEngine(),
            stateDidChange: { [weak localModel] chronos, teleprompter, signal in
                localModel?.updateChronos(chronos)
                localModel?.updateTeleprompter(teleprompter)
                localModel?.updateSignal(signal)
            },
            babelCommandHandler: { [weak providerModel] action in
                guard let providerModel else {
                    return BabelCommandResult(status: .rejected, reason: "Babel unavailable")
                }

                switch action {
                case .toggleFreeze:
                    providerModel.toggleBabelFreeze()
                    return BabelCommandResult(
                        status: .applied,
                        reason: providerModel.babel.frozen ? "Frozen" : "Resumed",
                        babel: providerModel.babel
                    )
                case .swapLanguages:
                    providerModel.swapBabelLanguages()
                    return BabelCommandResult(
                        status: .applied,
                        reason: providerModel.babel.sourceLanguage.uppercased() + " -> " + providerModel.babel.targetLanguage.uppercased(),
                        babel: providerModel.babel
                    )
                case let .selectPreset(preset):
                    providerModel.applyBabelPreset(preset)
                    return BabelCommandResult(
                        status: .applied,
                        reason: preset.displayTitle,
                        babel: providerModel.babel
                    )
                case .clearTranscript:
                    _ = providerModel.clearBabelTranscript()
                    return BabelCommandResult(
                        status: .applied,
                        reason: "Cleared",
                        babel: providerModel.babel
                    )
                case .saveTranscript:
                    let saved = providerModel.saveBabelTranscript()
                    return BabelCommandResult(
                        status: saved ? .applied : .rejected,
                        reason: saved ? "Saved" : (providerModel.babel.lines.last?.text == "EMPTY" ? "Empty transcript" : "Unavailable"),
                        babel: providerModel.babel
                    )
                case .repeatLast:
                    let repeated = providerModel.repeatBabelLast()
                    return BabelCommandResult(
                        status: repeated ? .applied : .rejected,
                        reason: repeated ? "Repeat last" : (providerModel.babel.lines.last?.text == "BUSY DROP" ? "Busy" : "No history"),
                        babel: providerModel.babel
                    )
                }
            }
        )
        super.init()
        bridge.setRuntimeEffectHandler { [weak self] effect in
            self?.handleRuntimeEffect(effect)
        }

        if let localModel {
            localModel.chronosDidChange = { [weak self] chronos in
                self?.syncChronosFromLocalModel(chronos.state)
            }
            localModel.teleprompterDidChange = { [weak self] teleprompter in
                self?.syncTeleprompterFromLocalModel(teleprompter.script)
            }
            localModel.signalDidChange = { [weak self] signal in
                self?.syncSignalFromLocalModel(signal)
            }
        }

        if let runtimeModel {
            runtimeModel.runtimeDidChange = { [weak self] snapshot in
                self?.syncRuntimeFromRuntimeModel(snapshot)
            }
        }

        if let providerModel {
            providerModel.oracleDidChange = { [weak self] oracle in
                self?.syncOracleFromProviderModel(oracle)
            }
            providerModel.babelDidChange = { [weak self] babel in
                self?.syncBabelFromProviderModel(babel)
            }
            providerModel.visionDidChange = { [weak self] vision in
                self?.syncVisionFromProviderModel(vision)
            }
        }

        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        isReachable = session.isReachable
        activationState = session.activationState
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let isReachable = session.isReachable
        let lastErrorMessage = error?.localizedDescription

        Task { @MainActor in
            self.activationState = activationState
            self.isReachable = isReachable
            self.lastErrorMessage = lastErrorMessage

            if error == nil {
                _ = try? self.bridge.publishSnapshot()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable

        Task { @MainActor in
            self.isReachable = isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        do {
            let command = try WatchBridgeWireCodec.decodeCommand(message)
            Task { @MainActor in
                do {
                    _ = try self.bridge.receiveReachableCommand(command, replyHandler: replyHandler)
                    self.syncRuntimeModelFromBridge()
                } catch {
                    replyHandler(["error": error.localizedDescription])
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        } catch {
            replyHandler(["error": error.localizedDescription])
            Task { @MainActor in
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        do {
            let command = try WatchBridgeWireCodec.decodeQueuedCommand(userInfo)
            Task { @MainActor in
                do {
                    _ = try self.bridge.receiveQueuedCommand(command)
                    self.syncRuntimeModelFromBridge()
                } catch {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        } catch {
            Task { @MainActor in
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.lastErrorMessage = nil
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    private func syncChronosFromLocalModel(_ state: ChronosState) {
        guard bridge.chronosSnapshot != state else { return }
        do {
            try bridge.updateChronos(ChronosEngine(state: state))
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func syncRuntimeFromRuntimeModel(_ snapshot: RuntimeSnapshot) {
        do {
            try bridge.updateRuntimeSurface(snapshot.surface)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func syncRuntimeModelFromBridge() {
        runtimeModel?.syncFromWatchSnapshot(bridge.latestSnapshot)
    }

    private func syncTeleprompterFromLocalModel(_ script: TeleprompterScript) {
        guard bridge.teleprompterSnapshot != script else { return }
        do {
            try bridge.updateTeleprompter(TeleprompterEngine(script: script))
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func syncSignalFromLocalModel(_ signal: SignalStack) {
        guard bridge.signalSnapshot != signal else { return }
        do {
            try bridge.updateSignal(signal)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func syncBabelFromProviderModel(_ babel: BabelEngine) {
        guard bridge.babelSnapshot != babel else { return }
        do {
            try bridge.updateBabel(babel)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func syncVisionFromProviderModel(_ vision: VisionEngine) {
        guard bridge.visionSnapshot != vision else { return }
        do {
            try bridge.updateVision(vision)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func syncOracleFromProviderModel(_ oracle: OracleEngine) {
        guard bridge.oracleSnapshot != oracle else { return }
        do {
            try bridge.updateOracle(oracle)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleRuntimeEffect(_ effect: RuntimeEffect) {
        switch effect {
            case let .openHandoff(urlString):
                guard let url = URL(string: urlString) else {
                lastErrorMessage = "Invalid handoff URL"
                return
            }
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                if !success {
                    self?.lastErrorMessage = "Handoff unavailable"
                }
            }
        case let .captureAudio(appID, _):
            switch appID {
            case .oracle:
                providerModel?.startOracleVoiceMock()
            case .babel:
                providerModel?.captureBabelAudioMock()
            case .vision, .chronos, .teleprompter, .signal:
                break
            }
        case .captureImage:
            providerModel?.captureVisionMock()
        case let .callOracle(prompt, _):
            providerModel?.oraclePrompt = prompt
            providerModel?.askOracle()
        case .translateText:
            break
        case .saveVisionNote:
            _ = providerModel?.saveVisionNote()
        case let .copyToClipboard(text):
            UIPasteboard.general.string = text
        case .scheduleNotification, .sendDrawNow, .sendOrbitDrawNow, .logDiagnostics:
            break
        }
    }
}
