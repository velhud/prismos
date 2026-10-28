import XCTest
import PrismDraw

final class PrismDrawTests: XCTestCase {
    func testPacksTextOnlyViewport() throws {
        let payload = try PrismDrawPacker.pack(
            DrawViewport(
                appID: "oracle",
                primitives: [
                    .text("READY", x: 320, y: 44, color: 0xFFFFFF, anchor: .middleCenter),
                    .text("Ask", x: 320, y: 140, color: 0xAAAAAA, anchor: .middleCenter)
                ]
            )
        )

        XCTAssertEqual(payload[0], PrismDrawConstants.version)
        XCTAssertEqual(payload[1], 0)
        XCTAssertEqual(payload[2], 6)
        XCTAssertEqual(payload[3], 2)
        XCTAssertLessThanOrEqual(payload.count, PrismDrawConstants.maxPayloadBytes)
    }

    func testEnforcesPrimitiveTextAndAppIDCaps() {
        XCTAssertThrowsError(try PrismDrawPacker.pack(DrawViewport(appID: "oracle", primitives: manyTextItems(13)))) { error in
            XCTAssertEqual(error as? PrismDrawError, .tooManyPrimitives(13))
        }

        XCTAssertThrowsError(
            try PrismDrawPacker.pack(
                DrawViewport(appID: "app-id-is-far-too-long", primitives: [])
            )
        ) { error in
            XCTAssertEqual(error as? PrismDrawError, .appIDTooLong(22))
        }

        XCTAssertThrowsError(
            try PrismDrawPacker.pack(
                DrawViewport(
                    appID: "oracle",
                    primitives: [.text(String(repeating: "x", count: 33), x: 320, y: 44, color: 0, anchor: .middleCenter)]
                )
            )
        ) { error in
            XCTAssertEqual(error as? PrismDrawError, .textTooLong(33))
        }
    }

    func testShapesAreDisabledByDefaultAndEncodedWhenEnabled() {
        let viewport = DrawViewport(appID: "oracle", primitives: [.line(x1: 0, y1: 0, x2: 10, y2: 10, color: 0, width: 1)])

        XCTAssertThrowsError(try PrismDrawPacker.pack(viewport)) { error in
            XCTAssertEqual(error as? PrismDrawError, .shapePrimitiveDisabled)
        }

        let payload = try? PrismDrawPacker.pack(viewport, options: PrismDrawOptions(shapesEnabled: true))
        XCTAssertEqual(payload?[1], PrismDrawConstants.shapeFlag)
    }

    func testRejectsInvalidCoordinatesAndOverlappingRows() {
        XCTAssertThrowsError(
            try PrismDrawPacker.pack(
                DrawViewport(appID: "oracle", primitives: [.text("bad", x: 641, y: 44, color: 0, anchor: .middleCenter)])
            )
        ) { error in
            XCTAssertEqual(error as? PrismDrawError, .coordinateOutOfBounds)
        }

        XCTAssertThrowsError(
            try PrismDrawPacker.pack(
                DrawViewport(
                    appID: "oracle",
                    primitives: [
                        .text("one", x: 320, y: 44, color: 0, anchor: .middleCenter),
                        .text("two", x: 320, y: 50, color: 0, anchor: .middleCenter)
                    ]
                )
            )
        ) { error in
            XCTAssertEqual(error as? PrismDrawError, .overlappingTextRows)
        }
    }

    func testAllowsSameRailRowWhenTextBoxesDoNotTouch() {
        XCTAssertNoThrow(
            try PrismDrawPacker.pack(
                DrawViewport(
                    appID: "orbit",
                    primitives: [
                        .text("1/6", x: 8, y: 4, color: 0, anchor: .topLeft),
                        .text("PRISM OS", x: 320, y: 4, color: 0, anchor: .topCenter),
                        .text("HOST", x: 632, y: 4, color: 0, anchor: .topRight)
                    ]
                )
            )
        )
    }

    func testPayloadCannotExceedDeviceBudget() {
        let primitives = (0..<8).map { index in
            DrawPrimitive.text(String(repeating: "x", count: 26), x: 320, y: UInt16(24 + index * 49), color: 0xFFFFFF, anchor: .middleCenter)
        }

        let payload = try? PrismDrawPacker.pack(DrawViewport(appID: "teleprompter", primitives: primitives))
        XCTAssertNotNil(payload)
        XCTAssertLessThanOrEqual(payload?.count ?? Int.max, PrismDrawConstants.maxPayloadBytes)
    }

    private func manyTextItems(_ count: Int) -> [DrawPrimitive] {
        (0..<count).map { index in
            .text("\(index)", x: 320, y: UInt16(index * 49), color: 0, anchor: .middleCenter)
        }
    }
}
