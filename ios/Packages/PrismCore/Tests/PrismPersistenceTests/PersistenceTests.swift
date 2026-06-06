import XCTest
@testable import PrismPersistence

final class PersistenceTests: XCTestCase {
    func testSettingsReadWrite() async {
        let repository = SettingsRepository()
        let snapshot = AppSettingsSnapshot(
            selectedDeviceID: "device-1",
            backgroundBLEEnabled: true,
            developerModeEnabled: true,
            shapePrimitivesEnabled: false,
            diagnosticsRedaction: "strict"
        )

        await repository.write(snapshot)
        let restored = await repository.read()

        XCTAssertEqual(restored, snapshot)
    }

    func testSessionSnapshotStoreAndRestore() async throws {
        let repository = InMemoryRepository<SessionStateSnapshot>()
        let snapshot = SessionStateSnapshot(
            connectionState: "connected",
            activeAppID: "chronos",
            orbitSelection: "chronos",
            focused: true,
            lastButtonEvent: "R:TAP",
            lastDrawSummary: "chronos 72 bytes",
            pendingMediaRequestIDs: ["media-1"],
            lastProviderRequestIDs: ["provider-1"]
        )

        try await repository.save(snapshot)
        let restored = try await repository.list()

        XCTAssertEqual(restored, [snapshot])
    }

    func testArtifactCRUDAndRetentionCleanup() async throws {
        let repository = InMemoryRepository<LocalArtifactRecord>()
        let expired = LocalArtifactRecord(id: "old", kind: .signalCard, title: "Old", payload: "gone", createdAt: 1, expiresAt: 5)
        let active = LocalArtifactRecord(id: "active", kind: .teleprompterScript, title: "Script", payload: "hello", createdAt: 1, expiresAt: 100)

        try await repository.save(expired)
        try await repository.save(active)
        try await RetentionCleaner().cleanup(now: 10, repository: repository)
        let afterCleanup = try await repository.list()

        XCTAssertEqual(afterCleanup, [active])

        try await repository.delete(active)
        let afterDelete = try await repository.list()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testProviderAppArtifactsUseExplicitKinds() async throws {
        let repository = InMemoryRepository<LocalArtifactRecord>()
        let oracle = LocalArtifactRecord(
            id: "oracle-1",
            kind: .oracleHistory,
            title: "Oracle Answer",
            payload: "74.57 Nm.",
            createdAt: 1
        )
        let vision = LocalArtifactRecord(
            id: "vision-1",
            kind: .visionNote,
            title: "Vision Note",
            payload: "ESP32 board",
            createdAt: 2
        )
        let babel = LocalArtifactRecord(
            id: "babel-1",
            kind: .babelTranscript,
            title: "Babel Transcript",
            payload: "bonjour -> hello",
            createdAt: 3
        )

        try await repository.save(oracle)
        try await repository.save(vision)
        try await repository.save(babel)
        let restored = try await repository.list()

        XCTAssertEqual(Set(restored.map(\.kind)), [.oracleHistory, .visionNote, .babelTranscript])
        XCTAssertTrue(restored.contains(oracle))
        XCTAssertTrue(restored.contains(vision))
        XCTAssertTrue(restored.contains(babel))
    }

    func testJSONFileRepositoryPersistsArtifactsAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("artifacts.json")
        let active = LocalArtifactRecord(id: "active", kind: .chronosTimer, title: "Timer", payload: "90", createdAt: 1)

        let writer = JSONFileRepository<LocalArtifactRecord>(fileURL: fileURL)
        try await writer.save(active)

        let reader = JSONFileRepository<LocalArtifactRecord>(fileURL: fileURL)
        let restored = try await reader.list()
        XCTAssertEqual(restored, [active])

        try await reader.delete(active)
        let reloaded = JSONFileRepository<LocalArtifactRecord>(fileURL: fileURL)
        let afterDelete = try await reloaded.list()
        XCTAssertTrue(afterDelete.isEmpty)

        try? FileManager.default.removeItem(at: directory)
    }

    func testRetentionCleanupWorksWithFileBackedRepository() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismRetentionTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("artifacts.json")
        let repository = JSONFileRepository<LocalArtifactRecord>(fileURL: fileURL)
        let expired = LocalArtifactRecord(id: "expired", kind: .signalCard, title: "Old", payload: "gone", createdAt: 1, expiresAt: 5)
        let active = LocalArtifactRecord(id: "active", kind: .teleprompterScript, title: "Script", payload: "hello", createdAt: 1, expiresAt: 100)

        try await repository.save(expired)
        try await repository.save(active)
        try await RetentionCleaner().cleanup(now: 10, repository: repository)

        let afterCleanup = try await repository.list()
        XCTAssertEqual(afterCleanup, [active])

        try? FileManager.default.removeItem(at: directory)
    }
}
