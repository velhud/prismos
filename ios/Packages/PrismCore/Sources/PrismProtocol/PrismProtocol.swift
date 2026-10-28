import Foundation

public enum PrismProtocolConstants {
    public static let magic: [UInt8] = [0x50, 0x4D]
    public static let version: UInt8 = 1
    public static let headerByteCount = 13
    public static let totalLengthUnknown = UInt32.max
    public static let defaultStreamTimeout: TimeInterval = 30

    public static let maxControlJSONBytes = 4_096
    public static let maxLogTextBytes = 8_192
    public static let maxAudioStreamBytes = 128 * 1_024
    public static let maxImageStreamBytes = 1_024 * 1_024
    public static let maxDrawBytes = 1_536
}

public enum PrismMessageKind: UInt8, CaseIterable, Sendable {
    case controlJSON = 0x01
    case streamAudio = 0x02
    case streamImage = 0x03
    case logText = 0x04
    case draw = 0x05

    public var maxPayloadBytes: Int {
        switch self {
        case .controlJSON:
            PrismProtocolConstants.maxControlJSONBytes
        case .streamAudio:
            PrismProtocolConstants.maxAudioStreamBytes
        case .streamImage:
            PrismProtocolConstants.maxImageStreamBytes
        case .logText:
            PrismProtocolConstants.maxLogTextBytes
        case .draw:
            PrismProtocolConstants.maxDrawBytes
        }
    }

    public var allowsUnknownLength: Bool {
        self == .streamAudio || self == .streamImage
    }
}

public struct PrismFrameFlags: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let start = PrismFrameFlags(rawValue: 0x01)
    public static let end = PrismFrameFlags(rawValue: 0x02)
    public static let validMask: UInt8 = start.rawValue | end.rawValue
}

public struct PrismFrameHeader: Equatable, Sendable {
    public var kind: PrismMessageKind
    public var flags: PrismFrameFlags
    public var messageID: UInt16
    public var sequence: UInt16
    public var totalLength: UInt32

    public init(
        kind: PrismMessageKind,
        flags: PrismFrameFlags,
        messageID: UInt16,
        sequence: UInt16,
        totalLength: UInt32
    ) {
        self.kind = kind
        self.flags = flags
        self.messageID = messageID
        self.sequence = sequence
        self.totalLength = totalLength
    }

    public var hasKnownLength: Bool {
        totalLength != PrismProtocolConstants.totalLengthUnknown
    }
}

public struct PrismFrame: Equatable, Sendable {
    public var header: PrismFrameHeader
    public var payloadFragment: Data

    public init(header: PrismFrameHeader, payloadFragment: Data) {
        self.header = header
        self.payloadFragment = payloadFragment
    }

    public var encoded: Data {
        var data = PrismProtocolCodec.encode(header)
        data.append(payloadFragment)
        return data
    }
}

public struct PrismCompleteMessage: Equatable, Sendable {
    public var kind: PrismMessageKind
    public var messageID: UInt16
    public var payload: Data

    public init(kind: PrismMessageKind, messageID: UInt16, payload: Data) {
        self.kind = kind
        self.messageID = messageID
        self.payload = payload
    }
}

public enum PrismProtocolError: Error, Equatable, Sendable {
    case frameTooShort
    case badMagic
    case unsupportedVersion(UInt8)
    case unknownKind(UInt8)
    case invalidFlags(UInt8)
    case unknownLengthNotAllowed(PrismMessageKind)
    case totalLengthExceedsLimit(kind: PrismMessageKind, total: UInt32, limit: Int)
    case fragmentExceedsKnownLength
    case missingStartFrame
    case sequenceGap(expected: UInt16, actual: UInt16)
    case inconsistentLength
    case tooManyStreams
    case timedOut
    case writeLengthTooSmall(Int)
}

public enum PrismProtocolCodec {
    public static func encode(_ header: PrismFrameHeader) -> Data {
        var bytes = [UInt8](repeating: 0, count: PrismProtocolConstants.headerByteCount)
        bytes[0] = PrismProtocolConstants.magic[0]
        bytes[1] = PrismProtocolConstants.magic[1]
        bytes[2] = PrismProtocolConstants.version
        bytes[3] = header.kind.rawValue
        bytes[4] = header.flags.rawValue
        writeUInt16LE(header.messageID, into: &bytes, at: 5)
        writeUInt16LE(header.sequence, into: &bytes, at: 7)
        writeUInt32LE(header.totalLength, into: &bytes, at: 9)
        return Data(bytes)
    }

    public static func decodeHeader(from data: Data) throws -> PrismFrameHeader {
        guard data.count >= PrismProtocolConstants.headerByteCount else {
            throw PrismProtocolError.frameTooShort
        }

        let bytes = [UInt8](data.prefix(PrismProtocolConstants.headerByteCount))
        guard bytes[0] == PrismProtocolConstants.magic[0], bytes[1] == PrismProtocolConstants.magic[1] else {
            throw PrismProtocolError.badMagic
        }
        guard bytes[2] == PrismProtocolConstants.version else {
            throw PrismProtocolError.unsupportedVersion(bytes[2])
        }
        guard let kind = PrismMessageKind(rawValue: bytes[3]) else {
            throw PrismProtocolError.unknownKind(bytes[3])
        }
        guard bytes[4] & ~PrismFrameFlags.validMask == 0 else {
            throw PrismProtocolError.invalidFlags(bytes[4])
        }

        return PrismFrameHeader(
            kind: kind,
            flags: PrismFrameFlags(rawValue: bytes[4]),
            messageID: readUInt16LE(bytes, at: 5),
            sequence: readUInt16LE(bytes, at: 7),
            totalLength: readUInt32LE(bytes, at: 9)
        )
    }

    public static func decodeFrame(from data: Data) throws -> PrismFrame {
        let header = try decodeHeader(from: data)
        let fragment = data.dropFirst(PrismProtocolConstants.headerByteCount)
        return PrismFrame(header: header, payloadFragment: Data(fragment))
    }

    private static func writeUInt16LE(_ value: UInt16, into bytes: inout [UInt8], at index: Int) {
        bytes[index] = UInt8(value & 0x00FF)
        bytes[index + 1] = UInt8((value >> 8) & 0x00FF)
    }

    private static func writeUInt32LE(_ value: UInt32, into bytes: inout [UInt8], at index: Int) {
        bytes[index] = UInt8(value & 0x000000FF)
        bytes[index + 1] = UInt8((value >> 8) & 0x000000FF)
        bytes[index + 2] = UInt8((value >> 16) & 0x000000FF)
        bytes[index + 3] = UInt8((value >> 24) & 0x000000FF)
    }

    private static func readUInt16LE(_ bytes: [UInt8], at index: Int) -> UInt16 {
        UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    private static func readUInt32LE(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }
}

public struct PrismFrameSplitter: Sendable {
    public init() {}

    public func split(
        kind: PrismMessageKind,
        payload: Data,
        messageID: UInt16,
        maxWriteLength: Int,
        knownLength: Bool = true
    ) throws -> [PrismFrame] {
        let maxFragmentLength = maxWriteLength - PrismProtocolConstants.headerByteCount
        guard maxFragmentLength > 0 else {
            throw PrismProtocolError.writeLengthTooSmall(maxWriteLength)
        }

        if payload.count > kind.maxPayloadBytes {
            throw PrismProtocolError.totalLengthExceedsLimit(
                kind: kind,
                total: UInt32(payload.count),
                limit: kind.maxPayloadBytes
            )
        }
        if !knownLength, !kind.allowsUnknownLength {
            throw PrismProtocolError.unknownLengthNotAllowed(kind)
        }

        let totalLength = knownLength ? UInt32(payload.count) : PrismProtocolConstants.totalLengthUnknown
        if payload.isEmpty {
            return [
                PrismFrame(
                    header: PrismFrameHeader(
                        kind: kind,
                        flags: [.start, .end],
                        messageID: messageID,
                        sequence: 0,
                        totalLength: totalLength
                    ),
                    payloadFragment: Data()
                )
            ]
        }

        var frames: [PrismFrame] = []
        var offset = 0
        var sequence: UInt16 = 0
        while offset < payload.count {
            let end = Swift.min(offset + maxFragmentLength, payload.count)
            var flags: PrismFrameFlags = []
            if offset == 0 {
                flags.insert(.start)
            }
            if end == payload.count {
                flags.insert(.end)
            }

            frames.append(
                PrismFrame(
                    header: PrismFrameHeader(
                        kind: kind,
                        flags: flags,
                        messageID: messageID,
                        sequence: sequence,
                        totalLength: totalLength
                    ),
                    payloadFragment: Data(payload[offset..<end])
                )
            )
            offset = end
            sequence &+= 1
        }
        return frames
    }
}

public struct PrismOutboundGate: Sendable {
    private var activeMessageID: UInt16?

    public init() {}

    public var hasActiveMessage: Bool {
        activeMessageID != nil
    }

    public mutating func begin(messageID: UInt16) -> Bool {
        guard activeMessageID == nil else {
            return false
        }
        activeMessageID = messageID
        return true
    }

    public mutating func finish(messageID: UInt16) {
        if activeMessageID == messageID {
            activeMessageID = nil
        }
    }
}

public final class PrismFrameReassembler {
    private struct State {
        var kind: PrismMessageKind
        var messageID: UInt16
        var knownTotal: Int?
        var buffer: Data
        var expectedSequence: UInt16
        var startedAt: TimeInterval
    }

    private var states: [Key: State] = [:]
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = PrismProtocolConstants.defaultStreamTimeout) {
        self.timeout = timeout
    }

    public func ingest(_ encodedFrame: Data, now: TimeInterval) throws -> PrismCompleteMessage? {
        let frame = try PrismProtocolCodec.decodeFrame(from: encodedFrame)
        return try ingest(frame, now: now)
    }

    public func ingest(_ frame: PrismFrame, now: TimeInterval) throws -> PrismCompleteMessage? {
        let header = frame.header
        let key = Key(kind: header.kind, messageID: header.messageID)
        let isStart = header.flags.contains(.start)
        let isEnd = header.flags.contains(.end)

        states = states.filter { $0.key == key || now - $0.value.startedAt <= timeout }
        if isStart {
            guard states[key] != nil || states.count < 4 else { throw PrismProtocolError.tooManyStreams }
            try validateStart(header: header)
            states[key] = State(
                kind: header.kind,
                messageID: header.messageID,
                knownTotal: header.hasKnownLength ? Int(header.totalLength) : nil,
                buffer: Data(),
                expectedSequence: 0,
                startedAt: now
            )
        }

        guard var state = states[key] else {
            throw PrismProtocolError.missingStartFrame
        }
        guard now - state.startedAt <= timeout else {
            states.removeValue(forKey: key)
            throw PrismProtocolError.timedOut
        }
        guard header.sequence == state.expectedSequence else {
            states.removeValue(forKey: key)
            throw PrismProtocolError.sequenceGap(expected: state.expectedSequence, actual: header.sequence)
        }
        guard state.knownTotal == (header.hasKnownLength ? Int(header.totalLength) : nil) else {
            states.removeValue(forKey: key); throw PrismProtocolError.inconsistentLength
        }
        state.expectedSequence &+= 1

        let nextSize = state.buffer.count + frame.payloadFragment.count
        if let knownTotal = state.knownTotal {
            guard nextSize <= knownTotal else {
                states.removeValue(forKey: key)
                throw PrismProtocolError.fragmentExceedsKnownLength
            }
        } else {
            guard nextSize <= header.kind.maxPayloadBytes else {
                states.removeValue(forKey: key)
                throw PrismProtocolError.totalLengthExceedsLimit(
                    kind: header.kind,
                    total: UInt32(nextSize),
                    limit: header.kind.maxPayloadBytes
                )
            }
        }

        state.buffer.append(frame.payloadFragment)
        if !isEnd {
            states[key] = state
            return nil
        }

        states.removeValue(forKey: key)
        if let knownTotal = state.knownTotal, state.buffer.count != knownTotal {
            throw PrismProtocolError.fragmentExceedsKnownLength
        }
        return PrismCompleteMessage(kind: state.kind, messageID: state.messageID, payload: state.buffer)
    }

    private func validateStart(header: PrismFrameHeader) throws {
        if !header.hasKnownLength {
            guard header.kind.allowsUnknownLength else {
                throw PrismProtocolError.unknownLengthNotAllowed(header.kind)
            }
            return
        }

        guard header.totalLength <= UInt32(header.kind.maxPayloadBytes) else {
            throw PrismProtocolError.totalLengthExceedsLimit(
                kind: header.kind,
                total: header.totalLength,
                limit: header.kind.maxPayloadBytes
            )
        }
    }

    private struct Key: Hashable {
        var kind: PrismMessageKind
        var messageID: UInt16
    }
}
