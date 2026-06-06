import Foundation

public enum PrismAppID: String, CaseIterable, Sendable, Codable {
    case oracle
    case vision
    case signal
    case chronos
    case teleprompter
    case babel
}

public enum ArchivedPrismAppID: String, CaseIterable, Sendable, Codable {
    case navigate
    case recall
}

public struct PrismViewport: Equatable, Sendable, Codable {
    public static let monocle = PrismViewport(width: 640, height: 400)

    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct PrismRequestID: RawRepresentable, Hashable, Sendable, Codable {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public func isCurrent(comparedTo current: PrismRequestID?) -> Bool {
        self == current
    }
}

public enum PrismButtonSide: String, Sendable, Codable {
    case left = "L"
    case right = "R"
}

public enum PrismButtonGesture: String, Sendable, Codable {
    case tap = "TAP"
    case doubleTap = "DOUBLE"
    case longPress = "LONG"

    public var isOSReserved: Bool {
        false
    }

    public func isOSReserved(on side: PrismButtonSide) -> Bool {
        switch (side, self) {
        case (.left, .longPress), (.right, .doubleTap):
            true
        case (.left, .tap), (.left, .doubleTap), (.right, .tap), (.right, .longPress):
            false
        }
    }
}

public struct ButtonEvent: Equatable, Sendable, Codable {
    public var side: PrismButtonSide
    public var gesture: PrismButtonGesture
    public var durationMilliseconds: Int

    public init(side: PrismButtonSide, gesture: PrismButtonGesture, durationMilliseconds: Int) {
        self.side = side
        self.gesture = gesture
        self.durationMilliseconds = durationMilliseconds
    }
}

public enum MediaEventKind: String, Sendable, Codable {
    case image = "IMAGE"
    case audio = "AUDIO"
}

public enum MediaEventStatus: String, Sendable, Codable {
    case start = "START"
    case end = "END"
    case error = "ERROR"
}

public struct MediaEvent: Equatable, Sendable, Codable {
    public var kind: MediaEventKind
    public var status: MediaEventStatus
    public var detail: String

    public init(kind: MediaEventKind, status: MediaEventStatus, detail: String = "") {
        self.kind = kind
        self.status = status
        self.detail = detail
    }
}
