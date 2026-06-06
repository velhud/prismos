import XCTest
import PrismModels
@testable import PrismRuntime

final class DeviceSessionRuntimeTests: XCTestCase {
    func testSessionTracksSelectedIdentityAndConnectedHealth() async {
        let session = DeviceSessionCore()
        let deviceID = UUID()

        await session.selectDevice(id: deviceID)
        await session.markConnected()
        let snapshot = await session.snapshot()

        XCTAssertEqual(snapshot.connection, .connected)
        XCTAssertEqual(snapshot.selectedDeviceID, deviceID)
        XCTAssertEqual(snapshot.transportHealth, .ready)
        XCTAssertEqual(snapshot.latestWidgets.map(\.appID), PrismAppID.allCases)
    }

    func testFocusedButtonQueuesLatestDrawOnly() async {
        let session = DeviceSessionCore()

        await session.focus(appID: .oracle)
        await session.receiveButton(ButtonEvent(side: .right, gesture: .tap, durationMilliseconds: 80))
        await session.receiveButton(ButtonEvent(side: .right, gesture: .tap, durationMilliseconds: 80))
        let snapshot = await session.snapshot()
        let draw = await session.drainOutboundDraw()

        XCTAssertEqual(snapshot.activeAppID, .oracle)
        XCTAssertEqual(snapshot.pendingDrawCount, 1)
        XCTAssertEqual(draw?.appID, PrismAppID.oracle.rawValue)
        let drainedAgain = await session.drainOutboundDraw()
        XCTAssertNil(drainedAgain)
    }

    func testReservedGestureDoesNotChangeFocusedApp() async {
        let session = DeviceSessionCore()

        await session.focus(appID: .oracle)
        await session.receiveButton(ButtonEvent(side: .left, gesture: .doubleTap, durationMilliseconds: 160))
        let snapshot = await session.snapshot()

        XCTAssertEqual(snapshot.activeAppID, .oracle)
        XCTAssertEqual(snapshot.pendingDrawCount, 1)
    }

    func testReconnectCanRestoreFocusedAppOrReturnToOrbit() async {
        let restoreSession = DeviceSessionCore()
        await restoreSession.focus(appID: .babel)
        await restoreSession.markDisconnected()
        await restoreSession.restoreAfterReconnect(policy: .lastSafeVisibleState)

        let restored = await restoreSession.snapshot()
        XCTAssertEqual(restored.connection, .connected)
        XCTAssertEqual(restored.activeAppID, .babel)

        let orbitSession = DeviceSessionCore()
        await orbitSession.focus(appID: .babel)
        await orbitSession.markDisconnected()
        await orbitSession.restoreAfterReconnect(policy: .orbit)

        let orbit = await orbitSession.snapshot()
        XCTAssertEqual(orbit.connection, .connected)
        XCTAssertNil(orbit.activeAppID)
    }

    func testPermissionControllerReportsMissingRequiredPermissions() {
        var permissions = PermissionController()
        permissions.record(.allowed, for: .bluetooth)
        permissions.record(.denied, for: .microphone)

        XCTAssertEqual(permissions.status(for: .bluetooth), .allowed)
        XCTAssertEqual(permissions.missingRequired([.bluetooth, .microphone, .camera]), [.microphone, .camera])
    }

    func testReconnectStateMachineClassifiesLifecycleAndRecoveryStates() {
        let machine = ReconnectStateMachine()

        let forceQuit = machine.decision(
            connection: .disconnected,
            lifecycle: .forceQuitLimited,
            rawDataSeen: true,
            nusSeen: false,
            knownDeviceUniquelyVisible: true
        )
        XCTAssertEqual(forceQuit.action, .showDegradedMode)
        XCTAssertTrue(forceQuit.userMessage.contains("force quit"))

        let recovery = machine.decision(
            connection: .recoveryOnly,
            lifecycle: .foreground,
            rawDataSeen: false,
            nusSeen: true,
            knownDeviceUniquelyVisible: true
        )
        XCTAssertEqual(recovery.action, .showRecoveryOnly)
        XCTAssertEqual(recovery.recoveryState, .safeModeLikely)
        XCTAssertTrue(recovery.recoveryState.disablesNormalControls)

        let wrongDevice = machine.decision(
            connection: .wrongDeviceRisk,
            lifecycle: .foreground,
            rawDataSeen: true,
            nusSeen: false,
            knownDeviceUniquelyVisible: false
        )
        XCTAssertEqual(wrongDevice.action, .blockWrongDevice)
    }

    func testHardenedOutboundQueuePrioritizesAndCoalesces() {
        var queue = HardenedOutboundQueue()
        queue.enqueue(OutboundPacket(kind: .debugLog, payloadSummary: "debug"), developerMode: false)
        queue.enqueue(OutboundPacket(kind: .hardwareCommand, payloadSummary: "capture"))
        queue.enqueue(OutboundPacket(kind: .orbitDraw, payloadSummary: "orbit old"))
        queue.enqueue(OutboundPacket(kind: .orbitDraw, payloadSummary: "orbit new"))
        queue.enqueue(OutboundPacket(kind: .focusedDraw, appID: .vision, payloadSummary: "focused old"))
        queue.enqueue(OutboundPacket(kind: .focusedDraw, appID: .vision, payloadSummary: "focused new"))

        XCTAssertEqual(queue.drainNext()?.payloadSummary, "focused new")
        XCTAssertEqual(queue.drainNext()?.payloadSummary, "orbit new")
        XCTAssertEqual(queue.drainNext()?.payloadSummary, "capture")
        XCTAssertNil(queue.drainNext())

        queue.enqueue(OutboundPacket(kind: .debugLog, payloadSummary: "developer debug"), developerMode: true)
        XCTAssertEqual(queue.drainNext()?.payloadSummary, "developer debug")
    }
}
