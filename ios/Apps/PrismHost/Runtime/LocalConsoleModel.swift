import Foundation
import PrismRuntime

@MainActor
final class LocalConsoleModel: ObservableObject {
    @Published private(set) var chronos = ChronosEngine()
    @Published private(set) var teleprompter = TeleprompterEngine(
        script: TeleprompterEngine.importScript(
            title: "Demo Script",
            body: "Welcome to PrismOS. Keep eye contact while the Host advances concise chunks."
        )
    )
    @Published private(set) var signal = SignalStack(
        cards: LocalConsoleModel.defaultSignalCards()
    )
    @Published var developerModeEnabled = false
    @Published var retentionDays = 7
    @Published var shapeGateEnabled = false
    @Published var chronosMinutes = 5
    @Published var teleprompterDraftTitle = "Demo Script"
    @Published var teleprompterDraftBody = "Welcome to PrismOS. Keep eye contact while the Host advances concise chunks."
    @Published var signalDraftSource = "PRISM"
    @Published var signalDraftTitle = ""
    @Published var signalDraftBody = ""
    @Published var signalDraftPriority: SignalPriority = .info
    @Published private(set) var lastChronosAlert: LocalAlertRequest?
    var chronosDidChange: (@MainActor (ChronosEngine) -> Void)?
    var teleprompterDidChange: (@MainActor (TeleprompterEngine) -> Void)?
    var signalDidChange: (@MainActor (SignalStack) -> Void)?
    private var lastTeleprompterAdvance = Date()

    var sessionRows: [String] {
        [
            "Chronos: \(chronos.state.runState.rawValue)",
            "Teleprompter: \(teleprompter.script.title)",
            "Signal: \(signal.visibleCards.count) card(s)"
        ]
    }

    private func notifyChronosDidChange() {
        chronosDidChange?(chronos)
    }

    private func notifyTeleprompterDidChange() {
        teleprompterDidChange?(teleprompter)
    }

    private func notifySignalDidChange() {
        signalDidChange?(signal)
    }

    private static func defaultSignalCards() -> [SignalCard] {
        [
            SignalCard(source: "PRISM", title: "Prism", body: "Sync Done", priority: .info),
            SignalCard(source: "SYS", title: "Battery", body: "Low", priority: .critical)
        ]
    }

    func startChronos() {
        if chronos.state.runState == .setup {
            chronos.reset(totalSeconds: chronosMinutes * 60)
        }
        chronos.start(at: Date())
        notifyChronosDidChange()
    }

    func pauseChronos() {
        chronos.pause(at: Date())
        notifyChronosDidChange()
    }

    func resetChronos() {
        chronos.reset(totalSeconds: chronosMinutes * 60)
        lastChronosAlert = nil
        notifyChronosDidChange()
    }

    func toggleChronosMode() {
        chronos.toggleMode()
        lastChronosAlert = nil
        notifyChronosDidChange()
    }

    func toggleChronosPinned() {
        chronos.togglePinned()
        notifyChronosDidChange()
    }

    func tickChronos(now: Date = Date()) {
        let previousState = chronos.state
        chronos.tick(at: now)
        lastChronosAlert = chronos.alertRequest()
        if chronos.state != previousState {
            notifyChronosDidChange()
        }
    }

    func updateChronos(_ chronos: ChronosEngine) {
        guard self.chronos.state != chronos.state else { return }
        self.chronos = chronos
        lastChronosAlert = chronos.alertRequest()
        notifyChronosDidChange()
    }

    func nextScriptLine() {
        teleprompter.next()
        notifyTeleprompterDidChange()
    }

    func previousScriptLine() {
        teleprompter.previous()
        notifyTeleprompterDidChange()
    }

    func moveTeleprompterLine(by delta: Int) {
        teleprompter.moveLine(by: delta)
        notifyTeleprompterDidChange()
    }

    func toggleScriptAuto() {
        teleprompter.toggleAuto()
        lastTeleprompterAdvance = Date()
        notifyTeleprompterDidChange()
    }

    func importTeleprompterDraft() {
        let wordsPerMinute = teleprompter.script.wordsPerMinute
        teleprompter = TeleprompterEngine(
            script: TeleprompterEngine.importScript(
                title: teleprompterDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Script" : teleprompterDraftTitle,
                body: teleprompterDraftBody
            )
        )
        teleprompter.setWordsPerMinute(wordsPerMinute)
        lastTeleprompterAdvance = Date()
        notifyTeleprompterDidChange()
    }

    func bookmarkOrResetTeleprompter() {
        teleprompter.bookmarkOrReset()
        notifyTeleprompterDidChange()
    }

    func bookmarkTeleprompter() {
        teleprompter.bookmark()
        notifyTeleprompterDidChange()
    }

    func resetTeleprompterToStart() {
        teleprompter.resetToStart()
        notifyTeleprompterDidChange()
    }

    func setTeleprompterWordsPerMinute(_ wordsPerMinute: Int) {
        teleprompter.setWordsPerMinute(wordsPerMinute)
        notifyTeleprompterDidChange()
    }

    func tickTeleprompter(now: Date = Date()) {
        guard teleprompter.script.mode == .auto, !teleprompter.script.chunks.isEmpty else {
            lastTeleprompterAdvance = now
            return
        }
        let interval = max(1.0, 240.0 / Double(teleprompter.script.wordsPerMinute))
        guard now.timeIntervalSince(lastTeleprompterAdvance) >= interval else { return }
        teleprompter.next()
        lastTeleprompterAdvance = now
        notifyTeleprompterDidChange()
    }

    func updateTeleprompter(_ teleprompter: TeleprompterEngine) {
        guard self.teleprompter.script != teleprompter.script else { return }
        self.teleprompter = teleprompter
        lastTeleprompterAdvance = Date()
        notifyTeleprompterDidChange()
    }

    func dismissSignal() {
        signal.dismissCurrent()
        notifySignalDidChange()
    }

    func moveSignalSelection(by delta: Int) {
        signal.moveSelection(by: delta)
        notifySignalDidChange()
    }

    func openSignalHandoff() -> String? {
        signal.openCurrentHandoff()
    }

    func reloadSignalCards() {
        signal.reloadSession()
        notifySignalDidChange()
    }

    func toggleSignalPrivacy() {
        signal.togglePrivacy()
        notifySignalDidChange()
    }

    func addSignalDraft() {
        let title = signalDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = signalDraftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else { return }
        let source = signalDraftSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = SignalCard(
            source: source.isEmpty ? "PRISM" : source.uppercased(),
            title: title,
            body: body,
            priority: signalDraftPriority
        )
        signal.reload(cards: signal.visibleCards + [card])
        signalDraftTitle = ""
        signalDraftBody = ""
        notifySignalDidChange()
    }

    func reloadDefaultSignalCards() {
        signal.reload(cards: Self.defaultSignalCards())
        notifySignalDidChange()
    }

    func updateSignal(_ signal: SignalStack) {
        guard self.signal != signal else { return }
        self.signal = signal
        notifySignalDidChange()
    }

    func clearLocalArtifacts() {
        chronos.reset()
        lastChronosAlert = nil
        teleprompter = TeleprompterEngine()
        signal.reload(cards: [])
        notifyChronosDidChange()
        notifyTeleprompterDidChange()
        notifySignalDidChange()
    }
}
