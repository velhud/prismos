import XCTest
import PrismModels
import PrismRuntime

final class RuntimeBoundaryTests: XCTestCase {
    func testPhaseZeroActiveAndArchivedAppsAreSeparated() {
        XCTAssertEqual(PrismAppID.allCases.map(\.rawValue), [
            "oracle",
            "vision",
            "signal",
            "chronos",
            "teleprompter",
            "babel"
        ])
        XCTAssertEqual(ArchivedPrismAppID.allCases.map(\.rawValue), ["navigate", "recall"])
    }

    func testRequestIDRejectsStaleCompletion() {
        let current = PrismRequestID()
        let stale = PrismRequestID()

        XCTAssertTrue(current.isCurrent(comparedTo: current))
        XCTAssertFalse(stale.isCurrent(comparedTo: current))
    }

    func testReservedGestureModelExistsOutsideRuntimeDispatch() {
        XCTAssertFalse(PrismButtonGesture.doubleTap.isOSReserved)
        XCTAssertTrue(PrismButtonGesture.doubleTap.isOSReserved(on: .right))
        XCTAssertFalse(PrismButtonGesture.doubleTap.isOSReserved(on: .left))
        XCTAssertTrue(PrismButtonGesture.longPress.isOSReserved(on: .left))
        XCTAssertFalse(PrismButtonGesture.tap.isOSReserved)
        XCTAssertEqual(
            RuntimeEffect.sendDrawNow(appID: .oracle),
            RuntimeEffect.sendDrawNow(appID: .oracle)
        )
    }
}
