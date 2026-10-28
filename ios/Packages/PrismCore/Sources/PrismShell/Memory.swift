import Foundation

public enum ArtifactKind: String, Codable, CaseIterable, Sendable { case note, transcript, answer, translation, decision, receipt, event, capture }
public enum Sensitivity: String, Codable, Sendable { case personal, sensitive }
public struct Provenance: Codable, Equatable, Sendable {
    public var source: String
    public var provider: String?
    public var requestID: UUID?
    public var createdAt: Date
    public init(source: String, provider: String? = nil, requestID: UUID? = nil, createdAt: Date = Date()) {
        self.source = source; self.provider = provider; self.requestID = requestID; self.createdAt = createdAt
    }
}
public struct LibraryArtifact: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var kind: ArtifactKind
    public var title: String
    public var body: String
    public var project: String?
    public var topic: String?
    public var provenance: Provenance
    public var sensitivity: Sensitivity
    public var expiresAt: Date?
    public var rawMedia: Data?
    public var candidate: ProactiveCandidate?
    public init(id: UUID = UUID(), sessionID: UUID, kind: ArtifactKind, title: String, body: String,
                project: String? = nil, topic: String? = nil, provenance: Provenance, sensitivity: Sensitivity = .personal,
                expiresAt: Date? = nil, rawMedia: Data? = nil, candidate: ProactiveCandidate? = nil) {
        self.id = id; self.sessionID = sessionID; self.kind = kind; self.title = title; self.body = body
        self.project = project; self.topic = topic; self.provenance = provenance; self.sensitivity = sensitivity
        self.expiresAt = expiresAt; self.rawMedia = rawMedia; self.candidate = candidate
    }
}
public struct ConversationRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var userText: String
    public var turn: AssistantTurn?
    public var provenance: Provenance
    public var status: String
    public init(id: UUID, sessionID: UUID, userText: String, turn: AssistantTurn? = nil, provenance: Provenance, status: String = "pending") {
        self.id = id; self.sessionID = sessionID; self.userText = userText; self.turn = turn; self.provenance = provenance; self.status = status
    }
}
public struct AssistantSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var kind: SessionKind = .conversation
    public var project: String?
    public var startedAt: Date = Date()
    public init() {}
}
public struct FocusTimer: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var end: Date
    public var completed: Bool = false
    public init(id: String, title: String, end: Date) { self.id = id; self.title = title; self.end = end }
}
public struct PrivacySettings: Codable, Equatable, Sendable {
    public var cloudProcessing = false
    public var calendarEnabled = false
    public var agentEnabled = false
    public var proactiveEnabled = false
    public var privateMode = false
    public var spokenOutput = true
    public var retainRawAudio = false
    public var retentionDays = 30
    public init() {}
}
public enum ReceiptStatus: String, Codable, Sendable { case executing, succeeded, failed, uncertain, undoing, undoUncertain, undone }
public struct ActionReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var requestID: UUID
    public var action: ProposedAction
    public var status: ReceiptStatus
    public var summary: String
    public var externalID: String?
    public var undoToken: String?
    public var createdAt: Date
    public var previousSession: AssistantSession?
    public var previousTimer: FocusTimer?
    public var previousTimerMutationID: String?
    public var previousSessionMutationID: String?
    public init(id: String, requestID: UUID, action: ProposedAction, status: ReceiptStatus, summary: String, createdAt: Date) {
        self.id = id; self.requestID = requestID; self.action = action; self.status = status; self.summary = summary; self.createdAt = createdAt
    }
}
public struct ShellArchive: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var session = AssistantSession()
    public var sessions: [AssistantSession] = []
    public var conversations: [ConversationRecord] = []
    public var artifacts: [LibraryArtifact] = []
    public var receipts: [ActionReceipt] = []
    public var timer: FocusTimer?
    public var timerMutationID: String?
    public var sessionMutationID: String?
    public var privacy = PrivacySettings()
    public var candidateHistory: [String: CandidateHistory] = [:]
    public var lastInterruptionAt: Date?
    public var watchCommands: [UUID] = []
    public var revision = 0
    public init() {}
    public mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Double(max(1, privacy.retentionDays)) * 86400)
        artifacts.removeAll { ($0.expiresAt.map { $0 <= now } ?? false) || $0.provenance.createdAt < cutoff }
        conversations.removeAll { $0.provenance.createdAt < cutoff }
        // Receipts retain identifiers through the policy window; never silently retry an uncertain external effect.
        receipts.removeAll { $0.createdAt < cutoff && ![.executing, .uncertain, .undoing, .undoUncertain].contains($0.status) && ($0.action.tool != .createReminder || [.failed, .undone].contains($0.status)) }
        for i in receipts.indices where receipts[i].createdAt < cutoff {
            receipts[i].action.arguments = .init(); receipts[i].action.summary = "Reminder action"
            receipts[i].summary = "Reminder receipt retained for undo and reconciliation"
        }
        sessions.removeAll { $0.startedAt < cutoff }
        candidateHistory = candidateHistory.filter { $0.value.expiresAt > now }
        if !privacy.retainRawAudio { for i in artifacts.indices { artifacts[i].rawMedia = nil } }
    }
    public func search(_ query: String, project: String? = nil) -> [LibraryArtifact] {
        artifacts.filter { a in
            (project == nil || a.project == project) && (query.isEmpty || [a.title,a.body,a.project ?? "",a.topic ?? ""].contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            })
        }.sorted { $0.provenance.createdAt > $1.provenance.createdAt }
    }
}
@MainActor public protocol ShellRepository: AnyObject {
    func load() throws -> ShellArchive
    func save(_ archive: ShellArchive) throws
}
@MainActor public final class FileShellRepository: ShellRepository {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> ShellArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return ShellArchive() }
        let value = try ShellJSON.decoder().decode(ShellArchive.self, from: Data(contentsOf: url))
        guard value.schemaVersion == 1 else { throw ShellError.invalid("Unsupported Library version. Original file preserved.") }
        return value
    }
    public func save(_ archive: ShellArchive) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let data = try ShellJSON.encoder().encode(archive)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
