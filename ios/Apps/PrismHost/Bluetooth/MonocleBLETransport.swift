import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

enum MonocleBLEUUIDs {
    static let rawDataService = "e5700001-7bac-429a-b4ce-57ff900f479d"
    static let rawDataRX = "e5700002-7bac-429a-b4ce-57ff900f479d"
    static let rawDataTX = "e5700003-7bac-429a-b4ce-57ff900f479d"

    static let nusService = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
    static let nusRX = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
    static let nusTX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
}

enum MonocleBLERestoration {
    static let centralManagerIdentifier = "com.prismos.PrismOS.monocle.central"

    static var centralManagerOptions: [String: Any] {
        #if canImport(CoreBluetooth)
        [CBCentralManagerOptionRestoreIdentifierKey: centralManagerIdentifier]
        #else
        [:]
        #endif
    }
}

enum MonocleServiceRole: Equatable {
    case runtimeRawData
    case recoveryNUS
    case unrelated
}

struct MonocleServiceClassifier {
    func role(for uuidString: String) -> MonocleServiceRole {
        switch uuidString.lowercased() {
        case MonocleBLEUUIDs.rawDataService:
            .runtimeRawData
        case MonocleBLEUUIDs.nusService:
            .recoveryNUS
        default:
            .unrelated
        }
    }
}

#if canImport(CoreBluetooth)
import PrismShell
import PrismProtocol
import Combine

/// Main-queue isolated CoreBluetooth owner. It never scans NUS, writes recovery commands, or selects by name.
@MainActor
final class CoreBluetoothMonocleAdapter: NSObject, ObservableObject, ShellDeviceLink, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Candidate: Identifiable {
        let id: UUID
        let label: String
    }
    @Published private(set) var phase: DeviceLinkPhase = .offline
    @Published private(set) var status = "Choose your Monocle in Settings"
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var lastDisplayAcknowledgedAt: Date?
    var onConnection: ((Bool) -> Void)?
    var onGesture: ((String, String) -> Void)?
    var onAudio: ((UUID, Data) -> Void)?
    var onError: ((Error) -> Void)?
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writer: CBCharacteristic?
    private var notifier: CBCharacteristic?
    private var queue = DeviceWriteQueue()
    private var receiver = PrismFrameReassembler()
    private var capture = AudioCaptureGate()
    private var eventGate = DeviceEventGate()
    private var sessionID = UUID()
    private var lastDeviceInputTimestamp: Int?
    private var readyAt = Date.distantFuture
    private var connectionDeadline = Date.distantFuture
    private var lastNotificationAt = Date.distantPast
    private var heartbeat: Timer?
    private var reconnect: Timer?
    private var retryCount = 0
    private var pairing = false
    private var stopped = false
    private var awaitingWriteEpoch: UUID?
    private var pendingDrawIDs: [UInt16: Date] = [:]
    private let defaults: UserDefaults
    private let identityKey = "prism.shell.peripheral"
    private var rememberedID: UUID? { defaults.string(forKey: identityKey).flatMap(UUID.init(uuidString:)) }
    override convenience init() { self.init(defaults: .standard) }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: MonocleBLERestoration.centralManagerOptions)
        heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func scanServices() -> [CBUUID] { [CBUUID(string: MonocleBLEUUIDs.rawDataService)] }
    func centralManagerOptions() -> [String: Any] { MonocleBLERestoration.centralManagerOptions }
    func role(for service: CBService) -> MonocleServiceRole { MonocleServiceClassifier().role(for: service.uuid.uuidString) }
    func discoverForPairing() {
        guard central.state == .poweredOn else { status = "Enable Bluetooth and allow access"; return }
        stopped = false; pairing = true; candidates = []; peripherals = [:]
        phase = .scanning; status = "Select the identifier of your Monocle"; connectionDeadline = Date().addingTimeInterval(20)
        central.scanForPeripherals(withServices: scanServices(), options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    func select(_ id: UUID) {
        guard let selected = peripherals[id] else { return }
        stopped = false; pairing = false
        defaults.set(id.uuidString, forKey: identityKey)
        if let old = peripheral, old.identifier != id { central.cancelPeripheralConnection(old) }
        central.stopScan(); connect(selected)
    }
    func reconnectRemembered() {
        guard !stopped, central.state == .poweredOn, let id = rememberedID else { return }
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first { connect(p) }
        else {
            pairing = false; phase = .scanning; status = "Looking for your Monocle"; connectionDeadline = Date().addingTimeInterval(20)
            central.scanForPeripherals(withServices: scanServices(), options: nil)
        }
    }
    func forget() {
        stopped = true; defaults.removeObject(forKey: identityKey); reconnect?.invalidate(); central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        invalidateLink(); status = "Choose your Monocle in Settings"
    }
    private func connect(_ p: CBPeripheral) {
        guard p.identifier == rememberedID else { return }
        if peripheral?.identifier == p.identifier && [.connecting,.discovering,.subscribing,.negotiating,.ready].contains(phase) { return }
        peripheral = p; p.delegate = self; connectionDeadline = Date().addingTimeInterval(25)
        phase = .connecting; status = "Connecting to your Monocle"
        if p.state == .connected { discover(p) } else { central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true]) }
    }
    private func discover(_ p: CBPeripheral) {
        phase = .discovering; status = "Preparing the display link"
        p.discoverServices(scanServices())
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            invalidateLink(); status = central.state == .unauthorized ? "Allow Bluetooth access in iPhone Settings" : "Bluetooth is unavailable"; return
        }
        reconnectRemembered()
    }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let id = rememberedID else { return }
        for p in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] where p.identifier == id {
            peripheral = p; p.delegate = self
            writer = nil; notifier = nil; queue.reset(); receiver = PrismFrameReassembler(); capture.cancel()
            sessionID = UUID(); connectionDeadline = Date().addingTimeInterval(25)
            if p.state == .connected { discover(p) } else { phase = .offline }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard pairing || p.identifier == rememberedID else { return }
        peripherals[p.identifier] = p
        if pairing {
            if !candidates.contains(where: { $0.id == p.identifier }) {
                candidates.append(.init(id: p.identifier, label: "Monocle · " + String(p.identifier.uuidString.suffix(8))))
            }
        } else { central.stopScan(); connect(p) }
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard p.identifier == rememberedID, peripheral?.identifier == p.identifier else { central.cancelPeripheralConnection(p); return }
        discover(p)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        guard p.identifier == peripheral?.identifier else { return }; invalidateLink(); scheduleReconnect()
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p.identifier == peripheral?.identifier else { return }; invalidateLink(); scheduleReconnect()
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral, error == nil,
              let service = peripheral.services?.first(where: { role(for: $0) == .runtimeRawData }) else { fail("Monocle runtime service unavailable"); return }
        peripheral.discoverCharacteristics([CBUUID(string: MonocleBLEUUIDs.rawDataRX), CBUUID(string: MonocleBLEUUIDs.rawDataTX)], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral, error == nil else { fail("Could not prepare Monocle characteristics"); return }
        writer = service.characteristics?.first { $0.uuid == CBUUID(string: MonocleBLEUUIDs.rawDataRX) }
        notifier = service.characteristics?.first { $0.uuid == CBUUID(string: MonocleBLEUUIDs.rawDataTX) }
        guard let writer, let notifier, writer.properties.contains(.write) || writer.properties.contains(.writeWithoutResponse),
              notifier.properties.contains(.notify) || notifier.properties.contains(.indicate) else { fail("Unsupported Monocle runtime link"); return }
        phase = .subscribing; peripheral.setNotifyValue(true, for: notifier)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic === notifier else { return }
        guard error == nil, characteristic.isNotifying else { fail("Monocle input subscription failed"); return }
        phase = .negotiating; status = "Checking Monocle compatibility"; sessionID = UUID(); lastNotificationAt = Date()
        do { try control(["cmd": "HELLO", "protocol_version": 1, "shell_version": 1, "request_id": sessionID.uuidString]) }
        catch { fail("Monocle handshake failed") }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic === notifier, error == nil, let bytes = characteristic.value else { return }
        do {
            let header = try PrismProtocolCodec.decodeHeader(from: bytes)
            if header.kind == .streamAudio {
                guard phase == .ready, capture.requestID != nil, capture.streamID == header.messageID else { return }
            }
            guard let message = try receiver.ingest(bytes, now: Date().timeIntervalSince1970) else { return }
            lastNotificationAt = Date()
            if message.kind == .streamAudio {
                guard phase == .ready else { return }
                let id = try capture.complete(stream: message.messageID, bytes: message.payload, now: Date())
                onAudio?(id, message.payload); return
            }
            guard message.kind == .controlJSON else { return }
            let event = try ShellJSON.decoder().decode(DeviceControlEvent.self, from: message.payload)
            if event.event == "HELLO", event.request_id == sessionID.uuidString {
                guard event.protocol_version == 1, event.shell_version == 1, let boot = event.boot_id else {
                    phase = .incompatible; status = "This Monocle needs the compatible shell runtime. No update will run automatically."; onConnection?(false); return
                }
                guard let timestamp = event.ts else { throw ShellError.invalid("Handshake clock missing") }
                lastDeviceInputTimestamp = nil; eventGate.newBoot(boot); eventGate.synchronize(deviceTimestamp: timestamp, receivedAt: Date()); phase = .ready; readyAt = Date(); retryCount = 0; status = "Monocle connected"; onConnection?(true); return
            }
            guard phase == .ready else { return }
            if event.event == "PONG", event.request_id == sessionID.uuidString, let timestamp = event.ts {
                eventGate.synchronize(deviceTimestamp: timestamp, receivedAt: Date()); return
            }
            if event.event == "DRAW_ACK", let id = event.stream_id, pendingDrawIDs.removeValue(forKey: id) != nil {
                if event.status == "IGNORED" { return }
                guard event.status == "OK" else { throw ShellError.invalid("Monocle rejected the display payload") }
                lastDisplayAcknowledgedAt = Date(); return
            }
            if event.event == "INTERACTION", event.status == "ERROR" {
                onError?(ShellError.unavailable("The lens was blanked. Start a new Ask to continue.")); return
            }
            if event.event == "MEDIA", event.request_id == capture.requestID?.uuidString {
                if event.status == "START", let stream = event.stream_id, let id = capture.requestID { try capture.started(id: id, stream: stream, now: Date()) }
                else if event.status == "ERROR" { capture.cancel(); onError?(ShellError.unavailable(event.detail ?? "Microphone capture failed")) }
                return
            }
            if event.event == "BTN", event.session_id == sessionID.uuidString, eventGate.accept(event, receivedAt: Date(), readyAt: readyAt), let side = event.id, let gesture = event.gesture { lastDeviceInputTimestamp = event.ts; onGesture?(side, gesture) }
        } catch PrismProtocolError.missingStartFrame {
            // Cancellation/restoration may leave continuation notifications already in CoreBluetooth's queue.
            return
        } catch ShellError.stale { return }
        catch { onError?(ShellError.unavailable("Monocle data could not be read. Reconnect or try again.")) }
    }
    func blank() {
        guard phase == .ready else { return }
        capture.cancel(); pendingDrawIDs = [:]
        // Finish at most the one ATT write already in flight, then interrupt reassembly with CLEAR.
        // Requests enqueued after CLEAR (including a new Ask) remain ordered and are not discarded.
        queue.discardPendingAfterAcknowledgement()
        try? control(["cmd": "CLEAR"])
    }
    func beginInteraction() throws {
        var command: [String: Any] = ["cmd": "BEGIN_INTERACTION"]
        if let timestamp = lastDeviceInputTimestamp { command["input_ts"] = timestamp }
        try control(command)
    }
    func project(_ payload: Data) throws {
        guard phase == .ready else { throw ShellError.unavailable("Monocle is offline") }
        let id = try enqueue(.draw, payload)
        pendingDrawIDs[id] = Date(); pendingDrawIDs = pendingDrawIDs.filter { Date().timeIntervalSince($0.value) < 15 }
    }
    func captureAudio(requestID: UUID) throws {
        guard phase == .ready else { throw ShellError.unavailable("Monocle is offline") }
        capture.begin(id: requestID, now: Date())
        try control(["cmd": "CAPTURE_AUDIO", "request_id": requestID.uuidString])
    }
    func cancelCapture() {
        guard capture.requestID != nil else { return }; capture.cancel()
        receiver = PrismFrameReassembler()
        try? control(["cmd": "CANCEL_CAPTURE"])
    }
    private var writeType: CBCharacteristicWriteType { writer?.properties.contains(.writeWithoutResponse) == true ? .withoutResponse : .withResponse }
    @discardableResult private func enqueue(_ kind: PrismMessageKind, _ data: Data) throws -> UInt16 {
        guard let p = peripheral, writer != nil, p.state == .connected else { throw ShellError.unavailable("Monocle disconnected") }
        let maxFrame = min(p.maximumWriteValueLength(for: writeType), p.maximumWriteValueLength(for: .withoutResponse))
        let id = try queue.enqueue(kind: kind, payload: data, maxWriteLength: maxFrame)
        for old in queue.supersededIDs { pendingDrawIDs.removeValue(forKey: old) }
        pump(); return id
    }
    private func control(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard data.count <= 384 else { throw ShellError.invalid("Device control exceeds wire bounds") }
        try enqueue(.controlJSON, data)
    }
    private func pump() {
        guard let p = peripheral, let writer else { return }
        let response = writeType == .withResponse
        while let frame = queue.take(canSend: response || p.canSendWriteWithoutResponse, withResponse: response) {
            awaitingWriteEpoch = queue.epoch; p.writeValue(frame, for: writer, type: writeType)
            if response { return }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic === writer, let epoch = awaitingWriteEpoch else { return }
        guard error == nil else { fail("Monocle write failed"); return }
        queue.acknowledge(epoch: epoch); awaitingWriteEpoch = nil
        pump()
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { if peripheral === self.peripheral { pump() } }
    private func tick() {
        if phase == .ready {
            if Date().timeIntervalSince(lastNotificationAt) > 20 || pendingDrawIDs.values.contains(where: { Date().timeIntervalSince($0) > 15 }) {
                fail("Monocle link is stale; reconnecting"); return
            }
            try? control(["cmd": "PING", "request_id": sessionID.uuidString])
            if let deadline = capture.deadline, deadline <= Date() { cancelCapture(); onError?(ShellError.unavailable("Microphone transfer timed out")) }
        } else if [.scanning,.connecting,.discovering,.subscribing,.negotiating].contains(phase), connectionDeadline <= Date() {
            central.stopScan()
            if pairing { phase = .offline; status = "No selection made. Try pairing again." }
            else { fail("Connection timed out") }
        }
    }
    private func invalidateLink() {
        phase = .offline; queue.reset(); writer = nil; notifier = nil; pendingDrawIDs = [:]; awaitingWriteEpoch = nil
        capture.cancel(); receiver = PrismFrameReassembler(); onConnection?(false)
    }
    private func fail(_ message: String) {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        invalidateLink(); status = message; scheduleReconnect()
    }
    private func scheduleReconnect() {
        guard !stopped, rememberedID != nil, !pairing else { return }
        reconnect?.invalidate(); retryCount += 1
        let delay = min(30, pow(2, Double(min(retryCount, 5))))
        reconnect = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reconnectRemembered() }
        }
    }
}
#endif
