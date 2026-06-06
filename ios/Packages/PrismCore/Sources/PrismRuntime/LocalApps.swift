import Foundation
import PrismDraw
import PrismModels

public enum ChronosMode: String, Sendable, Codable {
    case timer
    case stopwatch
}

public enum ChronosRunState: String, Sendable, Codable {
    case setup
    case running
    case paused
    case alarm
}

public struct LocalAlertRequest: Equatable, Sendable, Codable {
    public enum Delivery: String, Sendable, Codable {
        case notificationAndHaptic
    }

    public var id: UUID
    public var appID: PrismAppID
    public var title: String
    public var body: String
    public var delivery: Delivery

    public init(
        id: UUID = UUID(),
        appID: PrismAppID,
        title: String,
        body: String,
        delivery: Delivery = .notificationAndHaptic
    ) {
        self.id = id
        self.appID = appID
        self.title = title
        self.body = body
        self.delivery = delivery
    }
}

public struct ChronosState: Equatable, Sendable, Codable {
    public var id: UUID
    public var mode: ChronosMode
    public var totalSeconds: Int
    public var startedAt: Date?
    public var accumulatedSeconds: Int
    public var runState: ChronosRunState
    public var pinned: Bool

    public init(
        id: UUID = UUID(),
        mode: ChronosMode = .timer,
        totalSeconds: Int = 300,
        startedAt: Date? = nil,
        accumulatedSeconds: Int = 0,
        runState: ChronosRunState = .setup,
        pinned: Bool = false
    ) {
        self.id = id
        self.mode = mode
        self.totalSeconds = min(max(totalSeconds, 1), 24 * 60 * 60)
        self.startedAt = startedAt
        self.accumulatedSeconds = max(0, accumulatedSeconds)
        self.runState = runState
        self.pinned = pinned
    }

    public func elapsed(at now: Date) -> Int {
        let currentRun = startedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        return accumulatedSeconds + currentRun
    }

    public func remaining(at now: Date) -> Int {
        max(0, totalSeconds - elapsed(at: now))
    }
}

public struct ChronosEngine: Sendable {
    public private(set) var state: ChronosState

    public init(state: ChronosState = ChronosState()) {
        self.state = state
    }

    public mutating func start(at now: Date) {
        guard state.runState != .alarm else { return }
        state.startedAt = now
        state.runState = .running
    }

    public mutating func pause(at now: Date) {
        guard state.runState == .running else { return }
        state.accumulatedSeconds = state.elapsed(at: now)
        state.startedAt = nil
        state.runState = .paused
    }

    public mutating func reset(totalSeconds: Int? = nil) {
        state = ChronosState(mode: state.mode, totalSeconds: totalSeconds ?? state.totalSeconds, pinned: state.pinned)
    }

    public mutating func toggleMode() {
        let nextMode: ChronosMode = state.mode == .timer ? .stopwatch : .timer
        state = ChronosState(mode: nextMode, totalSeconds: state.totalSeconds, pinned: state.pinned)
    }

    public mutating func togglePinned() {
        state.pinned.toggle()
    }

    public mutating func adjustDuration(by delta: Int) {
        state.totalSeconds = min(max(state.totalSeconds + delta, 1), 24 * 60 * 60)
        state.accumulatedSeconds = min(state.accumulatedSeconds, state.totalSeconds)
    }

    public mutating func dismissAlarm() {
        guard state.runState == .alarm else { return }
        reset(totalSeconds: state.totalSeconds)
    }

    public mutating func tick(at now: Date) {
        guard state.mode == .timer, state.runState == .running, state.remaining(at: now) == 0 else { return }
        state.accumulatedSeconds = state.totalSeconds
        state.startedAt = nil
        state.runState = .alarm
    }

    public func alertRequest() -> LocalAlertRequest? {
        guard state.runState == .alarm else { return nil }
        return LocalAlertRequest(
            id: state.id,
            appID: .chronos,
            title: "Chronos",
            body: "Timer complete"
        )
    }

    public func render(at now: Date) -> DrawViewport {
        let main: String
        let status: String
        let progress: Int
        switch state.mode {
        case .timer:
            main = format(seconds: state.remaining(at: now))
            status = state.runState == .alarm ? "ALARM" : (state.pinned ? "PINNED TIMER" : "TIMER")
            progress = state.totalSeconds == 0 ? 100 : min(max((state.elapsed(at: now) * 100) / state.totalSeconds, 0), 100)
        case .stopwatch:
            main = format(seconds: state.elapsed(at: now))
            status = state.pinned ? "PINNED STOPWATCH" : "STOPWATCH"
            progress = (state.elapsed(at: now) % 60) * 100 / 60
        }
        let command: String
        switch state.runState {
        case .alarm:
            command = "TAP DISMISS"
        case .running:
            command = "L/R PIN  HOLD R PAUSE"
        case .setup, .paused:
            command = "L/R ADJ  HOLD R RUN"
        }
        return MonocleLensLayout.viewport(
            appID: .chronos,
            title: "CHRONOS",
            lines: [main, status, state.mode.rawValue.uppercased(), "\(progress)%"],
            command: command,
            right: "\(progress)%",
            accent: MonocleLensLayout.yellow
        )
    }

    private func format(seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

public enum TeleprompterMode: String, Sendable, Codable {
    case manual
    case auto
}

public struct TeleprompterScript: Equatable, Sendable, Codable {
    public var id: UUID
    public var title: String
    public var chunks: [String]
    public var currentIndex: Int
    public var mode: TeleprompterMode
    public var wordsPerMinute: Int
    public var bookmarkIndex: Int?

    public init(
        id: UUID = UUID(),
        title: String,
        chunks: [String],
        currentIndex: Int = 0,
        mode: TeleprompterMode = .manual,
        wordsPerMinute: Int = 140,
        bookmarkIndex: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.chunks = chunks
        self.currentIndex = min(max(currentIndex, 0), max(chunks.count - 1, 0))
        self.mode = mode
        self.wordsPerMinute = min(max(wordsPerMinute, 60), 240)
        self.bookmarkIndex = bookmarkIndex
    }
}

public struct TeleprompterEngine: Sendable {
    public private(set) var script: TeleprompterScript

    public init(script: TeleprompterScript = TeleprompterEngine.emptyScript) {
        self.script = script
    }

    public static let emptyScript = TeleprompterScript(title: "Empty", chunks: [])

    public static func importScript(title: String, body: String, maxLineCharacters: Int = 22) -> TeleprompterScript {
        let words = body
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .map(String.init)
        var chunks: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if candidate.count <= maxLineCharacters {
                current = candidate
            } else {
                if !current.isEmpty {
                    chunks.append(current)
                }
                current = String(word.prefix(maxLineCharacters))
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return TeleprompterScript(title: title, chunks: chunks)
    }

    public mutating func edit(body: String) {
        script = Self.importScript(title: script.title, body: body)
    }

    public mutating func next() {
        moveLine(by: 1)
    }

    public mutating func previous() {
        moveLine(by: -1)
    }

    public mutating func toggleAuto() {
        script.mode = script.mode == .manual ? .auto : .manual
    }

    public mutating func setWordsPerMinute(_ wordsPerMinute: Int) {
        script.wordsPerMinute = min(max(wordsPerMinute, 60), 240)
    }

    public mutating func resetToStart() {
        script.currentIndex = 0
    }

    public mutating func moveLine(by delta: Int) {
        guard !script.chunks.isEmpty, delta != 0 else { return }
        let upperBound = max(script.chunks.count - 1, 0)
        script.currentIndex = min(max(script.currentIndex + delta, 0), upperBound)
    }

    public mutating func bookmark() {
        script.bookmarkIndex = script.currentIndex
    }

    public mutating func tickTeleprompter(at now: Date, lastAdvanceAt: inout Date) {
        guard script.mode == .auto, !script.chunks.isEmpty else {
            lastAdvanceAt = now
            return
        }

        let interval = max(1.0, 240.0 / Double(script.wordsPerMinute))
        guard now.timeIntervalSince(lastAdvanceAt) >= interval else { return }

        moveLine(by: 1)
        lastAdvanceAt = now
    }

    public mutating func bookmarkOrReset() {
        if script.bookmarkIndex == script.currentIndex {
            script.currentIndex = 0
            script.bookmarkIndex = nil
        } else {
            script.bookmarkIndex = script.currentIndex
        }
    }

    public func render() -> DrawViewport {
        guard !script.chunks.isEmpty else {
            return MonocleLensLayout.viewport(
                appID: .teleprompter,
                title: "TELEPROMPT",
                lines: ["NO SCRIPT", "IMPORT ON PHONE"],
                command: "OPEN PHONE",
                accent: MonocleLensLayout.cyan
            )
        }

        let previous = line(at: script.currentIndex - 1) ?? ""
        let current = line(at: script.currentIndex) ?? ""
        let next = line(at: script.currentIndex + 1) ?? ""
        let progress = Int(Double(script.currentIndex + 1) / Double(max(script.chunks.count, 1)) * 100.0)
        let command = script.mode == .auto ? "L/R SPEED HOLD R MAN" : "L/R LINE  HOLD R AUTO"
        return MonocleLensLayout.viewport(
            appID: .teleprompter,
            title: "TELEPROMPT",
            lines: ["  \(previous)", "> \(current)", "  \(next)", "\(script.mode.rawValue.uppercased()) \(script.wordsPerMinute) WPM", "\(progress)%"],
            command: command,
            left: "\(script.currentIndex + 1)/\(script.chunks.count)",
            accent: MonocleLensLayout.cyan
        )
    }

    private func line(at index: Int) -> String? {
        guard script.chunks.indices.contains(index) else { return nil }
        return script.chunks[index]
    }
}

public enum SignalPriority: Int, CaseIterable, Sendable, Codable {
    case info = 0
    case important = 1
    case critical = 2

    public var displayName: String {
        switch self {
        case .info:
            "Info"
        case .important:
            "Important"
        case .critical:
            "Critical"
        }
    }
}

public struct SignalCard: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var source: String
    public var title: String
    public var body: String
    public var priority: SignalPriority
    public var handoffURL: String?
    public var expiresAt: Date?

    public init(
        id: UUID = UUID(),
        source: String,
        title: String,
        body: String,
        priority: SignalPriority = .info,
        handoffURL: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.body = body
        self.priority = priority
        self.handoffURL = handoffURL
        self.expiresAt = expiresAt
    }
}

public struct SignalStack: Equatable, Sendable {
    public private(set) var cards: [SignalCard]
    public private(set) var dismissedIDs: Set<UUID>
    public private(set) var selectedCardID: UUID?
    public var privacyMode: Bool
    public var allowedSources: Set<String>

    public init(
        cards: [SignalCard] = [],
        dismissedIDs: Set<UUID> = [],
        selectedCardID: UUID? = nil,
        privacyMode: Bool = false,
        allowedSources: Set<String> = []
    ) {
        self.cards = cards
        self.dismissedIDs = dismissedIDs
        self.selectedCardID = selectedCardID
        self.privacyMode = privacyMode
        self.allowedSources = allowedSources
        normalizeSelection()
    }

    public var visibleCards: [SignalCard] {
        cards
            .filter { !dismissedIDs.contains($0.id) }
            .filter { allowedSources.isEmpty || allowedSources.contains($0.source) }
            .sorted { left, right in
                if left.priority.rawValue == right.priority.rawValue {
                    return left.title < right.title
                }
                return left.priority.rawValue > right.priority.rawValue
            }
    }

    public var currentCard: SignalCard? {
        let cards = visibleCards
        if let selectedCardID, let selected = cards.first(where: { $0.id == selectedCardID }) {
            return selected
        }
        return cards.first
    }

    public var currentIndex: Int? {
        guard let currentCard else { return nil }
        return visibleCards.firstIndex(where: { $0.id == currentCard.id })
    }

    public var visibleCardCount: Int {
        visibleCards.count
    }

    public var hasCurrentHandoff: Bool {
        currentCard?.handoffURL != nil
    }

    public mutating func dismissCurrent() {
        guard let currentCard else { return }
        let cards = visibleCards
        let currentIndex = cards.firstIndex(where: { $0.id == currentCard.id }) ?? 0
        dismissedIDs.insert(currentCard.id)
        let remainingCards = visibleCards
        guard !remainingCards.isEmpty else {
            selectedCardID = nil
            return
        }
        selectedCardID = remainingCards[min(currentIndex, remainingCards.count - 1)].id
    }

    public mutating func reload(cards: [SignalCard]) {
        self.cards = cards
        dismissedIDs.removeAll()
        selectedCardID = nil
        normalizeSelection()
    }

    public mutating func moveSelection(by delta: Int) {
        guard delta != 0, !visibleCards.isEmpty else { return }
        let cards = visibleCards
        let currentIndex = self.currentIndex ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), cards.count - 1)
        selectedCardID = cards[nextIndex].id
    }

    public mutating func selectCurrentCard(_ cardID: UUID?) {
        selectedCardID = cardID
        normalizeSelection()
    }

    public mutating func cleanupExpired(now: Date) {
        cards.removeAll { card in
            card.expiresAt.map { $0 <= now } ?? false
        }
        normalizeSelection()
    }

    public mutating func togglePrivacy() {
        privacyMode.toggle()
    }

    public mutating func reloadSession() {
        reload(cards: cards)
    }

    public func openCurrentHandoff() -> String? {
        currentCard?.handoffURL
    }

    public func render() -> DrawViewport {
        guard let card = currentCard else {
            return MonocleLensLayout.viewport(
                appID: .signal,
                title: "SIGNAL",
                lines: ["EMPTY STACK", "R RELOAD"],
                command: "R RELOAD",
                left: "0/0",
                accent: MonocleLensLayout.green
            )
        }
        let title = privacyMode ? "PRIVATE" : card.title
        let body = privacyMode ? "OPEN PHONE" : card.body
        let count = currentIndex.map { "\($0 + 1)/\(visibleCardCount)" } ?? "1/\(max(visibleCardCount, 1))"
        let command = hasCurrentHandoff ? "R DISMISS HOLD R OPEN" : "L NEXT   R DISMISS"
        return MonocleLensLayout.viewport(
            appID: .signal,
            title: "SIGNAL",
            lines: [card.priority.displayName.uppercased(), title, body],
            command: command,
            left: count,
            right: privacyMode ? "PRIV" : String(card.source.prefix(5)).uppercased(),
            accent: MonocleLensLayout.green
        )
    }

    private mutating func normalizeSelection() {
        let cards = visibleCards
        guard !cards.isEmpty else {
            selectedCardID = nil
            return
        }
        if let selectedCardID, cards.contains(where: { $0.id == selectedCardID }) {
            return
        }
        selectedCardID = cards.first?.id
    }
}
