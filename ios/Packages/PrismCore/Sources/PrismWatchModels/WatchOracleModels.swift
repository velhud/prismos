import Foundation

public enum WatchOraclePhase: String, CaseIterable, Sendable, Codable {
    case ready
    case listening
    case thinking
    case answer
    case cancelled
    case error

    public var displayTitle: String {
        switch self {
        case .ready:
            "READY"
        case .listening:
            "LISTENING"
        case .thinking:
            "THINKING"
        case .answer:
            "ANSWER"
        case .cancelled:
            "CANCELLED"
        case .error:
            "ERROR"
        }
    }

    public var isBusy: Bool {
        switch self {
        case .listening, .thinking:
            true
        case .ready, .answer, .cancelled, .error:
            false
        }
    }
}

public enum WatchOracleDensity: String, CaseIterable, Sendable, Codable {
    case shorter
    case balanced
    case moreDetail

    public var displayTitle: String {
        switch self {
        case .shorter:
            "SHORT"
        case .balanced:
            "BALANCED"
        case .moreDetail:
            "DETAIL"
        }
    }

    public var canShorten: Bool {
        self != .shorter
    }

    public var canExpand: Bool {
        self != .moreDetail
    }
}

public enum WatchOracleAction: Equatable, Sendable, Codable {
    case ask
    case followUp
    case clear
    case toggleKeep
    case copy
    case shorter
    case moreDetail
    case adjustPage(Int)
}

public struct WatchOracleState: Equatable, Sendable, Codable {
    public var phase: WatchOraclePhase
    public var density: WatchOracleDensity
    public var pageIndex: Int
    public var pageCount: Int
    public var historyCount: Int
    public var isKept: Bool
    public var promptText: String?
    public var pageText: String?
    public var errorText: String?
    public var lastUpdatedAt: Date

    public init(
        phase: WatchOraclePhase = .ready,
        density: WatchOracleDensity = .balanced,
        pageIndex: Int = 0,
        pageCount: Int = 0,
        historyCount: Int = 0,
        isKept: Bool = false,
        promptText: String? = nil,
        pageText: String? = nil,
        errorText: String? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.phase = phase
        self.density = density
        self.pageIndex = min(max(pageIndex, 0), max(pageCount - 1, 0))
        self.pageCount = max(pageCount, 0)
        self.historyCount = max(historyCount, 0)
        self.isKept = isKept
        self.promptText = promptText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pageText = pageText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.errorText = errorText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var statusTitle: String {
        phase.displayTitle
    }

    public var pageTitle: String {
        guard pageCount > 0 else {
            return "0/0"
        }
        return "\(min(pageIndex + 1, pageCount))/\(pageCount)"
    }

    public var historyTitle: String {
        historyCount == 0 ? "NO HISTORY" : "\(historyCount) HISTORY"
    }

    public var densityTitle: String {
        density.displayTitle
    }

    public var keepTitle: String {
        isKept ? "KEPT" : "OPEN"
    }

    public var primaryActionTitle: String {
        phase == .answer ? "FOLLOW UP" : "ASK"
    }

    public var secondaryActionTitle: String {
        switch phase {
        case .answer:
            isKept ? "UNKEEP" : "KEEP"
        case .listening, .thinking:
            "CANCEL"
        case .ready, .cancelled, .error:
            "CLEAR"
        }
    }

    public var clearActionTitle: String {
        phase.isBusy ? "CANCEL" : "CLEAR"
    }

    public var copyActionTitle: String {
        "COPY"
    }

    public var shorterActionTitle: String {
        "SHORTER"
    }

    public var moreDetailActionTitle: String {
        "MORE"
    }

    public var crownHintTitle: String {
        phase == .answer ? "PAGE" : "DENSITY"
    }

    public var compactTitle: String {
        switch phase {
        case .ready:
            return "ASK READY"
        case .listening:
            return "LISTENING"
        case .thinking:
            return "THINKING"
        case .answer:
            return "\(pageTitle) \(keepTitle)"
        case .cancelled:
            return "CANCELLED"
        case .error:
            return errorText?.uppercased() ?? "ERROR"
        }
    }

    public var detailTitle: String {
        switch phase {
        case .ready:
            return "TAP ASK TO START"
        case .listening:
            return promptText?.isEmpty == false ? promptText! : "LISTENING ON MONOCLE"
        case .thinking:
            return promptText?.isEmpty == false ? promptText! : "SYNTHESIZING"
        case .answer:
            return pageText?.isEmpty == false ? pageText! : "PRIVATE"
        case .cancelled:
            return "READY"
        case .error:
            return errorText?.isEmpty == false ? errorText! : "OFFLINE"
        }
    }

    public var canKeep: Bool {
        phase == .answer
    }

    public var canCopy: Bool {
        phase == .answer
    }

    public var canAdjustPage: Bool {
        phase == .answer && pageCount > 1
    }

    public var canClear: Bool {
        phase != .ready
    }

    public var canAsk: Bool {
        !phase.isBusy
    }

    public var canShorten: Bool {
        density.canShorten
    }

    public var canExpand: Bool {
        density.canExpand
    }

    public static func sample(
        phase: WatchOraclePhase = .ready,
        density: WatchOracleDensity = .balanced,
        pageIndex: Int = 0,
        pageCount: Int = 0,
        historyCount: Int = 0,
        isKept: Bool = false,
        promptText: String? = nil,
        pageText: String? = nil,
        errorText: String? = nil,
        lastUpdatedAt: Date = Date()
    ) -> WatchOracleState {
        WatchOracleState(
            phase: phase,
            density: density,
            pageIndex: pageIndex,
            pageCount: pageCount,
            historyCount: historyCount,
            isKept: isKept,
            promptText: promptText,
            pageText: pageText,
            errorText: errorText,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}
