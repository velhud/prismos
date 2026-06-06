import SwiftUI
import PrismModels
import PrismRuntime

enum PrismTheme {
    static let backgroundTop = Color(red: 0.055, green: 0.047, blue: 0.04)
    static let backgroundBottom = Color(red: 0.02, green: 0.024, blue: 0.028)
    static let surface = Color(red: 0.105, green: 0.092, blue: 0.076).opacity(0.86)
    static let elevatedSurface = Color(red: 0.15, green: 0.125, blue: 0.092).opacity(0.92)
    static let gold = Color(red: 0.83, green: 0.62, blue: 0.25)
    static let goldDim = Color(red: 0.48, green: 0.36, blue: 0.12)
    static let graphite = Color(red: 0.44, green: 0.48, blue: 0.50)
    static let success = Color(red: 0.38, green: 0.78, blue: 0.55)
    static let warning = Color(red: 0.94, green: 0.70, blue: 0.28)
    static let danger = Color(red: 0.90, green: 0.35, blue: 0.32)
    static let cyan = Color(red: 0.34, green: 0.72, blue: 0.88)

    static var background: some View {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PrismHeaderCard: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var status: String
    var tint: Color = PrismTheme.gold

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(PrismTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            PrismStatusPill(text: status, tint: tint)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PrismTheme.gold.opacity(0.48), lineWidth: 1.2)
        )
    }
}

struct PrismMetricBadge: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color = PrismTheme.gold

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
        }
    }
}

struct PrismStatusPill: View {
    var text: String
    var tint: Color = PrismTheme.gold

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(text)
    }
}

struct PrismAppRow: View {
    var widget: RuntimeWidget
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: widget.appID.prismSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(widget.appID.prismAccent)
                .frame(width: 38, height: 38)
                .background(widget.appID.prismAccent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(widget.appID.prismAccent.opacity(isSelected ? 0.72 : 0.26), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(widget.label)
                        .font(.body.weight(.semibold))
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(PrismTheme.success)
                    }
                }
                Text(widget.appID.prismRole)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            PrismStatusPill(text: widget.status, tint: isSelected ? PrismTheme.success : PrismTheme.graphite)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(widget.label), \(widget.appID.prismRole), \(widget.status)")
    }
}

struct PrismAppTile: View {
    var widget: RuntimeWidget
    var isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .center, spacing: 6) {
                Image(systemName: widget.appID.prismSymbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(widget.appID.prismAccent)
                    .frame(width: 40, height: 40)
                    .background(widget.appID.prismAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(widget.appID.prismAccent.opacity(isSelected ? 0.9 : 0.5), lineWidth: 1.2)
                    )

                Text(widget.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)

                Text(widget.appID.prismRole)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PrismTheme.success)
                    .padding(3)
                    .background(PrismTheme.backgroundTop, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .center)
        .background(PrismTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? PrismTheme.success.opacity(0.92) : PrismTheme.gold.opacity(0.48), lineWidth: isSelected ? 1.6 : 1.15)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(widget.label), \(widget.appID.prismRole)\(isSelected ? ", selected" : "")")
    }
}

struct PrismSectionLabel: View {
    var title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func prismScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(PrismTheme.background.ignoresSafeArea())
            .tint(PrismTheme.gold)
            .toolbarBackground(PrismTheme.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(PrismTheme.backgroundTop, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
    }

    func prismRow() -> some View {
        self
            .listRowBackground(PrismTheme.surface)
            .listRowSeparatorTint(PrismTheme.goldDim.opacity(0.45))
    }

    func prismHeaderRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension PrismAppID {
    var prismSymbol: String {
        switch self {
        case .oracle:
            "sparkles"
        case .vision:
            "camera.viewfinder"
        case .signal:
            "bell.badge"
        case .chronos:
            "timer"
        case .teleprompter:
            "text.alignleft"
        case .babel:
            "character.bubble"
        }
    }

    var prismRole: String {
        switch self {
        case .oracle:
            "Assistant and concise answers"
        case .vision:
            "Snapshot analysis and OCR"
        case .signal:
            "Attention cards and privacy"
        case .chronos:
            "Timers and glanceable time"
        case .teleprompter:
            "Script pacing and prompts"
        case .babel:
            "Translation and subtitles"
        }
    }

    var prismAccent: Color {
        switch self {
        case .oracle:
            PrismTheme.gold
        case .vision:
            PrismTheme.cyan
        case .signal:
            PrismTheme.warning
        case .chronos:
            PrismTheme.success
        case .teleprompter:
            Color(red: 0.78, green: 0.68, blue: 0.95)
        case .babel:
            Color(red: 0.95, green: 0.58, blue: 0.40)
        }
    }
}
