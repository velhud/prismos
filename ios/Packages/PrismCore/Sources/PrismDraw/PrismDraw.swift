import Foundation
import PrismModels

public enum PrismDrawConstants {
    public static let version: UInt8 = 1
    public static let maxPayloadBytes = 1_536
    public static let maxPrimitiveCount = 12
    public static let maxAppIDBytes = 16
    public static let maxTextBytes = 32
    public static let shapeFlag: UInt8 = 0x01
}

public enum DrawAnchor: UInt8, CaseIterable, Sendable, Codable {
    case middleCenter = 0
    case topLeft = 1
    case topCenter = 2
    case topRight = 3
    case middleLeft = 4
    case middleRight = 5
    case bottomLeft = 6
    case bottomCenter = 7
    case bottomRight = 8
}

public enum DrawPrimitive: Equatable, Sendable {
    case text(String, x: UInt16, y: UInt16, color: UInt32, anchor: DrawAnchor)
    case line(x1: UInt16, y1: UInt16, x2: UInt16, y2: UInt16, color: UInt32, width: UInt8)
    case rectangle(x1: UInt16, y1: UInt16, x2: UInt16, y2: UInt16, color: UInt32)
    case fill(color: UInt32)
}

public struct DrawViewport: Equatable, Sendable {
    public var appID: String
    public var primitives: [DrawPrimitive]

    public init(appID: String, primitives: [DrawPrimitive]) {
        self.appID = appID
        self.primitives = primitives
    }
}

public struct PrismDrawOptions: Equatable, Sendable {
    public var shapesEnabled: Bool
    public var viewport: PrismViewport

    public init(shapesEnabled: Bool = false, viewport: PrismViewport = .monocle) {
        self.shapesEnabled = shapesEnabled
        self.viewport = viewport
    }
}

public enum PrismDrawError: Error, Equatable, Sendable {
    case appIDTooLong(Int)
    case tooManyPrimitives(Int)
    case textTooLong(Int)
    case shapePrimitiveDisabled
    case coordinateOutOfBounds
    case invalidLineWidth(UInt8)
    case payloadTooLarge(Int)
    case unsupportedTextEncoding
    case overlappingTextRows
}

public enum PrismDrawPacker {
    public static func pack(_ viewport: DrawViewport, options: PrismDrawOptions = PrismDrawOptions()) throws -> Data {
        guard let appBytes = viewport.appID.data(using: .utf8) else {
            throw PrismDrawError.unsupportedTextEncoding
        }
        guard appBytes.count <= PrismDrawConstants.maxAppIDBytes else {
            throw PrismDrawError.appIDTooLong(appBytes.count)
        }
        guard viewport.primitives.count <= PrismDrawConstants.maxPrimitiveCount else {
            throw PrismDrawError.tooManyPrimitives(viewport.primitives.count)
        }

        try MonocleDisplayValidator.validate(viewport, options: options)

        var payload = Data([
            PrismDrawConstants.version,
            options.shapesEnabled ? PrismDrawConstants.shapeFlag : 0,
            UInt8(appBytes.count),
            UInt8(viewport.primitives.count)
        ])
        payload.append(appBytes)

        for primitive in viewport.primitives {
            switch primitive {
            case let .text(text, x, y, color, anchor):
                guard let textBytes = text.data(using: .utf8) else {
                    throw PrismDrawError.unsupportedTextEncoding
                }
                guard textBytes.count <= PrismDrawConstants.maxTextBytes else {
                    throw PrismDrawError.textTooLong(textBytes.count)
                }
                payload.append(0x01)
                appendUInt16LE(x, to: &payload)
                appendUInt16LE(y, to: &payload)
                appendUInt32LE(color, to: &payload)
                payload.append(anchor.rawValue)
                payload.append(UInt8(textBytes.count))
                payload.append(textBytes)
            case let .line(x1, y1, x2, y2, color, width):
                guard options.shapesEnabled else {
                    throw PrismDrawError.shapePrimitiveDisabled
                }
                guard (1...8).contains(width) else {
                    throw PrismDrawError.invalidLineWidth(width)
                }
                payload.append(0x02)
                appendUInt16LE(x1, to: &payload)
                appendUInt16LE(y1, to: &payload)
                appendUInt16LE(x2, to: &payload)
                appendUInt16LE(y2, to: &payload)
                appendUInt32LE(color, to: &payload)
                payload.append(width)
            case let .rectangle(x1, y1, x2, y2, color):
                guard options.shapesEnabled else {
                    throw PrismDrawError.shapePrimitiveDisabled
                }
                payload.append(0x03)
                appendUInt16LE(x1, to: &payload)
                appendUInt16LE(y1, to: &payload)
                appendUInt16LE(x2, to: &payload)
                appendUInt16LE(y2, to: &payload)
                appendUInt32LE(color, to: &payload)
            case let .fill(color):
                guard options.shapesEnabled else {
                    throw PrismDrawError.shapePrimitiveDisabled
                }
                payload.append(0x04)
                appendUInt32LE(color, to: &payload)
            }

            guard payload.count <= PrismDrawConstants.maxPayloadBytes else {
                throw PrismDrawError.payloadTooLarge(payload.count)
            }
        }

        return payload
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

public struct MonocleDisplayMetrics: Equatable, Sendable {
    public static let current = MonocleDisplayMetrics(width: 640, height: 400, fontWidth: 24, fontHeight: 48)

    public var width: Int
    public var height: Int
    public var fontWidth: Int
    public var fontHeight: Int

    public init(width: Int, height: Int, fontWidth: Int, fontHeight: Int) {
        self.width = width
        self.height = height
        self.fontWidth = fontWidth
        self.fontHeight = fontHeight
    }

    public var visibleColumns: Int {
        width / fontWidth
    }
}

public enum MonocleDisplayValidator {
    public static func validate(_ viewport: DrawViewport, options: PrismDrawOptions) throws {
        var textBounds: [CGRectLike] = []
        for primitive in viewport.primitives {
            switch primitive {
            case let .text(text, x, y, _, anchor):
                try validatePoint(x: x, y: y, viewport: options.viewport)
                let rect = CGRectLike.textBounds(text: text, x: Int(x), y: Int(y), anchor: anchor)
                if textBounds.contains(where: { $0.intersects(with: rect) }) {
                    throw PrismDrawError.overlappingTextRows
                }
                textBounds.append(rect)
            case let .line(x1, y1, x2, y2, _, _):
                try validatePoint(x: x1, y: y1, viewport: options.viewport)
                try validatePoint(x: x2, y: y2, viewport: options.viewport)
            case let .rectangle(x1, y1, x2, y2, _):
                try validatePoint(x: x1, y: y1, viewport: options.viewport)
                try validatePoint(x: x2, y: y2, viewport: options.viewport)
            case .fill:
                break
            }
        }
    }

    private static func validatePoint(x: UInt16, y: UInt16, viewport: PrismViewport) throws {
        guard Int(x) >= 0, Int(x) <= viewport.width, Int(y) >= 0, Int(y) <= viewport.height else {
            throw PrismDrawError.coordinateOutOfBounds
        }
    }

    private struct CGRectLike {
        var left: Int
        var right: Int
        var top: Int
        var bottom: Int

        static func textBounds(text: String, x: Int, y: Int, anchor: DrawAnchor) -> CGRectLike {
            let width = text.count * MonocleDisplayMetrics.current.fontWidth
            let height = MonocleDisplayMetrics.current.fontHeight
            let left: Int
            switch anchor {
            case .topLeft, .middleLeft, .bottomLeft:
                left = x
            case .topRight, .middleRight, .bottomRight:
                left = x - width
            case .topCenter, .middleCenter, .bottomCenter:
                left = x - width / 2
            }
            let top: Int
            switch anchor {
            case .topLeft, .topCenter, .topRight:
                top = y
            case .bottomLeft, .bottomCenter, .bottomRight:
                top = y - height
            case .middleCenter, .middleLeft, .middleRight:
                top = y - height / 2
            }
            return CGRectLike(left: left, right: left + width, top: top, bottom: top + height)
        }

        func intersects(with other: CGRectLike) -> Bool {
            left < other.right && other.left < right && top < other.bottom && other.top < bottom
        }
    }
}
