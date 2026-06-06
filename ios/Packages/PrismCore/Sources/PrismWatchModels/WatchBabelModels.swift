import Foundation
import PrismModels

public enum WatchBabelPhase: String, CaseIterable, Sendable, Codable {
    case ready
    case listening
    case transcribing
    case translating
    case frozen
    case error

    public var displayTitle: String {
        switch self {
        case .ready:
            "READY"
        case .listening:
            "LISTENING"
        case .transcribing:
            "TRANSCRIBING"
        case .translating:
            "TRANSLATING"
        case .frozen:
            "FROZEN"
        case .error:
            "ERROR"
        }
    }
}

public enum WatchBabelPreset: String, CaseIterable, Sendable, Codable {
    case jaToEn
    case enToJa
    case frToEn
    case enToFr
    case esToEn
    case enToEs
    case deToEn
    case enToDe

    public var sourceLanguage: String {
        switch self {
        case .jaToEn:
            "ja"
        case .enToJa:
            "en"
        case .frToEn:
            "fr"
        case .enToFr:
            "en"
        case .esToEn:
            "es"
        case .enToEs:
            "en"
        case .deToEn:
            "de"
        case .enToDe:
            "en"
        }
    }

    public var targetLanguage: String {
        switch self {
        case .jaToEn:
            "en"
        case .enToJa:
            "ja"
        case .frToEn:
            "en"
        case .enToFr:
            "fr"
        case .esToEn:
            "en"
        case .enToEs:
            "es"
        case .deToEn:
            "en"
        case .enToDe:
            "de"
        }
    }

    public var displayTitle: String {
        "\(sourceLanguage.uppercased()) -> \(targetLanguage.uppercased())"
    }

    public init?(sourceLanguage: String, targetLanguage: String) {
        let normalizedSource = sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTarget = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = Self.allCases.first(where: { $0.sourceLanguage == normalizedSource && $0.targetLanguage == normalizedTarget }) else {
            return nil
        }
        self = match
    }
}

public enum WatchBabelLineKind: String, CaseIterable, Sendable, Codable {
    case raw
    case final
    case system

    public var displayTitle: String {
        switch self {
        case .raw:
            "RAW"
        case .final:
            "FINAL"
        case .system:
            "SYSTEM"
        }
    }
}

public struct WatchBabelLine: Identifiable, Equatable, Sendable, Codable {
    public var id: PrismRequestID
    public var kind: WatchBabelLineKind
    public var text: String

    public init(id: PrismRequestID = PrismRequestID(), kind: WatchBabelLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public enum WatchBabelAction: Equatable, Sendable, Codable {
    case toggleFreeze
    case swapLanguages
    case selectPreset(WatchBabelPreset)
    case clearTranscript
    case saveTranscript
    case repeatLast
}

public struct WatchBabelState: Equatable, Sendable, Codable {
    public var sourceLanguage: String
    public var targetLanguage: String
    public var phase: WatchBabelPhase
    public var audioLevel: Double
    public var lines: [WatchBabelLine]
    public var savedTranscriptCount: Int
    public var canRepeatLast: Bool
    public var lastUpdatedAt: Date

    public init(
        sourceLanguage: String = "ja",
        targetLanguage: String = "en",
        phase: WatchBabelPhase = .ready,
        audioLevel: Double = 0,
        lines: [WatchBabelLine] = [],
        savedTranscriptCount: Int = 0,
        canRepeatLast: Bool = false,
        lastUpdatedAt: Date = Date()
    ) {
        self.sourceLanguage = sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.targetLanguage = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.phase = phase
        self.audioLevel = min(max(audioLevel, 0), 1)
        self.lines = lines
        self.savedTranscriptCount = max(savedTranscriptCount, 0)
        self.canRepeatLast = canRepeatLast
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var pairTitle: String {
        "\(sourceLanguage.uppercased()) -> \(targetLanguage.uppercased())"
    }

    public var compactTitle: String {
        "\(pairTitle) • \(phase.displayTitle)"
    }

    public var statusTitle: String {
        phase.displayTitle
    }

    public var presetTitle: String {
        resolvedPreset?.displayTitle ?? "CUSTOM"
    }

    public var savedTranscriptTitle: String {
        savedTranscriptCount == 0 ? "NO SAVES" : "\(savedTranscriptCount) SAVED"
    }

    public var hasTranscript: Bool {
        lines.contains { $0.kind == .raw || $0.kind == .final }
    }

    public var primaryActionTitle: String {
        phase == .frozen ? "RESUME" : "FREEZE"
    }

    public var secondaryActionTitle: String {
        "SWAP"
    }

    public var clearActionTitle: String {
        "CLEAR"
    }

    public var saveActionTitle: String {
        "SAVE"
    }

    public var repeatActionTitle: String {
        "REPEAT"
    }

    public var isFrozen: Bool {
        phase == .frozen
    }

    public var hasHistory: Bool {
        hasTranscript || savedTranscriptCount > 0 || canRepeatLast
    }

    public var resolvedPreset: WatchBabelPreset? {
        WatchBabelPreset(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
    }

    public func displayLines(masked: Bool) -> [WatchBabelLine] {
        guard masked else {
            return lines
        }
        return lines.map { line in
            switch line.kind {
            case .raw, .final:
                WatchBabelLine(id: line.id, kind: line.kind, text: "PRIVATE")
            case .system:
                line
            }
        }
    }

    public static func sample(
        sourceLanguage: String = "ja",
        targetLanguage: String = "en",
        phase: WatchBabelPhase = .translating,
        audioLevel: Double = 0.42,
        lines: [WatchBabelLine]? = nil,
        savedTranscriptCount: Int = 1,
        canRepeatLast: Bool = true,
        lastUpdatedAt: Date = Date()
    ) -> WatchBabelState {
        WatchBabelState(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            phase: phase,
            audioLevel: audioLevel,
            lines: lines ?? [
                WatchBabelLine(kind: .system, text: "LISTENING"),
                WatchBabelLine(kind: .raw, text: "konnichiwa"),
                WatchBabelLine(kind: .final, text: "hello")
            ],
            savedTranscriptCount: savedTranscriptCount,
            canRepeatLast: canRepeatLast,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}
