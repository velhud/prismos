import Foundation
import PrismRuntime

@MainActor
final class DeviceConsoleModel: ObservableObject {
    @Published private(set) var connectionState: DeviceConnectionState = .noDevice
    @Published private(set) var candidates: [KnownDevice] = []
    @Published private(set) var selectedDevice: KnownDevice?
    @Published private(set) var diagnostics: [DiagnosticRow] = []
    @Published private(set) var rawDataAvailable = false
    @Published private(set) var nusAvailable = false
    @Published private(set) var lifecycleState: BackgroundLifecycleState = .foreground
    @Published private(set) var recoveryState: RecoveryModeState = .waitingForHost
    @Published private(set) var reconnectMessage = "Foreground only until selected inAi glasses are connected."
    @Published private(set) var lastSuccessfulConnectionAt: Date?

    private let transport: MonocleTransport
    private let identityStore: DeviceIdentityStore
    private let reconnectStateMachine = ReconnectStateMachine()
    private var maxWriteLength = 20

    init(
        transport: MonocleTransport = MockMonocleTransport(),
        identityStore: DeviceIdentityStore = UserDefaultsDeviceIdentityStore()
    ) {
        self.transport = transport
        self.identityStore = identityStore
    }

    func startScan() {
        connectionState = .scanning
        candidates = transport.scanForRawDataDevices(knownDeviceID: nil)
        rawDataAvailable = candidates.contains { $0.rawDataServiceSeen }
        nusAvailable = candidates.contains { $0.nusServiceSeen }
        connectionState = candidates.isEmpty ? .noDevice : .selected
        updateRecoveryState(knownDeviceUniquelyVisible: candidates.count == 1)
        appendDiagnostic(category: "BLE", message: "Scan returned \(candidates.count) explicit candidate(s)")
    }

    func reconnectStoredDevice() {
        guard let storedID = identityStore.knownDeviceID else {
            appendDiagnostic(category: "Identity", message: "No stored inAi glasses identity")
            connectionState = .noDevice
            return
        }

        connectionState = .scanning
        candidates = transport.scanForRawDataDevices(knownDeviceID: storedID)
        guard candidates.count == 1, let storedDevice = candidates.first else {
            connectionState = .wrongDeviceRisk
            updateRecoveryState(knownDeviceUniquelyVisible: false)
            appendDiagnostic(category: "Identity", message: "Stored identity was not uniquely visible")
            return
        }

        selectedDevice = storedDevice
        connectSelected()
    }

    func select(_ device: KnownDevice) {
        selectedDevice = device
        rawDataAvailable = device.rawDataServiceSeen
        nusAvailable = device.nusServiceSeen
        identityStore.knownDeviceID = device.id
        connectionState = device.rawDataServiceSeen ? .selected : .recoveryOnly
        updateRecoveryState(knownDeviceUniquelyVisible: true)
        appendDiagnostic(category: "Identity", message: "Selected \(device.displayName)")
    }

    func connectSelected() {
        guard let selectedDevice else {
            connectionState = .noDevice
            return
        }

        let result = transport.connect(to: selectedDevice)
        rawDataAvailable = result.rawDataAvailable
        nusAvailable = result.nusAvailable
        maxWriteLength = result.maxWriteLength
        connectionState = result.state
        if result.state == .connected {
            lastSuccessfulConnectionAt = Date()
        }
        updateRecoveryState(knownDeviceUniquelyVisible: true)
        appendDiagnostic(category: "BLE", message: result.message)
    }

    func recordLifecycle(_ state: BackgroundLifecycleState) {
        lifecycleState = state
        updateRecoveryState(knownDeviceUniquelyVisible: selectedDevice != nil)
        appendDiagnostic(category: "Lifecycle", message: reconnectMessage)
    }

    func sendStaticDraw() {
        guard connectionState.canSendDraw else {
            appendDiagnostic(category: "DRAW", message: "Static DRAW blocked by connection state")
            return
        }

        do {
            let message = MonocleOutboundMessage.staticTextDraw()
            let result = try transport.send(message, maxWriteLength: maxWriteLength)
            appendDiagnostic(category: "DRAW", message: "\(result.message); \(result.byteCount) bytes")
        } catch {
            appendDiagnostic(category: "DRAW", message: "Static DRAW failed: \(error)")
        }
    }

    func receiveNotification(_ data: Data) {
        do {
            guard let event = try transport.ingestNotification(data) else {
                return
            }
            switch event {
            case let .button(value):
                appendDiagnostic(category: "BTN", message: value)
            case let .media(value):
                appendDiagnostic(category: "MEDIA", message: value)
            case let .diagnostic(value):
                appendDiagnostic(category: "CTRL", message: value)
            }
        } catch {
            appendDiagnostic(category: "CTRL", message: "Notification rejected: \(error)")
        }
    }

    private func appendDiagnostic(category: String, message: String) {
        diagnostics.insert(DiagnosticRow(category: category, message: message), at: 0)
        diagnostics = Array(diagnostics.prefix(200))
    }

    private func updateRecoveryState(knownDeviceUniquelyVisible: Bool) {
        let decision = reconnectStateMachine.decision(
            connection: connectionState.runtimeConnection,
            lifecycle: lifecycleState,
            rawDataSeen: rawDataAvailable,
            nusSeen: nusAvailable,
            knownDeviceUniquelyVisible: knownDeviceUniquelyVisible
        )
        recoveryState = decision.recoveryState
        reconnectMessage = decision.userMessage
    }
}

enum DeviceConnectionState: String, Equatable {
    case noDevice
    case scanning
    case selected
    case connected
    case disconnected
    case bluetoothOff
    case permissionDenied
    case wrongDeviceRisk
    case recoveryOnly

    var label: String {
        switch self {
        case .noDevice:
            "No device"
        case .scanning:
            "Scanning"
        case .selected:
            "Selected"
        case .connected:
            "Connected"
        case .disconnected:
            "Disconnected"
        case .bluetoothOff:
            "Bluetooth off"
        case .permissionDenied:
            "Permission denied"
        case .wrongDeviceRisk:
            "Wrong device risk"
        case .recoveryOnly:
            "Recovery only"
        }
    }

    var canSendDraw: Bool {
        self == .connected
    }

    var runtimeConnection: DeviceSessionConnection {
        switch self {
        case .noDevice:
            .noDevice
        case .scanning:
            .scanning
        case .selected:
            .selected
        case .connected:
            .connected
        case .disconnected:
            .disconnected
        case .bluetoothOff:
            .bluetoothOff
        case .permissionDenied:
            .permissionDenied
        case .wrongDeviceRisk:
            .wrongDeviceRisk
        case .recoveryOnly:
            .recoveryOnly
        }
    }
}

struct KnownDevice: Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var advertisedName: String
    var rawDataServiceSeen: Bool
    var nusServiceSeen: Bool
}

struct DiagnosticRow: Identifiable, Equatable {
    var id = UUID()
    var category: String
    var message: String
}

protocol DeviceIdentityStore: AnyObject {
    var knownDeviceID: UUID? { get set }
}

final class UserDefaultsDeviceIdentityStore: DeviceIdentityStore {
    private let defaults: UserDefaults
    private let key = "PrismOS.KnownMonocleDeviceID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var knownDeviceID: UUID? {
        get {
            defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
        }
        set {
            defaults.set(newValue?.uuidString, forKey: key)
        }
    }
}

final class InMemoryDeviceIdentityStore: DeviceIdentityStore {
    var knownDeviceID: UUID?
}
