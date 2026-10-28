import Foundation
import PrismDraw

/// The only owner of lens coordinates. No model-authored drawing instructions enter here.
public enum PrismSceneRenderer {
    public static func wrap(_ text: String, columns: Int = 24, byteLimit: Int = 32) -> [String] {
        var result: [String] = []
        for paragraph in text.components(separatedBy: .newlines) {
            var line = ""
            for word in paragraph.split(whereSeparator: { $0.isWhitespace }) {
                let token = String(word)
                if !line.isEmpty && line.count + 1 + token.count <= columns && (line + " " + token).utf8.count <= byteLimit {
                    line += " " + token; continue
                }
                if !line.isEmpty { result.append(line); line = "" }
                for char in token {
                    if line.count >= columns || (line + String(char)).utf8.count > byteLimit {
                        if !line.isEmpty { result.append(line) }; line = ""
                    }
                    // A single extended grapheme may itself exceed the wire byte limit.
                    if String(char).utf8.count > byteLimit { result.append("?") } else { line.append(char) }
                }
            }
            if !line.isEmpty { result.append(line) }
        }
        return result
    }
    public static func contentRows(_ scene: LensScene, now: Date) -> [String] {
        switch scene.kind {
        case .blank: return []
        case .activity: return wrap(scene.body)
        case .fact, .alert, .confirmation: return wrap(scene.body) + scene.items.flatMap { wrap($0.label + ($0.value.isEmpty ? "" : ": " + $0.value)) }
        case .list: return wrap(scene.body) + scene.items.enumerated().flatMap { wrap("\($0.offset + 1). \($0.element.label) \($0.element.value)") }
        case .comparison: return wrap(scene.body) + scene.items.flatMap { wrap($0.label.uppercased()) + wrap($0.value) }
        case .choice: return wrap(scene.body) + scene.items.enumerated().flatMap { wrap("\($0.offset + 1). \($0.element.label)") + wrap($0.element.value) }
        case .progress:
            let value = Int((scene.progress ?? 0) * 100)
            let filled = value / 10
            return ["[" + String(repeating: "=", count: filled) + String(repeating: " ", count: 10 - filled) + "] \(value)%"] + wrap(scene.body)
        case .caption: return wrap(scene.body) // complete caption paging; phone retains all turns
        case .timer:
            let seconds = max(0, Int((scene.timerEnd ?? now).timeIntervalSince(now).rounded(.up)))
            return [String(format: "%02d:%02d", seconds / 60, seconds % 60)] + wrap(scene.body)
        case .route: return scene.items.flatMap { wrap($0.label) + wrap($0.value) } + wrap(scene.body)
        }
    }
    public static func pages(_ scene: LensScene, now: Date = Date(), stale: Bool = false) -> [DrawViewport] {
        guard scene.kind != .blank else { return [DrawViewport(appID: "prism", primitives: [])] }
        let title = wrap(stale ? "OFFLINE / STALE" : scene.title).first ?? scene.kind.rawValue.uppercased()
        let rows = contentRows(scene, now: now)
        let pageCount = max(1, (rows.count + 3) / 4)
        return (0..<pageCount).map { page in
            var primitives: [DrawPrimitive] = [.text(title, x: 32, y: 24, color: 0x00AAFFFF, anchor: .topLeft)]
            for (index, row) in rows.dropFirst(page * 4).prefix(4).enumerated() {
                primitives.append(.text(row, x: 32, y: UInt16(96 + index * 56), color: 0x00FFFFFF, anchor: .topLeft))
            }
            let footer = pageCount > 1 ? "\(page + 1)/\(pageCount)  R NEXT" : (scene.kind == .choice ? "Choose on phone / Watch" : "")
            if !footer.isEmpty { primitives.append(.text(String(footer.prefix(24)), x: 32, y: 344, color: 0x00AAAAAA, anchor: .topLeft)) }
            return DrawViewport(appID: "prism", primitives: primitives)
        }
    }
}
public struct PhoneProjection: Equatable, Sendable {
    public var scene: LensScene
    public var completeAnswer: String
    public var actions: [ProposedAction]
    public init(turn: AssistantTurn, privateMode: Bool) {
        scene = privateMode ? .blank : turn.lensScene
        completeAnswer = turn.canonicalAnswer
        actions = turn.proposedActions
    }
}
public struct ShellWatchSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: Date
    public var expiresAt: Date?
    public var sessionID: UUID
    public var phase: String
    public var connected: Bool
    public var privateMode: Bool
    public var scene: LensScene
    public var actionTitles: [String]
    public var actionPreviews: [ProposedAction]
    public var actionIDs: [String]
    public var receipt: String?
    public var canUndo: Bool
    public init(version: Int, updatedAt: Date, sessionID: UUID, phase: String, connected: Bool, privateMode: Bool,
                scene: LensScene, actions: [ProposedAction], receipt: String?, canUndo: Bool, expiresAt: Date? = nil) {
        self.version = version; self.updatedAt = updatedAt; self.expiresAt = expiresAt; self.sessionID = sessionID; self.phase = phase
        self.connected = connected; self.privateMode = privateMode
        var wristScene = scene
        wristScene.title = String(scene.title.prefix(160)); wristScene.body = String(scene.body.prefix(1024))
        wristScene.items = scene.items.prefix(4).map { .init(String($0.label.prefix(128)), String($0.value.prefix(256)), actionID: $0.actionID) }
        self.scene = privateMode ? .blank : wristScene
        actionPreviews = privateMode ? [] : actions.filter { ((try? ShellJSON.encoder().encode($0).count) ?? Int.max) <= 4096 }
        actionTitles = actionPreviews.map(\.summary); actionIDs = actionPreviews.map(\.id)
        self.receipt = privateMode ? nil : receipt; self.canUndo = !privateMode && canUndo
    }
}
public struct ShellWatchCommand: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case ask, clear, next, confirm, undo, dismiss, snooze, refresh }
    public var id: UUID
    public var snapshotVersion: Int
    public var sessionID: UUID
    public var createdAt: Date
    public var kind: Kind
    public var actionID: String?
    public init(id: UUID = UUID(), snapshotVersion: Int, sessionID: UUID, createdAt: Date = Date(), kind: Kind, actionID: String? = nil) {
        self.id = id; self.snapshotVersion = snapshotVersion; self.sessionID = sessionID; self.createdAt = createdAt
        self.kind = kind; self.actionID = actionID
    }
}
