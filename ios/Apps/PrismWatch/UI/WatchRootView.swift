import SwiftUI
import PrismWatchModels

struct WatchRootView: View {
    @StateObject private var model: WatchConnectivityClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: WatchConnectivityClient) {
        _model = StateObject(wrappedValue: store)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    statusPanel
                    if let notice = degradedStateNotice {
                        degradedNoticePanel(notice)
                    }
                    selectorPanel
                    if model.selectedAppID == .oracle {
                        oraclePanel
                    } else if model.selectedAppID == .chronos {
                        chronosPanel
                    } else if model.selectedAppID == .teleprompter {
                        teleprompterPanel
                    } else if model.selectedAppID == .signal {
                        signalPanel
                    } else if model.selectedAppID == .vision {
                        visionPanel
                    } else if model.selectedAppID == .babel {
                        babelPanel
                    } else {
                        actionPanel
                    }
                }
                .padding(8)
            }
            .onAppear {
                DispatchQueue.main.async {
                    scrollToVisibleAnchor(using: proxy, reduceMotion: reduceMotion)
                }
            }
            .onChange(of: model.snapshot.version) { _ in
                DispatchQueue.main.async {
                    scrollToVisibleAnchor(using: proxy, reduceMotion: reduceMotion)
                }
            }
            .onChange(of: model.selectedAppID) { _ in
                DispatchQueue.main.async {
                    scrollToVisibleAnchor(using: proxy, reduceMotion: reduceMotion)
                }
            }
        }
        .background(WatchTheme.background.ignoresSafeArea())
        .tint(WatchTheme.gold)
        .navigationTitle("Lens")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusPanel: some View {
        WatchPanel(
            title: "Lens Deck",
            systemImage: "scope",
            accent: model.canIssueCommands ? WatchTheme.success : WatchTheme.warning
        ) {
            VStack(alignment: .leading, spacing: 6) {
                WatchMetricRow(
                    label: "Link",
                    value: model.transportReachable ? "REACHABLE" : "OFFLINE",
                    tint: model.transportReachable ? WatchTheme.success : WatchTheme.warning
                )

                WatchMetricRow(
                    label: "Host",
                    value: model.snapshot.connection.displayTitle,
                    tint: model.snapshot.connection.isReachable ? WatchTheme.success : WatchTheme.warning
                )

                WatchMetricRow(
                    label: "Surface",
                    value: model.snapshot.activeSurface.displayTitle,
                    tint: model.snapshot.activeAppID?.watchAccent ?? WatchTheme.gold
                )

                WatchMetricRow(
                    label: "Privacy",
                    value: model.snapshot.privacyMode ? "ON" : "OFF",
                    tint: model.snapshot.privacyMode ? WatchTheme.warning : WatchTheme.success
                )

                WatchMetricRow(
                    label: "Capture",
                    value: model.snapshot.captureActive ? "LIVE" : "IDLE",
                    tint: model.snapshot.captureActive ? WatchTheme.cyan : WatchTheme.goldDim
                )

                WatchMetricRow(
                    label: "Pending",
                    value: "\(model.pendingCommands.count)",
                    tint: model.pendingCommands.isEmpty ? WatchTheme.goldDim : WatchTheme.warning
                )

                Divider()
                    .overlay(WatchTheme.goldDim.opacity(0.35))

                if let activeApp = model.snapshot.activeApp {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: activeApp.appID.watchSymbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(activeApp.appID.watchAccent)
                            .frame(width: 18, height: 18)
                            .background(activeApp.appID.watchAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeApp.title.uppercased())
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(activeApp.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 4) {
                        WatchStatusPill(text: activeApp.primaryActionTitle, tint: activeApp.appID.watchAccent)
                        if let secondary = activeApp.secondaryActionTitle {
                            WatchStatusPill(text: secondary, tint: WatchTheme.goldDim)
                        }
                    }
                }

                if let acknowledgement = model.lastAcknowledgement {
                    Divider()
                        .overlay(WatchTheme.goldDim.opacity(0.35))

                    WatchMetricRow(
                        label: "Ack",
                        value: acknowledgement.displayText,
                        tint: acknowledgement.status == .applied ? WatchTheme.success : acknowledgement.status == .queued ? WatchTheme.warning : WatchTheme.danger
                    )

                    if let reason = acknowledgement.reason {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let error = model.lastErrorMessage {
                    Divider()
                        .overlay(WatchTheme.goldDim.opacity(0.35))

                    WatchMetricRow(label: "Ack", value: "WAITING", tint: WatchTheme.goldDim)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .id("status")
    }

    private var selectorPanel: some View {
        WatchPanel(title: "Apps", systemImage: "square.grid.2x2", accent: model.selectedAppID.watchAccent) {
            HStack(spacing: 6) {
                WatchIconButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Previous app",
                    accent: model.previousSelectableApp.watchAccent
                ) {
                    model.selectPreviousApp()
                }

                WatchAppSwitcherCard(
                    appID: model.selectedAppID,
                    summary: selectedAppSummary,
                    isFocused: model.snapshot.activeAppID == model.selectedAppID,
                    canFocus: model.canIssueCommands
                ) {
                    model.focusSelectedApp()
                }

                WatchIconButton(
                    systemImage: "chevron.right",
                    accessibilityLabel: "Next app",
                    accent: model.nextSelectableApp.watchAccent
                ) {
                    model.selectNextApp()
                }
            }
        }
        .id("selector")
    }

    private var selectedAppSummary: WatchAppSummary {
        return WatchAppSummary(appID: model.selectedAppID)
    }

    private var actionPanel: some View {
        WatchPanel(title: "Actions", systemImage: "cursorarrow.rays", accent: model.selectedAppID.watchAccent) {
            VStack(spacing: 6) {
                Button {
                    model.focusSelectedApp()
                } label: {
                    VStack(spacing: 2) {
                        Label("Focus", systemImage: "target")
                            .frame(maxWidth: .infinity)
                        Text(model.selectedAppID.watchTitle.uppercased())
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.selectedAppID.watchAccent)
                .disabled(!model.canIssueCommands)

                WatchSystemActionRow(model: model)
            }
        }
        .id("actions")
    }

    @ViewBuilder
    private func degradedNoticePanel(_ notice: WatchStateNotice) -> some View {
        WatchPanel(title: notice.title, systemImage: notice.systemImage, accent: notice.tint) {
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    WatchStatusPill(text: notice.pillText, tint: notice.tint)
                    if let secondary = notice.secondaryPillText {
                        WatchStatusPill(text: secondary, tint: WatchTheme.goldDim)
                    }
                }

                if notice.showsRefresh, model.canRefresh {
                    WatchIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Refresh Snapshot",
                        accent: notice.tint
                    ) {
                        model.refreshSnapshot()
                    }
                    .accessibilityHint("Ask the iPhone host to publish the latest state.")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(notice.title). \(notice.message)")
        }
        .id("notice")
    }

    private var oraclePanel: some View {
        OracleDeckView(model: model)
            .id(PrismAppID.oracle.rawValue)
    }

    private struct OracleDeckView: View {
        @ObservedObject var model: WatchConnectivityClient
        @State private var crownPosition: Double = 0
        @State private var lastCrownPosition: Double = 0

        var body: some View {
            let oracle = model.snapshot.oracle
            let isFocused = model.snapshot.activeAppID == .oracle
            let canControl = model.canIssueCommands && isFocused
            let canPrompt = canControl && model.snapshot.privacyMode == false && (oracle?.canAsk ?? false)
            let canSecondary = canControl && (oracle?.canKeep == true || oracle?.canClear == true)
            let canCopy = canControl && (oracle?.canCopy == true)
            let canAdjust = canControl && oracle != nil

            WatchPanel(title: "Oracle", systemImage: "sparkles", accent: WatchTheme.gold) {
                VStack(spacing: 8) {
                if !isFocused {
                    WatchIconButton(
                        systemImage: "target",
                        accessibilityLabel: "Focus Oracle",
                        accent: WatchTheme.gold,
                        prominent: true
                    ) {
                        model.focusSelectedApp()
                    }
                    .disabled(!model.canIssueCommands)
                }

                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            WatchStatusPill(text: oracle?.statusTitle ?? "READY", tint: phaseTint(for: oracle?.phase))
                            WatchStatusPill(text: oracle?.pageTitle ?? "0/0", tint: WatchTheme.gold)
                            WatchStatusPill(text: oracle?.densityTitle ?? "BALANCED", tint: densityTint(for: oracle?.density))
                        }

                        HStack(spacing: 4) {
                            WatchStatusPill(text: oracle?.historyTitle ?? "NO HISTORY", tint: WatchTheme.goldDim)
                            WatchStatusPill(text: oracle?.keepTitle ?? "OPEN", tint: keepTint(for: oracle))
                            if model.snapshot.privacyMode {
                                WatchStatusPill(text: "PRIVATE", tint: WatchTheme.warning)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let prompt = promptText(for: oracle), !prompt.isEmpty {
                                Text(prompt)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }

                            Text(displayText(for: oracle, privacyMode: model.snapshot.privacyMode))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(displayTint(for: oracle, privacyMode: model.snapshot.privacyMode))
                                .lineLimit(4)
                                .minimumScaleFactor(0.72)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(WatchTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Text(oracle?.compactTitle ?? "ASK READY")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .padding(8)
                    .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(WatchTheme.gold.opacity(0.36), lineWidth: 1)
                    )
                    .focusable(true)
                    .digitalCrownRotation(
                        $crownPosition,
                        from: -12,
                        through: 12,
                        by: 1,
                        sensitivity: .medium,
                        isContinuous: true,
                        isHapticFeedbackEnabled: true
                    )
                    .onAppear {
                        resetCrownTracking()
                    }
                    .onDisappear {
                        resetCrownTracking()
                    }
                    .onChange(of: crownPosition) { newValue in
                        handleCrownChange(to: newValue, canControl: canAdjust)
                    }

                    HStack(spacing: 6) {
                        Button {
                            model.oraclePrimaryAction()
                        } label: {
                            Label(oracle?.primaryActionTitle ?? "ASK", systemImage: primaryActionSymbol(for: oracle))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(primaryTint(for: oracle))
                        .disabled(!canPrompt)

                        Button {
                            model.oracleSecondaryAction()
                        } label: {
                            Label(oracle?.secondaryActionTitle ?? "CLEAR", systemImage: secondaryActionSymbol(for: oracle))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canSecondary)
                    }
                    .font(.caption.weight(.semibold))

                    HStack(spacing: 6) {
                        WatchIconButton(systemImage: "doc.on.doc", accessibilityLabel: oracle?.copyActionTitle ?? "Copy answer") {
                            model.copyOracleAnswer()
                        }
                        .disabled(!canCopy)

                        WatchIconButton(systemImage: "minus.circle", accessibilityLabel: oracle?.shorterActionTitle ?? "Make answer shorter") {
                            model.makeOracleShorter()
                        }
                        .disabled(!canControl || !(oracle?.canShorten ?? false))

                        WatchIconButton(systemImage: "plus.circle", accessibilityLabel: oracle?.moreDetailActionTitle ?? "More detail") {
                            model.makeOracleMoreDetailed()
                        }
                        .disabled(!canControl || !(oracle?.canExpand ?? false))
                    }

                    WatchSystemActionRow(model: model, privacySystemImage: model.snapshot.privacyMode ? "eye.slash" : "hand.raised.fill")
                }
            }
        }

        private func handleCrownChange(to newValue: Double, canControl: Bool) {
            guard canControl else {
                lastCrownPosition = newValue
                return
            }

            let delta = Int(newValue - lastCrownPosition)
            guard delta != 0 else { return }

            model.adjustOraclePage(by: delta)
            lastCrownPosition = newValue
        }

        private func resetCrownTracking() {
            crownPosition = 0
            lastCrownPosition = 0
        }

        private func promptText(for oracle: WatchOracleState?) -> String? {
            oracle?.promptText
        }

        private func displayText(for oracle: WatchOracleState?, privacyMode: Bool) -> String {
            guard let oracle else {
                return "TAP ASK TO START"
            }

            if privacyMode && oracle.phase == .answer {
                return "PRIVATE"
            }

            return oracle.detailTitle
        }

        private func displayTint(for oracle: WatchOracleState?, privacyMode: Bool) -> Color {
            guard let oracle else {
                return WatchTheme.goldDim
            }

            if privacyMode && oracle.phase == .answer {
                return WatchTheme.warning
            }

            switch oracle.phase {
            case .ready:
                return WatchTheme.gold
            case .listening, .thinking:
                return WatchTheme.cyan
            case .answer:
                return oracle.isKept ? WatchTheme.success : WatchTheme.gold
            case .cancelled:
                return WatchTheme.goldDim
            case .error:
                return WatchTheme.danger
            }
        }

        private func primaryTint(for oracle: WatchOracleState?) -> Color {
            switch oracle?.phase {
            case .answer:
                return WatchTheme.success
            case .listening, .thinking:
                return WatchTheme.cyan
            case .cancelled, .error, .ready, .none:
                return WatchTheme.gold
            }
        }

        private func phaseTint(for phase: WatchOraclePhase?) -> Color {
            switch phase {
            case .answer:
                return WatchTheme.success
            case .listening, .thinking:
                return WatchTheme.cyan
            case .cancelled:
                return WatchTheme.goldDim
            case .error:
                return WatchTheme.danger
            case .ready, .none:
                return WatchTheme.gold
            }
        }

        private func densityTint(for density: WatchOracleDensity?) -> Color {
            switch density {
            case .shorter:
                return WatchTheme.goldDim
            case .balanced:
                return WatchTheme.gold
            case .moreDetail:
                return WatchTheme.success
            case .none:
                return WatchTheme.goldDim
            }
        }

        private func keepTint(for oracle: WatchOracleState?) -> Color {
            guard let oracle else {
                return WatchTheme.goldDim
            }
            return oracle.isKept ? WatchTheme.success : WatchTheme.goldDim
        }

        private func primaryActionSymbol(for oracle: WatchOracleState?) -> String {
            switch oracle?.phase {
            case .answer:
                return "arrow.triangle.branch"
            case .listening, .thinking:
                return "sparkles"
            case .cancelled, .error, .ready, .none:
                return "sparkles"
            }
        }

        private func secondaryActionSymbol(for oracle: WatchOracleState?) -> String {
            switch oracle?.phase {
            case .answer:
                return oracle?.isKept == true ? "bookmark.slash" : "bookmark"
            case .listening, .thinking:
                return "xmark.circle"
            case .cancelled, .error, .ready, .none:
                return "xmark.circle"
            }
        }
    }

    private var chronosPanel: some View {
        ChronosDeckView(model: model)
            .id(PrismAppID.chronos.rawValue)
    }

    private var teleprompterPanel: some View {
        TeleprompterDeckView(model: model)
            .id(PrismAppID.teleprompter.rawValue)
    }

    private var signalPanel: some View {
        SignalDeckView(model: model)
            .id(PrismAppID.signal.rawValue)
    }

    private var visionPanel: some View {
        VisionDeckView(model: model)
            .id(PrismAppID.vision.rawValue)
    }

    private var babelPanel: some View {
        BabelDeckView(model: model)
            .id(PrismAppID.babel.rawValue)
    }

    private func scrollToVisibleAnchor(using proxy: ScrollViewProxy, reduceMotion: Bool) {
        let target = degradedStateNotice == nil ? "selector" : "notice"
        if reduceMotion {
            proxy.scrollTo(target, anchor: .top)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private var degradedStateNotice: WatchStateNotice? {
        if model.snapshot.wrongDeviceRisk {
            return WatchStateNotice(
                title: "DEVICE RISK",
                message: "Monocle identity is ambiguous. Select the device on iPhone.",
                systemImage: "exclamationmark.triangle.fill",
                tint: WatchTheme.danger,
                pillText: "OPEN IPHONE",
                secondaryPillText: nil,
                showsRefresh: true
            )
        }

        if !model.transportReachable {
            return WatchStateNotice(
                title: "PHONE OFFLINE",
                message: "Open PrismHost on iPhone to reconnect.",
                systemImage: "iphone.gen1.slash",
                tint: WatchTheme.warning,
                pillText: "OPEN IPHONE",
                secondaryPillText: nil,
                showsRefresh: true
            )
        }

        switch model.snapshot.connection {
        case .stale:
            return WatchStateNotice(
                title: "STALE SNAPSHOT",
                message: "Watch state is stale. Refresh on iPhone to resync live data.",
                systemImage: "clock.arrow.circlepath",
                tint: WatchTheme.warning,
                pillText: "STALE",
                secondaryPillText: nil,
                showsRefresh: true
            )
        case .recovery:
            return WatchStateNotice(
                title: "RECOVERY ONLY",
                message: "Safe Mode and NUS are recovery-only until Raw Data returns.",
                systemImage: "exclamationmark.shield.fill",
                tint: WatchTheme.danger,
                pillText: "RECOVERY",
                secondaryPillText: nil,
                showsRefresh: true
            )
        case .phone, .monocle:
            break
        }

        if let acknowledgement = model.lastAcknowledgement, acknowledgement.status == .rejected || acknowledgement.status == .stale {
            return WatchStateNotice(
                title: acknowledgement.status.displayText,
                message: acknowledgement.reason ?? "The last command was blocked.",
                systemImage: acknowledgement.status == .stale ? "clock.arrow.circlepath" : "hand.raised.fill",
                tint: acknowledgement.status == .stale ? WatchTheme.warning : WatchTheme.danger,
                pillText: acknowledgement.status.displayText,
                secondaryPillText: nil,
                showsRefresh: true
            )
        }

        if let reason = model.lastErrorMessage {
            return WatchStateNotice(
                title: "BLOCKED",
                message: reason,
                systemImage: "hand.raised.fill",
                tint: WatchTheme.danger,
                pillText: "BLOCKED",
                secondaryPillText: nil,
                showsRefresh: true
            )
        }

        return nil
    }
}

private struct WatchStateNotice {
    var title: String
    var message: String
    var systemImage: String
    var tint: Color
    var pillText: String
    var secondaryPillText: String?
    var showsRefresh: Bool
}

@MainActor
private extension WatchConnectivityClient {
    var selectableApps: [PrismAppID] {
        PrismAppID.allCases
    }

    var previousSelectableApp: PrismAppID {
        appAdjacent(to: selectedAppID, offset: -1)
    }

    var nextSelectableApp: PrismAppID {
        appAdjacent(to: selectedAppID, offset: 1)
    }

    func selectPreviousApp() {
        selectApp(previousSelectableApp)
    }

    func selectNextApp() {
        selectApp(nextSelectableApp)
    }

    private func appAdjacent(to appID: PrismAppID, offset: Int) -> PrismAppID {
        let apps = selectableApps
        guard let index = apps.firstIndex(of: appID), !apps.isEmpty else {
            return .oracle
        }

        let wrapped = (index + offset + apps.count) % apps.count
        return apps[wrapped]
    }
}

private struct WatchAppSwitcherCard: View {
    var appID: PrismAppID
    var summary: WatchAppSummary
    var isFocused: Bool
    var canFocus: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: appID.watchSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(appID.watchAccent)
                        .frame(width: 32, height: 32)
                        .background(appID.watchAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(appID.watchAccent.opacity(isFocused ? 0.85 : 0.46), lineWidth: isFocused ? 1.4 : 1)
                        )

                    if isFocused {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WatchTheme.success)
                            .background(WatchTheme.backgroundTop, in: Circle())
                            .offset(x: 3, y: -3)
                            .accessibilityHidden(true)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)

                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            .background(WatchTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isFocused ? WatchTheme.success.opacity(0.82) : appID.watchAccent.opacity(0.42), lineWidth: isFocused ? 1.4 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canFocus || isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.title), \(summary.subtitle)\(isFocused ? ", focused" : ", tap to focus")")
    }
}

private struct WatchSystemActionRow: View {
    @ObservedObject var model: WatchConnectivityClient
    var privacySystemImage: String = "hand.raised.fill"

    var body: some View {
        HStack(spacing: 6) {
            WatchIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Refresh Snapshot") {
                model.refreshSnapshot()
            }
            .disabled(!model.canRefresh)

            WatchIconButton(
                systemImage: privacySystemImage,
                accessibilityLabel: model.snapshot.privacyMode ? "Privacy On" : "Privacy Off"
            ) {
                model.togglePrivacy()
            }
            .disabled(!model.canIssueCommands)
        }
    }
}

private struct WatchIconButton: View {
    @Environment(\.isEnabled) private var isEnabled

    var systemImage: String
    var accessibilityLabel: String
    var accent: Color = WatchTheme.gold
    var prominent: Bool = false
    var role: ButtonRole? = nil
    var action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEnabled ? accent : .secondary)
                .frame(width: prominent ? 38 : 30, height: 30)
                .background(
                    (isEnabled ? accent : WatchTheme.goldDim).opacity(prominent ? 0.24 : 0.14),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke((isEnabled ? accent : WatchTheme.goldDim).opacity(prominent ? 0.62 : 0.42), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ChronosDeckView: View {
    @ObservedObject var model: WatchConnectivityClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPresetSeconds: Int = 300
    @State private var isSyncingPresetSelection = false

    private let presetSeconds = [60, 120, 300, 600, 900, 1800]

    var body: some View {
        let chronos = model.snapshot.chronos
        let isFocused = model.snapshot.activeAppID == .chronos
        let canControl = model.canIssueCommands && isFocused

        WatchPanel(title: "Chronos", systemImage: "timer", accent: WatchTheme.success) {
            VStack(spacing: 8) {
                if !isFocused {
                    WatchIconButton(
                        systemImage: "target",
                        accessibilityLabel: "Focus Chronos",
                        accent: WatchTheme.success,
                        prominent: true
                    ) {
                        model.focusSelectedApp()
                    }
                    .disabled(!model.canIssueCommands)
                }

                TimelineView(.periodic(from: Date(), by: 0.5)) { timeline in
                    let liveDisplay = displayState(for: chronos, connection: model.snapshot.connection, now: timeline.date)
                    VStack(spacing: 6) {
                        ZStack {
                            ChronosRing(
                                progress: liveDisplay.progress,
                                accent: liveDisplay.isAlarm ? WatchTheme.warning : WatchTheme.success,
                                reduceMotion: reduceMotion
                            )
                            VStack(spacing: 2) {
                                Text(liveDisplay.timeText)
                                    .font(.system(size: liveDisplay.timeFontSize, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .foregroundStyle(liveDisplay.isAlarm ? WatchTheme.warning : .primary)
                                Text(liveDisplay.modeText)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6)
                        }
                        .frame(height: 88)

                        HStack(spacing: 6) {
                            WatchStatusPill(text: liveDisplay.stateText, tint: liveDisplay.isAlarm ? WatchTheme.warning : WatchTheme.success)
                            WatchStatusPill(text: liveDisplay.pinText, tint: WatchTheme.goldDim)
                            if liveDisplay.isStale {
                                WatchStatusPill(text: "ESTIMATE", tint: WatchTheme.warning)
                            }
                        }

                        if let chronos {
                            Text(chronos.compactTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        } else {
                            Text("Waiting for host timer state")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }

                Picker(
                    "Preset",
                    selection: Binding(
                        get: { selectedPresetSeconds },
                        set: { selectedPresetSeconds = $0 }
                    )
                ) {
                    ForEach(presetSeconds, id: \.self) { seconds in
                        Text(label(for: seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(height: 76)
                .disabled(!canControl || chronos?.runState == .running || chronos?.runState == .alarm)
                .onAppear {
                    syncPresetSelection(from: chronos)
                }
                .onChange(of: chronos?.totalSeconds) { _ in
                    syncPresetSelection(from: chronos)
                }
                .onChange(of: selectedPresetSeconds) { newValue in
                    guard !isSyncingPresetSelection else { return }
                    guard canControl, chronos?.runState != .running, chronos?.runState != .alarm else { return }
                    model.applyChronosPreset(seconds: newValue)
                }

                VStack(spacing: 6) {
                    Button {
                        model.startPauseResumeChronos()
                    } label: {
                        Label(primaryActionTitle(for: chronos), systemImage: primaryActionSymbol(for: chronos))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(primaryTint(for: chronos))
                    .disabled(!canControl)

                    HStack(spacing: 6) {
                        WatchIconButton(systemImage: "arrow.counterclockwise", accessibilityLabel: "Reset Chronos") {
                            model.resetChronos()
                        }
                        .disabled(!canControl || chronos?.runState == .alarm)

                        WatchIconButton(systemImage: "timer", accessibilityLabel: modeActionTitle(for: chronos)) {
                            model.toggleChronosMode()
                        }
                        .disabled(!canControl || chronos?.runState == .running || chronos?.runState == .alarm)
                    }

                    HStack(spacing: 6) {
                        WatchIconButton(systemImage: "pin", accessibilityLabel: pinActionTitle(for: chronos)) {
                            model.toggleChronosPin()
                        }
                        .disabled(!canControl)

                        Button {
                            model.addChronosTime(30)
                        } label: {
                            Label("+30", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canControl || chronos?.runState == .alarm)

                        Button {
                            model.addChronosTime(60)
                        } label: {
                            Label("+1m", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canControl || chronos?.runState == .alarm)
                    }

                    WatchSystemActionRow(model: model)
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func syncPresetSelection(from chronos: WatchChronosState?) {
        isSyncingPresetSelection = true
        guard let chronos else {
            selectedPresetSeconds = 300
            DispatchQueue.main.async {
                isSyncingPresetSelection = false
            }
            return
        }

        let nearest = presetSeconds.min(by: { abs($0 - chronos.totalSeconds) < abs($1 - chronos.totalSeconds) }) ?? chronos.totalSeconds
        selectedPresetSeconds = nearest
        DispatchQueue.main.async {
            isSyncingPresetSelection = false
        }
    }

    private func label(for seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(remainder)s"
    }

    private func primaryActionTitle(for chronos: WatchChronosState?) -> String {
        chronos?.primaryActionTitle ?? "START"
    }

    private func primaryActionSymbol(for chronos: WatchChronosState?) -> String {
        switch chronos?.runState {
        case .running:
            "pause"
        case .paused:
            "play"
        case .alarm:
            "bell.fill"
        case .setup, .none:
            "play.fill"
        }
    }

    private func modeActionTitle(for chronos: WatchChronosState?) -> String {
        chronos?.modeActionTitle ?? "STOPWATCH"
    }

    private func pinActionTitle(for chronos: WatchChronosState?) -> String {
        chronos?.pinActionTitle ?? "PIN"
    }

    private func primaryTint(for chronos: WatchChronosState?) -> Color {
        switch chronos?.runState {
        case .alarm:
            WatchTheme.warning
        case .paused:
            WatchTheme.cyan
        case .running:
            WatchTheme.success
        case .setup, .none:
            WatchTheme.success
        }
    }

    private func displayState(
        for chronos: WatchChronosState?,
        connection: ConnectionState,
        now: Date
    ) -> ChronosDisplayState {
        guard let chronos else {
            return ChronosDisplayState(
                timeText: "--:--",
                modeText: "CHRONOS",
                stateText: "WAITING",
                pinText: "FREE",
                progress: 0,
                timeFontSize: 29,
                isAlarm: false,
                isStale: connection == .stale || connection == .recovery
            )
        }

        let isStale = connection == .stale || connection == .recovery
        let elapsed = max(0, now.timeIntervalSince(chronos.lastUpdatedAt))
        let liveSeconds: Double
        switch chronos.mode {
        case .timer:
            liveSeconds = chronos.runState == .running ? max(0, Double(chronos.remainingSeconds) - elapsed) : Double(chronos.remainingSeconds)
        case .stopwatch:
            liveSeconds = chronos.runState == .running ? Double(chronos.elapsedSeconds) + elapsed : Double(chronos.elapsedSeconds)
        }

        let wholeSeconds = Int(liveSeconds.rounded(.down))
        let formattedTime: String
        if wholeSeconds < 60 {
            let tenths = max(0, Int((liveSeconds - Double(wholeSeconds)) * 10))
            formattedTime = String(format: "%02d.%d", wholeSeconds, tenths)
        } else {
            formattedTime = String(format: "%02d:%02d", wholeSeconds / 60, wholeSeconds % 60)
        }

        let progress: Double
        switch chronos.mode {
        case .timer:
            progress = chronos.totalSeconds <= 0 ? 1 : min(1, max(0, 1 - (liveSeconds / Double(chronos.totalSeconds))))
        case .stopwatch:
            progress = min(1, max(0, (liveSeconds.truncatingRemainder(dividingBy: 60)) / 60))
        }

        return ChronosDisplayState(
            timeText: formattedTime,
            modeText: chronos.mode.displayTitle,
            stateText: chronos.statusTitle,
            pinText: chronos.isPinned ? "PINNED" : "FREE",
            progress: progress,
            timeFontSize: wholeSeconds < 60 ? 27 : 29,
            isAlarm: chronos.runState == .alarm,
            isStale: isStale
        )
    }
}

private struct TeleprompterDeckView: View {
    @ObservedObject var model: WatchConnectivityClient
    @State private var crownPosition: Double = 0
    @State private var lastCrownPosition: Double = 0
    @State private var resetArmed = false

    var body: some View {
        let teleprompter = model.snapshot.teleprompter
        let isFocused = model.snapshot.activeAppID == .teleprompter
        let canControl = model.canIssueCommands && isFocused
        let hasScript = (teleprompter?.isEmpty == false)
        let privacyMode = model.snapshot.privacyMode

        WatchPanel(title: "Teleprompter", systemImage: "text.alignleft", accent: model.selectedAppID.watchAccent) {
            VStack(spacing: 8) {
                if !isFocused {
                    WatchIconButton(
                        systemImage: "target",
                        accessibilityLabel: "Focus Stage",
                        accent: model.selectedAppID.watchAccent,
                        prominent: true
                    ) {
                        model.focusSelectedApp()
                    }
                    .disabled(!model.canIssueCommands)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        WatchStatusPill(text: teleprompter?.lineProgressTitle ?? "0/0", tint: WatchTheme.gold)
                        WatchStatusPill(
                            text: teleprompter?.modeTitle ?? "MANUAL",
                            tint: (teleprompter?.mode == .auto) ? WatchTheme.success : WatchTheme.cyan
                        )
                        WatchStatusPill(text: teleprompter?.speedTitle ?? "140 WPM", tint: WatchTheme.goldDim)
                    }

                    HStack(spacing: 6) {
                        WatchStatusPill(text: teleprompter?.bookmarkStatusTitle ?? "NO BOOKMARK", tint: WatchTheme.warning)
                        WatchStatusPill(text: teleprompter?.crownHintTitle ?? "LINE", tint: WatchTheme.goldDim)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(primaryScriptText(for: teleprompter, privacyMode: privacyMode, hasScript: hasScript))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(privacyMode ? WatchTheme.warning : .primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(secondaryScriptText(for: teleprompter, privacyMode: privacyMode, hasScript: hasScript))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(WatchTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    ProgressView(value: progressFraction(for: teleprompter))
                        .tint(model.selectedAppID.watchAccent)

                    Text(teleprompter?.compactTitle ?? "0/0 MANUAL 140 WPM")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(8)
                .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(model.selectedAppID.watchAccent.opacity(0.36), lineWidth: 1)
                )
                .focusable(true)
                .digitalCrownRotation(
                    $crownPosition,
                    from: -12,
                    through: 12,
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: true,
                    isHapticFeedbackEnabled: true
                )
                .onAppear {
                    resetCrownTracking()
                }
                .onDisappear {
                    resetCrownTracking()
                    resetArmed = false
                }
                .onChange(of: crownPosition) { newValue in
                    handleCrownChange(to: newValue, teleprompter: teleprompter, canControl: canControl)
                }

                HStack(spacing: 6) {
                    WatchIconButton(systemImage: "chevron.up", accessibilityLabel: "Previous line") {
                        model.teleprompterPreviousLine()
                    }
                    .disabled(!canControl || !hasScript)

                    Button {
                        model.toggleTeleprompterPlayPause()
                    } label: {
                        Label(primaryActionTitle(for: teleprompter), systemImage: primaryActionSymbol(for: teleprompter))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(primaryTint(for: teleprompter))
                    .disabled(!canControl || !hasScript)

                    WatchIconButton(systemImage: "chevron.down", accessibilityLabel: "Next line") {
                        model.teleprompterNextLine()
                    }
                    .disabled(!canControl || !hasScript)
                }

                HStack(spacing: 6) {
                    WatchIconButton(systemImage: "bookmark", accessibilityLabel: "Bookmark") {
                        model.bookmarkTeleprompter()
                    }
                    .disabled(!canControl || !hasScript)

                    WatchIconButton(
                        systemImage: privacyMode ? "eye" : "eye.slash",
                        accessibilityLabel: privacyMode ? "Reveal script" : "Blank lens"
                    ) {
                        model.togglePrivacy()
                    }
                    .disabled(!canControl)
                }

                Toggle(isOn: $resetArmed) {
                    Label(resetArmed ? "Reset Armed" : "Reset Guard", systemImage: resetArmed ? "lock.open.fill" : "lock.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(!canControl || !hasScript)

                Button(role: .destructive) {
                    model.resetTeleprompter()
                    resetArmed = false
                    resetCrownTracking()
                } label: {
                    Label("Start Over", systemImage: "backward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(WatchTheme.danger)
                .disabled(!canControl || !hasScript || !resetArmed)
            }
        }
    }

    private func handleCrownChange(
        to newValue: Double,
        teleprompter: WatchTeleprompterState?,
        canControl: Bool
    ) {
        guard canControl, let teleprompter, !teleprompter.isEmpty else {
            lastCrownPosition = newValue
            return
        }

        let delta = Int(newValue - lastCrownPosition)
        guard delta != 0 else { return }

        if teleprompter.mode == .manual {
            model.adjustTeleprompterLine(by: delta)
        } else {
            model.adjustTeleprompterWordsPerMinute(by: delta)
        }

        lastCrownPosition = newValue
    }

    private func resetCrownTracking() {
        crownPosition = 0
        lastCrownPosition = 0
    }

    private func primaryActionTitle(for teleprompter: WatchTeleprompterState?) -> String {
        teleprompter?.primaryActionTitle ?? "PLAY"
    }

    private func primaryActionSymbol(for teleprompter: WatchTeleprompterState?) -> String {
        switch teleprompter?.mode {
        case .auto:
            "pause.fill"
        case .manual, .none:
            "play.fill"
        }
    }

    private func primaryTint(for teleprompter: WatchTeleprompterState?) -> Color {
        switch teleprompter?.mode {
        case .auto:
            WatchTheme.success
        case .manual, .none:
            WatchTheme.cyan
        }
    }

    private func progressFraction(for teleprompter: WatchTeleprompterState?) -> Double {
        guard let teleprompter, teleprompter.totalChunks > 0 else {
            return 0
        }
        return min(1, max(0, Double(teleprompter.currentIndex + 1) / Double(teleprompter.totalChunks)))
    }

    private func primaryScriptText(
        for teleprompter: WatchTeleprompterState?,
        privacyMode: Bool,
        hasScript: Bool
    ) -> String {
        if privacyMode {
            return "BLANK LENS"
        }
        if let currentLine = teleprompter?.currentLine, !currentLine.isEmpty {
            return currentLine
        }
        return hasScript ? "NO SCRIPT" : "PASTE SCRIPT ON PHONE"
    }

    private func secondaryScriptText(
        for teleprompter: WatchTeleprompterState?,
        privacyMode: Bool,
        hasScript: Bool
    ) -> String {
        if privacyMode {
            return "SCRIPT HIDDEN"
        }
        if let nextLine = teleprompter?.nextLine, !nextLine.isEmpty {
            return nextLine
        }
        return hasScript ? "WAITING FOR NEXT LINE" : "IMPORT ON PHONE"
    }
}

private struct SignalDeckView: View {
    @ObservedObject var model: WatchConnectivityClient

    var body: some View {
        let signal = model.snapshot.signal
        let isFocused = model.snapshot.activeAppID == .signal
        let canControl = model.canIssueCommands && isFocused
        let hasCards = signal?.isEmpty == false
        let hasHandoff = signal?.hasHandoff == true
        let isEmpty = signal?.isEmpty ?? true
        let bodyText = signal?.isEmpty == true ? "RELOAD ON PHONE" : (signal?.bodyLine ?? "RELOAD ON PHONE")

        WatchPanel(title: "Signal", systemImage: "bell.badge", accent: model.selectedAppID.watchAccent) {
            VStack(spacing: 8) {
                if !isFocused {
                    WatchIconButton(
                        systemImage: "target",
                        accessibilityLabel: "Focus Signal",
                        accent: model.selectedAppID.watchAccent,
                        prominent: true
                    ) {
                        model.focusSelectedApp()
                    }
                    .disabled(!model.canIssueCommands)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        WatchStatusPill(text: signal?.positionTitle ?? "0/0", tint: WatchTheme.gold)
                        WatchStatusPill(
                            text: signal?.priorityTitle ?? "INFO",
                            tint: priorityTint(for: signal?.currentCard?.priority)
                        )
                        WatchStatusPill(text: signal?.sourceTitle ?? "SIGNAL", tint: WatchTheme.cyan)
                        WatchStatusPill(
                            text: hasHandoff ? "HANDOFF" : "NO HANDOFF",
                            tint: hasHandoff ? WatchTheme.success : WatchTheme.goldDim
                        )
                        if signal?.privacyMode == true {
                            WatchStatusPill(text: "PRIVATE", tint: WatchTheme.warning)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(signal?.titleLine ?? "EMPTY STACK")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(signal?.privacyMode == true ? WatchTheme.warning : .primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(bodyText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(WatchTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(signal?.compactTitle ?? "EMPTY STACK")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(8)
                .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(model.selectedAppID.watchAccent.opacity(0.36), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    WatchIconButton(systemImage: "chevron.up", accessibilityLabel: "Previous card") {
                        model.moveSignalCardBackward()
                    }
                    .disabled(!canControl || !hasCards || (signal?.visibleCardCount ?? 0) <= 1)

                    WatchIconButton(systemImage: "chevron.down", accessibilityLabel: "Next card") {
                        model.moveSignalCardForward()
                    }
                    .disabled(!canControl || !hasCards || (signal?.visibleCardCount ?? 0) <= 1)
                }

                HStack(spacing: 6) {
                    WatchIconButton(
                        systemImage: "checkmark",
                        accessibilityLabel: "Dismiss card",
                        accent: WatchTheme.warning,
                        prominent: true
                    ) {
                        model.dismissSignalCard()
                    }
                    .disabled(!canControl || !hasCards)

                    WatchIconButton(systemImage: "arrow.up.right.square", accessibilityLabel: "Open handoff") {
                        model.openSignalHandoff()
                    }
                    .disabled(!canControl || !hasHandoff)
                }

                HStack(spacing: 6) {
                    WatchIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Reload Signal") {
                        model.reloadSignalStack()
                    }
                    .disabled(!canControl || !isEmpty)

                    WatchIconButton(
                        systemImage: signal?.privacyMode == true ? "eye.slash" : "hand.raised.fill",
                        accessibilityLabel: signal?.privacyActionTitle ?? "Toggle Signal privacy"
                    ) {
                        model.toggleSignalPrivacy()
                    }
                    .disabled(!canControl)
                }
            }
        }
    }

    private func priorityTint(for priority: WatchSignalPriority?) -> Color {
        switch priority {
        case .critical:
            WatchTheme.danger
        case .important:
            WatchTheme.warning
        case .info, .none:
            WatchTheme.cyan
        }
    }
}

private struct VisionDeckView: View {
    @ObservedObject var model: WatchConnectivityClient

    var body: some View {
        let vision = model.snapshot.vision
        let isFocused = model.snapshot.activeAppID == .vision
        let canControl = model.canIssueCommands && isFocused

        WatchPanel(title: "Vision", systemImage: "camera.viewfinder", accent: model.selectedAppID.watchAccent) {
            VStack(spacing: 8) {
                if !isFocused {
                    WatchIconButton(
                        systemImage: "target",
                        accessibilityLabel: "Focus Vision",
                        accent: model.selectedAppID.watchAccent,
                        prominent: true
                    ) {
                        model.focusSelectedApp()
                    }
                    .disabled(!model.canIssueCommands)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        WatchStatusPill(text: vision?.modeTitle ?? "IDENTIFY", tint: model.selectedAppID.watchAccent)
                        WatchStatusPill(text: vision?.statusTitle ?? "READY", tint: phaseTint(for: vision?.phase))
                        WatchStatusPill(text: vision?.savedNoteTitle ?? "NO SAVES", tint: vision?.savedNoteCount == 0 ? WatchTheme.goldDim : WatchTheme.success)
                        if model.snapshot.privacyMode {
                            WatchStatusPill(text: "PRIVATE", tint: WatchTheme.warning)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(vision?.compactTitle ?? "IDENTIFY READY")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(model.snapshot.privacyMode && (vision?.hasResult == true) ? WatchTheme.warning : .primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(vision?.detailTitle ?? "READY FOR SCENE")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(WatchTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(vision?.savedNoteTitle ?? "NO SAVES")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(8)
                .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(model.selectedAppID.watchAccent.opacity(0.36), lineWidth: 1)
                )

                Button {
                    if vision?.phase == .ready {
                        model.captureVision()
                    } else {
                        model.retakeVision()
                    }
                } label: {
                    Label(vision?.primaryActionTitle ?? "CAPTURE", systemImage: vision?.phase == .ready ? "camera.viewfinder" : "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.cyan)
                .disabled(!canControl || !(vision?.canCapture ?? false))

                HStack(spacing: 6) {
                    WatchIconButton(systemImage: "xmark.circle", accessibilityLabel: "Cancel capture") {
                        model.cancelVisionCapture()
                    }
                    .disabled(!canControl || !(vision?.canCancel ?? false))

                    WatchIconButton(systemImage: "viewfinder", accessibilityLabel: vision?.modeActionTitle ?? "Toggle Vision mode") {
                        model.toggleVisionMode()
                    }
                    .disabled(!canControl || !(vision?.canToggleMode ?? false))
                }

                HStack(spacing: 6) {
                    WatchIconButton(systemImage: "tray.and.arrow.down", accessibilityLabel: "Save note") {
                        model.saveVisionNote()
                    }
                    .disabled(!canControl || !(vision?.canSaveNote ?? false))

                    WatchIconButton(systemImage: "sparkles", accessibilityLabel: "Ask Oracle") {
                        model.askVisionOracle()
                    }
                    .disabled(!canControl || !(vision?.canAskOracle ?? false))
                }

                WatchSystemActionRow(model: model)
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func phaseTint(for phase: WatchVisionPhase?) -> Color {
        switch phase {
        case .result:
            WatchTheme.success
        case .saved:
            WatchTheme.cyan
        case .waitingImage, .analyzing:
            WatchTheme.warning
        case .error:
            WatchTheme.danger
        case .ready, .none:
            WatchTheme.gold
        }
    }
}

private struct BabelDeckView: View {
    @ObservedObject var model: WatchConnectivityClient
    @State private var selectedPreset: WatchBabelPreset = .jaToEn

    var body: some View {
        let babel = model.snapshot.babel
        let isFocused = model.snapshot.activeAppID == .babel
        let canControl = model.canIssueCommands && isFocused
        let visibleLines = babel?.displayLines(masked: model.snapshot.privacyMode) ?? []

        WatchPanel(title: "Babel", systemImage: "character.bubble", accent: model.selectedAppID.watchAccent) {
            VStack(spacing: 8) {
                if !isFocused {
                    WatchIconButton(
                        systemImage: "target",
                        accessibilityLabel: "Focus Babel",
                        accent: model.selectedAppID.watchAccent,
                        prominent: true
                    ) {
                        model.focusSelectedApp()
                    }
                    .disabled(!model.canIssueCommands)
                }

                HStack(spacing: 6) {
                    WatchStatusPill(text: babel?.pairTitle ?? "JA -> EN", tint: model.selectedAppID.watchAccent)
                    WatchStatusPill(text: babel?.statusTitle ?? "READY", tint: phaseTint(for: babel?.phase))
                    WatchStatusPill(text: babel?.presetTitle ?? "PRESET", tint: WatchTheme.goldDim)
                    if model.snapshot.privacyMode {
                        WatchStatusPill(text: "PRIVATE", tint: WatchTheme.warning)
                    }
                    if let saved = babel, saved.savedTranscriptCount > 0 {
                        WatchStatusPill(text: saved.savedTranscriptTitle, tint: WatchTheme.success)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(babel?.compactTitle ?? "JA -> EN • READY")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 0)
                        Text(String(format: "%.0f%%", (babel?.audioLevel ?? 0) * 100))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WatchTheme.cyan)
                    }

                    ProgressView(value: babel?.audioLevel ?? 0)
                        .tint(WatchTheme.cyan)

                    VStack(alignment: .leading, spacing: 3) {
                        if visibleLines.isEmpty {
                            Text("TAP TO LISTEN")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        } else {
                            ForEach(visibleLines.suffix(3)) { line in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(line.kind.displayTitle)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(lineTint(for: line.kind))
                                        .frame(width: 36, alignment: .leading)
                                    Text(line.text)
                                        .font(.caption2)
                                        .foregroundStyle(lineTint(for: line.kind))
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.72)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(WatchTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(8)
                .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(model.selectedAppID.watchAccent.opacity(0.36), lineWidth: 1)
                )

                Picker("Preset", selection: $selectedPreset) {
                    ForEach(WatchBabelPreset.allCases, id: \.self) { preset in
                        Text(preset.displayTitle).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(height: 72)
                .clipped()
                .onAppear {
                    syncPresetSelection(from: babel)
                }
                .onChange(of: babel?.resolvedPreset?.rawValue ?? "custom") { _ in
                    syncPresetSelection(from: babel)
                }

                WatchIconButton(systemImage: "checkmark", accessibilityLabel: "Apply language preset") {
                    model.selectBabelPreset(selectedPreset)
                }
                .disabled(!canControl)

                HStack(spacing: 6) {
                    Button {
                        model.toggleBabelFreeze()
                    } label: {
                        Label(babel?.primaryActionTitle ?? "FREEZE", systemImage: babel?.isFrozen == true ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(babel?.isFrozen == true ? WatchTheme.cyan : WatchTheme.success)
                    .disabled(!canControl)

                    WatchIconButton(systemImage: "arrow.left.arrow.right", accessibilityLabel: "Swap languages") {
                        model.swapBabelLanguages()
                    }
                    .disabled(!canControl)
                }

                HStack(spacing: 6) {
                    WatchIconButton(systemImage: "arrow.counterclockwise", accessibilityLabel: "Repeat last translation") {
                        model.repeatBabelLast()
                    }
                    .disabled(!canControl || !(babel?.canRepeatLast ?? false))

                    WatchIconButton(systemImage: "tray.and.arrow.down", accessibilityLabel: "Save transcript") {
                        model.saveBabelTranscript()
                    }
                    .disabled(!canControl || !(babel?.hasTranscript ?? false))

                    WatchIconButton(
                        systemImage: "trash",
                        accessibilityLabel: "Clear transcript",
                        accent: WatchTheme.danger,
                        role: .destructive
                    ) {
                        model.clearBabelTranscript()
                    }
                    .disabled(!canControl)
                }
            }
        }
    }

    private func syncPresetSelection(from babel: WatchBabelState?) {
        if let preset = babel?.resolvedPreset {
            selectedPreset = preset
            return
        }
        if !WatchBabelPreset.allCases.contains(selectedPreset) {
            selectedPreset = .jaToEn
        }
    }

    private func phaseTint(for phase: WatchBabelPhase?) -> Color {
        switch phase {
        case .frozen:
            WatchTheme.warning
        case .error:
            WatchTheme.danger
        case .listening, .transcribing, .translating:
            WatchTheme.cyan
        case .ready, .none:
            WatchTheme.success
        }
    }

    private func lineTint(for kind: WatchBabelLineKind) -> Color {
        switch kind {
        case .raw:
            WatchTheme.goldDim
        case .final:
            .primary
        case .system:
            WatchTheme.warning
        }
    }
}

private struct ChronosDisplayState {
    var timeText: String
    var modeText: String
    var stateText: String
    var pinText: String
    var progress: Double
    var timeFontSize: CGFloat
    var isAlarm: Bool
    var isStale: Bool
}

private struct ChronosRing: View {
    var progress: Double
    var accent: Color
    var reduceMotion: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(WatchTheme.goldDim.opacity(0.35), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.2), value: progress)
        }
    }
}

#Preview("Connected") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 11,
                activeSurface: .app(.oracle),
                connection: .phone,
                privacyMode: false,
                captureActive: false,
                activeApp: .oracle,
                acknowledgement: WatchAcknowledgement(
                    commandID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                    status: .applied,
                    reason: "Focused oracle",
                    snapshotVersion: 11
                )
            ),
            transportReachable: true,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}

#Preview("Chronos") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 22,
                activeSurface: .app(.chronos),
                connection: .phone,
                privacyMode: false,
                captureActive: false,
                activeApp: .chronos,
                chronos: WatchChronosState(
                    mode: .timer,
                    runState: .running,
                    totalSeconds: 300,
                    remainingSeconds: 167,
                    elapsedSeconds: 133,
                    isPinned: true,
                    lastUpdatedAt: Date()
                ),
                acknowledgement: WatchAcknowledgement(
                    commandID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                    status: .applied,
                    reason: "Timer complete",
                    snapshotVersion: 22,
                    haptic: .alarm,
                    displayText: "ALARM"
                )
            ),
            transportReachable: true,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}

#Preview("Teleprompter") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 24,
                activeSurface: .app(.teleprompter),
                connection: .phone,
                privacyMode: false,
                captureActive: false,
                activeApp: .teleprompter,
                teleprompter: WatchTeleprompterState.sample()
            ),
            transportReachable: true,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}

#Preview("Signal") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 25,
                activeSurface: .app(.signal),
                connection: .phone,
                privacyMode: false,
                captureActive: false,
                activeApp: .signal,
                signal: WatchSignalState.sample()
            ),
            transportReachable: true,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}

#Preview("Vision") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 26,
                activeSurface: .app(.vision),
                connection: .phone,
                privacyMode: false,
                captureActive: false,
                activeApp: .vision,
                vision: WatchVisionState.sample(
                    mode: .readText,
                    phase: .result,
                    summary: "ESP32 BOARD ONLINE",
                    ocrText: "PRESS TOP BUTTON",
                    savedNoteCount: 1
                )
            ),
            transportReachable: true,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}

#Preview("Stale") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 17,
                activeSurface: .app(.vision),
                connection: .stale,
                privacyMode: true,
                captureActive: true,
                activeApp: .vision,
                vision: WatchVisionState(
                    mode: .readText,
                    phase: .result,
                    savedNoteCount: 0
                ),
                acknowledgement: WatchAcknowledgement(
                    commandID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                    status: .queued,
                    reason: "Queued for host",
                    snapshotVersion: 17
                )
            ),
            transportReachable: true,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}

#Preview("Offline") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 18,
                activeSurface: .orbit,
                connection: .phone,
                privacyMode: false,
                captureActive: false,
                activeApp: .oracle
            ),
            transportReachable: false,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}

#Preview("Recovery") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 19,
                activeSurface: .orbit,
                connection: .recovery,
                privacyMode: false,
                captureActive: false,
                activeApp: .oracle
            ),
            transportReachable: true,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}

#Preview("Wrong Device") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 20,
                activeSurface: .orbit,
                connection: .phone,
                privacyMode: false,
                captureActive: false,
                wrongDeviceRisk: true,
                activeApp: .oracle
            ),
            transportReachable: true,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}

#Preview("Blocked") {
    WatchRootView(
        store: WatchConnectivityClient(
            snapshot: WatchSnapshot.sample(
                version: 21,
                activeSurface: .app(.oracle),
                connection: .phone,
                privacyMode: true,
                captureActive: false,
                activeApp: .oracle,
                acknowledgement: WatchAcknowledgement(
                    commandID: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
                    status: .rejected,
                    reason: "Privacy mode",
                    snapshotVersion: 21
                )
            ),
            transportReachable: true,
            activateSession: false
        )
    )
    .frame(width: 162, height: 197)
}
