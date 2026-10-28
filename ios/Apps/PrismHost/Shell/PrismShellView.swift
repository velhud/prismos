import SwiftUI
import PrismShell
import PrismDraw

struct PrismShellView: View {
    @EnvironmentObject private var host: ShellHostModel
    var body: some View {
        Group {
            if let error = host.startupError { ContentUnavailableView("Library unavailable", systemImage: "lock.doc", description: Text(error)) }
            else {
                TabView {
                    NavigationStack { ShellHomeView() }.tabItem { Label("Home", systemImage: "sparkles") }
                    NavigationStack { ShellLensView() }.tabItem { Label("Lens", systemImage: "eyeglasses") }
                    NavigationStack { ShellLibraryView() }.tabItem { Label("Library", systemImage: "books.vertical") }
                    NavigationStack { ShellSettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
                }
            }
        }
        .tint(PrismTheme.gold).preferredColorScheme(.dark)
        .task { await host.refreshSources() }
    }
}
private struct ShellHomeView: View {
    @EnvironmentObject private var host: ShellHostModel
    @State private var input = ""
    @State private var project = ""
    @FocusState private var inputFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(host.link.status, systemImage: host.engine?.connected == true ? "checkmark.circle" : "antenna.radiowaves.left.and.right")
                if let engine = host.engine {
                    Text(engine.phase).font(.headline).accessibilityIdentifier("assistant.phase")
                    if host.voice.state != "Silent" { Text(host.voice.state).font(.caption) }
                    HStack {
                        Text(engine.archive.session.kind.rawValue.capitalized)
                        if let name = engine.archive.session.project { Text(name).foregroundStyle(.secondary) }
                        Spacer()
                        Button("New session") { host.perform { try engine.newSession(project: project.isEmpty ? nil : project) } }
                    }
                    TextField("Project (optional)", text: $project).textFieldStyle(.roundedBorder)
                    TextField("Ask Prism or capture a thought", text: $input, axis: .vertical)
                        .lineLimit(3...8).textFieldStyle(.roundedBorder).focused($inputFocused).accessibilityIdentifier("assistant.input")
                    HStack {
                        Button("Ask", systemImage: "arrow.up.circle.fill") { inputFocused = false; engine.submit(input); input = "" }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("assistant.ask")
                        Button("Speak", systemImage: "mic") { engine.beginListening() }.buttonStyle(.bordered)
                        Button("Blank", systemImage: "xmark") { engine.clear() }.buttonStyle(.bordered).accessibilityIdentifier("assistant.blank")
                    }
                    if let timer = engine.archive.timer {
                        HStack {
                            Text(timer.title)
                            Spacer()
                            if timer.completed { Text("Finished") } else { Text(timer.end, style: .timer) }
                        }
                    }
                    if let candidate = engine.activeCandidate {
                        Text("\(candidate.source.capitalized) · \(candidate.eventTime.formatted(date: .omitted, time: .shortened))").font(.caption)
                        Text(engine.archive.candidateHistory[candidate.id]?.interpretation ?? candidate.reason).font(.caption).foregroundStyle(.secondary)
                        if let expires = engine.expiresAt { Text("Until " + expires.formatted(date: .omitted, time: .shortened)).font(.caption) }
                        HStack {
                            Button("Dismiss") { host.perform { try engine.dismissCandidate() } }
                            Button("Snooze 5 min") { host.perform { try engine.dismissCandidate(snoozeSeconds: 300) } }
                        }
                    }
                    if let turn = engine.currentRecord?.turn {
                        NativeExperienceCard(scene: engine.scene)
                        Text(turn.canonicalAnswer).textSelection(.enabled).accessibilityIdentifier("assistant.completeAnswer")
                        if let question = turn.clarification { Text(question).font(.headline) }
                        ForEach(engine.actions) { action in
                            ActionPreview(action: action) {
                                let revision = engine.archive.revision
                                host.perform { try await engine.confirm(actionID: action.id, revision: revision) }
                            }
                        }
                    } else if engine.scene.kind != .blank { NativeExperienceCard(scene: engine.scene) }
                    if let receipt = engine.lastReceipt {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(receipt.summary).font(.headline)
                            if receipt.status == .succeeded && receipt.undoToken != nil {
                                Button("Undo", systemImage: "arrow.uturn.backward") { host.perform { try await engine.undo(receiptID: receipt.id) } }.accessibilityIdentifier("assistant.undo")
                            }
                            if [.uncertain, .undoUncertain].contains(receipt.status) {
                                Button("Check action outcome") { host.perform { try await engine.reconcile(receiptID: receipt.id) } }
                            }
                        }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let error = engine.lastError { Text(error).foregroundStyle(.secondary).accessibilityIdentifier("assistant.error") }
                }
            }.padding()
        }.navigationTitle("PrismOS")
    }
}
private struct ActionPreview: View {
    var action: ProposedAction
    var confirm: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action.summary).font(.headline)
            if let title = action.arguments.title { Text(title) }
            if let body = action.arguments.body { Text(body).textSelection(.enabled) }
            if let query = action.arguments.query { Text(query) }
            if let project = action.arguments.project { Text("Project: \(project)") }
            if let topic = action.arguments.topic { Text("Topic: \(topic)") }
            if let date = action.arguments.dueAt { Text(date.formatted(date: .complete, time: .shortened)) }
            if let seconds = action.arguments.seconds { Text("\(seconds) seconds") }
            if let session = action.arguments.sessionKind { Text("Session: \(session.rawValue)") }
            Button("Confirm", systemImage: "checkmark.circle", action: confirm).buttonStyle(.borderedProminent)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
struct NativeExperienceCard: View {
    var scene: LensScene
    var body: some View {
        if scene.kind != .blank {
            VStack(alignment: .leading, spacing: 12) {
                Label(scene.title, systemImage: symbol).font(.headline)
                switch scene.kind {
                case .comparison:
                    ForEach(Array(scene.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top) { Text(item.label).bold().frame(maxWidth: .infinity, alignment: .leading); Text(item.value).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    Text(scene.body)
                case .progress:
                    ProgressView(value: scene.progress ?? 0); Text(scene.body)
                case .timer:
                    if let end = scene.timerEnd { Text(end, style: .timer).font(.largeTitle.monospacedDigit()) }; Text(scene.body)
                case .list, .choice, .route:
                    Text(scene.body)
                    ForEach(Array(scene.items.enumerated()), id: \.offset) { index, item in
                        Label { VStack(alignment: .leading) { Text(item.label).bold(); Text(item.value) } } icon: { Text("\(index + 1)") }
                    }
                case .caption: Text(scene.body).font(.title3).textSelection(.enabled)
                case .activity: ProgressView(); Text(scene.body)
                default: Text(scene.body).textSelection(.enabled)
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private var symbol: String {
        switch scene.kind {
        case .alert: return "exclamationmark.circle"
        case .confirmation: return "checkmark.circle"
        case .timer: return "timer"
        case .comparison: return "arrow.left.arrow.right"
        case .caption: return "captions.bubble"
        case .route: return "arrow.turn.up.right"
        default: return "sparkles"
        }
    }
}
private struct ShellLensView: View {
    @EnvironmentObject private var host: ShellHostModel
    var body: some View {
        ScrollView {
            if let e = host.engine {
                VStack(alignment: .leading, spacing: 16) {
                    MonocleDisplayPreview(viewport: e.viewport)
                    Text(e.connected ? "Connected" : "Phone preview · Monocle offline")
                    if let end = e.expiresAt { Text("Expires \(end.formatted(date: .omitted, time: .standard))") }
                    if let ack = host.link.lastDisplayAcknowledgedAt { Text("Display acknowledged \(ack.formatted(date: .omitted, time: .standard))").font(.caption) }
                    HStack {
                        Button("Clear") { e.clear() }
                        Button(e.pinned ? "Unpin" : "Pin") { e.togglePin() }
                        Button("Next page") { e.nextPage() }
                    }.buttonStyle(.bordered)
                    if let candidate = e.activeCandidate {
                        Text("Source: \(candidate.source)\n\(candidate.reason)")
                        if let interpretation = e.archive.candidateHistory[candidate.id]?.interpretation { Text(interpretation) }
                    }
                }.padding()
            }
        }.navigationTitle("Lens")
    }
}
private struct ShellLibraryView: View {
    @EnvironmentObject private var host: ShellHostModel
    @State private var query = ""
    var body: some View {
        List {
            if let engine = host.engine {
                Section("Conversations") {
                    ForEach(engine.archive.conversations.reversed().filter { query.isEmpty || ($0.userText + ($0.turn?.canonicalAnswer ?? "")).localizedCaseInsensitiveContains(query) }) { record in
                        NavigationLink(String(record.userText.prefix(100))) {
                            ScrollView { VStack(alignment: .leading, spacing: 20) {
                                Text(record.userText).font(.headline)
                                Text(record.turn?.canonicalAnswer ?? record.status)
                                if let spoken = record.turn?.spokenResponse { Text("Spoken response").font(.caption); Text(spoken) }
                                Text(record.provenance.createdAt.formatted()).font(.caption)
                                ShareLink(item: record.userText + "\n\n" + (record.turn?.canonicalAnswer ?? record.status))
                            }.textSelection(.enabled).padding() }.navigationTitle("Conversation")
                        }
                    }
                }
                Section("Action receipts") {
                    ForEach(engine.archive.receipts.reversed().filter { query.isEmpty || $0.summary.localizedCaseInsensitiveContains(query) }) { receipt in
                        NavigationLink { ReceiptDetailView(receiptID: receipt.id) } label: {
                            VStack(alignment: .leading) { Text(receipt.summary); Text(receipt.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("Artifacts") {
                    ForEach(engine.archive.search(query).filter { $0.kind != .receipt }) { artifact in
                        NavigationLink {
                            ArtifactDetailView(artifact: artifact)
                        } label: { VStack(alignment: .leading) {
                            Text(artifact.title); Text([artifact.kind.rawValue,artifact.project,artifact.topic].compactMap{$0}.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        } }
                    }
                }
            }
        }.searchable(text: $query).navigationTitle("Library").accessibilityIdentifier("library.list")
    }
}
private struct ReceiptDetailView: View {
    @EnvironmentObject private var host: ShellHostModel
    let receiptID: String
    var body: some View {
        ScrollView {
            if let engine = host.engine, let receipt = engine.archive.receipts.first(where: { $0.id == receiptID }) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(receipt.summary).font(.headline)
                    Text(receipt.status.rawValue.capitalized)
                    if let title = receipt.action.arguments.title { Text(title) }
                    if let body = receipt.action.arguments.body { Text(body).textSelection(.enabled) }
                    if let project = receipt.action.arguments.project { Text("Project: " + project) }
                    if let topic = receipt.action.arguments.topic { Text("Topic: " + topic) }
                    if let due = receipt.action.arguments.dueAt { Text(due.formatted()) }
                    Text(receipt.createdAt.formatted()).font(.caption)
                    if receipt.status == .succeeded && receipt.undoToken != nil {
                        Button("Undo action") { host.perform { try await engine.undo(receiptID: receipt.id) } }
                    }
                    if [.uncertain, .undoUncertain].contains(receipt.status) {
                        Button("Check outcome") { host.perform { try await engine.reconcile(receiptID: receipt.id) } }
                    }
                    ShareLink(item: receipt.summary)
                }.padding()
            }
        }.navigationTitle("Action receipt")
    }
}
private struct ArtifactDetailView: View {
    @EnvironmentObject private var host: ShellHostModel
    @Environment(\.dismiss) private var dismiss
    let artifact: LibraryArtifact
    private var displayed: LibraryArtifact { host.engine?.archive.artifacts.first { $0.id == artifact.id } ?? artifact }
    @State private var editBody = ""
    @State private var editTitle = ""
    @State private var editing = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text(displayed.title).font(.headline); Text(displayed.body).textSelection(.enabled)
            Text("Source: \(displayed.provenance.source)")
            if let candidate = displayed.candidate {
                Text(candidate.reason)
                Text("Event: " + candidate.eventTime.formatted())
                Text("Observed: " + candidate.observedAt.formatted()).font(.caption)
                Text("Expires: " + candidate.expiresAt.formatted()).font(.caption)
            }
            if let provider = displayed.provenance.provider { Text("Processed by \(provider)") }
            Text(displayed.provenance.createdAt.formatted()).font(.caption)
            ShareLink(item: displayed.body).accessibilityIdentifier("artifact.share")
            if displayed.kind == .note {
                Button("Edit note") { editTitle = displayed.title; editBody = displayed.body; editing = true }
            }
            Button("Delete artifact", role: .destructive) { host.perform { try host.engine?.deleteArtifact(artifact.id); dismiss() } }
        }.padding() }.navigationTitle("Artifact")
        .sheet(isPresented: $editing) {
            NavigationStack { Form {
                TextField("Title", text: $editTitle)
                TextEditor(text: $editBody).frame(minHeight: 240).accessibilityIdentifier("artifact.editBody")
                Button("Save changes") { host.perform { try host.engine?.editNote(artifact.id, title: editTitle, body: editBody); editing = false } }
            }.navigationTitle("Edit note") }
        }
    }
}
private struct ShellSettingsView: View {
    @EnvironmentObject private var host: ShellHostModel
    @AppStorage("prism.developerMode") private var developer = false
    @State private var key = ""
    @State private var endpoint = ""
    @State private var token = ""
    @State private var confirmDelete = false
    @State private var saved = false
    private func privacy(_ keyPath: WritableKeyPath<PrivacySettings, Bool>) -> Binding<Bool> {
        Binding(get: { host.engine?.archive.privacy[keyPath: keyPath] ?? false }, set: { value in host.setPrivacy { $0[keyPath: keyPath] = value } })
    }
    var body: some View {
        Form {
            Section("Monocle") {
                Text(host.link.status)
                Button("Pair a Monocle") { host.link.discoverForPairing() }
                ForEach(host.link.candidates) { candidate in Button(candidate.label) { host.link.select(candidate.id) } }
                Button("Reconnect") { host.link.reconnectRemembered() }
                Button("Forget Monocle", role: .destructive) { host.link.forget() }
            }
            Section("Assistant and voice") {
                Toggle("Allow cloud processing", isOn: privacy(\.cloudProcessing)).accessibilityIdentifier("settings.cloud")
                Text("Requests, permitted context and recordings are sent to the configured API provider. API billing is separate from ChatGPT or Codex subscriptions.").font(.caption)
                SecureField("Assistant API key", text: $key).textContentType(.password)
                Button(saved ? "Key saved" : "Save key") { saved = host.saveKey(key); key = "" }
                Button("Remove key", role: .destructive) { host.removeKey(); saved = false }
                Toggle("Spoken responses", isOn: privacy(\.spokenOutput))
                Text("Speech uses the iPhone voice and current headphones or speaker. A route change stops playback.").font(.caption)
            }
            Section("Focus timer alerts") {
                Button("Allow timer notifications") { host.perform { _ = try await host.timerNotifications.requestAccess(); host.objectWillChange.send() } }
                Text(host.timerNotifications.status).font(.caption)
                Text("Timers persist locally. iOS can deliver an allowed alert while PrismOS is in the background.").font(.caption)
            }
            Section("Context") {
                Button("Allow Calendar access") {
                    host.perform { let granted = try await host.native.requestCalendarAccess(); host.setPrivacy { $0.calendarEnabled = granted }; await host.refreshSources() }
                }
                Toggle("Use Calendar", isOn: privacy(\.calendarEnabled))
                Toggle("Useful upcoming event surfaces", isOn: privacy(\.proactiveEnabled))
                Toggle("Use authenticated agent gateway", isOn: privacy(\.agentEnabled))
                TextField("HTTPS agent gateway", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Gateway token", text: $token)
                Button("Save gateway") { host.perform { try host.configureAgent(endpoint: endpoint, token: token); token = ""; await host.refreshSources() } }
            }
            Section("Privacy and retention") {
                Toggle("Hide lens and Watch content", isOn: privacy(\.privateMode))
                Toggle("Retain original audio", isOn: privacy(\.retainRawAudio))
                Stepper("Keep content \(host.engine?.archive.privacy.retentionDays ?? 30) days", value: Binding(get: { host.engine?.archive.privacy.retentionDays ?? 30 }, set: { value in host.setPrivacy { $0.retentionDays = value } }), in: 1...365)
                Button("Delete Library content", role: .destructive) { confirmDelete = true }
                Text("Deleting content preserves the minimum reminder receipt ledger needed to prevent duplicate effects and offer undo. Deleting a transcript does not delete related answers; Delete Library content removes conversation copies.").font(.caption)
            }
            Section("Gestures") {
                Text("Double right: Ask\nHold right: follow up\nRight: review then confirm an action, or next page\nLeft: next choice, dismiss, or undo a receipt\nDouble left: pin\nHold left: blank immediately")
            }
            Section("Development") {
                Toggle("Developer Mode", isOn: $developer)
                if developer { NavigationLink("Developer console") { DeveloperConsoleContainer() } }
            }
        }.navigationTitle("Settings")
        .confirmationDialog("Delete all Library content?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete content", role: .destructive) { host.perform { try host.engine?.deleteAllContent() } }
        }
    }
}
/// Simulation owners are constructed only after explicitly entering Developer Mode.
private struct DeveloperConsoleContainer: View {
    @StateObject private var device = DeviceConsoleModel(transport: MockMonocleTransport())
    @StateObject private var runtime = RuntimeConsoleModel()
    @StateObject private var local = LocalConsoleModel()
    @StateObject private var services: ServiceConsoleModel
    @StateObject private var provider: ProviderConsoleModel
    init() {
        let s = ServiceConsoleModel(); _services = StateObject(wrappedValue: s); _provider = StateObject(wrappedValue: ProviderConsoleModel(services: s))
    }
    var body: some View {
        RootConsoleView().environmentObject(device).environmentObject(runtime).environmentObject(local).environmentObject(services).environmentObject(provider)
            .navigationTitle("Developer simulation")
    }
}
