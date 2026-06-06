import Foundation

public enum WatchVisionMode: String, CaseIterable, Sendable, Codable {
    case identify
    case readText

    public var displayTitle: String {
        switch self {
        case .identify:
            "IDENTIFY"
        case .readText:
            "READ TEXT"
        }
    }
}

public enum WatchVisionPhase: String, CaseIterable, Sendable, Codable {
    case ready
    case waitingImage
    case analyzing
    case result
    case saved
    case error

    public var displayTitle: String {
        switch self {
        case .ready:
            "READY"
        case .waitingImage:
            "CAPTURE"
        case .analyzing:
            "ANALYZING"
        case .result:
            "RESULT"
        case .saved:
            "SAVED"
        case .error:
            "ERROR"
        }
    }

    public var isBusy: Bool {
        switch self {
        case .waitingImage, .analyzing:
            true
        case .ready, .result, .saved, .error:
            false
        }
    }
}

public enum WatchVisionAction: Equatable, Sendable, Codable {
    case capture
    case retake
    case toggleMode
    case cancel
    case saveNote
    case askOracle
}

public struct WatchVisionState: Equatable, Sendable, Codable {
    public var mode: WatchVisionMode
    public var phase: WatchVisionPhase
    public var summary: String?
    public var ocrText: String?
    public var savedNoteCount: Int
    public var lastUpdatedAt: Date

    public init(
        mode: WatchVisionMode = .identify,
        phase: WatchVisionPhase = .ready,
        summary: String? = nil,
        ocrText: String? = nil,
        savedNoteCount: Int = 0,
        lastUpdatedAt: Date = Date()
    ) {
        self.mode = mode
        self.phase = phase
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ocrText = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.savedNoteCount = max(savedNoteCount, 0)
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var statusTitle: String {
        phase.displayTitle
    }

    public var modeTitle: String {
        mode.displayTitle
    }

    public var modeActionTitle: String {
        mode == .identify ? WatchVisionMode.readText.displayTitle : WatchVisionMode.identify.displayTitle
    }

    public var primaryActionTitle: String {
        phase == .ready ? "CAPTURE" : "RETAKE"
    }

    public var secondaryActionTitle: String {
        switch phase {
        case .ready, .error:
            modeActionTitle
        case .waitingImage, .analyzing:
            "CANCEL"
        case .result:
            "SAVE"
        case .saved:
            "ASK ORACLE"
        }
    }

    public var compactTitle: String {
        switch phase {
        case .ready:
            return "\(mode.displayTitle) READY"
        case .waitingImage:
            return "CAPTURE PENDING"
        case .analyzing:
            return "ANALYZING"
        case .result:
            if let summary, !summary.isEmpty {
                return summary
            }
            return "RESULT"
        case .saved:
            if let summary, !summary.isEmpty {
                return "SAVED • \(summary)"
            }
            return "SAVED"
        case .error:
            if let summary, !summary.isEmpty {
                return summary
            }
            return "ERROR"
        }
    }

    public var detailTitle: String {
        switch phase {
        case .ready:
            return mode == .identify ? "READY FOR SCENE" : "READY FOR TEXT"
        case .waitingImage:
            return "WAITING FOR IMAGE"
        case .analyzing:
            return "ANALYZING ON PHONE"
        case .result:
            if mode == .readText, let ocrText, !ocrText.isEmpty {
                return ocrText
            }
            if let summary, !summary.isEmpty {
                return summary
            }
            return "RESULT HIDDEN"
        case .saved:
            if mode == .readText, let ocrText, !ocrText.isEmpty {
                return ocrText
            }
            if let summary, !summary.isEmpty {
                return summary
            }
            return "SAVED NOTE HIDDEN"
        case .error:
            if let summary, !summary.isEmpty {
                return summary
            }
            return "TRY AGAIN"
        }
    }

    public var savedNoteTitle: String {
        savedNoteCount == 0 ? "NO SAVES" : "\(savedNoteCount) SAVED"
    }

    public var hasResult: Bool {
        phase == .result || phase == .saved
    }

    public var isBusy: Bool {
        phase.isBusy
    }

    public var canCancel: Bool {
        phase != .ready
    }

    public var canSaveNote: Bool {
        phase == .result
    }

    public var canAskOracle: Bool {
        hasResult
    }

    public var canToggleMode: Bool {
        !isBusy
    }

    public var canCapture: Bool {
        !isBusy
    }

    public static func sample(
        mode: WatchVisionMode = .identify,
        phase: WatchVisionPhase = .result,
        summary: String? = "ESP32 BOARD ONLINE",
        ocrText: String? = "PRESS THE TOP BUTTON",
        savedNoteCount: Int = 0,
        lastUpdatedAt: Date = Date()
    ) -> WatchVisionState {
        WatchVisionState(
            mode: mode,
            phase: phase,
            summary: summary,
            ocrText: ocrText,
            savedNoteCount: savedNoteCount,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}
