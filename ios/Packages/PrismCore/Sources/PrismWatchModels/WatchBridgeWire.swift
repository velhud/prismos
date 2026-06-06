import Foundation

public enum WatchBridgeMessageKind: String, CaseIterable, Sendable, Codable {
    case snapshot
    case command
    case acknowledgement
    case queuedCommand
}

public struct WatchBridgeEnvelope: Equatable, Sendable, Codable {
    public var kind: WatchBridgeMessageKind
    public var payload: Data

    public init(kind: WatchBridgeMessageKind, payload: Data) {
        self.kind = kind
        self.payload = payload
    }
}

public enum WatchBridgeWireError: Error, Equatable, Sendable {
    case missingKind
    case missingPayload
    case unexpectedKind(expected: WatchBridgeMessageKind, actual: String?)
    case invalidPayload
}

public enum WatchBridgeWireCodec {
    public static let kindKey = "kind"
    public static let payloadKey = "payload"

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ envelope: WatchBridgeEnvelope) throws -> [String: Any] {
        [
            kindKey: envelope.kind.rawValue,
            payloadKey: envelope.payload
        ]
    }

    public static func encodeSnapshot(_ snapshot: WatchSnapshot) throws -> [String: Any] {
        try encode(WatchBridgeEnvelope(kind: .snapshot, payload: encoder.encode(snapshot)))
    }

    public static func encodeCommand(_ command: WatchCommand) throws -> [String: Any] {
        try encode(WatchBridgeEnvelope(kind: .command, payload: encoder.encode(command)))
    }

    public static func encodeQueuedCommand(_ command: WatchCommand) throws -> [String: Any] {
        try encode(WatchBridgeEnvelope(kind: .queuedCommand, payload: encoder.encode(command)))
    }

    public static func encodeAcknowledgement(_ acknowledgement: WatchAcknowledgement) throws -> [String: Any] {
        try encode(WatchBridgeEnvelope(kind: .acknowledgement, payload: encoder.encode(acknowledgement)))
    }

    public static func decodeSnapshot(_ dictionary: [String: Any]) throws -> WatchSnapshot {
        let envelope = try decodeEnvelope(dictionary, expectedKind: .snapshot)
        return try decoder.decode(WatchSnapshot.self, from: envelope.payload)
    }

    public static func decodeCommand(_ dictionary: [String: Any]) throws -> WatchCommand {
        let envelope = try decodeEnvelope(dictionary, expectedKind: .command)
        return try decoder.decode(WatchCommand.self, from: envelope.payload)
    }

    public static func decodeQueuedCommand(_ dictionary: [String: Any]) throws -> WatchCommand {
        let envelope = try decodeEnvelope(dictionary, expectedKind: .queuedCommand)
        return try decoder.decode(WatchCommand.self, from: envelope.payload)
    }

    public static func decodeAcknowledgement(_ dictionary: [String: Any]) throws -> WatchAcknowledgement {
        let envelope = try decodeEnvelope(dictionary, expectedKind: .acknowledgement)
        return try decoder.decode(WatchAcknowledgement.self, from: envelope.payload)
    }

    private static func decodeEnvelope(_ dictionary: [String: Any], expectedKind: WatchBridgeMessageKind) throws -> WatchBridgeEnvelope {
        guard let rawKind = dictionary[kindKey] as? String else {
            throw WatchBridgeWireError.missingKind
        }
        guard let kind = WatchBridgeMessageKind(rawValue: rawKind) else {
            throw WatchBridgeWireError.unexpectedKind(expected: expectedKind, actual: rawKind)
        }
        guard let payload = dictionary[payloadKey] as? Data else {
            throw WatchBridgeWireError.missingPayload
        }
        guard kind == expectedKind else {
            throw WatchBridgeWireError.unexpectedKind(expected: expectedKind, actual: rawKind)
        }
        return WatchBridgeEnvelope(kind: kind, payload: payload)
    }
}
