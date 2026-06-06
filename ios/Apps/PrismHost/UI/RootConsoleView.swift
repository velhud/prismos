import SwiftUI
import PrismAI
import PrismModels
import PrismRuntime

struct RootConsoleView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DeviceView()
            }
            .tabItem {
                Label("Device", systemImage: "visionpro")
            }

            NavigationStack {
                AppsView()
            }
            .tabItem {
                Label("Apps", systemImage: "square.grid.2x2")
            }

            NavigationStack {
                DisplayPreviewView()
            }
            .tabItem {
                Label("Preview", systemImage: "display")
            }

            NavigationStack {
                SessionsView()
            }
            .tabItem {
                Label("Sessions", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                DiagnosticsView()
            }
            .tabItem {
                Label("Diagnostics", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(PrismTheme.gold)
        .preferredColorScheme(.dark)
    }
}

struct AppsView: View {
    @EnvironmentObject private var runtime: RuntimeConsoleModel
    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppsCompactHeader(activeApp: runtime.activeAppLabel)
            AppsOrbitBar(activeApp: runtime.activeAppLabel) {
                runtime.exitToOrbit()
            }

            HStack(alignment: .lastTextBaseline) {
                Text("Apps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(runtime.activeAppRows.count) active")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(runtime.activeAppRows, id: \.appID) { app in
                    Button {
                        runtime.focus(app.appID)
                    } label: {
                        PrismAppTile(widget: app, isSelected: runtime.activeAppLabel.lowercased() == app.appID.rawValue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            AppsInputBar {
                runtime.sendMockTapRight()
            } onReservedGesture: {
                runtime.sendReservedGesture()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Apps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .prismScreen()
    }
}

private struct AppsCompactHeader: View {
    var activeApp: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PrismTheme.gold)
                .frame(width: 34, height: 34)
                .background(PrismTheme.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PrismTheme.gold.opacity(0.55), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("PrismOS")
                    .font(.headline.weight(.semibold))
                Text("Monocle app launcher")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(activeApp.uppercased())
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(PrismTheme.gold)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(PrismTheme.gold.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PrismTheme.gold.opacity(0.5), lineWidth: 1.15)
        )
    }
}

private struct AppsOrbitBar: View {
    var activeApp: String
    var onReturn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(activeApp, systemImage: "scope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            Button(action: onReturn) {
                Label("Orbit", systemImage: "circle.grid.cross")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PrismTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PrismTheme.goldDim.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct AppsInputBar: View {
    var onTapRight: () -> Void
    var onReservedGesture: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTapRight) {
                Label("Tap Right", systemImage: "arrow.turn.down.right")
                    .frame(maxWidth: .infinity)
            }

            Button(action: onReservedGesture) {
                Label("Reserved", systemImage: "hand.raised")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

struct SessionsView: View {
    @EnvironmentObject private var local: LocalConsoleModel
    @EnvironmentObject private var provider: ProviderConsoleModel
    private let teleprompterTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            PrismHeaderCard(
                title: "Sessions",
                subtitle: "Local and provider-backed app controls.",
                systemImage: "rectangle.stack",
                status: "Host"
            )
            .prismHeaderRow()

            Section("Local") {
                ForEach(local.sessionRows, id: \.self) { row in
                    Text(row)
                        .prismRow()
                }
            }

            Section("Chronos") {
                LabeledContent("State", value: local.chronos.state.runState.rawValue.capitalized)
                    .prismRow()
                LabeledContent("Mode", value: local.chronos.state.mode.rawValue.capitalized)
                    .prismRow()
                LabeledContent("Pinned", value: local.chronos.state.pinned ? "Yes" : "No")
                    .prismRow()
                Stepper("Duration: \(local.chronosMinutes) min", value: $local.chronosMinutes, in: 1...180)
                    .prismRow()
                Button {
                    local.startChronos()
                } label: {
                    Label("Start Chronos", systemImage: "play")
                }
                .prismRow()
                Button {
                    local.pauseChronos()
                } label: {
                    Label("Pause Chronos", systemImage: "pause")
                }
                .prismRow()
                Button(role: .destructive) {
                    local.resetChronos()
                } label: {
                    Label("Reset Chronos", systemImage: "arrow.counterclockwise")
                }
                .prismRow()
                Button {
                    local.toggleChronosMode()
                } label: {
                    Label("Timer Or Stopwatch", systemImage: "timer")
                }
                .prismRow()
                Button {
                    local.toggleChronosPinned()
                } label: {
                    Label("Pin Or Unpin", systemImage: "pin")
                }
                .prismRow()
            }

            Section("Teleprompter") {
                LabeledContent("Script", value: local.teleprompter.script.title)
                    .prismRow()
                LabeledContent("Mode", value: local.teleprompter.script.mode.rawValue.capitalized)
                    .prismRow()
                LabeledContent("Line", value: "\(min(local.teleprompter.script.currentIndex + 1, max(local.teleprompter.script.chunks.count, 1)))/\(max(local.teleprompter.script.chunks.count, 1))")
                    .prismRow()
                TextField("Script title", text: $local.teleprompterDraftTitle)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Teleprompter script title")
                    .prismRow()
                TextEditor(text: $local.teleprompterDraftBody)
                    .frame(minHeight: 96)
                    .accessibilityLabel("Teleprompter script body")
                    .prismRow()
                Button {
                    local.importTeleprompterDraft()
                } label: {
                    Label("Load Script", systemImage: "text.page")
                }
                .prismRow()
                Stepper(
                    "Speed: \(local.teleprompter.script.wordsPerMinute) WPM",
                    value: Binding(
                        get: { local.teleprompter.script.wordsPerMinute },
                        set: { local.setTeleprompterWordsPerMinute($0) }
                    ),
                    in: 60...240,
                    step: 10
                )
                .prismRow()
                HStack(spacing: 10) {
                    Button {
                        local.previousScriptLine()
                    } label: {
                        Label("Previous", systemImage: "chevron.up")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        local.nextScriptLine()
                    } label: {
                        Label("Next", systemImage: "chevron.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .prismRow()
                Button {
                    local.toggleScriptAuto()
                } label: {
                    Label("Toggle Auto Scroll", systemImage: "speedometer")
                }
                .prismRow()
                HStack(spacing: 10) {
                    Button {
                        local.bookmarkOrResetTeleprompter()
                    } label: {
                        Label("Bookmark", systemImage: "bookmark")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        local.resetTeleprompterToStart()
                    } label: {
                        Label("Start Over", systemImage: "backward.end")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .prismRow()
            }

            Section("Signal") {
                LabeledContent("Cards", value: "\(local.signal.visibleCards.count)")
                    .prismRow()
                LabeledContent("Privacy", value: local.signal.privacyMode ? "On" : "Off")
                    .prismRow()
                if let card = local.signal.currentCard {
                    Text(card.title)
                        .prismRow()
                    Text(local.signal.privacyMode ? "Private" : card.body)
                        .foregroundStyle(.secondary)
                        .prismRow()
                }
                Button {
                    local.dismissSignal()
                } label: {
                    Label("Dismiss Current Card", systemImage: "checkmark")
                }
                .prismRow()
                Button {
                    local.toggleSignalPrivacy()
                } label: {
                    Label("Toggle Privacy", systemImage: "eye.slash")
                }
                .prismRow()
                TextField("Source", text: $local.signalDraftSource)
                    .textInputAutocapitalization(.characters)
                    .accessibilityLabel("Signal source")
                    .prismRow()
                TextField("Title", text: $local.signalDraftTitle)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Signal title")
                    .prismRow()
                TextField("Body", text: $local.signalDraftBody)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Signal body")
                    .prismRow()
                Picker("Priority", selection: $local.signalDraftPriority) {
                    ForEach(SignalPriority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .prismRow()
                Button {
                    local.addSignalDraft()
                } label: {
                    Label("Add Signal Card", systemImage: "plus.rectangle.on.rectangle")
                }
                .prismRow()
                Button {
                    local.reloadDefaultSignalCards()
                } label: {
                    Label("Reload Example Cards", systemImage: "arrow.clockwise")
                }
                .prismRow()
            }

            Section("Oracle") {
                ForEach(provider.oracleRows, id: \.self) { row in
                    Text(row)
                        .prismRow()
                }
                TextField("Ask Oracle", text: $provider.oraclePrompt)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Ask Oracle")
                    .prismRow()
                Button {
                    provider.askOracle()
                } label: {
                    Label("Ask Typed Query", systemImage: "text.bubble")
                }
                .prismRow()
                Button {
                    provider.startOracleVoiceMock()
                } label: {
                    Label("Mock Voice Ask", systemImage: "waveform")
                }
                .prismRow()
                Button(role: .destructive) {
                    provider.cancelOracle()
                } label: {
                    Label("Cancel Oracle", systemImage: "xmark.circle")
                }
                .prismRow()
            }

            Section("Vision") {
                ForEach(provider.visionRows, id: \.self) { row in
                    Text(row)
                        .prismRow()
                }
                Button {
                    provider.captureVisionMock()
                } label: {
                    Label("Mock Capture", systemImage: "camera")
                }
                .prismRow()
                Button {
                    provider.toggleVisionMode()
                } label: {
                    Label("Toggle OCR Mode", systemImage: "text.viewfinder")
                }
                .prismRow()
                Button {
                    provider.saveVisionNote()
                } label: {
                    Label("Save Vision Note", systemImage: "square.and.arrow.down")
                }
                .prismRow()
            }

            Section("Babel") {
                ForEach(provider.babelRows, id: \.self) { row in
                    Text(row)
                        .prismRow()
                }
                HStack(spacing: 10) {
                    TextField("Source", text: $provider.babelSourceLanguage)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Babel source language")
                    TextField("Target", text: $provider.babelTargetLanguage)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Babel target language")
                }
                .prismRow()
                Button {
                    provider.applyBabelLanguages()
                } label: {
                    Label("Apply Languages", systemImage: "globe")
                }
                .prismRow()
                TextField("Text to translate", text: $provider.babelText)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Text to translate")
                    .prismRow()
                Button {
                    provider.translateBabelText()
                } label: {
                    Label("Translate Text", systemImage: "character.bubble")
                }
                .prismRow()
                Button {
                    provider.captureBabelAudioMock()
                } label: {
                    Label("Mock Audio Translate", systemImage: "mic")
                }
                .prismRow()
                Button {
                    provider.toggleBabelFreeze()
                } label: {
                    Label("Freeze Or Resume", systemImage: "pause.circle")
                }
                .prismRow()
                Button {
                    provider.swapBabelLanguages()
                } label: {
                    Label("Swap Languages", systemImage: "arrow.left.arrow.right")
                }
                .prismRow()
                Button {
                    provider.saveAndClearBabel()
                } label: {
                    Label("Save And Clear", systemImage: "tray.and.arrow.down")
                }
                .prismRow()
            }
        }
        .navigationTitle("Sessions")
        .onReceive(teleprompterTimer) { now in
            local.tickTeleprompter(now: now)
        }
        .prismScreen()
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var model: DeviceConsoleModel
    @EnvironmentObject private var runtime: RuntimeConsoleModel

    var body: some View {
        List {
            PrismHeaderCard(
                title: "Diagnostics",
                subtitle: "Redacted device and runtime events.",
                systemImage: "waveform.path.ecg.rectangle",
                status: "\(model.diagnostics.count + runtime.snapshot.diagnostics.count)"
            )
            .prismHeaderRow()

            Section("Device") {
                ForEach(model.diagnostics) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(event.message)
                    }
                    .prismRow()
                }
            }

            Section("Runtime") {
                ForEach(runtime.snapshot.diagnostics, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(event.redactedMessage)
                    }
                    .prismRow()
                }
            }
        }
        .navigationTitle("Diagnostics")
        .prismScreen()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var local: LocalConsoleModel
    @EnvironmentObject private var services: ServiceConsoleModel
    @State private var confirmClear = false
    @State private var providerKey = ""

    var body: some View {
        Form {
            PrismHeaderCard(
                title: "Settings",
                subtitle: "Provider routing, privacy, and retention.",
                systemImage: "gearshape.2",
                status: services.providerMode.displayName
            )
            .prismHeaderRow()

            Section("Runtime") {
                Picker("Provider Mode", selection: $services.providerMode) {
                    ForEach(ProviderMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .prismRow()
                Picker("Transcription", selection: $services.transcriptionMode) {
                    ForEach(ProviderMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .prismRow()
                Picker("Vision", selection: $services.visionMode) {
                    ForEach(ProviderMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .prismRow()
                Picker("Translation", selection: $services.translationMode) {
                    ForEach(ProviderMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .prismRow()
                Toggle("Shape Primitives", isOn: $local.shapeGateEnabled)
                    .prismRow()
            }
            Section("OpenAI Models") {
                LabeledContent("Text") {
                    modelTextField("Text model", text: $services.openAITextModelID)
                }
                .prismRow()
                LabeledContent("Vision") {
                    modelTextField("Vision model", text: $services.openAIVisionModelID)
                }
                .prismRow()
                LabeledContent("Translation") {
                    modelTextField("Translation model", text: $services.openAITranslationModelID)
                }
                .prismRow()
                LabeledContent("Transcription") {
                    modelTextField("Transcription model", text: $services.openAITranscriptionModelID)
                }
                .prismRow()
                LabeledContent("Realtime Session") {
                    modelTextField("Realtime session", text: $services.openAIRealtimeSessionModelID)
                }
                .prismRow()
                LabeledContent("Realtime Delay") {
                    modelTextField("Realtime delay", text: $services.openAIRealtimeTranscriptionDelay)
                }
                .prismRow()
                LabeledContent("Reasoning") {
                    modelTextField("Reasoning effort", text: $services.openAIReasoningEffort)
                }
                .prismRow()
                LabeledContent("Verbosity") {
                    modelTextField("Text verbosity", text: $services.openAITextVerbosity)
                }
                .prismRow()
                Toggle("Store Responses", isOn: $services.openAIStoreResponses)
                    .prismRow()
            }
            Section("Provider Secrets") {
                LabeledContent("API Key", value: services.providerKeyStatus.rawValue)
                    .prismRow()
                SecureField("OpenAI API Key", text: $providerKey)
                    .textContentType(.password)
                    .prismRow()
                Button {
                    services.saveProviderKey(providerKey)
                    providerKey = ""
                } label: {
                    Label("Save Provider Key", systemImage: "key")
                }
                .prismRow()
                Button(role: .destructive) {
                    services.deleteProviderKey()
                } label: {
                    Label("Delete Provider Key", systemImage: "key.slash")
                }
                .prismRow()
                Toggle("Require Cloud Approval", isOn: $services.requireCloudApproval)
                    .prismRow()
            }
            Section("Privacy") {
                LabeledContent("Secrets", value: "Keychain")
                    .prismRow()
                LabeledContent("Diagnostics", value: "Redacted")
                    .prismRow()
                Stepper("Retention: \(local.retentionDays) day(s)", value: $local.retentionDays, in: 1...30)
                    .prismRow()
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Clear Local Artifacts", systemImage: "trash")
                }
                .prismRow()
                .confirmationDialog("Clear local artifacts?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Clear", role: .destructive) {
                        local.clearLocalArtifacts()
                    }
                }
            }
            Section("Diagnostics Preview") {
                Toggle("Raw Diagnostics", isOn: $services.diagnosticsRawMode)
                    .onChange(of: services.diagnosticsRawMode) { _, _ in
                        services.refreshDiagnosticsPreview()
                    }
                    .prismRow()
                LabeledContent("Export", value: services.diagnosticsExportSummary)
                    .prismRow()
                Button {
                    services.createRedactedDiagnosticsExport()
                } label: {
                    Label("Create Redacted Export", systemImage: "square.and.arrow.up")
                }
                .prismRow()
                ForEach(services.diagnosticsPreview, id: \.self) { line in
                    Text(line)
                        .prismRow()
                }
            }
            Section("Developer") {
                Toggle("Developer Mode", isOn: $local.developerModeEnabled)
                    .prismRow()
            }
        }
        .navigationTitle("Settings")
        .prismScreen()
    }

    private func modelTextField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(title)
    }
}
