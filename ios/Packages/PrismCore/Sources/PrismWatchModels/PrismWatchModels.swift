import Foundation
@_exported import PrismModels

public extension PrismAppID {
    var watchTitle: String {
        switch self {
        case .oracle:
            "Oracle"
        case .vision:
            "Vision"
        case .signal:
            "Signal"
        case .chronos:
            "Chronos"
        case .teleprompter:
            "Teleprompter"
        case .babel:
            "Babel"
        }
    }

    var watchSubtitle: String {
        switch self {
        case .oracle:
            "Ask / answer"
        case .vision:
            "Capture / inspect"
        case .signal:
            "Triage / dismiss"
        case .chronos:
            "Timer / alarm"
        case .teleprompter:
            "Scroll / cue"
        case .babel:
            "Translate / freeze"
        }
    }
}

public enum WatchSurface: Equatable, Sendable, Codable {
    case orbit
    case app(PrismAppID)

    public var displayTitle: String {
        switch self {
        case .orbit:
            "ORBIT"
        case let .app(appID):
            appID.watchTitle
        }
    }

    public var appID: PrismAppID? {
        switch self {
        case .orbit:
            nil
        case let .app(appID):
            appID
        }
    }
}

public enum WatchDeckState: String, CaseIterable, Sendable, Codable {
    case lens
    case app
    case privacy
    case connection
    case handoff

    public var displayTitle: String {
        switch self {
        case .lens:
            "LENS"
        case .app:
            "APP"
        case .privacy:
            "PRIVACY"
        case .connection:
            "CONNECTION"
        case .handoff:
            "HANDOFF"
        }
    }
}

public enum ConnectionState: String, CaseIterable, Sendable, Codable {
    case phone
    case monocle
    case recovery
    case stale

    public var displayTitle: String {
        switch self {
        case .phone:
            "PHONE"
        case .monocle:
            "MONOCLE"
        case .recovery:
            "RECOVERY"
        case .stale:
            "STALE"
        }
    }

    public var isReachable: Bool {
        switch self {
        case .phone, .monocle:
            true
        case .recovery, .stale:
            false
        }
    }
}

public struct WatchAppWidget: Equatable, Sendable, Codable {
    public var appID: PrismAppID
    public var title: String
    public var subtitle: String
    public var isFocused: Bool
    public var isDisabled: Bool

    public init(
        appID: PrismAppID,
        title: String? = nil,
        subtitle: String? = nil,
        isFocused: Bool = false,
        isDisabled: Bool = false
    ) {
        self.appID = appID
        self.title = title ?? appID.watchTitle
        self.subtitle = subtitle ?? appID.watchSubtitle
        self.isFocused = isFocused
        self.isDisabled = isDisabled
    }
}

public struct WatchAppSummary: Equatable, Sendable, Codable {
    public var appID: PrismAppID
    public var title: String
    public var subtitle: String
    public var primaryActionTitle: String
    public var secondaryActionTitle: String?
    public var isPrivacySensitive: Bool

    public init(
        appID: PrismAppID,
        title: String? = nil,
        subtitle: String? = nil,
        primaryActionTitle: String = "Open",
        secondaryActionTitle: String? = nil,
        isPrivacySensitive: Bool = false
    ) {
        self.appID = appID
        self.title = title ?? appID.watchTitle
        self.subtitle = subtitle ?? appID.watchSubtitle
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.isPrivacySensitive = isPrivacySensitive
    }
}

public enum WatchChronosMode: String, CaseIterable, Sendable, Codable {
    case timer
    case stopwatch

    public var displayTitle: String {
        switch self {
        case .timer:
            "TIMER"
        case .stopwatch:
            "STOPWATCH"
        }
    }
}

public enum WatchChronosRunState: String, CaseIterable, Sendable, Codable {
    case setup
    case running
    case paused
    case alarm

    public var displayTitle: String {
        switch self {
        case .setup:
            "SETUP"
        case .running:
            "RUNNING"
        case .paused:
            "PAUSED"
        case .alarm:
            "ALARM"
        }
    }
}

public enum WatchChronosAction: Equatable, Sendable, Codable {
    case startPauseResume
    case reset
    case dismissAlarm
    case toggleMode
    case togglePin
    case adjustDuration(Int)
    case addTime(Int)
    case applyPreset(Int)
}

public struct WatchChronosState: Equatable, Sendable, Codable {
    public var mode: WatchChronosMode
    public var runState: WatchChronosRunState
    public var totalSeconds: Int
    public var remainingSeconds: Int
    public var elapsedSeconds: Int
    public var isPinned: Bool
    public var lastUpdatedAt: Date

    public init(
        mode: WatchChronosMode = .timer,
        runState: WatchChronosRunState = .setup,
        totalSeconds: Int = 300,
        remainingSeconds: Int = 300,
        elapsedSeconds: Int = 0,
        isPinned: Bool = false,
        lastUpdatedAt: Date = Date()
    ) {
        self.mode = mode
        self.runState = runState
        self.totalSeconds = max(1, min(totalSeconds, 24 * 60 * 60))
        self.remainingSeconds = max(0, min(remainingSeconds, 24 * 60 * 60))
        self.elapsedSeconds = max(0, min(elapsedSeconds, 24 * 60 * 60))
        self.isPinned = isPinned
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var displaySeconds: Int {
        switch mode {
        case .timer:
            remainingSeconds
        case .stopwatch:
            elapsedSeconds
        }
    }

    public var compactTitle: String {
        if runState == .alarm {
            return "ALARM"
        }
        return "\(mode.displayTitle) \(Self.format(seconds: displaySeconds))"
    }

    public var statusTitle: String {
        switch runState {
        case .setup:
            "SETUP"
        case .running:
            "RUNNING"
        case .paused:
            "PAUSED"
        case .alarm:
            "ALARM"
        }
    }

    public var primaryActionTitle: String {
        switch runState {
        case .setup:
            "START"
        case .running:
            "PAUSE"
        case .paused:
            "RESUME"
        case .alarm:
            "DISMISS"
        }
    }

    public var secondaryActionTitle: String {
        switch runState {
        case .alarm:
            "RESET"
        case .setup:
            isPinned ? "UNPIN" : "PIN"
        case .running, .paused:
            "RESET"
        }
    }

    public var modeActionTitle: String {
        mode == .timer ? "STOPWATCH" : "TIMER"
    }

    public var pinActionTitle: String {
        isPinned ? "UNPIN" : "PIN"
    }

    public var durationHintTitle: String {
        mode == .timer ? "DURATION" : "WATCH"
    }

    private static func format(seconds: Int) -> String {
        let minutes = seconds / 60
        let remaining = seconds % 60
        if seconds < 60 {
            return String(format: "%02d", seconds)
        }
        return String(format: "%02d:%02d", minutes, remaining)
    }
}

public enum WatchTeleprompterMode: String, CaseIterable, Sendable, Codable {
    case manual
    case auto

    public var displayTitle: String {
        switch self {
        case .manual:
            "MANUAL"
        case .auto:
            "AUTO"
        }
    }
}

public enum WatchTeleprompterAction: Equatable, Sendable, Codable {
    case nextLine
    case previousLine
    case togglePlayPause
    case adjustLine(Int)
    case adjustWordsPerMinute(Int)
    case bookmark
    case startOver
}

public struct WatchTeleprompterState: Equatable, Sendable, Codable {
    public var title: String
    public var mode: WatchTeleprompterMode
    public var currentIndex: Int
    public var totalChunks: Int
    public var wordsPerMinute: Int
    public var bookmarkIndex: Int?
    public var currentLine: String?
    public var nextLine: String?
    public var lastUpdatedAt: Date

    public init(
        title: String = "Demo Script",
        mode: WatchTeleprompterMode = .manual,
        currentIndex: Int = 0,
        totalChunks: Int = 0,
        wordsPerMinute: Int = 140,
        bookmarkIndex: Int? = nil,
        currentLine: String? = nil,
        nextLine: String? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.title = title
        self.mode = mode
        self.totalChunks = max(totalChunks, 0)
        self.currentIndex = min(max(currentIndex, 0), max(self.totalChunks - 1, 0))
        self.wordsPerMinute = min(max(wordsPerMinute, 60), 240)
        self.bookmarkIndex = bookmarkIndex
        self.currentLine = currentLine
        self.nextLine = nextLine
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var lineProgressTitle: String {
        guard totalChunks > 0 else {
            return "0/0"
        }
        return "\(min(currentIndex + 1, totalChunks))/\(totalChunks)"
    }

    public var compactTitle: String {
        "\(lineProgressTitle) \(mode.displayTitle) \(wordsPerMinute) WPM"
    }

    public var modeTitle: String {
        mode.displayTitle
    }

    public var speedTitle: String {
        "\(wordsPerMinute) WPM"
    }

    public var primaryActionTitle: String {
        mode == .manual ? "PLAY" : "PAUSE"
    }

    public var secondaryActionTitle: String {
        "BOOKMARK"
    }

    public var crownHintTitle: String {
        mode == .manual ? "LINE" : "WPM"
    }

    public var bookmarkStatusTitle: String {
        guard let bookmarkIndex else {
            return "NO BOOKMARK"
        }
        if bookmarkIndex == currentIndex {
            return "BOOKMARKED"
        }
        return "BOOKMARK \(bookmarkIndex + 1)"
    }

    public var isEmpty: Bool {
        totalChunks == 0
    }

    public var hasPreviewText: Bool {
        currentLine != nil || nextLine != nil
    }

    public static func sample(
        title: String = "Demo Script",
        mode: WatchTeleprompterMode = .manual,
        currentIndex: Int = 1,
        totalChunks: Int = 4,
        wordsPerMinute: Int = 140,
        bookmarkIndex: Int? = 1,
        currentLine: String? = "KEEP EYE CONTACT",
        nextLine: String? = "ADVANCE CONCISE CHUNKS"
    ) -> WatchTeleprompterState {
        WatchTeleprompterState(
            title: title,
            mode: mode,
            currentIndex: currentIndex,
            totalChunks: totalChunks,
            wordsPerMinute: wordsPerMinute,
            bookmarkIndex: bookmarkIndex,
            currentLine: currentLine,
            nextLine: nextLine
        )
    }
}

public enum WatchSignalPriority: Int, CaseIterable, Sendable, Codable {
    case info = 0
    case important = 1
    case critical = 2

    public var displayTitle: String {
        switch self {
        case .info:
            "INFO"
        case .important:
            "IMPORTANT"
        case .critical:
            "CRITICAL"
        }
    }
}

public enum WatchSignalAction: Equatable, Sendable, Codable {
    case dismiss
    case next
    case previous
    case openHandoff
    case reload
    case togglePrivacy
}

public struct WatchSignalCard: Equatable, Sendable, Codable {
    public var id: UUID
    public var source: String
    public var title: String
    public var body: String?
    public var priority: WatchSignalPriority
    public var handoffURL: String?

    public init(
        id: UUID = UUID(),
        source: String,
        title: String,
        body: String? = nil,
        priority: WatchSignalPriority = .info,
        handoffURL: String? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.body = body
        self.priority = priority
        self.handoffURL = handoffURL
    }
}

public struct WatchSignalState: Equatable, Sendable, Codable {
    public var privacyMode: Bool
    public var visibleCardCount: Int
    public var currentIndex: Int
    public var currentCard: WatchSignalCard?
    public var lastUpdatedAt: Date

    public init(
        privacyMode: Bool = false,
        visibleCardCount: Int = 0,
        currentIndex: Int = 0,
        currentCard: WatchSignalCard? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.privacyMode = privacyMode
        self.visibleCardCount = max(visibleCardCount, 0)
        self.currentIndex = min(max(currentIndex, 0), max(self.visibleCardCount - 1, 0))
        self.currentCard = currentCard
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var isEmpty: Bool {
        visibleCardCount == 0 || currentCard == nil
    }

    public var positionTitle: String {
        guard !isEmpty else {
            return "0/0"
        }
        return "\(min(currentIndex + 1, visibleCardCount))/\(visibleCardCount)"
    }

    public var sourceTitle: String {
        currentCard?.source ?? "SIGNAL"
    }

    public var priorityTitle: String {
        currentCard?.priority.displayTitle ?? WatchSignalPriority.info.displayTitle
    }

    public var titleLine: String {
        if isEmpty {
            return "EMPTY STACK"
        }
        if privacyMode {
            return "PRIVATE"
        }
        return currentCard?.title ?? "EMPTY STACK"
    }

    public var bodyLine: String {
        if isEmpty {
            return "RELOAD ON PHONE"
        }
        if privacyMode {
            return "OPEN PHONE"
        }
        return currentCard?.body ?? "RELOAD ON PHONE"
    }

    public var compactTitle: String {
        if isEmpty {
            return "EMPTY STACK"
        }
        return "\(positionTitle) \(priorityTitle)"
    }

    public var primaryActionTitle: String {
        isEmpty ? "RELOAD" : "DISMISS"
    }

    public var secondaryActionTitle: String? {
        guard !isEmpty else {
            return nil
        }
        return currentCard?.handoffURL == nil ? "NEXT" : "OPEN"
    }

    public var privacyActionTitle: String {
        privacyMode ? "PRIVATE ON" : "PRIVATE OFF"
    }

    public var hasHandoff: Bool {
        currentCard?.handoffURL != nil
    }

    public static func sample(
        privacyMode: Bool = false,
        lastUpdatedAt: Date = Date()
    ) -> WatchSignalState {
        WatchSignalState(
            privacyMode: privacyMode,
            visibleCardCount: 2,
            currentIndex: 0,
            currentCard: WatchSignalCard(
                source: "SYS",
                title: "Battery",
                body: "Low",
                priority: .critical
            ),
            lastUpdatedAt: lastUpdatedAt
        )
    }
}

public enum WatchCommandKind: String, CaseIterable, Sendable, Codable {
    case selectDeck
    case focusApp
    case primaryAction
    case secondaryAction
    case chronos
    case teleprompter
    case signal
    case babel
    case vision
    case oracle
    case togglePrivacy
    case crownDelta
    case refreshSnapshot
    case requestReconnect
    case dismiss
    case save
    case bookmark
    case cancel

    public var isLocalOnly: Bool {
        self == .selectDeck
    }

    public var isQueueEligible: Bool {
        switch self {
        case .save, .bookmark, .dismiss:
            true
        case .selectDeck, .focusApp, .primaryAction, .secondaryAction, .chronos, .teleprompter, .signal, .babel, .vision, .oracle, .togglePrivacy, .crownDelta, .refreshSnapshot, .requestReconnect, .cancel:
            false
        }
    }
}

public enum WatchCommandValue: Equatable, Sendable, Codable {
    case deck(WatchDeckState)
    case chronos(WatchChronosAction)
    case teleprompter(WatchTeleprompterAction)
    case signal(WatchSignalAction)
    case babel(WatchBabelAction)
    case vision(WatchVisionAction)
    case oracle(WatchOracleAction)
    case delta(Int)
    case text(String)
    case flag(Bool)
}

public struct WatchCommand: Equatable, Sendable, Codable {
    public var id: UUID
    public var snapshotVersion: UInt64
    public var kind: WatchCommandKind
    public var appID: PrismAppID?
    public var value: WatchCommandValue?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        snapshotVersion: UInt64,
        kind: WatchCommandKind,
        appID: PrismAppID? = nil,
        value: WatchCommandValue? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.snapshotVersion = snapshotVersion
        self.kind = kind
        self.appID = appID
        self.value = value
        self.createdAt = createdAt
    }
}

public enum WatchCommandStatus: String, CaseIterable, Sendable, Codable {
    case applied
    case rejected
    case queued
    case stale

    public var displayText: String {
        switch self {
        case .applied:
            "APPLIED"
        case .rejected:
            "REJECTED"
        case .queued:
            "QUEUED"
        case .stale:
            "STALE"
        }
    }

    public var hapticHint: WatchHapticHint {
        switch self {
        case .applied:
            .success
        case .rejected:
            .failure
        case .queued:
            .warning
        case .stale:
            .retry
        }
    }
}

public enum WatchHapticHint: String, CaseIterable, Sendable, Codable {
    case none
    case success
    case warning
    case failure
    case retry
    case alarm
}

public struct WatchAcknowledgement: Equatable, Sendable, Codable {
    public var commandID: UUID
    public var status: WatchCommandStatus
    public var reason: String?
    public var snapshotVersion: UInt64
    public var haptic: WatchHapticHint
    public var displayText: String

    public init(
        commandID: UUID,
        status: WatchCommandStatus,
        reason: String? = nil,
        snapshotVersion: UInt64,
        haptic: WatchHapticHint? = nil,
        displayText: String? = nil
    ) {
        self.commandID = commandID
        self.status = status
        self.reason = reason
        self.snapshotVersion = snapshotVersion
        self.haptic = haptic ?? status.hapticHint
        self.displayText = displayText ?? status.displayText
    }
}

public struct WatchSnapshot: Equatable, Sendable, Codable {
    public var version: UInt64
    public var activeSurface: WatchSurface
    public var connection: ConnectionState
    public var privacyMode: Bool
    public var captureActive: Bool
    public var wrongDeviceRisk: Bool
    public var widgets: [WatchAppWidget]
    public var activeApp: WatchAppSummary?
    public var oracle: WatchOracleState?
    public var chronos: WatchChronosState?
    public var teleprompter: WatchTeleprompterState?
    public var signal: WatchSignalState?
    public var babel: WatchBabelState?
    public var vision: WatchVisionState?
    public var lastAcknowledgement: WatchAcknowledgement?

    public init(
        version: UInt64,
        activeSurface: WatchSurface,
        connection: ConnectionState,
        privacyMode: Bool,
        captureActive: Bool,
        wrongDeviceRisk: Bool = false,
        widgets: [WatchAppWidget],
        activeApp: WatchAppSummary? = nil,
        oracle: WatchOracleState? = nil,
        chronos: WatchChronosState? = nil,
        teleprompter: WatchTeleprompterState? = nil,
        signal: WatchSignalState? = nil,
        babel: WatchBabelState? = nil,
        vision: WatchVisionState? = nil,
        lastAcknowledgement: WatchAcknowledgement? = nil
    ) {
        self.version = version
        self.activeSurface = activeSurface
        self.connection = connection
        self.privacyMode = privacyMode
        self.captureActive = captureActive
        self.wrongDeviceRisk = wrongDeviceRisk
        self.widgets = widgets
        self.activeApp = activeApp
        self.oracle = oracle
        self.chronos = chronos
        self.teleprompter = teleprompter
        self.signal = signal
        self.babel = babel
        self.vision = vision
        self.lastAcknowledgement = lastAcknowledgement
    }

    public var activeAppID: PrismAppID? {
        activeSurface.appID
    }
}

public enum WatchCommandValidationError: Error, Equatable, Sendable {
    case staleSnapshot(expected: UInt64, actual: UInt64)
    case unreachablePhone(command: WatchCommandKind)
    case missingPayload(command: WatchCommandKind)
}

public struct WatchCommandValidator {
    public init() {}

    public func validate(_ command: WatchCommand, against snapshot: WatchSnapshot) throws {
        try validateShape(command)

        if command.kind == .refreshSnapshot {
            return
        }

        guard !command.kind.isLocalOnly else {
            return
        }

        guard command.snapshotVersion == snapshot.version else {
            throw WatchCommandValidationError.staleSnapshot(expected: snapshot.version, actual: command.snapshotVersion)
        }

        guard snapshot.connection.isReachable else {
            throw WatchCommandValidationError.unreachablePhone(command: command.kind)
        }
    }

    private func validateShape(_ command: WatchCommand) throws {
        switch command.kind {
        case .selectDeck:
            guard case .deck = command.value else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .focusApp, .primaryAction, .secondaryAction:
            guard command.appID != nil else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .chronos:
            guard command.appID == .chronos else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
            guard case .chronos = command.value else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .teleprompter:
            guard command.appID == .teleprompter else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
            guard case .teleprompter = command.value else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .signal:
            guard command.appID == .signal else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
            guard case .signal = command.value else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .babel:
            guard command.appID == .babel else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
            guard case .babel = command.value else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .vision:
            guard command.appID == .vision else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
            guard case .vision = command.value else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .oracle:
            guard command.appID == .oracle else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
            guard case .oracle = command.value else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .togglePrivacy:
            guard case .flag = command.value else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .crownDelta:
            guard case .delta = command.value else {
                throw WatchCommandValidationError.missingPayload(command: command.kind)
            }
        case .refreshSnapshot, .requestReconnect, .dismiss, .save, .bookmark, .cancel:
            break
        }
    }
}

public enum WatchUIAction: Equatable, Sendable {
    case selectDeck(WatchDeckState)
    case focusApp(PrismAppID)
    case primaryAction(PrismAppID)
    case secondaryAction(PrismAppID)
    case chronos(WatchChronosAction)
    case teleprompter(WatchTeleprompterAction)
    case signal(WatchSignalAction)
    case babel(WatchBabelAction)
    case vision(WatchVisionAction)
    case oracle(WatchOracleAction)
    case togglePrivacy(Bool)
    case crownDelta(Int)
    case commitCrown
    case refreshSnapshot
    case cancel
}

public struct WatchCommandReducer {
    private var pendingCrownDelta: Int
    private var lastSnapshotVersion: UInt64?
    private let validator: WatchCommandValidator

    public init(validator: WatchCommandValidator = WatchCommandValidator()) {
        self.pendingCrownDelta = 0
        self.lastSnapshotVersion = nil
        self.validator = validator
    }

    public mutating func reduce(_ action: WatchUIAction, against snapshot: WatchSnapshot) throws -> WatchCommand? {
        if lastSnapshotVersion != snapshot.version {
            pendingCrownDelta = 0
            lastSnapshotVersion = snapshot.version
        }

        switch action {
        case let .selectDeck(deck):
            pendingCrownDelta = 0
            let command = WatchCommand(snapshotVersion: snapshot.version, kind: .selectDeck, value: .deck(deck))
            try validator.validate(command, against: snapshot)
            return command
        case let .focusApp(appID):
            pendingCrownDelta = 0
            let command = WatchCommand(snapshotVersion: snapshot.version, kind: .focusApp, appID: appID)
            try validator.validate(command, against: snapshot)
            return command
        case let .primaryAction(appID):
            pendingCrownDelta = 0
            let command = WatchCommand(snapshotVersion: snapshot.version, kind: .primaryAction, appID: appID)
            try validator.validate(command, against: snapshot)
            return command
        case let .secondaryAction(appID):
            pendingCrownDelta = 0
            let command = WatchCommand(snapshotVersion: snapshot.version, kind: .secondaryAction, appID: appID)
            try validator.validate(command, against: snapshot)
            return command
        case let .chronos(action):
            pendingCrownDelta = 0
            let command = WatchCommand(
                snapshotVersion: snapshot.version,
                kind: .chronos,
                appID: .chronos,
                value: .chronos(action)
            )
            try validator.validate(command, against: snapshot)
            return command
        case let .teleprompter(action):
            pendingCrownDelta = 0
            let command = WatchCommand(
                snapshotVersion: snapshot.version,
                kind: .teleprompter,
                appID: .teleprompter,
                value: .teleprompter(action)
            )
            try validator.validate(command, against: snapshot)
            return command
        case let .signal(action):
            pendingCrownDelta = 0
            let command = WatchCommand(
                snapshotVersion: snapshot.version,
                kind: .signal,
                appID: .signal,
                value: .signal(action)
            )
            try validator.validate(command, against: snapshot)
            return command
        case let .babel(action):
            pendingCrownDelta = 0
            let command = WatchCommand(
                snapshotVersion: snapshot.version,
                kind: .babel,
                appID: .babel,
                value: .babel(action)
            )
            try validator.validate(command, against: snapshot)
            return command
        case let .vision(action):
            pendingCrownDelta = 0
            let command = WatchCommand(
                snapshotVersion: snapshot.version,
                kind: .vision,
                appID: .vision,
                value: .vision(action)
            )
            try validator.validate(command, against: snapshot)
            return command
        case let .oracle(action):
            pendingCrownDelta = 0
            let command = WatchCommand(
                snapshotVersion: snapshot.version,
                kind: .oracle,
                appID: .oracle,
                value: .oracle(action)
            )
            try validator.validate(command, against: snapshot)
            return command
        case let .togglePrivacy(enabled):
            pendingCrownDelta = 0
            let command = WatchCommand(snapshotVersion: snapshot.version, kind: .togglePrivacy, value: .flag(enabled))
            try validator.validate(command, against: snapshot)
            return command
        case let .crownDelta(delta):
            guard delta != 0 else {
                return nil
            }
            pendingCrownDelta += delta
            return nil
        case .commitCrown:
            guard pendingCrownDelta != 0 else {
                return nil
            }
            let command = WatchCommand(
                snapshotVersion: snapshot.version,
                kind: .crownDelta,
                value: .delta(pendingCrownDelta)
            )
            try validator.validate(command, against: snapshot)
            pendingCrownDelta = 0
            return command
        case .refreshSnapshot:
            pendingCrownDelta = 0
            let command = WatchCommand(snapshotVersion: snapshot.version, kind: .refreshSnapshot)
            try validator.validate(command, against: snapshot)
            return command
        case .cancel:
            pendingCrownDelta = 0
            let command = WatchCommand(snapshotVersion: snapshot.version, kind: .cancel)
            try validator.validate(command, against: snapshot)
            return command
        }
    }
}

public extension WatchSnapshot {
    static func sample(
        version: UInt64 = 1,
        activeSurface: WatchSurface = .app(.oracle),
        connection: ConnectionState = .phone,
        privacyMode: Bool = false,
        captureActive: Bool = false,
        wrongDeviceRisk: Bool = false,
        activeApp: PrismAppID = .oracle,
        chronos: WatchChronosState? = nil,
        teleprompter: WatchTeleprompterState? = nil,
        signal: WatchSignalState? = nil,
        babel: WatchBabelState? = nil,
        vision: WatchVisionState? = nil,
        oracle: WatchOracleState? = nil,
        acknowledgement: WatchAcknowledgement? = nil
    ) -> WatchSnapshot {
        let chronosState = chronos ?? (activeApp == .chronos ? WatchChronosState() : nil)
        let teleprompterState = teleprompter ?? (activeApp == .teleprompter ? WatchTeleprompterState.sample() : nil)
        let signalState = signal ?? (activeApp == .signal ? WatchSignalState.sample() : nil)
        let babelState = babel ?? (activeApp == .babel ? WatchBabelState.sample() : nil)
        let visionState = vision ?? (activeApp == .vision ? WatchVisionState.sample() : nil)
        let oracleState = oracle ?? (activeApp == .oracle ? WatchOracleState.sample(
            phase: .answer,
            density: .balanced,
            pageIndex: 0,
            pageCount: 2,
            historyCount: 3,
            isKept: true,
            promptText: "WHAT IS TUNGSTEN?",
            pageText: "3422 C (6192 F)."
        ) : nil)
        return WatchSnapshot(
            version: version,
            activeSurface: activeSurface,
            connection: connection,
            privacyMode: privacyMode,
            captureActive: captureActive,
            wrongDeviceRisk: wrongDeviceRisk,
            widgets: PrismAppID.allCases.map { appID in
                switch appID {
                case .chronos:
                    return WatchAppWidget(
                        appID: appID,
                        subtitle: chronosState?.compactTitle,
                        isFocused: appID == activeApp
                    )
                case .teleprompter:
                    return WatchAppWidget(
                        appID: appID,
                        subtitle: teleprompterState?.compactTitle,
                        isFocused: appID == activeApp
                    )
                case .signal:
                    return WatchAppWidget(
                        appID: appID,
                        subtitle: signalState?.titleLine,
                        isFocused: appID == activeApp
                    )
                case .babel:
                    return WatchAppWidget(
                        appID: appID,
                        subtitle: babelState?.compactTitle,
                        isFocused: appID == activeApp
                    )
                case .vision:
                    return WatchAppWidget(
                        appID: appID,
                        subtitle: visionState?.compactTitle,
                        isFocused: appID == activeApp
                    )
                case .oracle:
                    return WatchAppWidget(
                        appID: appID,
                        subtitle: oracleState?.compactTitle,
                        isFocused: appID == activeApp
                    )
                }
            },
            activeApp: activeApp == .chronos
                ? WatchAppSummary(
                    appID: activeApp,
                    subtitle: chronosState?.compactTitle ?? WatchAppSummary(appID: activeApp).subtitle,
                    primaryActionTitle: chronosState?.primaryActionTitle ?? "START",
                    secondaryActionTitle: chronosState?.secondaryActionTitle ?? "RESET",
                    isPrivacySensitive: false
                )
                : activeApp == .teleprompter
                ? WatchAppSummary(
                    appID: activeApp,
                    subtitle: teleprompterState?.compactTitle ?? WatchAppSummary(appID: activeApp).subtitle,
                    primaryActionTitle: teleprompterState?.primaryActionTitle ?? "PLAY",
                    secondaryActionTitle: teleprompterState?.secondaryActionTitle ?? "BOOKMARK",
                    isPrivacySensitive: true
                )
                : activeApp == .signal
                ? WatchAppSummary(
                    appID: activeApp,
                    subtitle: signalState?.titleLine ?? WatchAppSummary(appID: activeApp).subtitle,
                    primaryActionTitle: signalState?.primaryActionTitle ?? "DISMISS",
                    secondaryActionTitle: signalState?.secondaryActionTitle,
                    isPrivacySensitive: true
                )
                : activeApp == .babel
                ? WatchAppSummary(
                    appID: activeApp,
                    subtitle: babelState?.compactTitle ?? WatchAppSummary(appID: activeApp).subtitle,
                    primaryActionTitle: babelState?.primaryActionTitle ?? "FREEZE",
                    secondaryActionTitle: babelState?.secondaryActionTitle,
                    isPrivacySensitive: true
                )
                : activeApp == .vision
                ? WatchAppSummary(
                    appID: activeApp,
                    subtitle: visionState?.compactTitle ?? WatchAppSummary(appID: activeApp).subtitle,
                    primaryActionTitle: visionState?.primaryActionTitle ?? "CAPTURE",
                    secondaryActionTitle: visionState?.secondaryActionTitle,
                    isPrivacySensitive: true
                )
                : activeApp == .oracle
                ? WatchAppSummary(
                    appID: activeApp,
                    subtitle: oracleState?.compactTitle ?? WatchAppSummary(appID: activeApp).subtitle,
                    primaryActionTitle: oracleState?.primaryActionTitle ?? "ASK",
                    secondaryActionTitle: oracleState?.secondaryActionTitle ?? "CLEAR",
                    isPrivacySensitive: true
                )
                : WatchAppSummary(appID: activeApp),
            oracle: oracleState,
            chronos: chronosState,
            teleprompter: teleprompterState,
            signal: signalState,
            babel: babelState,
            vision: visionState,
            lastAcknowledgement: acknowledgement
        )
    }
}
