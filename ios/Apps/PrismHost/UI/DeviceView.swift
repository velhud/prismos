import SwiftUI
import PrismRuntime

struct DeviceView: View {
    @EnvironmentObject private var model: DeviceConsoleModel
    @EnvironmentObject private var runtime: RuntimeConsoleModel

    var body: some View {
        List {
            PrismHeaderCard(
                title: "inAi glasses",
                subtitle: "Identity and recovery.",
                systemImage: "visionpro",
                status: model.connectionState.label,
                tint: model.connectionState.canSendDraw ? PrismTheme.success : PrismTheme.warning
            )
            .prismHeaderRow()

            Section("Connection") {
                PrismMetricBadge(title: "State", value: model.connectionState.label, systemImage: "antenna.radiowaves.left.and.right", tint: model.connectionState.canSendDraw ? PrismTheme.success : PrismTheme.warning)
                    .prismRow()
                LabeledContent("Selected glasses", value: model.selectedDevice?.displayName ?? "None")
                    .prismRow()
                LabeledContent("Active App", value: runtime.activeAppLabel)
                    .prismRow()
                LabeledContent("Raw Data", value: model.rawDataAvailable ? "Available" : "Unavailable")
                    .prismRow()
                LabeledContent("NUS Recovery", value: model.nusAvailable ? "Visible" : "Not visible")
                    .prismRow()
                LabeledContent("Lifecycle", value: model.lifecycleState.displayName)
                    .prismRow()
                LabeledContent("Recovery", value: model.recoveryState.displayName)
                    .prismRow()
                LabeledContent("Last Connected", value: model.lastSuccessfulConnectionAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    .prismRow()
            }

            Section("Actions") {
                Button {
                    model.startScan()
                } label: {
                    Label("Scan for inAi glasses", systemImage: "dot.radiowaves.left.and.right")
                }
                .prismRow()

                Button {
                    model.connectSelected()
                } label: {
                    Label("Connect Selected", systemImage: "link")
                }
                .disabled(model.selectedDevice == nil)
                .prismRow()

                Button {
                    model.sendStaticDraw()
                } label: {
                    Label("Send Static DRAW", systemImage: "rectangle.and.text.magnifyingglass")
                }
                .disabled(!model.connectionState.canSendDraw)
                .prismRow()
            }

            Section("Lifecycle") {
                Text(model.reconnectMessage)
                    .foregroundStyle(.secondary)
                    .prismRow()
                Button {
                    model.recordLifecycle(.restoredByCoreBluetooth)
                } label: {
                    Label("Simulate Restoration Wake", systemImage: "arrow.clockwise.icloud")
                }
                .prismRow()
                Button {
                    model.recordLifecycle(.forceQuitLimited)
                } label: {
                    Label("Show Force-Quit Limitation", systemImage: "exclamationmark.triangle")
                }
                .prismRow()
            }

            if !model.candidates.isEmpty {
                Section("Candidates") {
                    ForEach(model.candidates) { candidate in
                        Button {
                            model.select(candidate)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.displayName)
                                Text(candidate.id.uuidString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .prismRow()
                    }
                }
            }

            if model.connectionState == .recoveryOnly || model.recoveryState.disablesNormalControls {
                Section("Recovery") {
                    Text("Safe Mode or NUS is recovery-only. Normal app controls stay disabled until Raw Data runtime is available.")
                        .foregroundStyle(.secondary)
                        .prismRow()
                    LabeledContent("Raw Data", value: model.rawDataAvailable ? "Available" : "Unavailable")
                        .prismRow()
                    LabeledContent("NUS", value: model.nusAvailable ? "Visible" : "Not visible")
                        .prismRow()
                    LabeledContent("Runbook", value: "Documentation/MONOCLE_RECOVERY_RUNBOOK.md")
                        .prismRow()
                    Text("Use the selected device identity. Do not connect by name or attempt automatic repair.")
                        .foregroundStyle(.secondary)
                        .prismRow()
                }
            }
        }
        .navigationTitle("Device")
        .prismScreen()
    }
}

private extension BackgroundLifecycleState {
    var displayName: String {
        switch self {
        case .foreground:
            "Foreground"
        case .backgroundWake:
            "Background Wake"
        case .restoredByCoreBluetooth:
            "CoreBluetooth Restored"
        case .forceQuitLimited:
            "Force-Quit Limited"
        case .bluetoothPoweredOff:
            "Bluetooth Off"
        case .permissionDenied:
            "Permission Denied"
        case .lowBattery:
            "Low Battery"
        }
    }
}

private extension RecoveryModeState {
    var displayName: String {
        switch self {
        case .runtimeAvailable:
            "Runtime Available"
        case .waitingForHost:
            "Waiting For Host"
        case .safeModeLikely:
            "Safe Mode Likely"
        case .unknownMonocle:
            "Unknown glasses"
        case .wrongDeviceRisk:
            "Wrong Device Risk"
        }
    }
}
