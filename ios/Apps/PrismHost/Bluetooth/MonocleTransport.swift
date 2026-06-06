import Foundation

protocol MonocleTransport: Sendable {
    func scanForRawDataDevices(knownDeviceID: UUID?) -> [KnownDevice]
    func connect(to device: KnownDevice) -> MonocleConnectionResult
    func send(_ message: MonocleOutboundMessage, maxWriteLength: Int) throws -> MonocleWriteResult
    func ingestNotification(_ data: Data) throws -> MonocleInboundEvent?
}

struct MonocleConnectionResult: Equatable, Sendable {
    var state: DeviceConnectionState
    var rawDataAvailable: Bool
    var nusAvailable: Bool
    var maxWriteLength: Int
    var message: String
}

struct MonocleWriteResult: Equatable, Sendable {
    var frameCount: Int
    var byteCount: Int
    var message: String
}

enum MonocleTransportError: Error, Equatable, Sendable {
    case writeLengthTooSmall(Int)
    case payloadTooLarge(Int)
    case writeInProgress
    case malformedNotification
    case unsupportedNotificationKind(UInt8)
}

enum MonocleInboundEvent: Equatable, Sendable {
    case button(String)
    case media(String)
    case diagnostic(String)
}

struct MonocleOutboundMessage: Equatable, Sendable {
    var kind: UInt8
    var messageID: UInt16
    var payload: Data

    static func staticTextDraw(
        text: String = "PrismOS",
        appID: String = "host",
        messageID: UInt16 = 1
    ) -> MonocleOutboundMessage {
        var payload = Data([1, 0])
        appendLengthPrefixed(appID, to: &payload)
        payload.append(1)
        payload.append(0x01)
        appendUInt16LE(320, to: &payload)
        appendUInt16LE(200, to: &payload)
        appendUInt32LE(0x00FF_FFFF, to: &payload)
        payload.append(0)
        appendLengthPrefixed(text, to: &payload)
        return MonocleOutboundMessage(kind: 0x05, messageID: messageID, payload: payload)
    }

    func frames(maxWriteLength: Int) throws -> [Data] {
        let headerByteCount = 13
        let maxFragmentLength = maxWriteLength - headerByteCount
        guard maxFragmentLength > 0 else {
            throw MonocleTransportError.writeLengthTooSmall(maxWriteLength)
        }
        guard payload.count <= 1_536 else {
            throw MonocleTransportError.payloadTooLarge(payload.count)
        }

        var frames: [Data] = []
        var offset = 0
        var sequence: UInt16 = 0
        repeat {
            let end = min(offset + maxFragmentLength, payload.count)
            let fragment = payload[offset..<end]
            var flags: UInt8 = 0
            if offset == 0 {
                flags |= 0x01
            }
            if end == payload.count {
                flags |= 0x02
            }

            var frame = Data([0x50, 0x4D, 1, kind, flags])
            Self.appendUInt16LE(messageID, to: &frame)
            Self.appendUInt16LE(sequence, to: &frame)
            Self.appendUInt32LE(UInt32(payload.count), to: &frame)
            frame.append(fragment)
            frames.append(frame)
            offset = end
            sequence &+= 1
        } while offset < payload.count

        return frames
    }

    private static func appendLengthPrefixed(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8.prefix(255))
        data.append(UInt8(bytes.count))
        data.append(bytes)
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0x00FF))
        data.append(UInt8((value >> 8) & 0x00FF))
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0x000000FF))
        data.append(UInt8((value >> 8) & 0x000000FF))
        data.append(UInt8((value >> 16) & 0x000000FF))
        data.append(UInt8((value >> 24) & 0x000000FF))
    }
}

struct MockMonocleTransport: MonocleTransport {
    private let deviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    var devices: [KnownDevice]?
    var maxWriteLength = 64
    var notification: Data?

    func scanForRawDataDevices(knownDeviceID: UUID? = nil) -> [KnownDevice] {
        let candidates = devices ?? [
            KnownDevice(
                id: deviceID,
                displayName: "Demo Monocle",
                advertisedName: "Monocle",
                rawDataServiceSeen: true,
                nusServiceSeen: false
            )
        ]
        guard let knownDeviceID else {
            return candidates
        }
        return candidates.filter { $0.id == knownDeviceID }
    }

    func connect(to device: KnownDevice) -> MonocleConnectionResult {
        if device.rawDataServiceSeen {
            return MonocleConnectionResult(
                state: .connected,
                rawDataAvailable: true,
                nusAvailable: device.nusServiceSeen,
                maxWriteLength: maxWriteLength,
                message: "Connected to selected Raw Data device"
            )
        }

        return MonocleConnectionResult(
            state: .recoveryOnly,
            rawDataAvailable: false,
            nusAvailable: device.nusServiceSeen,
            maxWriteLength: maxWriteLength,
            message: "NUS recovery visible; normal runtime disabled"
        )
    }

    func send(_ message: MonocleOutboundMessage, maxWriteLength: Int) throws -> MonocleWriteResult {
        let frames = try message.frames(maxWriteLength: maxWriteLength)
        return MonocleWriteResult(
            frameCount: frames.count,
            byteCount: frames.reduce(0) { $0 + $1.count },
            message: "Queued \(frames.count) framed Raw Data write(s)"
        )
    }

    func ingestNotification(_ data: Data) throws -> MonocleInboundEvent? {
        try MonocleControlNotificationDecoder.decode(data)
    }
}

enum MonocleControlNotificationDecoder {
    static func decode(_ data: Data) throws -> MonocleInboundEvent? {
        guard data.count >= 5 else {
            throw MonocleTransportError.malformedNotification
        }
        guard data[data.startIndex] == 0x50, data[data.index(after: data.startIndex)] == 0x4D else {
            throw MonocleTransportError.malformedNotification
        }
        let kind = data[data.index(data.startIndex, offsetBy: 3)]
        guard kind == 0x01 else {
            throw MonocleTransportError.unsupportedNotificationKind(kind)
        }
        let payload = data.dropFirst(13)
        guard let text = String(data: payload, encoding: .utf8) else {
            throw MonocleTransportError.malformedNotification
        }
        if text.contains("\"event\":\"BTN\"") || text.contains("\"type\":\"BTN\"") {
            return .button(text)
        }
        if text.contains("\"event\":\"MEDIA\"") || text.contains("\"type\":\"MEDIA\"") {
            return .media(text)
        }
        return .diagnostic(text)
    }
}

private func appendUInt16LE(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0x00FF))
    data.append(UInt8((value >> 8) & 0x00FF))
}

private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0x000000FF))
    data.append(UInt8((value >> 8) & 0x000000FF))
    data.append(UInt8((value >> 16) & 0x000000FF))
    data.append(UInt8((value >> 24) & 0x000000FF))
}
