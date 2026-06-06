import Foundation

public protocol PrismRepository: Sendable {
    associatedtype Entity: Sendable

    func list() async throws -> [Entity]
    func save(_ entity: Entity) async throws
    func delete(_ entity: Entity) async throws
}

public actor InMemoryRepository<Entity: Identifiable & Equatable & Sendable>: PrismRepository where Entity.ID: Hashable & Sendable {
    private var storage: [Entity.ID: Entity]

    public init(_ entities: [Entity] = []) {
        self.storage = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
    }

    public func list() async throws -> [Entity] {
        Array(storage.values)
    }

    public func save(_ entity: Entity) async throws {
        storage[entity.id] = entity
    }

    public func delete(_ entity: Entity) async throws {
        storage.removeValue(forKey: entity.id)
    }
}

public actor JSONFileRepository<Entity: Identifiable & Codable & Equatable & Sendable>: PrismRepository
where Entity.ID: Hashable & Codable & Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func list() async throws -> [Entity] {
        try load()
    }

    public func save(_ entity: Entity) async throws {
        var entities = try load()
        if let index = entities.firstIndex(where: { $0.id == entity.id }) {
            entities[index] = entity
        } else {
            entities.append(entity)
        }
        try persist(entities)
    }

    public func delete(_ entity: Entity) async throws {
        var entities = try load()
        entities.removeAll { $0.id == entity.id }
        try persist(entities)
    }

    private func load() throws -> [Entity] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([Entity].self, from: data)
    }

    private func persist(_ entities: [Entity]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(entities)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public struct AppSettingsSnapshot: Equatable, Sendable, Codable {
    public var selectedDeviceID: String?
    public var backgroundBLEEnabled: Bool
    public var developerModeEnabled: Bool
    public var shapePrimitivesEnabled: Bool
    public var diagnosticsRedaction: String

    public init(
        selectedDeviceID: String? = nil,
        backgroundBLEEnabled: Bool = false,
        developerModeEnabled: Bool = false,
        shapePrimitivesEnabled: Bool = false,
        diagnosticsRedaction: String = "redacted"
    ) {
        self.selectedDeviceID = selectedDeviceID
        self.backgroundBLEEnabled = backgroundBLEEnabled
        self.developerModeEnabled = developerModeEnabled
        self.shapePrimitivesEnabled = shapePrimitivesEnabled
        self.diagnosticsRedaction = diagnosticsRedaction
    }
}

public struct SessionStateSnapshot: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var connectionState: String
    public var activeAppID: String?
    public var orbitSelection: String?
    public var focused: Bool
    public var lastButtonEvent: String?
    public var lastDrawSummary: String?
    public var pendingMediaRequestIDs: [String]
    public var lastProviderRequestIDs: [String]

    public init(
        id: String = "default",
        connectionState: String,
        activeAppID: String? = nil,
        orbitSelection: String? = nil,
        focused: Bool = false,
        lastButtonEvent: String? = nil,
        lastDrawSummary: String? = nil,
        pendingMediaRequestIDs: [String] = [],
        lastProviderRequestIDs: [String] = []
    ) {
        self.id = id
        self.connectionState = connectionState
        self.activeAppID = activeAppID
        self.orbitSelection = orbitSelection
        self.focused = focused
        self.lastButtonEvent = lastButtonEvent
        self.lastDrawSummary = lastDrawSummary
        self.pendingMediaRequestIDs = pendingMediaRequestIDs
        self.lastProviderRequestIDs = lastProviderRequestIDs
    }
}

public struct LocalArtifactRecord: Identifiable, Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case chronosTimer
        case teleprompterScript
        case signalCard
        case oracleHistory
        case visionNote
        case babelTranscript
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var payload: String
    public var createdAt: Int
    public var expiresAt: Int?

    public init(id: String, kind: Kind, title: String, payload: String, createdAt: Int, expiresAt: Int? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.payload = payload
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public actor SettingsRepository {
    private var snapshot: AppSettingsSnapshot

    public init(snapshot: AppSettingsSnapshot = AppSettingsSnapshot()) {
        self.snapshot = snapshot
    }

    public func read() -> AppSettingsSnapshot {
        snapshot
    }

    public func write(_ snapshot: AppSettingsSnapshot) {
        self.snapshot = snapshot
    }
}

public actor RetentionCleaner {
    public init() {}

    public func cleanup<Repository: PrismRepository>(now: Int, repository: Repository) async throws
    where Repository.Entity == LocalArtifactRecord {
        let records = try await repository.list()
        for record in records where record.expiresAt.map({ $0 <= now }) ?? false {
            try await repository.delete(record)
        }
    }
}
