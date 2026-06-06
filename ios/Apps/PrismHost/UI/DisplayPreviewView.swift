import SwiftUI
import PrismDraw

struct DisplayPreviewView: View {
    @EnvironmentObject private var runtime: RuntimeConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewCompactHeader(activeApp: runtime.activeAppLabel)

            MonocleDisplayPreview(viewport: runtime.previewViewport)

            PreviewStatsPanel(viewport: runtime.previewViewport)

            HStack(spacing: 10) {
                Button {
                    runtime.sendMockTapRight()
                } label: {
                    Label("Tap Right", systemImage: "arrow.turn.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    runtime.exitToOrbit()
                } label: {
                    Label("Orbit", systemImage: "circle.grid.cross")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .prismScreen()
    }
}

private struct PreviewCompactHeader: View {
    var activeApp: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "display")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PrismTheme.gold)
                .frame(width: 34, height: 34)
                .background(PrismTheme.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PrismTheme.gold.opacity(0.55), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Preview")
                    .font(.headline.weight(.semibold))
                Text("640 x 400 host DRAW")
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

struct MonocleDisplayPreview: View {
    var viewport: DrawViewport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let scale = min(geometry.size.width / 640, geometry.size.height / 400)
                let canvasSize = CGSize(width: 640 * scale, height: 400 * scale)

                ZStack {
                    Color.black
                    ForEach(Array(viewport.primitives.enumerated()), id: \.offset) { _, primitive in
                        primitiveView(primitive, scale: scale)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PrismTheme.gold.opacity(0.86), lineWidth: 1.35)
                )
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .aspectRatio(640.0 / 400.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(PrismTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PrismTheme.goldDim.opacity(0.58), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Monocle display preview for \(viewport.appID), \(viewport.primitives.count) primitives")
        }
    }

    @ViewBuilder
    private func primitiveView(_ primitive: DrawPrimitive, scale: CGFloat) -> some View {
        switch primitive {
        case let .text(text, x, y, color, anchor):
            Text(text)
                .font(.system(size: max(7, 48 * scale), weight: .regular, design: .monospaced))
                .foregroundStyle(Color.drawColor(color))
                .lineLimit(1)
                .frame(width: CGFloat(text.count * 24) * scale, height: 48 * scale)
                .minimumScaleFactor(0.65)
                .position(adjustedTextPosition(text: text, x: x, y: y, anchor: anchor, scale: scale))
        case let .line(x1, y1, x2, y2, color, width):
            Path { path in
                path.move(to: CGPoint(x: CGFloat(x1) * scale, y: CGFloat(y1) * scale))
                path.addLine(to: CGPoint(x: CGFloat(x2) * scale, y: CGFloat(y2) * scale))
            }
            .stroke(Color.drawColor(color), lineWidth: max(1, CGFloat(width) * scale))
        case let .rectangle(x1, y1, x2, y2, color):
            Path { path in
                path.addRect(CGRect(
                    x: CGFloat(min(x1, x2)) * scale,
                    y: CGFloat(min(y1, y2)) * scale,
                    width: CGFloat(x1 > x2 ? x1 - x2 : x2 - x1) * scale,
                    height: CGFloat(y1 > y2 ? y1 - y2 : y2 - y1) * scale
                ))
            }
            .stroke(Color.drawColor(color), lineWidth: 1)
        case let .fill(color):
            Color.drawColor(color)
        }
    }

    private func adjustedTextPosition(
        text: String,
        x: UInt16,
        y: UInt16,
        anchor: DrawAnchor,
        scale: CGFloat
    ) -> CGPoint {
        let base = CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale)
        let textWidth = CGFloat(text.count * 24) * scale
        let textHeight = 48 * scale
        let offsetX: CGFloat
        let offsetY: CGFloat
        switch anchor {
        case .middleCenter:
            offsetX = 0
            offsetY = 0
        case .topLeft:
            offsetX = textWidth / 2
            offsetY = textHeight / 2
        case .topCenter:
            offsetX = 0
            offsetY = textHeight / 2
        case .topRight:
            offsetX = -textWidth / 2
            offsetY = textHeight / 2
        case .middleLeft:
            offsetX = textWidth / 2
            offsetY = 0
        case .middleRight:
            offsetX = -textWidth / 2
            offsetY = 0
        case .bottomLeft:
            offsetX = textWidth / 2
            offsetY = -textHeight / 2
        case .bottomCenter:
            offsetX = 0
            offsetY = -textHeight / 2
        case .bottomRight:
            offsetX = -textWidth / 2
            offsetY = -textHeight / 2
        }
        return CGPoint(x: base.x + offsetX, y: base.y + offsetY)
    }
}

private struct PreviewStatsPanel: View {
    var viewport: DrawViewport

    var body: some View {
        HStack(spacing: 10) {
            PreviewStat(label: "App ID", value: viewport.appID)
            PreviewStat(label: "Primitives", value: "\(viewport.primitives.count)")
        }
    }
}

private struct PreviewStat: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PrismTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PrismTheme.gold.opacity(0.48), lineWidth: 1.2)
        )
    }
}

private extension Color {
    static func drawColor(_ value: UInt32) -> Color {
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}
