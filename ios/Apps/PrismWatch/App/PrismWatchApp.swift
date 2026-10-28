import SwiftUI
import WatchConnectivity
import PrismShell

@MainActor
@main
struct PrismWatchApp: App {
    @StateObject private var store = ShellWatchClient()
    var body: some Scene { WindowGroup { ShellWatchView(store: store) } }
}

@MainActor
final class ShellWatchClient: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: ShellWatchSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var reachable = false
    private let session = WCSession.default
    override init() {
        super.init()
        if WCSession.isSupported() { session.delegate = self; session.activate() }
    }
    func refresh() {
        guard reachable else { error = "Phone unreachable"; return }
        session.sendMessage(["prism.shell.refresh": true], replyHandler: { [weak self] message in
            Task { @MainActor in self?.ingest(message) }
        }, errorHandler: { [weak self] _ in Task { @MainActor in self?.error = "Phone unreachable" } })
    }
    func send(_ kind: ShellWatchCommand.Kind, actionID: String? = nil) {
        if kind == .refresh { refresh(); return }
        guard reachable, let snapshot, Date().timeIntervalSince(snapshot.updatedAt) <= 30 else { error = "Open PrismOS on your iPhone to refresh"; return }
        let command = ShellWatchCommand(snapshotVersion: snapshot.version, sessionID: snapshot.sessionID, kind: kind, actionID: actionID)
        do {
            let data = try ShellJSON.encoder().encode(command)
            session.sendMessage(["prism.shell.command": data], replyHandler: { [weak self] response in
                Task { @MainActor in self?.ingest(response) }
            }, errorHandler: { [weak self] _ in Task { @MainActor in self?.error = "Phone unreachable. No action was queued." } })
        } catch { self.error = error.localizedDescription }
    }
    private func ingest(_ message: [String: Any]) {
        if let data = message["prism.shell.snapshot"] as? Data {
            do { snapshot = try ShellJSON.decoder().decode(ShellWatchSnapshot.self, from: data); error = nil }
            catch { self.error = "Phone state could not be read" }
        } else if let error = message["error"] as? String { self.error = error }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext; let reachable = session.isReachable
        Task { @MainActor in self.reachable = reachable; self.ingest(context) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable; let context = session.receivedApplicationContext
        Task { @MainActor in self.reachable = reachable; self.ingest(context) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.ingest(applicationContext) }
    }
}

struct ShellWatchView: View {
    @ObservedObject var store: ShellWatchClient
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let stale = store.snapshot.map { context.date.timeIntervalSince($0.updatedAt) > 30 } ?? true
            let expired = store.snapshot?.expiresAt.map { $0 <= context.date } ?? false
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PrismOS").font(.headline)
                    if let state = store.snapshot {
                        Text(stale || !store.reachable ? "Phone state is stale" : state.phase).font(.caption)
                        if expired { Text("Surface expired") }
                        else if state.privateMode { Label("Private", systemImage: "eye.slash") }
                        else {
                            switch state.scene.kind {
                            case .blank: Text("Ready when you are")
                            case .timer:
                                Text(state.scene.title)
                                if let end = state.scene.timerEnd { Text(end, style: .timer).font(.title2.monospacedDigit()) }
                            case .progress: Text(state.scene.title); ProgressView(value: state.scene.progress ?? 0)
                            case .comparison, .list, .choice, .route:
                                Text(state.scene.title).bold()
                                ForEach(Array(state.scene.items.prefix(4).enumerated()), id: \.offset) { _, item in Text(item.label + " " + item.value).font(.caption) }
                            default: Text(state.scene.title).bold(); Text(state.scene.body).font(.caption)
                            }
                            if let receipt = state.receipt { Text(receipt).font(.caption) }
                        }
                        Group {
                            Button { store.send(.ask) } label: { Label("Ask", systemImage: "mic") }
                            Button { store.send(.clear) } label: { Label("Blank lens", systemImage: "xmark") }
                            Button("Next") { store.send(.next) }
                            if !state.privateMode && !expired {
                                ForEach(state.actionPreviews) { action in
                                    VStack(alignment: .leading) {
                                        Text(action.summary).bold()
                                        if let title = action.arguments.title { Text(title) }
                                        if let body = action.arguments.body { Text(body) }
                                        if let project = action.arguments.project { Text("Project: " + project) }
                                        if let topic = action.arguments.topic { Text("Topic: " + topic) }
                                        if let due = action.arguments.dueAt { Text(due.formatted()) }
                                        if let seconds = action.arguments.seconds { Text("\(seconds) seconds") }
                                        if let kind = action.arguments.sessionKind { Text(kind.rawValue) }
                                        Button("Confirm") { store.send(.confirm, actionID: action.id) }
                                    }
                                }
                                if state.canUndo { Button("Undo last action") { store.send(.undo) } }
                                Button("Dismiss") { store.send(.dismiss) }
                                Button("Snooze 5 min") { store.send(.snooze) }
                            }
                        }.disabled(stale || !store.reachable)
                        Button("Refresh") { store.refresh() }.disabled(!store.reachable)
                    } else { Text("Open PrismOS on your iPhone"); Button("Refresh") { store.refresh() }.disabled(!store.reachable) }
                    if let error = store.error { Text(error).font(.caption) }
                }
            }
        }
    }
}
