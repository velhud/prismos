import Foundation
import WatchConnectivity
import PrismWatchModels

@MainActor
final class WatchConnectivityClient: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: WatchSnapshot
    @Published private(set) var lastAcknowledgement: WatchAcknowledgement?
    @Published private(set) var pendingCommands: [WatchCommand]
    @Published private(set) var transportReachable: Bool
    @Published private(set) var activationState: WCSessionActivationState
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var selectedAppID: PrismAppID

    private var sessionModel: WatchSessionModel
    private var lastDeliveredAcknowledgementID: UUID?
    private let session: WCSession
    private let haptics: WatchHaptics

    init(
        snapshot initialSnapshot: WatchSnapshot? = nil,
        transportReachable: Bool = false,
        activateSession: Bool = true
    ) {
        let debug = Self.debugLaunchConfiguration()
        let snapshot = initialSnapshot ?? Self.makeDefaultSnapshot(debug: debug)
        self.sessionModel = WatchSessionModel(snapshot: snapshot)
        self.session = WCSession.default
        self.haptics = WatchHaptics()
        self.snapshot = snapshot
        self.lastAcknowledgement = snapshot.lastAcknowledgement
        self.pendingCommands = []
        self.transportReachable = transportReachable
        self.activationState = activateSession ? .notActivated : .activated
        self.lastErrorMessage = snapshot.lastAcknowledgement?.reason ?? debug.lastErrorMessage
        self.selectedAppID = snapshot.activeApp?.appID ?? .oracle
        self.lastDeliveredAcknowledgementID = snapshot.lastAcknowledgement?.commandID
        super.init()
        syncFromModel()

        if debug.disableSession {
            self.transportReachable = debug.transportReachable ?? transportReachable
            activationState = .activated
            return
        }

        guard activateSession, WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        self.transportReachable = session.isReachable
        activationState = session.activationState
    }

    private static func makeDefaultSnapshot(debug: WatchDebugLaunchConfiguration = WatchDebugLaunchConfiguration()) -> WatchSnapshot {
        let activeApp = launchSelectedAppID() ?? .oracle
        let acknowledgement: WatchAcknowledgement? = debug.acknowledgement
        return WatchSnapshot.sample(
            activeSurface: .orbit,
            connection: debug.connection ?? .phone,
            privacyMode: debug.privacyMode,
            captureActive: debug.captureActive,
            wrongDeviceRisk: debug.wrongDeviceRisk,
            activeApp: activeApp,
            acknowledgement: acknowledgement
        )
    }

    private struct WatchDebugLaunchConfiguration {
        var connection: ConnectionState? = nil
        var privacyMode: Bool = false
        var captureActive: Bool = false
        var wrongDeviceRisk: Bool = false
        var disableSession: Bool = false
        var transportReachable: Bool? = nil
        var lastErrorMessage: String? = nil
        var acknowledgement: WatchAcknowledgement? = nil
    }

    private static func debugLaunchConfiguration() -> WatchDebugLaunchConfiguration {
        let environment = ProcessInfo.processInfo.environment
        var config = WatchDebugLaunchConfiguration()
        config.connection = environment["PRISMOS_WATCH_DEBUG_CONNECTION"].flatMap { ConnectionState(rawValue: $0.lowercased()) }
        config.privacyMode = parseBool(environment["PRISMOS_WATCH_DEBUG_PRIVACY_MODE"])
        config.captureActive = parseBool(environment["PRISMOS_WATCH_DEBUG_CAPTURE_ACTIVE"])
        config.wrongDeviceRisk = parseBool(environment["PRISMOS_WATCH_DEBUG_WRONG_DEVICE_RISK"])
        config.disableSession = parseBool(environment["PRISMOS_WATCH_DEBUG_DISABLE_SESSION"])
        config.transportReachable = environment["PRISMOS_WATCH_DEBUG_TRANSPORT_REACHABLE"].map(parseBool)
        config.lastErrorMessage = environment["PRISMOS_WATCH_DEBUG_LAST_ERROR"]
        if let rawStatus = environment["PRISMOS_WATCH_DEBUG_ACK_STATUS"], let status = WatchCommandStatus(rawValue: rawStatus.lowercased()) {
            config.acknowledgement = WatchAcknowledgement(
                commandID: UUID(),
                status: status,
                reason: environment["PRISMOS_WATCH_DEBUG_ACK_REASON"],
                snapshotVersion: 1
            )
        }
        return config
    }

    private static func parseBool(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func launchSelectedAppID() -> PrismAppID? {
        let process = ProcessInfo.processInfo
        if let explicit = process.environment["PRISMOS_WATCH_SELECTED_APP"], let appID = PrismAppID(rawValue: explicit.lowercased()) {
            return appID
        }

        let arguments = process.arguments
        if let flagIndex = arguments.firstIndex(of: "-PRISMOS_WATCH_SELECTED_APP"), flagIndex + 1 < arguments.endIndex {
            let rawValue = arguments[arguments.index(after: flagIndex)].lowercased()
            return PrismAppID(rawValue: rawValue)
        }

        if let flagIndex = arguments.firstIndex(of: "-watchSelectedApp"), flagIndex + 1 < arguments.endIndex {
            let rawValue = arguments[arguments.index(after: flagIndex)].lowercased()
            return PrismAppID(rawValue: rawValue)
        }

        return nil
    }

    var canRefresh: Bool {
        activationState == .activated && transportReachable
    }

    var canIssueCommands: Bool {
        canRefresh && snapshot.connection.isReachable && !snapshot.wrongDeviceRisk
    }

    func selectApp(_ appID: PrismAppID) {
        guard selectedAppID != appID else { return }
        selectedAppID = appID
    }

    func focusSelectedApp() {
        issue(.focusApp(selectedAppID))
    }

    func refreshSnapshot() {
        issue(.refreshSnapshot)
    }

    func togglePrivacy() {
        issue(.togglePrivacy(!snapshot.privacyMode))
    }

    func startPauseResumeChronos() {
        issue(.chronos(.startPauseResume))
    }

    func resetChronos() {
        issue(.chronos(.reset))
    }

    func dismissChronosAlarm() {
        issue(.chronos(.dismissAlarm))
    }

    func toggleChronosMode() {
        issue(.chronos(.toggleMode))
    }

    func toggleChronosPin() {
        issue(.chronos(.togglePin))
    }

    func adjustChronosDuration(by seconds: Int) {
        issue(.chronos(.adjustDuration(seconds)))
    }

    func addChronosTime(_ seconds: Int) {
        issue(.chronos(.addTime(seconds)))
    }

    func applyChronosPreset(seconds: Int) {
        issue(.chronos(.applyPreset(seconds)))
    }

    func teleprompterNextLine() {
        issue(.teleprompter(.nextLine))
    }

    func teleprompterPreviousLine() {
        issue(.teleprompter(.previousLine))
    }

    func toggleTeleprompterPlayPause() {
        issue(.teleprompter(.togglePlayPause))
    }

    func adjustTeleprompterLine(by delta: Int) {
        guard delta != 0 else { return }
        issue(.teleprompter(.adjustLine(delta)))
    }

    func adjustTeleprompterWordsPerMinute(by delta: Int) {
        guard delta != 0 else { return }
        issue(.teleprompter(.adjustWordsPerMinute(delta)))
    }

    func bookmarkTeleprompter() {
        issue(.teleprompter(.bookmark))
    }

    func resetTeleprompter() {
        issue(.teleprompter(.startOver))
    }

    func dismissSignalCard() {
        issue(.signal(.dismiss))
    }

    func moveSignalCardForward() {
        issue(.signal(.next))
    }

    func moveSignalCardBackward() {
        issue(.signal(.previous))
    }

    func openSignalHandoff() {
        issue(.signal(.openHandoff))
    }

    func reloadSignalStack() {
        issue(.signal(.reload))
    }

    func toggleSignalPrivacy() {
        issue(.signal(.togglePrivacy))
    }

    func toggleBabelFreeze() {
        issue(.babel(.toggleFreeze))
    }

    func swapBabelLanguages() {
        issue(.babel(.swapLanguages))
    }

    func selectBabelPreset(_ preset: WatchBabelPreset) {
        issue(.babel(.selectPreset(preset)))
    }

    func saveBabelTranscript() {
        issue(.babel(.saveTranscript))
    }

    func clearBabelTranscript() {
        issue(.babel(.clearTranscript))
    }

    func repeatBabelLast() {
        issue(.babel(.repeatLast))
    }

    func oraclePrimaryAction() {
        if snapshot.oracle?.phase == .answer {
            followUpOracle()
        } else {
            askOracle()
        }
    }

    func oracleSecondaryAction() {
        if snapshot.oracle?.phase == .answer {
            toggleOracleKeep()
        } else {
            clearOracle()
        }
    }

    func askOracle() {
        issue(.oracle(.ask))
    }

    func followUpOracle() {
        issue(.oracle(.followUp))
    }

    func clearOracle() {
        issue(.oracle(.clear))
    }

    func toggleOracleKeep() {
        issue(.oracle(.toggleKeep))
    }

    func copyOracleAnswer() {
        issue(.oracle(.copy))
    }

    func makeOracleShorter() {
        issue(.oracle(.shorter))
    }

    func makeOracleMoreDetailed() {
        issue(.oracle(.moreDetail))
    }

    func adjustOraclePage(by delta: Int) {
        guard delta != 0 else { return }
        issue(.oracle(.adjustPage(delta)))
    }

    func captureVision() {
        issue(.vision(.capture))
    }

    func retakeVision() {
        issue(.vision(.retake))
    }

    func toggleVisionMode() {
        issue(.vision(.toggleMode))
    }

    func cancelVisionCapture() {
        issue(.vision(.cancel))
    }

    func saveVisionNote() {
        issue(.vision(.saveNote))
    }

    func askVisionOracle() {
        issue(.vision(.askOracle))
    }

    private func issue(_ action: WatchUIAction) {
        do {
            guard let command = try sessionModel.issue(action) else {
                return
            }
            transmit(command)
        } catch let validationError as WatchCommandValidationError {
            handleValidationFailure(validationError)
        } catch {
            lastErrorMessage = error.localizedDescription
            haptics.play(.failure)
        }
    }

    private func deliverAcknowledgementIfNeeded(_ acknowledgement: WatchAcknowledgement?) {
        guard let acknowledgement else { return }
        guard lastDeliveredAcknowledgementID != acknowledgement.commandID else { return }
        lastDeliveredAcknowledgementID = acknowledgement.commandID
        haptics.play(acknowledgement.haptic)
        if acknowledgement.status == .rejected || acknowledgement.status == .stale {
            lastErrorMessage = acknowledgement.reason
        } else {
            lastErrorMessage = nil
        }
    }

    private func transmit(_ command: WatchCommand) {
        guard activationState == .activated else {
            handleLocalFailure(command, reason: "Session not activated")
            return
        }

        if session.isReachable {
            do {
                let payload = try WatchBridgeWireCodec.encodeCommand(command)
                session.sendMessage(
                    payload,
                    replyHandler: { [weak self] reply in
                        Task { @MainActor in
                            self?.handleReply(reply, for: command)
                        }
                    },
                    errorHandler: { [weak self] error in
                        Task { @MainActor in
                            self?.handleSendError(error, for: command)
                        }
                    }
                )
                return
            } catch {
                handleLocalFailure(command, reason: error.localizedDescription)
                return
            }
        }

        if command.kind.isQueueEligible {
            do {
                let payload = try WatchBridgeWireCodec.encodeQueuedCommand(command)
                session.transferUserInfo(payload)
                let queued = WatchAcknowledgement(
                    commandID: command.id,
                    status: .queued,
                    reason: "Queued for host",
                    snapshotVersion: command.snapshotVersion
                )
                sessionModel.record(queued, removePending: false)
                syncFromModel()
                haptics.play(.warning)
                lastErrorMessage = nil
            } catch {
                handleLocalFailure(command, reason: error.localizedDescription)
            }
            return
        }

        handleLocalFailure(command, reason: "Phone unreachable")
    }

    private func handleReply(_ reply: [String: Any], for command: WatchCommand) {
        if let acknowledgement = try? WatchBridgeWireCodec.decodeAcknowledgement(reply) {
            sessionModel.record(acknowledgement)
            syncFromModel()
            deliverAcknowledgementIfNeeded(acknowledgement)
            if acknowledgement.status == .applied || acknowledgement.status == .queued {
                lastErrorMessage = nil
            }
            if command.kind == .focusApp && acknowledgement.status == .applied {
                selectedAppID = command.appID ?? selectedAppID
            }
            return
        }

        if let error = reply["error"] as? String {
            handleLocalFailure(command, reason: error)
            return
        }

        handleLocalFailure(command, reason: "Malformed reply")
    }

    private func handleSendError(_ error: Error, for command: WatchCommand) {
        if command.kind.isQueueEligible && !session.isReachable {
            do {
                let payload = try WatchBridgeWireCodec.encodeQueuedCommand(command)
                session.transferUserInfo(payload)
                let queued = WatchAcknowledgement(
                    commandID: command.id,
                    status: .queued,
                    reason: "Queued for host",
                    snapshotVersion: command.snapshotVersion
                )
                sessionModel.record(queued, removePending: false)
                syncFromModel()
                haptics.play(.warning)
                lastErrorMessage = nil
                return
            } catch {
                handleLocalFailure(command, reason: error.localizedDescription)
                return
            }
        }

        handleLocalFailure(command, reason: error.localizedDescription)
    }

    private func handleLocalFailure(_ command: WatchCommand, reason: String) {
        let acknowledgement = WatchAcknowledgement(
            commandID: command.id,
            status: .rejected,
            reason: reason,
            snapshotVersion: command.snapshotVersion
        )
        sessionModel.record(acknowledgement)
        syncFromModel()
        deliverAcknowledgementIfNeeded(acknowledgement)
        lastErrorMessage = reason
    }

    private func handleValidationFailure(_ error: WatchCommandValidationError) {
        let reason: String
        let feedback: WatchHapticHint
        switch error {
        case let .staleSnapshot(expected, actual):
            reason = "Stale \(actual) != \(expected)"
            feedback = .retry
        case .unreachablePhone:
            reason = "Phone unreachable"
            feedback = .failure
        case .missingPayload:
            reason = "Missing payload"
            feedback = .failure
        }
        lastErrorMessage = reason
        haptics.play(feedback)
    }

    private func syncFromModel() {
        snapshot = sessionModel.snapshot
        lastAcknowledgement = sessionModel.lastAcknowledgement
        pendingCommands = sessionModel.pendingCommands
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let isReachable = session.isReachable
        let lastErrorMessage = error?.localizedDescription

        Task { @MainActor in
            self.activationState = activationState
            self.transportReachable = isReachable
            self.lastErrorMessage = lastErrorMessage
            if error == nil {
                self.syncFromModel()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable

        Task { @MainActor in
            self.transportReachable = isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            do {
                try self.sessionModel.ingest(applicationContext: applicationContext)
                self.syncFromModel()
                self.deliverAcknowledgementIfNeeded(self.snapshot.lastAcknowledgement)
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            do {
                try self.sessionModel.ingest(queuedCommand: userInfo)
                self.syncFromModel()
                self.deliverAcknowledgementIfNeeded(self.snapshot.lastAcknowledgement)
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }
}
