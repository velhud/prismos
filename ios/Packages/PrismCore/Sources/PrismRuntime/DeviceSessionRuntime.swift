import Foundation
import PrismDraw
import PrismModels

public enum DeviceSessionConnection: String, Sendable, Codable {
    case noDevice
    case scanning
    case selected
    case connected
    case disconnected
    case bluetoothOff
    case permissionDenied
    case wrongDeviceRisk
    case recoveryOnly
}

public enum DeviceTransportHealth: String, Sendable, Codable {
    case unavailable
    case ready
    case backpressured
    case degraded
    case failed
}

public enum ReconnectRestorePolicy: String, Sendable, Codable {
    case lastSafeVisibleState
    case orbit
}

public enum BackgroundLifecycleState: String, Sendable, Codable {
    case foreground
    case backgroundWake
    case restoredByCoreBluetooth
    case forceQuitLimited
    case bluetoothPoweredOff
    case permissionDenied
    case lowBattery
}

public enum RecoveryModeState: String, Sendable, Codable {
    case runtimeAvailable
    case waitingForHost
    case safeModeLikely
    case unknownMonocle
    case wrongDeviceRisk

    public var disablesNormalControls: Bool {
        switch self {
        case .runtimeAvailable, .waitingForHost:
            false
        case .safeModeLikely, .unknownMonocle, .wrongDeviceRisk:
            true
        }
    }
}

public struct ReconnectDecision: Equatable, Sendable {
    public enum Action: String, Sendable {
        case retrieveKnownPeripheral
        case userApprovedServiceScan
        case showRecoveryOnly
        case showDegradedMode
        case blockWrongDevice
    }

    public var action: Action
    public var recoveryState: RecoveryModeState
    public var userMessage: String

    public init(action: Action, recoveryState: RecoveryModeState, userMessage: String) {
        self.action = action
        self.recoveryState = recoveryState
        self.userMessage = userMessage
    }
}

public struct ReconnectStateMachine: Sendable {
    public init() {}

    public func decision(
        connection: DeviceSessionConnection,
        lifecycle: BackgroundLifecycleState,
        rawDataSeen: Bool,
        nusSeen: Bool,
        knownDeviceUniquelyVisible: Bool
    ) -> ReconnectDecision {
        if lifecycle == .forceQuitLimited {
            return ReconnectDecision(
                action: .showDegradedMode,
                recoveryState: .waitingForHost,
                userMessage: "iOS will not relaunch PrismHost for BLE after force quit. Reopen the app."
            )
        }
        if lifecycle == .bluetoothPoweredOff || connection == .bluetoothOff {
            return ReconnectDecision(
                action: .showDegradedMode,
                recoveryState: .waitingForHost,
                userMessage: "Bluetooth is off. Turn it on to reconnect."
            )
        }
        if lifecycle == .permissionDenied || connection == .permissionDenied {
            return ReconnectDecision(
                action: .showDegradedMode,
                recoveryState: .waitingForHost,
                userMessage: "Bluetooth permission is denied. Update Settings to reconnect."
            )
        }
        if nusSeen && !rawDataSeen {
            return ReconnectDecision(
                action: .showRecoveryOnly,
                recoveryState: .safeModeLikely,
                userMessage: "NUS recovery is visible but Raw Data is not. Safe Mode is recovery-only."
            )
        }
        if !knownDeviceUniquelyVisible && connection == .wrongDeviceRisk {
            return ReconnectDecision(
                action: .blockWrongDevice,
                recoveryState: .wrongDeviceRisk,
                userMessage: "Stored Monocle identity is not uniquely visible. Select the device manually."
            )
        }
        if knownDeviceUniquelyVisible {
            return ReconnectDecision(
                action: .retrieveKnownPeripheral,
                recoveryState: rawDataSeen ? .runtimeAvailable : .waitingForHost,
                userMessage: "Known Monocle can be retrieved by stored identifier."
            )
        }
        return ReconnectDecision(
            action: .userApprovedServiceScan,
            recoveryState: rawDataSeen ? .runtimeAvailable : .unknownMonocle,
            userMessage: "Scan by Raw Data service after user approval."
        )
    }
}

public struct DeviceSessionSnapshot: Equatable, Sendable {
    public var connection: DeviceSessionConnection
    public var selectedDeviceID: UUID?
    public var activeAppID: PrismAppID?
    public var transportHealth: DeviceTransportHealth
    public var latestWidgets: [RuntimeWidget]
    public var pendingDrawCount: Int

    public init(
        connection: DeviceSessionConnection,
        selectedDeviceID: UUID?,
        activeAppID: PrismAppID?,
        transportHealth: DeviceTransportHealth,
        latestWidgets: [RuntimeWidget],
        pendingDrawCount: Int
    ) {
        self.connection = connection
        self.selectedDeviceID = selectedDeviceID
        self.activeAppID = activeAppID
        self.transportHealth = transportHealth
        self.latestWidgets = latestWidgets
        self.pendingDrawCount = pendingDrawCount
    }
}

public struct OutboundDrawQueue: Sendable {
    private var pending: DrawViewport?

    public init() {}

    public var count: Int {
        pending == nil ? 0 : 1
    }

    public mutating func enqueue(_ viewport: DrawViewport) {
        pending = viewport
    }

    public mutating func drain() -> DrawViewport? {
        defer { pending = nil }
        return pending
    }
}

public enum OutboundPacketKind: String, Sendable, Equatable {
    case focusedDraw
    case orbitDraw
    case hardwareCommand
    case debugLog
}

public struct OutboundPacket: Equatable, Sendable {
    public var kind: OutboundPacketKind
    public var appID: PrismAppID?
    public var messageID: PrismRequestID
    public var payloadSummary: String

    public init(
        kind: OutboundPacketKind,
        appID: PrismAppID? = nil,
        messageID: PrismRequestID = PrismRequestID(),
        payloadSummary: String
    ) {
        self.kind = kind
        self.appID = appID
        self.messageID = messageID
        self.payloadSummary = payloadSummary
    }
}

public struct HardenedOutboundQueue: Sendable {
    private var focusedDraw: OutboundPacket?
    private var orbitDraw: OutboundPacket?
    private var hardwareCommand: OutboundPacket?
    private var debugLog: OutboundPacket?

    public init() {}

    public mutating func enqueue(_ packet: OutboundPacket, developerMode: Bool = false) {
        switch packet.kind {
        case .focusedDraw:
            focusedDraw = packet
        case .orbitDraw:
            orbitDraw = packet
        case .hardwareCommand:
            hardwareCommand = packet
        case .debugLog:
            if developerMode {
                debugLog = packet
            }
        }
    }

    public mutating func drainNext() -> OutboundPacket? {
        if let packet = focusedDraw {
            focusedDraw = nil
            return packet
        }
        if let packet = orbitDraw {
            orbitDraw = nil
            return packet
        }
        if let packet = hardwareCommand {
            hardwareCommand = nil
            return packet
        }
        defer { debugLog = nil }
        return debugLog
    }
}

public actor DeviceSessionCore {
    private var connection: DeviceSessionConnection = .noDevice
    private var selectedDeviceID: UUID?
    private var transportHealth: DeviceTransportHealth = .unavailable
    private var coordinator: AppCoordinatorCore
    private var outboundQueue = OutboundDrawQueue()

    public init(coordinator: AppCoordinatorCore = AppCoordinatorCore()) {
        self.coordinator = coordinator
        if let initial = self.coordinator.nextDraw() {
            outboundQueue.enqueue(initial)
        }
    }

    public func selectDevice(id: UUID) {
        selectedDeviceID = id
        connection = .selected
        transportHealth = .unavailable
    }

    public func markConnected() {
        connection = .connected
        transportHealth = .ready
        enqueueCurrentDraw()
    }

    public func markDisconnected() {
        connection = .disconnected
        transportHealth = .degraded
    }

    public func restoreAfterReconnect(policy: ReconnectRestorePolicy) {
        connection = .connected
        transportHealth = .ready
        if policy == .orbit {
            _ = coordinator.exitToOrbit()
        }
        enqueueCurrentDraw()
    }

    public func markRecoveryOnly() {
        connection = .recoveryOnly
        transportHealth = .degraded
        outboundQueue.enqueue(HostRuntimeRegistry().render(appID: .oracle, context: RuntimeContext(fallback: .recoveryOnly)) ?? HostRuntimeRegistry().renderOrbit())
    }

    public func focus(appID: PrismAppID) {
        _ = coordinator.focus(appID: appID)
        enqueueCurrentDraw()
    }

    public func receiveButton(_ event: ButtonEvent) {
        _ = coordinator.handleButton(event)
        enqueueCurrentDraw()
    }

    public func receiveMedia(_ event: MediaEvent) {
        _ = coordinator.handleMedia(event)
        enqueueCurrentDraw()
    }

    public func drainOutboundDraw() -> DrawViewport? {
        outboundQueue.drain()
    }

    public func snapshot() -> DeviceSessionSnapshot {
        let runtimeSnapshot = coordinator.snapshot()
        let activeAppID: PrismAppID?
        if case let .focused(appID) = runtimeSnapshot.surface {
            activeAppID = appID
        } else {
            activeAppID = nil
        }
        return DeviceSessionSnapshot(
            connection: connection,
            selectedDeviceID: selectedDeviceID,
            activeAppID: activeAppID,
            transportHealth: transportHealth,
            latestWidgets: runtimeSnapshot.widgets,
            pendingDrawCount: outboundQueue.count
        )
    }

    private func enqueueCurrentDraw() {
        outboundQueue.enqueue(coordinator.snapshot().latestDraw)
    }
}

public enum PrismPermission: String, CaseIterable, Sendable, Codable {
    case bluetooth
    case microphone
    case camera
    case speech
    case notifications
}

public enum PermissionStatus: String, Sendable, Codable {
    case unknown
    case allowed
    case denied
}

public struct PermissionController: Sendable {
    private var statuses: [PrismPermission: PermissionStatus]

    public init(statuses: [PrismPermission: PermissionStatus] = [:]) {
        self.statuses = statuses
    }

    public func status(for permission: PrismPermission) -> PermissionStatus {
        statuses[permission] ?? .unknown
    }

    public mutating func record(_ status: PermissionStatus, for permission: PrismPermission) {
        statuses[permission] = status
    }

    public func missingRequired(_ permissions: [PrismPermission]) -> [PrismPermission] {
        permissions.filter { status(for: $0) != .allowed }
    }
}
