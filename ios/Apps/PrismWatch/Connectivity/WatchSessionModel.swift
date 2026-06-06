import Foundation
import SwiftUI
import PrismWatchModels

@MainActor
final class WatchSessionModel: ObservableObject {
    @Published private(set) var snapshot: WatchSnapshot
    @Published private(set) var lastAcknowledgement: WatchAcknowledgement?
    @Published private(set) var pendingCommands: [WatchCommand]
    @Published private(set) var isReachable: Bool

    private var reducer = WatchCommandReducer()

    init(snapshot: WatchSnapshot = .sample(activeSurface: .orbit, activeApp: .oracle)) {
        self.snapshot = snapshot
        self.lastAcknowledgement = snapshot.lastAcknowledgement
        self.pendingCommands = []
        self.isReachable = snapshot.connection.isReachable
    }

    func apply(_ snapshot: WatchSnapshot) {
        self.snapshot = snapshot
        self.lastAcknowledgement = snapshot.lastAcknowledgement
        self.isReachable = snapshot.connection.isReachable
        if let acknowledgement = snapshot.lastAcknowledgement, acknowledgement.status != .queued {
            pendingCommands.removeAll { command in
                acknowledgement.commandID == command.id
            }
        }
    }

    func record(_ acknowledgement: WatchAcknowledgement, removePending: Bool = true) {
        lastAcknowledgement = acknowledgement
        snapshot.lastAcknowledgement = acknowledgement
        if removePending && acknowledgement.status != .queued {
            pendingCommands.removeAll { $0.id == acknowledgement.commandID }
        }
    }

    func ingest(applicationContext: [String: Any]) throws {
        apply(try WatchBridgeWireCodec.decodeSnapshot(applicationContext))
    }

    func ingest(acknowledgement userInfo: [String: Any]) throws {
        record(try WatchBridgeWireCodec.decodeAcknowledgement(userInfo))
    }

    func ingest(queuedCommand userInfo: [String: Any]) throws {
        let command = try WatchBridgeWireCodec.decodeQueuedCommand(userInfo)
        if pendingCommands.contains(where: { $0.id == command.id }) || lastAcknowledgement?.commandID == command.id {
            return
        }
        pendingCommands.append(command)
        let acknowledgement = WatchAcknowledgement(
            commandID: command.id,
            status: .queued,
            reason: "Queued for host",
            snapshotVersion: snapshot.version
        )
        record(acknowledgement, removePending: false)
    }

    func issue(_ action: WatchUIAction) throws -> WatchCommand? {
        guard let command = try reducer.reduce(action, against: snapshot) else {
            return nil
        }
        pendingCommands.append(command)
        return command
    }
}
