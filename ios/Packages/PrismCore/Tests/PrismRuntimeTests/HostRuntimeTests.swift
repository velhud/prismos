import XCTest
import PrismDraw
import PrismModels
@testable import PrismRuntime

final class HostRuntimeTests: XCTestCase {
    func testRegistryContainsOnlyActiveApps() {
        let registry = HostRuntimeRegistry()

        XCTAssertEqual(registry.activeAppIDs, PrismAppID.allCases)
        XCTAssertFalse(registry.widgetSnapshot().contains { $0.label == "Navigate" || $0.label == "Recall" })
    }

    func testEveryActiveAppRendersUnderDrawBudget() throws {
        let registry = HostRuntimeRegistry()

        for appID in registry.activeAppIDs {
            let viewport = try XCTUnwrap(registry.render(appID: appID))
            let payload = try PrismDrawPacker.pack(viewport)
            XCTAssertLessThanOrEqual(payload.count, PrismDrawConstants.maxPayloadBytes, "\(appID.rawValue) exceeded draw budget")
        }
    }

    func testOrbitRendersUnderDrawBudgetWithoutArchivedApps() throws {
        let registry = HostRuntimeRegistry()

        let viewport = registry.renderOrbit()
        let payload = try PrismDrawPacker.pack(viewport)

        XCTAssertLessThanOrEqual(payload.count, PrismDrawConstants.maxPayloadBytes)
        XCTAssertFalse(viewport.primitives.contains { primitive in
            if case let .text(text, _, _, _, _) = primitive {
                return text.contains("Navigate") || text.contains("Recall")
            }
            return false
        })
    }

    func testRuntimeDisplayTextFitsNativeDeviceColumns() throws {
        let registry = HostRuntimeRegistry()
        let maxColumns = MonocleDisplayTextStyle.nativeColumns
        let orbit = registry.renderOrbit()

        for viewport in [orbit] + registry.activeAppIDs.compactMap({ registry.render(appID: $0) }) {
            for primitive in viewport.primitives {
                if case let .text(text, _, _, _, _) = primitive {
                    XCTAssertLessThanOrEqual(text.count, maxColumns, "\(viewport.appID) text exceeds native columns: \(text)")
                }
            }
        }
    }

    func testFocusAndButtonRouteToOneRuntimeAndQueueDraw() {
        var coordinator = AppCoordinatorCore()
        let enterEffect = coordinator.focus(appID: .oracle)
        let buttonEffect = coordinator.handleButton(ButtonEvent(side: .right, gesture: .tap, durationMilliseconds: 80))
        let snapshot = coordinator.snapshot()

        XCTAssertEqual(enterEffect, .sendDrawNow(appID: .oracle))
        XCTAssertEqual(buttonEffect, .sendDrawNow(appID: .oracle))
        XCTAssertEqual(snapshot.surface, .focused(.oracle))
        XCTAssertEqual(coordinator.nextDraw()?.appID, PrismAppID.oracle.rawValue)
    }

    func testExitToOrbitQueuesOrbitDrawWithoutAppMasquerade() {
        var coordinator = AppCoordinatorCore()
        _ = coordinator.focus(appID: .vision)
        _ = coordinator.nextDraw()

        let effect = coordinator.exitToOrbit()
        let draw = coordinator.nextDraw()

        XCTAssertEqual(effect, .sendOrbitDrawNow)
        XCTAssertEqual(draw?.appID, "orbit")
        XCTAssertEqual(coordinator.snapshot().surface, .orbit)
    }

    func testRuntimeStateRetainsAcrossFocusChanges() {
        var registry = HostRuntimeRegistry()
        let tap = ButtonEvent(side: .right, gesture: .tap, durationMilliseconds: 80)

        _ = registry.button(tap, focusedAppID: .oracle, context: RuntimeContext())
        _ = registry.enter(appID: .vision, context: RuntimeContext())
        _ = registry.exit(appID: .vision, context: RuntimeContext())

        XCTAssertEqual(registry.runtimeState(appID: .oracle)?.buttonCount, 1)
    }

    func testReservedDoubleRightQuickLaunchesOracle() {
        var coordinator = AppCoordinatorCore()
        _ = coordinator.focus(appID: .vision)

        let effect = coordinator.handleButton(ButtonEvent(side: .right, gesture: .doubleTap, durationMilliseconds: 160))
        let snapshot = coordinator.snapshot()

        XCTAssertEqual(effect, .sendDrawNow(appID: .oracle))
        XCTAssertEqual(snapshot.surface, .focused(.oracle))
    }

    func testDoubleLeftStillReachesFocusedApp() {
        var coordinator = AppCoordinatorCore()
        _ = coordinator.focus(appID: .oracle)

        let effect = coordinator.handleButton(ButtonEvent(side: .left, gesture: .doubleTap, durationMilliseconds: 160))

        XCTAssertEqual(effect, .sendDrawNow(appID: .oracle))
    }

    func testDrawCoalescerKeepsOnlyLatestViewport() {
        var coalescer = DrawCoalescer()
        coalescer.enqueue(DrawViewport(appID: "old", primitives: []))
        coalescer.enqueue(DrawViewport(appID: "new", primitives: []))

        XCTAssertEqual(coalescer.drain()?.appID, "new")
        XCTAssertNil(coalescer.drain())
    }

    func testRequestTrackerRejectsStaleProviderCompletions() {
        var tracker = RuntimeRequestTracker()
        let first = tracker.begin(appID: .oracle)
        let second = tracker.begin(appID: .oracle)

        XCTAssertFalse(tracker.accepts(appID: .oracle, requestID: first))
        XCTAssertTrue(tracker.accepts(appID: .oracle, requestID: second))
    }

    func testFallbackStatesRenderHonestlyUnderBudget() throws {
        let registry = HostRuntimeRegistry()

        for fallback in RuntimeFallbackState.allCases {
            let context = RuntimeContext(fallback: fallback)
            let viewport = try XCTUnwrap(registry.render(appID: .oracle, context: context))
            let payload = try PrismDrawPacker.pack(viewport)

            XCTAssertLessThanOrEqual(payload.count, PrismDrawConstants.maxPayloadBytes)
            XCTAssertTrue(viewport.primitives.contains { primitive in
                if case let .text(text, _, _, _, _) = primitive {
                    return text == fallback.displayText
                }
                return false
            }, "\(fallback) did not render its honest fallback label")
        }
    }
}
