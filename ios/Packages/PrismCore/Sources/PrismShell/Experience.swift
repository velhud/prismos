import Foundation

public enum ShellError: Error, Equatable, LocalizedError {
    case invalid(String), unavailable(String), denied(String), stale, cancelled, uncertain
    public var errorDescription: String? {
        switch self {
        case .invalid(let s), .unavailable(let s), .denied(let s): return s
        case .stale: return "This interaction has expired. Ask again."
        case .cancelled: return "Cancelled"
        case .uncertain: return "The action outcome needs reconciliation before retrying."
        }
    }
}

public enum SceneKind: String, Codable, CaseIterable, Sendable {
    case blank, activity, fact, list, comparison, choice, confirmation, progress, caption, timer, alert, route
}
public struct SceneItem: Codable, Equatable, Sendable {
    public var label: String
    public var value: String
    public var actionID: String?
    public init(_ label: String, _ value: String = "", actionID: String? = nil) {
        self.label = label; self.value = value; self.actionID = actionID
    }
}
public struct LensScene: Codable, Equatable, Sendable {
    public var kind: SceneKind
    public var title: String
    public var body: String
    public var items: [SceneItem]
    public var progress: Double?
    public var timerEnd: Date?
    public var expiresInSeconds: Int
    public init(kind: SceneKind, title: String = "", body: String = "", items: [SceneItem] = [],
                progress: Double? = nil, timerEnd: Date? = nil, expiresInSeconds: Int = 30) {
        self.kind = kind; self.title = title; self.body = body; self.items = items
        self.progress = progress; self.timerEnd = timerEnd; self.expiresInSeconds = expiresInSeconds
    }
    public static let blank = LensScene(kind: .blank)
    public static func activity(_ text: String) -> Self { .init(kind: .activity, title: text, body: "Prism", expiresInSeconds: 60) }
    public func validate(actionIDs: Set<String>) throws {
        guard title.utf8.count <= 512, body.utf8.count <= 32_768, items.count <= 32,
              (1...3600).contains(expiresInSeconds), progress.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              items.allSatisfy({ $0.label.utf8.count <= 2048 && $0.value.utf8.count <= 8192 && ($0.actionID.map(actionIDs.contains) ?? true) })
        else { throw ShellError.invalid("Scene exceeds semantic bounds or references an unknown action") }
        switch kind {
        case .comparison: guard items.count >= 2 else { throw ShellError.invalid("Comparison needs two items") }
        case .choice: guard items.count >= 2, items.allSatisfy({ $0.actionID != nil }) else { throw ShellError.invalid("Choices need actions") }
        case .progress: guard progress != nil else { throw ShellError.invalid("Progress needs a value") }
        case .timer: guard timerEnd != nil else { throw ShellError.invalid("Timer needs an end time") }
        case .list: guard !items.isEmpty else { throw ShellError.invalid("List needs items") }
        case .blank: guard title.isEmpty && body.isEmpty && items.isEmpty else { throw ShellError.invalid("Blank scene contains content") }
        default: guard !title.isEmpty || !body.isEmpty else { throw ShellError.invalid("Empty scene") }
        }
    }
}

public enum ToolName: String, Codable, CaseIterable, Sendable {
    case saveNote = "save_note", retrieveNotes = "retrieve_notes", createReminder = "create_reminder"
    case readCalendar = "read_upcoming_calendar", agentStatus = "get_agent_status"
    case continueConversation = "continue_conversation"
    case startTimer = "start_timer", stopTimer = "stop_timer", setSession = "set_session"
    public var mutates: Bool { ![.retrieveNotes, .readCalendar, .agentStatus].contains(self) }
}
public enum SessionKind: String, Codable, CaseIterable, Sendable { case conversation, focus, walk, meeting, build, presentation }
public struct ToolArguments: Codable, Equatable, Sendable {
    public var title: String?
    public var body: String?
    public var project: String?
    public var topic: String?
    public var query: String?
    public var dueAt: Date?
    public var seconds: Int?
    public var sessionKind: SessionKind?
    public init(title: String? = nil, body: String? = nil, project: String? = nil, topic: String? = nil,
                query: String? = nil, dueAt: Date? = nil, seconds: Int? = nil, sessionKind: SessionKind? = nil) {
        self.title = title; self.body = body; self.project = project; self.topic = topic; self.query = query
        self.dueAt = dueAt; self.seconds = seconds; self.sessionKind = sessionKind
    }
}
public struct ProposedAction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var tool: ToolName
    public var summary: String
    public var arguments: ToolArguments
    public init(id: String, tool: ToolName, summary: String, arguments: ToolArguments) {
        self.id = id; self.tool = tool; self.summary = summary; self.arguments = arguments
    }
    public func validate(now: Date) throws {
        guard !id.isEmpty, id.utf8.count <= 80, !summary.isEmpty, summary.utf8.count <= 2048 else { throw ShellError.invalid("Invalid action identity") }
        let a = arguments
        guard (a.title?.utf8.count ?? 0) <= 512, (a.project?.utf8.count ?? 0) <= 512, (a.topic?.utf8.count ?? 0) <= 512 else { throw ShellError.invalid("Tool title or association too long") }
        guard [a.title,a.body,a.project,a.topic,a.query].compactMap({$0}).allSatisfy({$0.utf8.count <= 131_072}) else { throw ShellError.invalid("Tool input too large") }
        switch tool {
        case .saveNote: guard let b = a.body, !b.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              let t = a.title, !t.isEmpty else { throw ShellError.invalid("Note needs a title and complete body") }
        case .retrieveNotes, .continueConversation: guard a.query?.isEmpty == false else { throw ShellError.invalid("Search needs a query") }
        case .createReminder: guard a.title?.isEmpty == false, let due = a.dueAt, due > now,
                                    due.timeIntervalSince(now) < 10 * 366 * 86400 else { throw ShellError.invalid("Clarify reminder title and future date/time") }
        case .startTimer: guard let seconds = a.seconds, (1...86400).contains(seconds), a.title?.isEmpty == false else { throw ShellError.invalid("Timer needs a title and duration of 1 second to 24 hours") }
        case .setSession: guard a.sessionKind != nil else { throw ShellError.invalid("Session kind required") }
        case .readCalendar, .agentStatus, .stopTimer: break
        }
    }
}
public struct ArtifactMutation: Codable, Equatable, Sendable {
    public var title: String
    public var body: String
    public var kind: ArtifactKind
    public var project: String?
    public var topic: String?
    public init(title: String, body: String, kind: ArtifactKind = .note, project: String? = nil, topic: String? = nil) {
        self.title = title; self.body = body; self.kind = kind; self.project = project; self.topic = topic
    }
}
public struct ProactiveDecision: Codable, Equatable, Sendable {
    public enum Disposition: String, Codable, Sendable { case show, phoneOnly, suppress }
    public var candidateID: String
    public var disposition: Disposition
    public var reason: String
    public init(candidateID: String, disposition: Disposition, reason: String) {
        self.candidateID = candidateID; self.disposition = disposition; self.reason = reason
    }
}
public struct AssistantTurn: Codable, Equatable, Sendable {
    public var canonicalAnswer: String
    public var spokenResponse: String?
    public var lensScene: LensScene
    public var proposedActions: [ProposedAction]
    public var artifacts: [ArtifactMutation]
    public var clarification: String?
    public var project: String?
    public var proactiveDecision: ProactiveDecision?
    public init(canonicalAnswer: String, spokenResponse: String? = nil, lensScene: LensScene = .blank,
                proposedActions: [ProposedAction] = [], artifacts: [ArtifactMutation] = [], clarification: String? = nil,
                project: String? = nil, proactiveDecision: ProactiveDecision? = nil) {
        self.canonicalAnswer = canonicalAnswer; self.spokenResponse = spokenResponse; self.lensScene = lensScene
        self.proposedActions = proposedActions; self.artifacts = artifacts; self.clarification = clarification
        self.project = project; self.proactiveDecision = proactiveDecision
    }
    public func validate(now: Date) throws {
        guard !canonicalAnswer.isEmpty, canonicalAnswer.utf8.count <= 262_144,
              (spokenResponse?.utf8.count ?? 0) <= 65_536, proposedActions.count <= 8, artifacts.count <= 16,
              Set(proposedActions.map(\.id)).count == proposedActions.count else { throw ShellError.invalid("Invalid assistant turn") }
        if clarification != nil && !proposedActions.isEmpty { throw ShellError.invalid("Clarification cannot execute actions") }
        try lensScene.validate(actionIDs: Set(proposedActions.map(\.id)))
        for action in proposedActions { guard action.tool.mutates else { throw ShellError.invalid("Read tools must run through the read contract") }; try action.validate(now: now) }
        for artifact in artifacts {
            guard artifact.kind != .receipt, !artifact.title.isEmpty, artifact.body.utf8.count <= 262_144 else { throw ShellError.invalid("Invalid artifact") }
        }
    }
}
public struct ExperiencePlan: Codable, Equatable, Sendable {
    public var version: Int
    public var turn: AssistantTurn
    public init(turn: AssistantTurn) { version = 1; self.turn = turn }
    public func validate(now: Date) throws { guard version == 1 else { throw ShellError.invalid("Unsupported experience version") }; try turn.validate(now: now) }
}
public enum ShellJSON {
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw ShellError.invalid("Invalid ISO8601 date") }; return date
        }
        return d
    }
}
