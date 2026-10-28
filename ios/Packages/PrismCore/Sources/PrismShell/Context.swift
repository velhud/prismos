import Foundation

public struct CalendarItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var modifiedAt: Date?
    public init(id: String, title: String, start: Date, end: Date, location: String? = nil, modifiedAt: Date? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.location = location; self.modifiedAt = modifiedAt
    }
}
public struct AgentException: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var project: String?
    public var summary: String
    public var observedAt: Date
    public var expiresAt: Date
    public init(id: String, project: String?, summary: String, observedAt: Date, expiresAt: Date) {
        self.id = id; self.project = project; self.summary = summary; self.observedAt = observedAt; self.expiresAt = expiresAt
    }
}
public struct ContextSnapshot: Codable, Equatable, Sendable {
    public var calendar: [CalendarItem] = []
    public var agentExceptions: [AgentException] = []
    public var observedAt: Date
    public var unavailableSources: [String] = []
    public init(observedAt: Date = Date()) { self.observedAt = observedAt }
}
public struct ToolDescriptor: Codable, Equatable, Sendable {
    public var name: ToolName
    public var purpose: String
    public var requiresConfirmation: Bool
    public var supportsUndo: Bool
    public static let catalog: [ToolDescriptor] = [
        .init(name: .saveNote, purpose: "Save a complete structured note with project and topic", requiresConfirmation: true, supportsUndo: true),
        .init(name: .retrieveNotes, purpose: "Search full Library text using a model-selected query; interpret and rank returned records yourself", requiresConfirmation: false, supportsUndo: false),
        .init(name: .createReminder, purpose: "Create an EventKit reminder at an explicit future date/time; clarify ambiguity", requiresConfirmation: true, supportsUndo: true),
        .init(name: .readCalendar, purpose: "Read permitted upcoming calendar items", requiresConfirmation: false, supportsUndo: false),
        .init(name: .agentStatus, purpose: "Read authenticated agent exception snapshot when configured", requiresConfirmation: false, supportsUndo: false),
        .init(name: .startTimer, purpose: "Start a bounded focus timer", requiresConfirmation: true, supportsUndo: true),
        .init(name: .stopTimer, purpose: "Stop current focus timer", requiresConfirmation: true, supportsUndo: true),
        .init(name: .setSession, purpose: "Set active session kind and project", requiresConfirmation: true, supportsUndo: true)
    ]
}
public struct ContextBundle: Codable, Equatable, Sendable {
    public var currentTime: Date
    public var timeZone: String
    public var session: AssistantSession
    public var recentTurns: [ConversationRecord]
    public var recentArtifacts: [LibraryArtifact]
    public var sources: ContextSnapshot
    public var deviceConnected: Bool
    public var privateMode: Bool
    public var timer: FocusTimer?
    public var tools: [ToolDescriptor]
    public var omittedTurnCount: Int
    public static func assemble(archive: ShellArchive, sources: ContextSnapshot, connected: Bool, now: Date) -> ContextBundle {
        let records = archive.conversations.filter { $0.sessionID == archive.session.id }
        // Retain full records in storage. Admit whole records to a bounded request, never HUD fragments.
        var selected: [ConversationRecord] = []; var bytes = 0
        for record in records.suffix(12).reversed() {
            let size = (try? ShellJSON.encoder().encode(record).count) ?? 0
            if bytes + size > 196_608 { break }; selected.insert(record, at: 0); bytes += size
        }
        var artifacts: [LibraryArtifact] = []; var artifactBytes = 0
        for var artifact in archive.artifacts.suffix(12).reversed() {
            artifact.rawMedia = nil
            let size = (try? ShellJSON.encoder().encode(artifact).count) ?? 0
            if artifactBytes + size > 131_072 { continue }; artifacts.append(artifact); artifactBytes += size
        }
        return .init(currentTime: now, timeZone: TimeZone.current.identifier, session: archive.session,
                     recentTurns: selected, recentArtifacts: artifacts, sources: sources, deviceConnected: connected,
                     privateMode: archive.privacy.privateMode, timer: archive.timer, tools: ToolDescriptor.catalog,
                     omittedTurnCount: records.count - selected.count)
    }
}
public struct ProactiveCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var source: String
    public var observedAt: Date
    public var eventTime: Date
    public var reason: String
    public var expiresAt: Date
    public var content: String
    public var sensitive: Bool
    public init(id: String, source: String, observedAt: Date, eventTime: Date, reason: String,
                expiresAt: Date, content: String, sensitive: Bool = true) {
        self.id = id; self.source = source; self.observedAt = observedAt; self.eventTime = eventTime
        self.reason = reason; self.expiresAt = expiresAt; self.content = content; self.sensitive = sensitive
    }
}
public struct CandidateHistory: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case evaluated, shown, dismissed, snoozed, suppressed }
    public var state: State
    public var expiresAt: Date
    public var snoozedUntil: Date?
    public var interpretation: String?
    public init(state: State, expiresAt: Date, snoozedUntil: Date? = nil, interpretation: String? = nil) {
        self.state = state; self.expiresAt = expiresAt; self.snoozedUntil = snoozedUntil; self.interpretation = interpretation
    }
}
public protocol ProactiveSource {
    func candidates(snapshot: ContextSnapshot, now: Date) -> [ProactiveCandidate]
}
public struct CalendarProactiveSource: ProactiveSource {
    public init() {}
    public func candidates(snapshot: ContextSnapshot, now: Date) -> [ProactiveCandidate] {
        guard abs(now.timeIntervalSince(snapshot.observedAt)) <= 90, !snapshot.unavailableSources.contains("calendar") else { return [] }
        return snapshot.calendar.filter { $0.start > now && $0.start.timeIntervalSince(now) <= 1800 }.map {
            // Identity/version, time window and source existence are mechanics; relevance is left to AI.
            let stamp = Int($0.start.timeIntervalSince1970)
            let revision = Int(($0.modifiedAt ?? $0.start).timeIntervalSince1970)
            return .init(id: "calendar:\($0.id):\(stamp):\(revision)", source: "calendar", observedAt: snapshot.observedAt,
                         eventTime: $0.start, reason: "Calendar event starts within 30 minutes", expiresAt: $0.start,
                         content: "\($0.title)\n\($0.location ?? "")")
        }
    }
}
@MainActor public protocol NativeToolBoundary: AnyObject {
    func context(privacy: PrivacySettings, now: Date) async -> ContextSnapshot
    func createReminder(arguments: ToolArguments, idempotencyKey: String) async throws -> String
    func findReminder(idempotencyKey: String) async throws -> String?
    func undoReminder(externalID: String, idempotencyKey: String) async throws
}
public struct ModelRequest: Codable, Equatable, Sendable {
    public var id: UUID
    public var input: String
    public var context: ContextBundle
    public var candidates: [ProactiveCandidate]
    public var toolResults: [ToolReadResult]
    public init(id: UUID, input: String, context: ContextBundle, candidates: [ProactiveCandidate] = [], toolResults: [ToolReadResult] = []) {
        self.id = id; self.input = input; self.context = context; self.candidates = candidates; self.toolResults = toolResults
    }
}
public struct ToolReadResult: Codable, Equatable, Sendable {
    public var callID: String
    public var tool: ToolName
    public var content: String
    public init(callID: String, tool: ToolName, content: String) { self.callID = callID; self.tool = tool; self.content = content }
}
public enum ModelStep: Equatable, Sendable { case plan(ExperiencePlan), reads([ReadToolCall]) }
public struct ReadToolCall: Codable, Equatable, Sendable {
    public var id: String
    public var name: ToolName
    public var arguments: ToolArguments
    public init(id: String, name: ToolName, arguments: ToolArguments) { self.id = id; self.name = name; self.arguments = arguments }
}
public protocol ExperienceModel: Sendable {
    var providerID: String { get }
    func generate(_ request: ModelRequest) async throws -> ModelStep
}
/// Future voice adapters return transcripts to this host-owned orchestrator, never own its state/tools.
@MainActor public protocol ShellVoiceOutput: AnyObject {
    func speak(_ text: String)
    func stop()
}
@MainActor public protocol ShellDeviceLink: AnyObject {
    func blank()
    func beginInteraction() throws
    func project(_ payload: Data) throws
    func captureAudio(requestID: UUID) throws
    func cancelCapture()
}
