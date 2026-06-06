import SwiftUI
import PrismWatchModels

enum WatchTheme {
    static let backgroundTop = Color(red: 0.055, green: 0.047, blue: 0.04)
    static let backgroundBottom = Color(red: 0.02, green: 0.024, blue: 0.028)
    static let surface = Color(red: 0.105, green: 0.092, blue: 0.076).opacity(0.94)
    static let elevatedSurface = Color(red: 0.15, green: 0.125, blue: 0.092).opacity(0.98)
    static let gold = Color(red: 0.83, green: 0.62, blue: 0.25)
    static let goldDim = Color(red: 0.48, green: 0.36, blue: 0.12)
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

extension PrismAppID {
    var watchSymbol: String {
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

    var watchAccent: Color {
        switch self {
        case .oracle:
            WatchTheme.gold
        case .vision:
            WatchTheme.cyan
        case .signal:
            WatchTheme.warning
        case .chronos:
            WatchTheme.success
        case .teleprompter:
            Color(red: 0.78, green: 0.68, blue: 0.95)
        case .babel:
            Color(red: 0.95, green: 0.58, blue: 0.40)
        }
    }
}

struct WatchPanel<Content: View>: View {
    var title: String
    var systemImage: String
    var accent: Color = WatchTheme.gold
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 20, height: 20)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(10)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent.opacity(0.36), lineWidth: 1)
        )
    }
}

struct WatchStatusPill: View {
    var text: String
    var tint: Color = WatchTheme.gold

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(text)
    }
}

struct WatchMetricRow: View {
    var label: String
    var value: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            Spacer(minLength: 0)

            Text(value.uppercased())
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}
