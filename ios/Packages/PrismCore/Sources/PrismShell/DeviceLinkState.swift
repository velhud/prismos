import Foundation
import PrismProtocol

public enum DeviceLinkPhase: String, Codable, Sendable { case offline, scanning, connecting, discovering, subscribing, negotiating, ready, incompatible }
/// Pure bounded mechanics used by the production CoreBluetooth adapter and executable replay tests.
public struct DeviceWriteQueue {
    public struct Message: Equatable {
        public var id: UInt16
        public var kind: PrismMessageKind
        public var frames: [Data]
        public var offset: Int = 0
    }
    public private(set) var messages: [Message] = []
    public private(set) var supersededIDs: [UInt16] = []
    public private(set) var awaitingResponse = false
    public private(set) var epoch = UUID()
    private var nextID: UInt16 = 1
    public init() {}
    public mutating func reset() { messages = []; awaitingResponse = false; epoch = UUID() }
    public mutating func discardPendingAfterAcknowledgement() {
        if awaitingResponse, !messages.isEmpty {
            messages[0].frames = Array(messages[0].frames.prefix(messages[0].offset))
            messages = Array(messages.prefix(1))
        } else { messages = [] }
    }
    @discardableResult public mutating func enqueue(kind: PrismMessageKind, payload: Data, maxWriteLength: Int) throws -> UInt16 {
        // Supersede only complete unsent projections; never interleave an in-flight fragmented message.
        supersededIDs = []
        if kind == .draw {
            supersededIDs = messages.filter { $0.kind == .draw && $0.offset == 0 }.map(\.id)
            messages.removeAll { $0.kind == .draw && $0.offset == 0 }
        }
        guard messages.count < 8 else { throw ShellError.unavailable("Device write queue full") }
        let id = nextID; nextID &+= 1; if nextID == 0 { nextID = 1 }
        let frames = try PrismFrameSplitter().split(kind: kind, payload: payload, messageID: id, maxWriteLength: maxWriteLength).map(\.encoded)
        messages.append(.init(id: id, kind: kind, frames: frames)); return id
    }
    public mutating func take(canSend: Bool, withResponse: Bool) -> Data? {
        guard canSend, !awaitingResponse, !messages.isEmpty else { return nil }
        let frame = messages[0].frames[messages[0].offset]
        messages[0].offset += 1
        awaitingResponse = withResponse
        if messages[0].offset == messages[0].frames.count && !withResponse { messages.removeFirst() }
        return frame
    }
    public mutating func acknowledge(epoch: UUID) {
        guard self.epoch == epoch, awaitingResponse else { return }
        awaitingResponse = false
        if !messages.isEmpty && messages[0].offset == messages[0].frames.count { messages.removeFirst() }
    }
}
public struct DeviceControlEvent: Codable, Equatable, Sendable {
    public var event: String
    public var id: String?
    public var gesture: String?
    public var ts: Int?
    public var request_id: String?
    public var session_id: String?
    public var stream_id: UInt16?
    public var status: String?
    public var protocol_version: Int?
    public var shell_version: Int?
    public var boot_id: String?
    public var detail: String?
}
public struct DeviceEventGate {
    private var seen: [String] = []
    private var boot: String?
    private var deviceClock: Int?
    private var clockReceivedAt = Date.distantPast
    public init() {}
    public mutating func newBoot(_ id: String) { if boot != id { seen = []; boot = id } }
    public mutating func synchronize(deviceTimestamp: Int, receivedAt: Date) {
        deviceClock = deviceTimestamp; clockReceivedAt = receivedAt
    }
    public mutating func accept(_ event: DeviceControlEvent, receivedAt: Date, readyAt: Date) -> Bool {
        guard receivedAt >= readyAt, receivedAt.timeIntervalSince(readyAt) >= 0, boot != nil,
              let timestamp = event.ts, let clock = deviceClock else { return false }
        let period = 1 << 30
        let delta = ((timestamp - clock + period / 2) % period + period) % period - period / 2
        guard abs(Double(delta) / 1000 - receivedAt.timeIntervalSince(clockReceivedAt)) <= 10 else { return false }
        let key = "\(boot!):\(timestamp):\(event.id ?? ""):\(event.gesture ?? ""):\(event.event)"
        guard !seen.contains(key) else { return false }
        seen.append(key); seen = Array(seen.suffix(256)); return true
    }
}
public struct AudioCaptureGate {
    public private(set) var requestID: UUID?
    public private(set) var streamID: UInt16?
    public private(set) var deadline: Date?
    public init() {}
    public mutating func begin(id: UUID, now: Date) { requestID = id; streamID = nil; deadline = now.addingTimeInterval(20) }
    public mutating func started(id: UUID, stream: UInt16, now: Date) throws {
        guard requestID == id, deadline.map({ $0 > now }) == true, streamID == nil else { throw ShellError.stale }
        streamID = stream
    }
    public mutating func complete(stream: UInt16, bytes: Data, now: Date) throws -> UUID {
        guard let id = requestID, streamID == stream, deadline.map({ $0 > now }) == true, !bytes.isEmpty, bytes.count <= 64_000 else { throw ShellError.stale }
        cancel(); return id
    }
    public mutating func cancel() { requestID = nil; streamID = nil; deadline = nil }
}
