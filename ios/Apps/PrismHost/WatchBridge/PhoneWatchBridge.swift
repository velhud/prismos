import Foundation
import PrismRuntime
import PrismWatchModels

public protocol WatchBridgeSessioning: AnyObject {
    var isReachable: Bool { get }
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
    func transferUserInfo(_ userInfo: [String: Any])
}

public struct WatchBridgeState: Equatable, Sendable {
    public var connection: ConnectionState
    public var privacyMode: Bool
    public var captureActive: Bool
    public var wrongDeviceRisk: Bool
    public var oracle: WatchOracleState?
    public var chronos: WatchChronosState?
    public var teleprompter: WatchTeleprompterState?
    public var signal: WatchSignalState?
    public var babel: WatchBabelState?
    public var vision: WatchVisionState?

    public init(
        connection: ConnectionState = .phone,
        privacyMode: Bool = false,
        captureActive: Bool = false,
        wrongDeviceRisk: Bool = false,
        oracle: WatchOracleState? = nil,
        chronos: WatchChronosState? = nil,
        teleprompter: WatchTeleprompterState? = nil,
        signal: WatchSignalState? = nil,
        babel: WatchBabelState? = nil,
        vision: WatchVisionState? = nil
    ) {
        self.connection = connection
        self.privacyMode = privacyMode
        self.captureActive = captureActive
        self.wrongDeviceRisk = wrongDeviceRisk
        self.oracle = oracle
        self.chronos = chronos
        self.teleprompter = teleprompter
        self.signal = signal
        self.babel = babel
        self.vision = vision
    }
}

public struct BabelCommandResult: Equatable, Sendable {
    public var status: WatchCommandStatus
    public var reason: String
    public var babel: BabelEngine?

    public init(status: WatchCommandStatus, reason: String, babel: BabelEngine? = nil) {
        self.status = status
        self.reason = reason
        self.babel = babel
    }
}

public struct WatchSnapshotPublisher {
    public init() {}

    public func makeSnapshot(
        runtime: RuntimeSnapshot,
        version: UInt64,
        state: WatchBridgeState,
        acknowledgement: WatchAcknowledgement? = nil
    ) -> WatchSnapshot {
        let activeAppID: PrismAppID? = switch runtime.surface {
        case .orbit:
            nil
        case let .focused(appID):
            appID
        }

        let chronosSummary = state.chronos
        let teleprompterSummary = state.teleprompter
        let signalSummary = state.signal
        let babelSummary = state.babel
        let visionSummary = state.vision
        let oracleSummary = state.oracle

        return WatchSnapshot(
            version: version,
            activeSurface: activeAppID.map(WatchSurface.app) ?? .orbit,
            connection: state.connection,
            privacyMode: state.privacyMode,
            captureActive: state.captureActive,
            wrongDeviceRisk: state.wrongDeviceRisk,
            widgets: runtime.widgets.map { widget in
                let subtitle: String
                if widget.appID == .chronos, let chronosSummary {
                    subtitle = chronosSummary.compactTitle
                } else if widget.appID == .teleprompter, let teleprompterSummary {
                    subtitle = teleprompterSummary.compactTitle
                } else if widget.appID == .signal, let signalSummary {
                    subtitle = signalSummary.titleLine
                } else if widget.appID == .babel, let babelSummary {
                    subtitle = babelSummary.compactTitle
                } else if widget.appID == .vision, let visionSummary {
                    subtitle = visionSummary.compactTitle
                } else if widget.appID == .oracle, let oracleSummary {
                    subtitle = oracleSummary.compactTitle
                } else {
                    subtitle = state.privacyMode && widget.appID != .chronos ? "PRIVATE" : widget.status
                }
                return WatchAppWidget(
                    appID: widget.appID,
                    title: widget.label,
                    subtitle: subtitle,
                    isFocused: widget.appID == activeAppID,
                    isDisabled: state.connection == .recovery || state.connection == .stale || state.wrongDeviceRisk
                )
            },
            activeApp: activeAppID.flatMap { appID in
                runtime.widgets.first(where: { $0.appID == appID }).map { widget in
                    let subtitle: String
                    let primaryActionTitle: String
                    let secondaryActionTitle: String?
                    if appID == .chronos, let chronosSummary {
                        subtitle = chronosSummary.compactTitle
                        primaryActionTitle = chronosSummary.primaryActionTitle
                        secondaryActionTitle = chronosSummary.secondaryActionTitle
                    } else if appID == .teleprompter, let teleprompterSummary {
                        subtitle = teleprompterSummary.compactTitle
                        primaryActionTitle = teleprompterSummary.primaryActionTitle
                        secondaryActionTitle = teleprompterSummary.secondaryActionTitle
                    } else if appID == .signal, let signalSummary {
                        subtitle = signalSummary.titleLine
                        primaryActionTitle = signalSummary.primaryActionTitle
                        secondaryActionTitle = signalSummary.secondaryActionTitle
                    } else if appID == .babel, let babelSummary {
                        subtitle = babelSummary.compactTitle
                        primaryActionTitle = babelSummary.primaryActionTitle
                        secondaryActionTitle = babelSummary.secondaryActionTitle
                    } else if appID == .vision, let visionSummary {
                        subtitle = visionSummary.compactTitle
                        primaryActionTitle = visionSummary.primaryActionTitle
                        secondaryActionTitle = visionSummary.secondaryActionTitle
                    } else if appID == .oracle, let oracleSummary {
                        subtitle = oracleSummary.compactTitle
                        primaryActionTitle = oracleSummary.primaryActionTitle
                        secondaryActionTitle = oracleSummary.secondaryActionTitle
                    } else {
                        subtitle = state.privacyMode && appID != .chronos ? "PRIVATE" : widget.status
                        primaryActionTitle = Self.primaryActionTitle(for: appID)
                        secondaryActionTitle = Self.secondaryActionTitle(for: appID)
                    }
                    return WatchAppSummary(
                        appID: appID,
                        title: widget.label,
                        subtitle: subtitle,
                        primaryActionTitle: primaryActionTitle,
                        secondaryActionTitle: secondaryActionTitle,
                        isPrivacySensitive: appID != .chronos
                    )
                }
            },
            oracle: state.oracle,
            chronos: state.chronos,
            teleprompter: state.teleprompter,
            signal: state.signal,
            babel: state.babel,
            vision: state.vision,
            lastAcknowledgement: acknowledgement
        )
    }

    public func applicationContext(for snapshot: WatchSnapshot) throws -> [String: Any] {
        try WatchBridgeWireCodec.encodeSnapshot(snapshot)
    }

    private static func primaryActionTitle(for appID: PrismAppID) -> String {
        switch appID {
        case .oracle:
            "Ask"
        case .vision:
            "Capture"
        case .signal:
            "Dismiss"
        case .chronos:
            "Start"
        case .teleprompter:
            "Play"
        case .babel:
            "Translate"
        }
    }

    private static func secondaryActionTitle(for appID: PrismAppID) -> String? {
        switch appID {
        case .oracle:
            "Copy"
        case .vision:
            "Retake"
        case .signal:
            "Next"
        case .chronos:
            "Pause"
        case .teleprompter:
            "Bookmark"
        case .babel:
            "Swap"
        }
    }
}

public struct WatchAcknowledgementRouter {
    public init() {}

    public func reply(_ acknowledgement: WatchAcknowledgement, to replyHandler: (([String: Any]) -> Void)?) throws {
        guard let replyHandler else { return }
        replyHandler(try WatchBridgeWireCodec.encodeAcknowledgement(acknowledgement))
    }

    public func transferQueuedCommand(_ command: WatchCommand, to session: WatchBridgeSessioning) throws {
        session.transferUserInfo(try WatchBridgeWireCodec.encodeQueuedCommand(command))
    }
}

@MainActor
public final class PhoneWatchBridge {
    public private(set) var coordinator: AppCoordinatorCore
    public private(set) var state: WatchBridgeState
    public private(set) var latestSnapshot: WatchSnapshot
    public private(set) var lastAcknowledgement: WatchAcknowledgement?
    public private(set) var pendingQueuedCommands: [WatchCommand]
    public var chronosSnapshot: ChronosState {
        chronos.state
    }

    public var teleprompterSnapshot: TeleprompterScript {
        teleprompter.script
    }

    public var signalSnapshot: SignalStack {
        signal
    }

    public var babelSnapshot: BabelEngine {
        babel
    }

    public var visionSnapshot: VisionEngine {
        vision
    }

    public var oracleSnapshot: OracleEngine {
        oracle
    }

    private var snapshotVersion: UInt64
    private var acknowledgementsByCommandID: [UUID: WatchAcknowledgement]
    private var chronos: ChronosEngine
    private var chronosTicker: Timer?
    private var teleprompter: TeleprompterEngine
    private var teleprompterTicker: Timer?
    private var teleprompterLastAdvanceAt: Date
    private var signal: SignalStack
    private var babel: BabelEngine
    private var vision: VisionEngine
    private var oracle: OracleEngine
    private let stateDidChange: ((ChronosEngine, TeleprompterEngine, SignalStack) -> Void)?
    private let babelCommandHandler: ((WatchBabelAction) throws -> BabelCommandResult)?
    private var runtimeEffectHandler: ((RuntimeEffect) -> Void)?
    private let session: WatchBridgeSessioning
    private let snapshotPublisher: WatchSnapshotPublisher
    private let acknowledgementRouter: WatchAcknowledgementRouter
    private let validator: WatchCommandValidator

    public init(
        session: WatchBridgeSessioning,
        coordinator: AppCoordinatorCore = AppCoordinatorCore(),
        state: WatchBridgeState = WatchBridgeState(),
        chronos: ChronosEngine = ChronosEngine(),
        teleprompter: TeleprompterEngine = TeleprompterEngine(
            script: TeleprompterEngine.importScript(
                title: "Demo Script",
                body: "Welcome to PrismOS. Keep eye contact while the Host advances concise chunks."
            )
        ),
        signal: SignalStack = SignalStack(
            cards: [
                SignalCard(source: "PRISM", title: "Prism", body: "Sync Done", priority: .info),
                SignalCard(source: "SYS", title: "Battery", body: "Low", priority: .critical)
            ]
        ),
        babel: BabelEngine = BabelEngine(),
        vision: VisionEngine = VisionEngine(),
        oracle: OracleEngine = OracleEngine(),
        stateDidChange: ((ChronosEngine, TeleprompterEngine, SignalStack) -> Void)? = nil,
        babelCommandHandler: ((WatchBabelAction) throws -> BabelCommandResult)? = nil,
        runtimeEffectHandler: ((RuntimeEffect) -> Void)? = nil,
        snapshotPublisher: WatchSnapshotPublisher = WatchSnapshotPublisher(),
        acknowledgementRouter: WatchAcknowledgementRouter = WatchAcknowledgementRouter(),
        validator: WatchCommandValidator = WatchCommandValidator()
    ) {
        self.session = session
        self.coordinator = coordinator
        self.state = state
        self.stateDidChange = stateDidChange
        self.runtimeEffectHandler = runtimeEffectHandler
        self.snapshotPublisher = snapshotPublisher
        self.acknowledgementRouter = acknowledgementRouter
        self.validator = validator
        self.snapshotVersion = 1
        self.pendingQueuedCommands = []
        self.acknowledgementsByCommandID = [:]
        self.chronos = chronos
        self.chronosTicker = nil
        self.teleprompter = teleprompter
        self.teleprompterTicker = nil
        self.teleprompterLastAdvanceAt = Date()
        self.signal = signal
        self.babel = babel
        self.vision = vision
        self.oracle = oracle
        self.runtimeEffectHandler = runtimeEffectHandler
        self.babelCommandHandler = babelCommandHandler
        let initialNow = Date()
        var chronosEngine = chronos
        chronosEngine.tick(at: initialNow)
        self.chronos = chronosEngine
        self.state.chronos = Self.watchChronosState(for: chronosEngine.state, now: initialNow)
        self.teleprompterLastAdvanceAt = initialNow
        self.state.teleprompter = Self.watchTeleprompterState(for: teleprompter.script, now: initialNow, privacyMode: self.state.privacyMode)
        self.state.signal = Self.watchSignalState(for: signal, now: initialNow)
        self.state.babel = Self.watchBabelState(for: babel, now: initialNow, privacyMode: self.state.privacyMode)
        self.state.vision = Self.watchVisionState(for: vision, now: initialNow, privacyMode: self.state.privacyMode)
        self.state.oracle = Self.watchOracleState(for: oracle, now: initialNow, privacyMode: self.state.privacyMode)
        self.state.captureActive = self.state.vision?.isBusy == true || self.state.oracle?.phase.isBusy == true

        let runtime = coordinator.snapshot(context: Self.runtimeContext(for: self.state))
        self.latestSnapshot = snapshotPublisher.makeSnapshot(runtime: runtime, version: snapshotVersion, state: self.state)
        if let context = try? snapshotPublisher.applicationContext(for: latestSnapshot) {
            try? session.updateApplicationContext(context)
        }
        if self.chronos.state.runState == .alarm {
            _ = try? publishSnapshot(now: initialNow, acknowledgement: nil)
        }
        scheduleTeleprompterTickerIfNeeded()
        scheduleChronosTickerIfNeeded()
    }

    public func setRuntimeEffectHandler(_ handler: ((RuntimeEffect) -> Void)?) {
        runtimeEffectHandler = handler
    }

    deinit {
        chronosTicker?.invalidate()
        teleprompterTicker?.invalidate()
    }

    public func publishSnapshot() throws -> WatchSnapshot {
        try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateConnection(_ connection: ConnectionState) throws {
        state.connection = connection
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updatePrivacyMode(_ privacyMode: Bool) throws {
        state.privacyMode = privacyMode
        syncBabelState(now: Date())
        syncVisionState(now: Date())
        syncOracleState(now: Date())
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateCaptureActive(_ captureActive: Bool) throws {
        state.captureActive = captureActive
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateWrongDeviceRisk(_ wrongDeviceRisk: Bool) throws {
        state.wrongDeviceRisk = wrongDeviceRisk
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateRuntimeSurface(_ surface: RuntimeSurface) throws {
        let currentSurface = coordinator.snapshot(context: Self.runtimeContext(for: state)).surface
        guard currentSurface != surface else { return }

        switch surface {
        case .orbit:
            _ = coordinator.exitToOrbit(context: Self.runtimeContext(for: state))
        case let .focused(appID):
            _ = coordinator.focus(appID: appID, context: Self.runtimeContext(for: state))
        }

        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateChronos(_ chronos: ChronosEngine) throws {
        guard chronos.state != self.chronos.state else { return }
        self.chronos = chronos
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateTeleprompter(_ teleprompter: TeleprompterEngine) throws {
        guard teleprompter.script != self.teleprompter.script else { return }
        self.teleprompter = teleprompter
        teleprompterLastAdvanceAt = Date()
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateSignal(_ signal: SignalStack) throws {
        guard signal != self.signal else { return }
        self.signal = signal
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateBabel(_ babel: BabelEngine) throws {
        guard babel != self.babel else { return }
        self.babel = babel
        syncBabelState(now: Date())
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateVision(_ vision: VisionEngine) throws {
        guard vision != self.vision else { return }
        self.vision = vision
        syncVisionState(now: Date())
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    public func updateOracle(_ oracle: OracleEngine) throws {
        guard oracle != self.oracle else { return }
        self.oracle = oracle
        syncOracleState(now: Date())
        _ = try publishSnapshot(acknowledgement: latestSnapshot.lastAcknowledgement)
    }

    @discardableResult
    public func receiveReachableCommand(
        _ command: WatchCommand,
        replyHandler: (([String: Any]) -> Void)? = nil
    ) throws -> WatchAcknowledgement {
        if let cached = acknowledgementsByCommandID[command.id] {
            try acknowledgementRouter.reply(cached, to: replyHandler)
            return cached
        }

        if command.kind == .refreshSnapshot {
            let acknowledgement = try acknowledge(command, status: .applied, reason: "Snapshot refreshed")
            try publishSnapshot(acknowledgement: acknowledgement)
            try acknowledgementRouter.reply(acknowledgement, to: replyHandler)
            return acknowledgement
        }

        if let blocked = preflightBlock(for: command) {
            let acknowledgement = try acknowledge(command, status: blocked.status, reason: blocked.reason)
            try publishSnapshot(acknowledgement: acknowledgement)
            try acknowledgementRouter.reply(acknowledgement, to: replyHandler)
            return acknowledgement
        }

        if !session.isReachable {
            if command.kind.isQueueEligible {
                let acknowledgement = try queue(command, reason: "Queued for host")
                try acknowledgementRouter.reply(acknowledgement, to: replyHandler)
                return acknowledgement
            }
            let acknowledgement = try acknowledge(command, status: .rejected, reason: "Phone unreachable")
            try publishSnapshot(acknowledgement: acknowledgement)
            try acknowledgementRouter.reply(acknowledgement, to: replyHandler)
            return acknowledgement
        }

        do {
            try validator.validate(command, against: latestSnapshot)
        } catch let error as WatchCommandValidationError {
            switch error {
            case .unreachablePhone:
                if command.kind.isQueueEligible && !session.isReachable {
                    let acknowledgement = try queue(command, reason: "Queued for host")
                    try acknowledgementRouter.reply(acknowledgement, to: replyHandler)
                    return acknowledgement
                }
                let acknowledgement = try acknowledge(command, status: .rejected, reason: "Phone unreachable")
                try publishSnapshot(acknowledgement: acknowledgement)
                try acknowledgementRouter.reply(acknowledgement, to: replyHandler)
                return acknowledgement
            case let .staleSnapshot(expected, actual):
                let acknowledgement = try acknowledge(command, status: .stale, reason: "Stale \(actual) != \(expected)")
                try publishSnapshot(acknowledgement: acknowledgement)
                try acknowledgementRouter.reply(acknowledgement, to: replyHandler)
                return acknowledgement
            case .missingPayload:
                let acknowledgement = try acknowledge(command, status: .rejected, reason: "Missing payload")
                try publishSnapshot(acknowledgement: acknowledgement)
                try acknowledgementRouter.reply(acknowledgement, to: replyHandler)
                return acknowledgement
            }
        }

        let acknowledgement = try apply(command)
        try acknowledgementRouter.reply(acknowledgement, to: replyHandler)
        return acknowledgement
    }

    @discardableResult
    public func receiveQueuedCommand(_ command: WatchCommand) throws -> WatchAcknowledgement {
        if let cached = acknowledgementsByCommandID[command.id] {
            return cached
        }

        if command.kind == .refreshSnapshot {
            let acknowledgement = try acknowledge(command, status: .applied, reason: "Snapshot refreshed")
            try publishSnapshot(acknowledgement: acknowledgement)
            return acknowledgement
        }

        if let blocked = preflightBlock(for: command) {
            let acknowledgement = try acknowledge(command, status: blocked.status, reason: blocked.reason)
            try publishSnapshot(acknowledgement: acknowledgement)
            return acknowledgement
        }

        do {
            try validator.validate(command, against: latestSnapshot)
        } catch let error as WatchCommandValidationError {
            switch error {
            case .unreachablePhone:
                if command.kind.isQueueEligible {
                    return try queue(command, reason: "Queued for host")
                }
                let acknowledgement = try acknowledge(command, status: .rejected, reason: "Not queueable")
                try publishSnapshot(acknowledgement: acknowledgement)
                return acknowledgement
            case let .staleSnapshot(expected, actual):
                let acknowledgement = try acknowledge(command, status: .stale, reason: "Stale \(actual) != \(expected)")
                try publishSnapshot(acknowledgement: acknowledgement)
                return acknowledgement
            case .missingPayload:
                let acknowledgement = try acknowledge(command, status: .rejected, reason: "Missing payload")
                try publishSnapshot(acknowledgement: acknowledgement)
                return acknowledgement
            }
        }

        guard command.kind.isQueueEligible else {
            let acknowledgement = try acknowledge(command, status: .rejected, reason: "Not queueable")
            try publishSnapshot(acknowledgement: acknowledgement)
            return acknowledgement
        }
        return try queue(command, reason: "Queued for host")
    }

    @discardableResult
    public func drainQueuedCommands() throws -> [WatchAcknowledgement] {
        let queued = pendingQueuedCommands
        pendingQueuedCommands.removeAll()
        var acknowledgements: [WatchAcknowledgement] = []
        for command in queued {
            let acknowledgement = try apply(command)
            acknowledgements.append(acknowledgement)
        }
        return acknowledgements
    }

    private func applyChronos(_ action: WatchChronosAction, command: WatchCommand, now: Date) throws -> WatchAcknowledgement {
        chronos.tick(at: now)
        let reason: String
        let priorRunState = chronos.state.runState
        switch action {
        case .startPauseResume:
            switch priorRunState {
            case .setup, .paused:
                chronos.start(at: now)
                reason = priorRunState == .paused ? "Resumed" : "Started"
            case .running:
                chronos.pause(at: now)
                reason = "Paused"
            case .alarm:
                chronos.dismissAlarm()
                reason = "Dismissed"
            }
        case .reset:
            chronos.reset(totalSeconds: chronos.state.totalSeconds)
            reason = "Reset"
        case .dismissAlarm:
            guard chronos.state.runState == .alarm else {
                return try acknowledge(command, status: .rejected, reason: "No alarm")
            }
            chronos.dismissAlarm()
            reason = "Dismissed"
        case .toggleMode:
            guard chronos.state.runState != .running && chronos.state.runState != .alarm else {
                return try acknowledge(command, status: .rejected, reason: chronos.state.runState == .alarm ? "Alarm active" : "Running")
            }
            chronos.toggleMode()
            reason = chronos.state.mode == .timer ? "Timer" : "Stopwatch"
        case .togglePin:
            chronos.togglePinned()
            reason = chronos.state.pinned ? "Pinned" : "Unpinned"
        case let .adjustDuration(delta):
            guard chronos.state.runState != .alarm else {
                return try acknowledge(command, status: .rejected, reason: "Alarm active")
            }
            chronos.adjustDuration(by: delta)
            reason = delta >= 0 ? "Added \(Self.formatChronosDelta(delta))" : "Reduced \(Self.formatChronosDelta(delta))"
        case let .addTime(delta):
            guard chronos.state.runState != .alarm else {
                return try acknowledge(command, status: .rejected, reason: "Alarm active")
            }
            chronos.adjustDuration(by: delta)
            reason = "Added \(Self.formatChronosDelta(delta))"
        case let .applyPreset(seconds):
            guard chronos.state.runState != .running && chronos.state.runState != .alarm else {
                return try acknowledge(command, status: .rejected, reason: chronos.state.runState == .alarm ? "Alarm active" : "Running")
            }
            chronos.reset(totalSeconds: seconds)
            reason = "Preset \(Self.formatChronosDelta(seconds))"
        }

        syncChronosState(now: now)
        return try acknowledge(command, status: .applied, reason: reason)
    }

    private func applyTeleprompter(
        _ action: WatchTeleprompterAction,
        command: WatchCommand,
        now: Date
    ) throws -> WatchAcknowledgement {
        teleprompter.tickTeleprompter(at: now, lastAdvanceAt: &teleprompterLastAdvanceAt)
        guard !teleprompter.script.chunks.isEmpty else {
            return try acknowledge(command, status: .rejected, reason: "No script")
        }
        let reason: String
        switch action {
        case .nextLine:
            teleprompter.moveLine(by: 1)
            reason = "Next line"
        case .previousLine:
            teleprompter.moveLine(by: -1)
            reason = "Previous line"
        case .togglePlayPause:
            teleprompter.toggleAuto()
            teleprompterLastAdvanceAt = now
            reason = teleprompter.script.mode == .auto ? "Playing" : "Paused"
        case let .adjustLine(delta):
            guard teleprompter.script.mode == .manual else {
                return try acknowledge(command, status: .rejected, reason: "Auto mode")
            }
            teleprompter.moveLine(by: delta)
            reason = delta >= 0 ? "Advanced \(delta)" : "Rewound \(-delta)"
        case let .adjustWordsPerMinute(delta):
            guard teleprompter.script.mode == .auto else {
                return try acknowledge(command, status: .rejected, reason: "Manual mode")
            }
            teleprompter.setWordsPerMinute(teleprompter.script.wordsPerMinute + (delta * 10))
            reason = delta >= 0 ? "Faster \(delta * 10) WPM" : "Slower \(-delta * 10) WPM"
        case .bookmark:
            teleprompter.bookmark()
            reason = "Bookmarked"
        case .startOver:
            teleprompter.resetToStart()
            reason = "Reset"
        }

        teleprompterLastAdvanceAt = now
        syncTeleprompterState(now: now)
        return try acknowledge(command, status: .applied, reason: reason)
    }

    private func applySignal(
        _ action: WatchSignalAction,
        command: WatchCommand,
        now: Date
    ) throws -> WatchAcknowledgement {
        signal.cleanupExpired(now: now)

        if signal.visibleCards.isEmpty {
            switch action {
            case .reload:
                signal.reloadSession()
                syncSignalState(now: now)
                return try acknowledge(command, status: .applied, reason: "Reloaded")
            case .togglePrivacy:
                signal.togglePrivacy()
                syncSignalState(now: now)
                return try acknowledge(command, status: .applied, reason: signal.privacyMode ? "Privacy on" : "Privacy off")
            default:
                return try acknowledge(command, status: .rejected, reason: "Empty stack")
            }
        }

        let reason: String
        switch action {
        case .dismiss:
            signal.dismissCurrent()
            reason = "Dismissed"
        case .next:
            signal.moveSelection(by: 1)
            reason = "Next card"
        case .previous:
            signal.moveSelection(by: -1)
            reason = "Previous card"
        case .openHandoff:
            guard let handoffURL = signal.openCurrentHandoff(), !handoffURL.isEmpty else {
                return try acknowledge(command, status: .rejected, reason: "No handoff")
            }
            runtimeEffectHandler?(.openHandoff(urlString: handoffURL))
            reason = "Open handoff"
        case .reload:
            signal.reloadSession()
            reason = "Reloaded"
        case .togglePrivacy:
            signal.togglePrivacy()
            reason = signal.privacyMode ? "Privacy on" : "Privacy off"
        }

        syncSignalState(now: now)
        return try acknowledge(command, status: .applied, reason: reason)
    }

    private func apply(_ command: WatchCommand) throws -> WatchAcknowledgement {
        let now = Date()
        let acknowledgement: WatchAcknowledgement
        switch command.kind {
        case .selectDeck:
            acknowledgement = try acknowledge(command, status: .applied, reason: "Deck selected")
        case .focusApp:
            guard let appID = command.appID else {
                acknowledgement = try acknowledge(command, status: .rejected, reason: "Missing app")
                break
            }
            _ = coordinator.focus(appID: appID, context: Self.runtimeContext(for: state))
            acknowledgement = try acknowledge(command, status: .applied, reason: "Focused \(appID.rawValue)")
        case .primaryAction, .secondaryAction, .crownDelta, .requestReconnect, .refreshSnapshot, .cancel:
            acknowledgement = try acknowledge(command, status: .applied)
        case .chronos:
            guard case let .chronos(action) = command.value else {
                acknowledgement = try acknowledge(command, status: .rejected, reason: "Missing chronos action")
                break
            }
            acknowledgement = try applyChronos(action, command: command, now: now)
        case .teleprompter:
            guard case let .teleprompter(action) = command.value else {
                acknowledgement = try acknowledge(command, status: .rejected, reason: "Missing teleprompter action")
                break
            }
            acknowledgement = try applyTeleprompter(action, command: command, now: now)
        case .signal:
            guard case let .signal(action) = command.value else {
                acknowledgement = try acknowledge(command, status: .rejected, reason: "Missing signal action")
                break
            }
            acknowledgement = try applySignal(action, command: command, now: now)
        case .babel:
            guard case let .babel(action) = command.value else {
                acknowledgement = try acknowledge(command, status: .rejected, reason: "Missing Babel action")
                break
            }
            acknowledgement = try applyBabel(action, command: command, now: now)
        case .vision:
            guard case let .vision(action) = command.value else {
                acknowledgement = try acknowledge(command, status: .rejected, reason: "Missing Vision action")
                break
            }
            acknowledgement = try applyVision(action, command: command, now: now)
        case .oracle:
            guard case let .oracle(action) = command.value else {
                acknowledgement = try acknowledge(command, status: .rejected, reason: "Missing Oracle action")
                break
            }
            acknowledgement = try applyOracle(action, command: command, now: now)
        case .togglePrivacy:
            if case let .flag(enabled)? = command.value {
                state.privacyMode = enabled
            }
            acknowledgement = try acknowledge(command, status: .applied, reason: state.privacyMode ? "Privacy on" : "Privacy off")
        case .dismiss, .save, .bookmark:
            acknowledgement = try acknowledge(command, status: .applied, reason: "Queued action applied")
        }
        try publishSnapshot(now: now, acknowledgement: acknowledgement)
        return acknowledgement
    }

    private func applyBabel(_ action: WatchBabelAction, command: WatchCommand, now: Date) throws -> WatchAcknowledgement {
        guard let babelCommandHandler else {
            return try acknowledge(command, status: .rejected, reason: "Babel unavailable")
        }

        let result = try babelCommandHandler(action)
        if let updatedBabel = result.babel {
            babel = updatedBabel
        }
        syncBabelState(now: now)
        return try acknowledge(command, status: result.status, reason: result.reason)
    }

    private func applyVision(_ action: WatchVisionAction, command: WatchCommand, now: Date) throws -> WatchAcknowledgement {
        let reason: String
        let effect: RuntimeEffect?

        switch action {
        case .capture, .retake:
            guard !vision.isBusy else {
                return try acknowledge(command, status: .rejected, reason: "Capture active")
            }
            let priorState = vision.state
            effect = vision.capture()
            reason = priorState == .ready ? "Capture started" : "Retake started"
        case .toggleMode:
            let priorMode = vision.mode
            vision.toggleMode()
            guard vision.mode != priorMode else {
                return try acknowledge(command, status: .rejected, reason: "Capture active")
            }
            effect = nil
            reason = vision.mode.displayName.uppercased()
        case .cancel:
            let wasBusy = vision.isBusy
            guard vision.cancel() else {
                return try acknowledge(command, status: .rejected, reason: "Already ready")
            }
            effect = nil
            reason = wasBusy ? "Cancelled" : "Cleared"
        case .saveNote:
            guard let saveEffect = vision.saveCurrentResult() else {
                return try acknowledge(command, status: .rejected, reason: vision.hasSavedResult ? "Already saved" : "No result")
            }
            effect = saveEffect
            reason = "Saved"
        case .askOracle:
            guard let oracleEffect = vision.oracleFollowUp() else {
                return try acknowledge(command, status: .rejected, reason: "No result")
            }
            effect = oracleEffect
            reason = "Oracle follow-up"
        }

        syncVisionState(now: now)
        if let effect {
            runtimeEffectHandler?(effect)
        }
        return try acknowledge(command, status: .applied, reason: reason)
    }

    private func applyOracle(_ action: WatchOracleAction, command: WatchCommand, now: Date) throws -> WatchAcknowledgement {
        let reason: String
        let effect: RuntimeEffect?

        switch action {
        case .ask:
            effect = oracle.startVoiceAsk()
            reason = "Listening"
        case .followUp:
            guard let followUpEffect = oracle.followUp() else {
                return try acknowledge(command, status: .rejected, reason: "No answer")
            }
            effect = followUpEffect
            reason = "Follow up"
        case .clear:
            let wasBusy = oracle.currentRequestID != nil
            oracle.clear()
            effect = nil
            reason = wasBusy ? "Cancelled" : "Cleared"
        case .toggleKeep:
            guard oracle.toggleKeep() else {
                return try acknowledge(command, status: .rejected, reason: "No answer")
            }
            effect = nil
            reason = oracle.isCurrentAnswerKept ? "Kept" : "Unkept"
        case .copy:
            guard let copyEffect = oracle.copyAnswer() else {
                return try acknowledge(command, status: .rejected, reason: "No answer")
            }
            effect = copyEffect
            reason = "Copied"
        case .shorter:
            oracle.shorter()
            effect = nil
            reason = oracle.density.displayTitle
        case .moreDetail:
            oracle.moreDetail()
            effect = nil
            reason = oracle.density.displayTitle
        case let .adjustPage(delta):
            guard delta != 0 else {
                return try acknowledge(command, status: .applied, reason: "No change")
            }
            oracle.adjustPage(by: delta)
            effect = nil
            reason = oracle.currentAnswer == nil ? oracle.density.displayTitle : oracle.currentPageTitle
        }

        syncOracleState(now: now)
        if let effect {
            runtimeEffectHandler?(effect)
        }
        return try acknowledge(command, status: .applied, reason: reason)
    }

    private func queue(_ command: WatchCommand, reason: String) throws -> WatchAcknowledgement {
        let acknowledgement = try acknowledge(command, status: .queued, reason: reason)
        pendingQueuedCommands.append(command)
        try acknowledgementRouter.transferQueuedCommand(command, to: session)
        try publishSnapshot(acknowledgement: acknowledgement)
        return acknowledgement
    }

    @discardableResult
    private func publishSnapshot(now: Date = Date(), acknowledgement: WatchAcknowledgement?) throws -> WatchSnapshot {
        defer {
            stateDidChange?(chronos, teleprompter, signal)
        }
        chronos.tick(at: now)
        teleprompter.tickTeleprompter(at: now, lastAdvanceAt: &teleprompterLastAdvanceAt)
        syncChronosState(now: now)
        syncTeleprompterState(now: now)
        syncSignalState(now: now)
        syncBabelState(now: now)
        syncVisionState(now: now)
        syncOracleState(now: now)
        snapshotVersion += 1
        let runtime = coordinator.snapshot(context: Self.runtimeContext(for: state))
        let alarmAcknowledgement = chronosAlarmAcknowledgementIfNeeded() ?? acknowledgement ?? latestSnapshot.lastAcknowledgement
        let snapshot = snapshotPublisher.makeSnapshot(
            runtime: runtime,
            version: snapshotVersion,
            state: state,
            acknowledgement: alarmAcknowledgement
        )
        latestSnapshot = snapshot
        if let alarmAcknowledgement {
            lastAcknowledgement = alarmAcknowledgement
        } else if let acknowledgement {
            lastAcknowledgement = acknowledgement
        }
        try session.updateApplicationContext(try snapshotPublisher.applicationContext(for: snapshot))
        scheduleChronosTickerIfNeeded()
        scheduleTeleprompterTickerIfNeeded()
        return snapshot
    }

    private func syncChronosState(now: Date = Date()) {
        state.chronos = Self.watchChronosState(for: chronos.state, now: now)
    }

    private func syncTeleprompterState(now: Date = Date()) {
        state.teleprompter = Self.watchTeleprompterState(for: teleprompter.script, now: now, privacyMode: state.privacyMode)
    }

    private func syncSignalState(now: Date = Date()) {
        state.signal = Self.watchSignalState(for: signal, now: now)
    }

    private func syncBabelState(now: Date = Date()) {
        let nextState = Self.watchBabelState(for: babel, now: now, privacyMode: state.privacyMode)
        guard state.babel != nextState else { return }
        state.babel = nextState
    }

    private func syncVisionState(now: Date = Date()) {
        let nextState = Self.watchVisionState(for: vision, now: now, privacyMode: state.privacyMode)
        guard state.vision != nextState else {
            refreshCaptureActive()
            return
        }
        state.vision = nextState
        refreshCaptureActive()
    }

    private func syncOracleState(now: Date = Date()) {
        let nextState = Self.watchOracleState(for: oracle, now: now, privacyMode: state.privacyMode)
        guard state.oracle != nextState else {
            refreshCaptureActive()
            return
        }
        state.oracle = nextState
        refreshCaptureActive()
    }

    private func refreshCaptureActive() {
        state.captureActive = state.vision?.isBusy == true || state.oracle?.phase.isBusy == true
    }

    private func scheduleChronosTickerIfNeeded() {
        let shouldRun = chronos.state.runState == .running || chronos.state.runState == .alarm
        if shouldRun {
            if chronosTicker != nil {
                return
            }
            let ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.advanceChronosTimer()
                }
            }
            chronosTicker = ticker
            RunLoop.main.add(ticker, forMode: .common)
            return
        }

        chronosTicker?.invalidate()
        chronosTicker = nil
    }

    private func scheduleTeleprompterTickerIfNeeded() {
        let shouldRun = teleprompter.script.mode == .auto && !teleprompter.script.chunks.isEmpty
        if shouldRun {
            if teleprompterTicker != nil {
                return
            }
            let ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.advanceTeleprompterTimer()
                }
            }
            teleprompterTicker = ticker
            RunLoop.main.add(ticker, forMode: .common)
            return
        }

        teleprompterTicker?.invalidate()
        teleprompterTicker = nil
    }

    private func advanceChronosTimer() {
        let now = Date()
        _ = try? publishSnapshot(now: now, acknowledgement: nil)
    }

    private func advanceTeleprompterTimer() {
        let now = Date()
        _ = try? publishSnapshot(now: now, acknowledgement: nil)
    }

    private func chronosAlarmAcknowledgementIfNeeded() -> WatchAcknowledgement? {
        guard chronos.state.runState == .alarm else {
            return nil
        }

        if let lastAcknowledgement, lastAcknowledgement.commandID == chronos.state.id {
            return nil
        }

        let acknowledgement = WatchAcknowledgement(
            commandID: chronos.state.id,
            status: .applied,
            reason: "Timer complete",
            snapshotVersion: snapshotVersion + 1,
            haptic: .alarm,
            displayText: "ALARM"
        )
        lastAcknowledgement = acknowledgement
        return acknowledgement
    }

    static func watchBabelState(
        for babel: BabelEngine,
        now: Date,
        privacyMode: Bool
    ) -> WatchBabelState {
        let recentLines = Array(babel.lines.suffix(4)).map { line in
            WatchBabelLine(
                id: line.id,
                kind: WatchBabelLineKind(rawValue: line.kind.rawValue) ?? .system,
                text: privacyMode && (line.kind == .raw || line.kind == .final) ? "PRIVATE" : line.text
            )
        }

        return WatchBabelState(
            sourceLanguage: babel.sourceLanguage,
            targetLanguage: babel.targetLanguage,
            phase: watchBabelPhase(for: babel),
            audioLevel: watchBabelAudioLevel(for: babel),
            lines: recentLines,
            savedTranscriptCount: babel.savedTranscripts.count,
            canRepeatLast: !(babel.lastInputText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || !babel.savedTranscripts.isEmpty,
            lastUpdatedAt: now
        )
    }

    static func watchVisionState(
        for vision: VisionEngine,
        now: Date,
        privacyMode: Bool
    ) -> WatchVisionState {
        let mode: WatchVisionMode = vision.mode == .identify ? .identify : .readText

        switch vision.state {
        case .ready:
            return WatchVisionState(
                mode: mode,
                phase: .ready,
                savedNoteCount: vision.notes.count,
                lastUpdatedAt: now
            )
        case .waitingImage:
            return WatchVisionState(
                mode: mode,
                phase: .waitingImage,
                savedNoteCount: vision.notes.count,
                lastUpdatedAt: now
            )
        case .analyzing:
            return WatchVisionState(
                mode: mode,
                phase: .analyzing,
                savedNoteCount: vision.notes.count,
                lastUpdatedAt: now
            )
        case let .result(result):
            return WatchVisionState(
                mode: mode,
                phase: .result,
                summary: privacyMode ? nil : result.summary,
                ocrText: privacyMode ? nil : result.ocrText,
                savedNoteCount: vision.notes.count,
                lastUpdatedAt: now
            )
        case let .saved(result):
            return WatchVisionState(
                mode: mode,
                phase: .saved,
                summary: privacyMode ? nil : result.summary,
                ocrText: privacyMode ? nil : result.ocrText,
                savedNoteCount: vision.notes.count,
                lastUpdatedAt: now
            )
        case let .error(code):
            return WatchVisionState(
                mode: mode,
                phase: .error,
                summary: code,
                savedNoteCount: vision.notes.count,
                lastUpdatedAt: now
            )
        }
    }

    static func watchOracleState(
        for oracle: OracleEngine,
        now: Date,
        privacyMode: Bool
    ) -> WatchOracleState {
        let phase: WatchOraclePhase
        let promptText: String?
        let pageText: String?
        let errorText: String?

        switch oracle.state {
        case .ready:
            phase = .ready
            promptText = nil
            pageText = nil
            errorText = nil
        case .listening:
            phase = .listening
            promptText = nil
            pageText = nil
            errorText = nil
        case let .asking(_, prompt):
            phase = .thinking
            promptText = privacyMode ? nil : prompt
            pageText = nil
            errorText = nil
        case let .answer(answer):
            phase = .answer
            promptText = privacyMode ? nil : (answer.prompt.isEmpty ? nil : answer.prompt)
            pageText = privacyMode ? nil : oracle.currentPageText
            errorText = nil
        case .cancelled:
            phase = .cancelled
            promptText = nil
            pageText = nil
            errorText = nil
        case let .error(code):
            phase = .error
            promptText = nil
            pageText = nil
            errorText = code
        }

        return WatchOracleState(
            phase: phase,
            density: Self.watchOracleDensity(for: oracle.density),
            pageIndex: oracle.pageIndex,
            pageCount: oracle.currentPageCount,
            historyCount: oracle.historyCount,
            isKept: oracle.isCurrentAnswerKept,
            promptText: promptText,
            pageText: pageText,
            errorText: errorText,
            lastUpdatedAt: now
        )
    }

    private static func watchBabelPhase(for babel: BabelEngine) -> WatchBabelPhase {
        if babel.frozen {
            return .frozen
        }

        guard let lastLine = babel.lines.last else {
            return babel.currentRequestID == nil ? .ready : .listening
        }

        switch lastLine.kind {
        case .raw:
            return babel.currentRequestID == nil ? .ready : .transcribing
        case .final:
            return babel.currentRequestID == nil ? .ready : .translating
        case .system:
            switch lastLine.text.uppercased() {
            case "LISTENING":
                return .listening
            case "BUSY DROP", "EMPTY", "LANG REQUIRED", "NO HISTORY":
                return .error
            case "SAVED", "CLEARED", "RESUMED":
                return .ready
            default:
                return babel.currentRequestID == nil ? .ready : .translating
            }
        }
    }

    private static func watchBabelAudioLevel(for babel: BabelEngine) -> Double {
        if babel.frozen {
            return 0
        }
        guard babel.currentRequestID != nil else {
            return 0
        }

        guard let lastLine = babel.lines.last else {
            return 0.6
        }

        switch lastLine.kind {
        case .raw:
            return 0.8
        case .final:
            return 0.4
        case .system:
            return lastLine.text.uppercased() == "LISTENING" ? 0.6 : 0.3
        }
    }

    private static func watchTeleprompterState(
        for script: TeleprompterScript,
        now: Date,
        privacyMode: Bool
    ) -> WatchTeleprompterState {
        let mode: WatchTeleprompterMode = script.mode == .manual ? .manual : .auto
        let currentLine = script.chunks.indices.contains(script.currentIndex) ? script.chunks[script.currentIndex] : nil
        let nextLine = script.chunks.indices.contains(script.currentIndex + 1) ? script.chunks[script.currentIndex + 1] : nil
        return WatchTeleprompterState(
            title: privacyMode ? "PRIVATE" : script.title,
            mode: mode,
            currentIndex: script.currentIndex,
            totalChunks: script.chunks.count,
            wordsPerMinute: script.wordsPerMinute,
            bookmarkIndex: script.bookmarkIndex,
            currentLine: privacyMode ? nil : currentLine,
            nextLine: privacyMode ? nil : nextLine,
            lastUpdatedAt: now
        )
    }

    private static func watchSignalState(for signal: SignalStack, now: Date) -> WatchSignalState {
        let currentCard = signal.currentCard.map { card in
            WatchSignalCard(
                id: card.id,
                source: card.source,
                title: card.title,
                body: signal.privacyMode ? nil : card.body,
                priority: WatchSignalPriority(rawValue: card.priority.rawValue) ?? .info,
                handoffURL: card.handoffURL
            )
        }

        return WatchSignalState(
            privacyMode: signal.privacyMode,
            visibleCardCount: signal.visibleCardCount,
            currentIndex: signal.currentIndex ?? 0,
            currentCard: currentCard,
            lastUpdatedAt: now
        )
    }

    private static func watchChronosState(for state: ChronosState, now: Date) -> WatchChronosState {
        let mode: WatchChronosMode = state.mode == .timer ? .timer : .stopwatch
        let runState: WatchChronosRunState = switch state.runState {
        case .setup:
            .setup
        case .running:
            .running
        case .paused:
            .paused
        case .alarm:
            .alarm
        }

        return WatchChronosState(
            mode: mode,
            runState: runState,
            totalSeconds: state.totalSeconds,
            remainingSeconds: state.remaining(at: now),
            elapsedSeconds: state.elapsed(at: now),
            isPinned: state.pinned,
            lastUpdatedAt: now
        )
    }

    private static func watchOracleDensity(for density: OracleDensity) -> WatchOracleDensity {
        switch density {
        case .shorter:
            .shorter
        case .balanced:
            .balanced
        case .moreDetail:
            .moreDetail
        }
    }

    private static func formatChronosDelta(_ seconds: Int) -> String {
        let absolute = abs(seconds)
        if absolute >= 60 {
            let minutes = absolute / 60
            let remainder = absolute % 60
            if remainder == 0 {
                return "\(minutes)m"
            }
            return "\(minutes)m \(remainder)s"
        }
        return "\(absolute)s"
    }

    private func acknowledge(
        _ command: WatchCommand,
        status: WatchCommandStatus,
        reason: String? = nil
    ) throws -> WatchAcknowledgement {
        let acknowledgement = WatchAcknowledgement(
            commandID: command.id,
            status: status,
            reason: reason,
            snapshotVersion: snapshotVersion + 1,
            displayText: reason ?? status.displayText
        )
        acknowledgementsByCommandID[command.id] = acknowledgement
        lastAcknowledgement = acknowledgement
        return acknowledgement
    }

    private func preflightBlock(for command: WatchCommand) -> (status: WatchCommandStatus, reason: String)? {
        switch state.connection {
        case .stale:
            if command.kind != .refreshSnapshot {
                return (.stale, "Stale snapshot")
            }
        case .recovery:
            if command.kind != .refreshSnapshot {
                return (.rejected, "Recovery only")
            }
        case .phone, .monocle:
            break
        }

        if state.wrongDeviceRisk && command.kind != .refreshSnapshot {
            return (.rejected, "Wrong device risk")
        }

        if state.privacyMode {
            if Self.privacySensitiveKinds.contains(command.kind) {
                return (.rejected, "Privacy mode")
            }
            if command.kind == .oracle, case let .oracle(action)? = command.value {
                switch action {
                case .ask, .followUp:
                    return (.rejected, "Privacy mode")
                case .clear, .toggleKeep, .copy, .shorter, .moreDetail, .adjustPage:
                    break
                }
            }
        }

        return nil
    }

    private static func runtimeContext(for state: WatchBridgeState) -> RuntimeContext {
        switch state.connection {
        case .recovery:
            RuntimeContext(fallback: .recoveryOnly)
        case .stale:
            RuntimeContext(fallback: .waitingForHost)
        case .phone, .monocle:
            RuntimeContext()
        }
    }

    private static let privacySensitiveKinds: Set<WatchCommandKind> = [
        .primaryAction,
        .secondaryAction
    ]
}
