import Foundation
import PrismDraw
import PrismModels

public struct MonocleTextPolicy: Equatable, Sendable {
    public var maxCharacters: Int

    public init(maxCharacters: Int = 96) {
        self.maxCharacters = max(16, maxCharacters)
    }

    public func conciseHUDText(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        cleaned = cleaned.split(separator: " ").joined(separator: " ")
        guard cleaned.count > maxCharacters else { return cleaned }
        let index = cleaned.index(cleaned.startIndex, offsetBy: maxCharacters - 1)
        return String(cleaned[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func pages(for text: String, lineLength: Int = MonocleDisplayTextStyle.nativeColumns, linesPerPage: Int = 4) -> [String] {
        let words = conciseHUDText(text).split(separator: " ").map(String.init)
        var lines: [String] = []
        var current = ""
        for word in words {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= lineLength {
                current += " \(word)"
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }

        var pages: [String] = []
        var index = 0
        while index < lines.count {
            pages.append(lines[index..<min(index + linesPerPage, lines.count)].joined(separator: "\n"))
            index += linesPerPage
        }
        return pages.isEmpty ? [""] : pages
    }
}

public enum MonocleDisplayTextStyle {
    public static let nativeColumns = 26

    public static func system(_ text: String, limit: Int = nativeColumns) -> String {
        content(text.uppercased(), limit: limit)
    }

    public static func content(_ text: String, limit: Int = nativeColumns) -> String {
        var cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        while cleaned.count > limit || cleaned.utf8.count > PrismDrawConstants.maxTextBytes {
            guard !cleaned.isEmpty else {
                return cleaned
            }
            cleaned.removeLast()
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MonocleLensLayout {
    static let white: UInt32 = 0x00FF_FFFF
    static let gray: UInt32 = 0x00AA_AAAA
    static let dim: UInt32 = 0x0055_5555
    static let cyan: UInt32 = 0x0029_D0D0
    static let green: UInt32 = 0x001D_6914
    static let yellow: UInt32 = 0x00FF_EE33
    static let red: UInt32 = 0x00AD_2323

    static func viewport(
        appID: PrismAppID,
        title: String,
        lines: [String],
        command: String = "",
        left: String = "",
        right: String = "",
        accent: UInt32 = white
    ) -> DrawViewport {
        viewport(appID: appID.rawValue, title: title, lines: lines, command: command, left: left, right: right, accent: accent)
    }

    static func viewport(
        appID: String,
        title: String,
        lines: [String],
        command: String = "",
        left: String = "",
        right: String = "",
        accent: UInt32 = white
    ) -> DrawViewport {
        var primitives: [DrawPrimitive] = [
            text(left, x: 8, y: 4, color: dim, anchor: .topLeft, limit: 5),
            text(title, x: 320, y: 4, color: accent, anchor: .topCenter, limit: 14),
            text(right, x: 632, y: 4, color: dim, anchor: .topRight, limit: 5)
        ]
        let rows: [UInt16] = command.isEmpty ? [80, 136, 192, 248, 304, 360] : [84, 140, 196, 252, 308]
        for (line, y) in zip(lines.prefix(rows.count), rows) {
            primitives.append(text(line, x: 320, y: y, color: white, anchor: .middleCenter))
        }
        if !command.isEmpty {
            primitives.append(text(command, x: 320, y: 396, color: gray, anchor: .bottomCenter))
        }
        return DrawViewport(appID: appID, primitives: Array(primitives.prefix(PrismDrawConstants.maxPrimitiveCount)))
    }

    static func text(
        _ value: String,
        x: UInt16,
        y: UInt16,
        color: UInt32,
        anchor: DrawAnchor,
        limit: Int = MonocleDisplayTextStyle.nativeColumns
    ) -> DrawPrimitive {
        .text(MonocleDisplayTextStyle.content(value, limit: limit), x: x, y: y, color: color, anchor: anchor)
    }
}

public struct MediaRequestCommand: Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case captureAudio = "CAPTURE_AUDIO"
        case captureImage = "CAPTURE_IMAGE"
    }

    public var requestID: PrismRequestID
    public var appID: PrismAppID
    public var kind: Kind
    public var timeoutSeconds: Double
    public var sampleRate: Int?
    public var bitDepth: Int?

    public init(
        requestID: PrismRequestID = PrismRequestID(),
        appID: PrismAppID,
        kind: Kind,
        timeoutSeconds: Double,
        sampleRate: Int? = nil,
        bitDepth: Int? = nil
    ) {
        self.requestID = requestID
        self.appID = appID
        self.kind = kind
        self.timeoutSeconds = timeoutSeconds
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
    }

    public var effect: RuntimeEffect {
        switch kind {
        case .captureAudio:
            .captureAudio(appID: appID, requestID: requestID)
        case .captureImage:
            .captureImage(appID: appID, requestID: requestID)
        }
    }

    public var controlJSON: String {
        var fields: [String] = [
            #""type":"MEDIA""#,
            #""cmd":"\#(kind.rawValue)""#,
            #""app":"\#(appID.rawValue)""#
        ]
        if let sampleRate {
            fields.append(#""sample_rate":\#(sampleRate)"#)
        }
        if let bitDepth {
            fields.append(#""bit_depth":\#(bitDepth)"#)
        }
        return "{\(fields.joined(separator: ","))}"
    }
}

public enum OracleDensity: String, CaseIterable, Sendable, Codable {
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

    public var lineLength: Int {
        switch self {
        case .shorter:
            18
        case .balanced:
            22
        case .moreDetail:
            26
        }
    }

    public var linesPerPage: Int {
        switch self {
        case .shorter:
            3
        case .balanced:
            4
        case .moreDetail:
            5
        }
    }
}

public enum OracleState: Equatable, Sendable, Codable {
    case ready
    case listening(PrismRequestID)
    case asking(PrismRequestID, String)
    case answer(OracleAnswer)
    case cancelled
    case error(String)
}

public struct OracleAnswer: Identifiable, Equatable, Sendable, Codable {
    public var id: PrismRequestID
    public var prompt: String
    public var text: String
    public var source: String
    public var createdAt: Int
    public var saved: Bool

    public init(id: PrismRequestID, prompt: String, text: String, source: String, createdAt: Int, saved: Bool = false) {
        self.id = id
        self.prompt = prompt
        self.text = text
        self.source = source
        self.createdAt = createdAt
        self.saved = saved
    }
}

public struct OracleEngine: Equatable, Sendable {
    public private(set) var state: OracleState
    public private(set) var history: [OracleAnswer]
    public private(set) var currentRequestID: PrismRequestID?
    public private(set) var pageIndex: Int
    public private(set) var density: OracleDensity
    public var outputPolicy: MonocleTextPolicy

    public init(
        state: OracleState = .ready,
        history: [OracleAnswer] = [],
        density: OracleDensity = .balanced,
        outputPolicy: MonocleTextPolicy = MonocleTextPolicy()
    ) {
        self.state = state
        self.history = history
        self.currentRequestID = nil
        self.pageIndex = 0
        self.density = density
        self.outputPolicy = outputPolicy
    }

    public var currentAnswer: OracleAnswer? {
        guard case let .answer(answer) = state else { return nil }
        return answer
    }

    public var historyCount: Int {
        history.count
    }

    public var isCurrentAnswerKept: Bool {
        currentAnswer?.saved ?? false
    }

    public var currentPrompt: String? {
        switch state {
        case .ready:
            nil
        case .listening:
            "LISTENING"
        case let .asking(_, prompt):
            prompt
        case let .answer(answer):
            answer.prompt.isEmpty ? nil : answer.prompt
        case .cancelled:
            "CANCELLED"
        case let .error(code):
            code
        }
    }

    public var currentPageCount: Int {
        guard let answerText = currentAnswer?.text, !answerText.isEmpty else { return 0 }
        return pages(for: answerText).count
    }

    public var currentPageTitle: String {
        guard currentPageCount > 0 else {
            return "0/0"
        }
        return "\(min(pageIndex + 1, currentPageCount))/\(currentPageCount)"
    }

    public var currentPageText: String? {
        guard let answerText = currentAnswer?.text, !answerText.isEmpty else { return nil }
        let pageCount = currentPageCount
        guard pageCount > 0 else { return nil }
        let page = pages(for: answerText)[min(pageIndex, pageCount - 1)]
        return page
    }

    public mutating func startVoiceAsk() -> RuntimeEffect {
        let command = MediaRequestCommand(
            appID: .oracle,
            kind: .captureAudio,
            timeoutSeconds: 4,
            sampleRate: 8000,
            bitDepth: 8
        )
        currentRequestID = command.requestID
        state = .listening(command.requestID)
        pageIndex = 0
        return command.effect
    }

    public mutating func submitTypedPrompt(_ prompt: String, now: Int = Int(Date().timeIntervalSince1970)) -> RuntimeEffect? {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            state = .error("EMPTY")
            currentRequestID = nil
            pageIndex = 0
            return nil
        }
        let requestID = PrismRequestID()
        currentRequestID = requestID
        pageIndex = 0
        state = .asking(requestID, cleaned)
        return .callOracle(prompt: hudPrompt(for: cleaned), requestID: requestID)
    }

    public mutating func receiveTranscript(_ transcript: String, requestID: PrismRequestID) -> RuntimeEffect? {
        guard requestID.isCurrent(comparedTo: currentRequestID) else { return nil }
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            state = .error("???")
            currentRequestID = nil
            pageIndex = 0
            return nil
        }
        state = .asking(requestID, cleaned)
        return .callOracle(prompt: hudPrompt(for: cleaned), requestID: requestID)
    }

    public mutating func receiveAnswer(_ answer: String, requestID: PrismRequestID, source: String = "provider", now: Int = Int(Date().timeIntervalSince1970)) -> Bool {
        guard requestID.isCurrent(comparedTo: currentRequestID) else { return false }
        let prompt: String
        if case let .asking(_, activePrompt) = state {
            prompt = activePrompt
        } else {
            prompt = ""
        }
        let concise = outputPolicy.conciseHUDText(answer)
        let record = OracleAnswer(id: requestID, prompt: prompt, text: concise, source: source, createdAt: now)
        history.insert(record, at: 0)
        state = .answer(record)
        currentRequestID = nil
        pageIndex = 0
        return true
    }

    public mutating func cancel() {
        currentRequestID = nil
        state = .cancelled
        pageIndex = 0
    }

    public mutating func clear() {
        currentRequestID = nil
        pageIndex = 0
        switch state {
        case .ready:
            break
        case .listening, .asking:
            state = .cancelled
        case .answer, .cancelled, .error:
            state = .ready
        }
    }

    public mutating func fail(_ code: String) {
        currentRequestID = nil
        state = .error(code)
        pageIndex = 0
    }

    public mutating func toggleKeep() -> Bool {
        guard var answer = currentAnswer else { return false }
        answer.saved.toggle()
        history = history.map { record in
            guard record.id == answer.id else { return record }
            var updated = record
            updated.saved = answer.saved
            return updated
        }
        state = .answer(answer)
        return answer.saved
    }

    public mutating func copyAnswer() -> RuntimeEffect? {
        guard let answer = currentAnswer else { return nil }
        return .copyToClipboard(text: answer.text)
    }

    public mutating func nextPage() {
        adjustPage(by: 1, allowDensityChangeWhenNotAnswer: false)
    }

    public mutating func previousPage() {
        adjustPage(by: -1, allowDensityChangeWhenNotAnswer: false)
    }

    public mutating func adjustPage(by delta: Int, allowDensityChangeWhenNotAnswer: Bool = true) {
        guard delta != 0 else { return }
        guard let answer = currentAnswer else {
            guard allowDensityChangeWhenNotAnswer else { return }
            adjustDensity(by: delta)
            return
        }

        let pages = pages(for: answer.text)
        guard !pages.isEmpty else { return }
        pageIndex = min(max(pageIndex + delta, 0), pages.count - 1)
    }

    public mutating func shorter() {
        setDensity(.shorter)
    }

    public mutating func moreDetail() {
        setDensity(.moreDetail)
    }

    public mutating func setDensity(_ density: OracleDensity) {
        self.density = density
        pageIndex = 0
    }

    public mutating func followUp() -> RuntimeEffect? {
        guard let answer = currentAnswer else { return nil }
        let context = answer.text.isEmpty ? answer.prompt : answer.text
        let prompt = context.isEmpty ? "Give the next useful follow-up or caution." : "Give the next useful follow-up or caution about: \(context)"
        let requestID = PrismRequestID()
        currentRequestID = requestID
        pageIndex = 0
        state = .asking(requestID, prompt)
        return .callOracle(prompt: hudPrompt(for: prompt), requestID: requestID)
    }

    public func render() -> DrawViewport {
        let lines: [String]
        let command: String
        let right: String
        switch state {
        case .ready:
            lines = ["ASK READY", "R VOICE", "HOLD R PROMPT"]
            command = "R VOICE"
            right = "HOST"
        case .listening:
            lines = ["LISTENING", "SPEAK NOW", "MIC |||"]
            command = "L CANCEL"
            right = "MIC"
        case .asking:
            lines = ["THINKING", "HOST"]
            command = "L CANCEL"
            right = "WAIT"
        case let .answer(answer):
            let pages = pages(for: answer.text)
            let page = pages[min(pageIndex, pages.count - 1)]
            lines = [answer.saved ? "KEPT" : "ANSWER"] + page.split(separator: "\n").map(String.init)
            command = pageIndex < pages.count - 1 ? "L BACK   R NEXT" : "R KEEP  HOLD R TIP"
            right = "\(pageIndex + 1)/\(pages.count)"
        case .cancelled:
            lines = ["CANCELLED", "R VOICE"]
            command = "R VOICE"
            right = "HOST"
        case let .error(code):
            lines = [code, "R VOICE"]
            command = "R VOICE"
            right = "ERR"
        }
        return MonocleLensLayout.viewport(appID: .oracle, title: "ORACLE", lines: lines, command: command, right: right, accent: MonocleLensLayout.cyan)
    }

    private func hudPrompt(for prompt: String) -> String {
        "Answer for a Monocle HUD in under 25 words. Front-load facts. No Markdown.\n\(prompt)"
    }

    private mutating func adjustDensity(by delta: Int) {
        guard delta != 0 else { return }
        let nextDensity: OracleDensity
        if delta > 0 {
            nextDensity = .moreDetail
        } else {
            nextDensity = .shorter
        }
        density = nextDensity
        pageIndex = 0
    }

    private func pages(for text: String) -> [String] {
        outputPolicy.pages(
            for: text,
            lineLength: density.lineLength,
            linesPerPage: density.linesPerPage
        )
    }
}

public enum VisionMode: String, CaseIterable, Sendable, Codable {
    case identify
    case readText

    public var displayName: String {
        switch self {
        case .identify:
            "Identify"
        case .readText:
            "Read Text"
        }
    }
}

public enum VisionState: Equatable, Sendable, Codable {
    case ready
    case waitingImage(PrismRequestID)
    case analyzing(PrismRequestID, Int)
    case result(VisionResult)
    case saved(VisionResult)
    case error(String)
}

public struct VisionResult: Identifiable, Equatable, Sendable, Codable {
    public var id: PrismRequestID
    public var mode: VisionMode
    public var summary: String
    public var ocrText: String
    public var captureBytes: Int
    public var saved: Bool

    public init(id: PrismRequestID, mode: VisionMode, summary: String, ocrText: String = "", captureBytes: Int, saved: Bool = false) {
        self.id = id
        self.mode = mode
        self.summary = summary
        self.ocrText = ocrText
        self.captureBytes = captureBytes
        self.saved = saved
    }
}

public struct VisionEngine: Equatable, Sendable {
    public private(set) var mode: VisionMode
    public private(set) var state: VisionState
    public private(set) var notes: [VisionResult]
    public private(set) var currentRequestID: PrismRequestID?
    public var maxImageBytes: Int
    public var outputPolicy: MonocleTextPolicy

    public init(mode: VisionMode = .identify, maxImageBytes: Int = 512_000, outputPolicy: MonocleTextPolicy = MonocleTextPolicy()) {
        self.mode = mode
        self.state = .ready
        self.notes = []
        self.currentRequestID = nil
        self.maxImageBytes = maxImageBytes
        self.outputPolicy = outputPolicy
    }

    public mutating func toggleMode() {
        guard !isBusy else { return }
        mode = mode == .identify ? .readText : .identify
    }

    public var isBusy: Bool {
        switch state {
        case .waitingImage, .analyzing:
            true
        case .ready, .result, .saved, .error:
            false
        }
    }

    public var hasSavedResult: Bool {
        if case .saved = state {
            return true
        }
        return false
    }

    public mutating func capture() -> RuntimeEffect {
        let command = MediaRequestCommand(appID: .vision, kind: .captureImage, timeoutSeconds: 6)
        currentRequestID = command.requestID
        state = .waitingImage(command.requestID)
        return command.effect
    }

    public mutating func cancel() -> Bool {
        guard currentRequestID != nil || state != .ready else {
            return false
        }
        currentRequestID = nil
        state = .ready
        return true
    }

    public mutating func receiveImage(_ data: Data, requestID: PrismRequestID) -> Bool {
        guard requestID.isCurrent(comparedTo: currentRequestID) else { return false }
        guard data.count <= maxImageBytes else {
            state = .error("TOO BIG")
            currentRequestID = nil
            return false
        }
        guard data.count >= 4, data.first == 0xFF, data.dropFirst().first == 0xD8 else {
            state = .error("BAD JPEG")
            currentRequestID = nil
            return false
        }
        state = .analyzing(requestID, data.count)
        return true
    }

    public mutating func receiveAnalysis(summary: String, ocrText: String = "", requestID: PrismRequestID) -> Bool {
        guard requestID.isCurrent(comparedTo: currentRequestID) else { return false }
        let captureBytes: Int
        if case let .analyzing(_, bytes) = state {
            captureBytes = bytes
        } else {
            captureBytes = 0
        }
        let result = VisionResult(
            id: requestID,
            mode: mode,
            summary: outputPolicy.conciseHUDText(summary),
            ocrText: outputPolicy.conciseHUDText(ocrText),
            captureBytes: captureBytes
        )
        state = .result(result)
        currentRequestID = nil
        return true
    }

    public mutating func timeout() {
        currentRequestID = nil
        state = .error("NO IMAGE")
    }

    public mutating func fail(_ code: String) {
        currentRequestID = nil
        state = .error(code)
    }

    public mutating func saveCurrentResult() -> RuntimeEffect? {
        guard case var .result(result) = state else { return nil }
        result.saved = true
        notes.insert(result, at: 0)
        state = .saved(result)
        return .saveVisionNote(text: result.summary, requestID: result.id)
    }

    public func oracleFollowUp() -> RuntimeEffect? {
        guard let result = currentResult else { return nil }
        return .callOracle(prompt: "Give more context for this visual result: \(result.summary)", requestID: PrismRequestID())
    }

    public func copyOCRText() -> RuntimeEffect? {
        guard let result = currentResult, result.mode == .readText, !result.ocrText.isEmpty else { return nil }
        return .copyToClipboard(text: result.ocrText)
    }

    private var currentResult: VisionResult? {
        switch state {
        case let .result(result), let .saved(result):
            return result
        case .ready, .waitingImage, .analyzing, .error:
            return nil
        }
    }

    public func render() -> DrawViewport {
        let lines: [String]
        let command: String
        let right: String
        switch state {
        case .ready:
            lines = [mode.displayName.uppercased(), "ALIGN TARGET", "R CAPTURE"]
            command = "L MODE   R CAPTURE"
            right = "READY"
        case .waitingImage:
            lines = ["WAIT IMAGE", "MONOCLE CAMERA"]
            command = "L CANCEL"
            right = "WAIT"
        case .analyzing:
            lines = ["ANALYZING", "VISION MODEL"]
            command = "L CANCEL"
            right = "AI"
        case let .result(result):
            lines = ["RESULT"] + outputPolicy.pages(for: result.summary, lineLength: 24, linesPerPage: 4)[0].split(separator: "\n").map(String.init)
            command = "L RETAKE   R ORACLE"
            right = result.mode == .readText ? "OCR" : "ID"
        case .saved:
            lines = ["SAVED", "OPEN PHONE"]
            command = "L RETAKE"
            right = "SAVE"
        case let .error(code):
            lines = [code, "R CAPTURE"]
            command = "L MODE   R CAPTURE"
            right = "ERR"
        }
        return MonocleLensLayout.viewport(appID: .vision, title: "VISION", lines: lines, command: command, right: right, accent: MonocleLensLayout.green)
    }
}

public enum BabelLineKind: String, Sendable, Codable {
    case raw
    case final
    case system
}

public struct BabelLine: Identifiable, Equatable, Sendable, Codable {
    public var id: PrismRequestID
    public var kind: BabelLineKind
    public var text: String

    public init(id: PrismRequestID = PrismRequestID(), kind: BabelLineKind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public struct BabelEngine: Equatable, Sendable {
    public private(set) var sourceLanguage: String
    public private(set) var targetLanguage: String
    public private(set) var lines: [BabelLine]
    public private(set) var savedTranscripts: [String]
    public private(set) var currentRequestID: PrismRequestID?
    public private(set) var frozen: Bool
    public private(set) var lastInputText: String?
    public var outputPolicy: MonocleTextPolicy

    public init(sourceLanguage: String = "ja", targetLanguage: String = "en", outputPolicy: MonocleTextPolicy = MonocleTextPolicy()) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.lines = []
        self.savedTranscripts = []
        self.currentRequestID = nil
        self.frozen = false
        self.lastInputText = nil
        self.outputPolicy = outputPolicy
    }

    public mutating func captureAudio() -> RuntimeEffect? {
        guard currentRequestID == nil else {
            append(.system, "BUSY DROP")
            return nil
        }
        let command = MediaRequestCommand(
            appID: .babel,
            kind: .captureAudio,
            timeoutSeconds: 5,
            sampleRate: 8000,
            bitDepth: 8
        )
        currentRequestID = command.requestID
        append(.system, "LISTENING")
        return command.effect
    }

    public mutating func translateHostText(_ text: String) -> RuntimeEffect? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            append(.system, "EMPTY")
            return nil
        }
        guard currentRequestID == nil else {
            append(.system, "BUSY DROP")
            return nil
        }
        let requestID = PrismRequestID()
        currentRequestID = requestID
        lastInputText = cleaned
        append(.raw, cleaned)
        return .translateText(text: cleaned, from: sourceLanguage, to: targetLanguage, requestID: requestID)
    }

    public mutating func receiveTranscript(_ transcript: String, requestID: PrismRequestID) -> RuntimeEffect? {
        guard requestID.isCurrent(comparedTo: currentRequestID) else { return nil }
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            append(.system, "NO SPEECH")
            currentRequestID = nil
            return nil
        }
        lastInputText = cleaned
        append(.raw, cleaned)
        return .translateText(text: cleaned, from: sourceLanguage, to: targetLanguage, requestID: requestID)
    }

    public mutating func receiveTranslation(_ translation: String, requestID: PrismRequestID) -> Bool {
        guard requestID.isCurrent(comparedTo: currentRequestID) else { return false }
        append(.final, outputPolicy.conciseHUDText(translation))
        currentRequestID = nil
        return true
    }

    public mutating func toggleFreeze() {
        frozen.toggle()
        append(.system, frozen ? "FROZEN" : "RESUMED")
    }

    public mutating func swapLanguages() {
        swap(&sourceLanguage, &targetLanguage)
        append(.system, "\(sourceLanguage.uppercased())->\(targetLanguage.uppercased())")
    }

    public mutating func setLanguages(source: String, target: String) {
        let nextSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextSource.isEmpty, !nextTarget.isEmpty else {
            append(.system, "LANG REQUIRED")
            return
        }
        sourceLanguage = String(nextSource.prefix(8)).lowercased()
        targetLanguage = String(nextTarget.prefix(8)).lowercased()
        append(.system, "\(sourceLanguage.uppercased())->\(targetLanguage.uppercased())")
    }

    public mutating func saveAndClear() {
        let transcript = transcriptText()
        if !transcript.isEmpty {
            savedTranscripts.insert(transcript, at: 0)
        }
        lines = [BabelLine(kind: .system, text: "SAVED")]
        currentRequestID = nil
    }

    @discardableResult
    public mutating func saveTranscript() -> Bool {
        let transcript = transcriptText()
        guard !transcript.isEmpty else {
            append(.system, "EMPTY")
            return false
        }
        savedTranscripts.insert(transcript, at: 0)
        append(.system, "SAVED")
        return true
    }

    @discardableResult
    public mutating func clearTranscript() -> Bool {
        guard !lines.isEmpty else {
            append(.system, "CLEARED")
            currentRequestID = nil
            return false
        }
        lines = [BabelLine(kind: .system, text: "CLEARED")]
        currentRequestID = nil
        return true
    }

    public mutating func repeatLast() -> RuntimeEffect? {
        guard currentRequestID == nil else {
            append(.system, "BUSY DROP")
            return nil
        }

        let transcript = lastInputText ?? savedTranscripts.first
        guard let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            append(.system, "NO HISTORY")
            return nil
        }

        let requestID = PrismRequestID()
        currentRequestID = requestID
        append(.system, "REPEAT LAST")
        append(.raw, transcript)
        return .translateText(text: transcript, from: sourceLanguage, to: targetLanguage, requestID: requestID)
    }

    public mutating func fail(_ code: String) {
        append(.system, code)
        currentRequestID = nil
    }

    public func render() -> DrawViewport {
        let visible = frozen ? Array(lines.suffix(3)) : Array(lines.suffix(4))
        let status = frozen ? "FROZEN" : (currentRequestID == nil ? "READY" : "WAIT")
        var lineText = [status, "\(sourceLanguage.uppercased())->\(targetLanguage.uppercased())"]
        if visible.isEmpty {
            lineText.append("R LISTEN")
        } else {
            lineText.append(contentsOf: visible.map { line in
                switch line.kind {
                case .raw:
                    "IN \(line.text)"
                case .final:
                    "OUT \(line.text)"
                case .system:
                    "- \(line.text)"
                }
            })
        }
        let command = frozen ? "L RESUME   R LISTEN" : "L FREEZE   R LISTEN"
        return MonocleLensLayout.viewport(appID: .babel, title: "BABEL", lines: lineText, command: command, right: String(targetLanguage.uppercased().prefix(5)), accent: MonocleLensLayout.cyan)
    }

    private mutating func append(_ kind: BabelLineKind, _ text: String) {
        lines.append(BabelLine(kind: kind, text: outputPolicy.conciseHUDText(text)))
        if lines.count > 24 {
            lines.removeFirst(lines.count - 24)
        }
    }

    private func transcriptText() -> String {
        lines
            .filter { $0.kind != .system }
            .map(\.text)
            .joined(separator: "\n")
    }
}

private enum ProviderAppRenderer {
    static func viewport(appID: PrismAppID, lines: [String]) -> DrawViewport {
        MonocleLensLayout.viewport(appID: appID, title: appID.rawValue.uppercased(), lines: lines, command: "LONG L EXIT")
    }
}
