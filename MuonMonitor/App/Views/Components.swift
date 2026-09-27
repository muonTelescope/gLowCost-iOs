import SwiftUI

struct CardBackground: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardBackground(padding: padding)) }
}

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 4).padding(.top, 6)
    }
}

struct PhaseBadge: View {
    let phase: Phase
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(phase.tint).frame(width: 8, height: 8)
            Text(phase.title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(phase.tint)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(phase.tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct TagChip: View {
    let tag: String
    var selected = true
    var body: some View {
        let tint = TagCatalog.tint(for: tag)
        Text(tag).font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(selected ? tint : Palette.secondaryText)
            .background(selected ? tint.opacity(0.15) : Color.primary.opacity(0.06), in: Capsule())
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .monospaced).weight(.medium)).foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(Palette.secondaryText)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct Sparkline: View {
    let values: [Double]
    var tint: Color = Palette.accent
    var body: some View {
        GeometryReader { g in
            let lo = values.min() ?? 0, hi = values.max() ?? 1, span = max(hi - lo, 1e-9)
            Path { p in
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                                     y: g.size.height * (1 - CGFloat((v - lo) / span)))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }.stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

extension Double {
    var hpa: String { String(format: "%.1f", self) }
}

extension TimeInterval {
    /// 17 h 41 m
    var hoursMinutes: String {
        let m = Int(self / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60) m" : "\(m) m"
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Demo data · not a measurement", systemImage: "wand.and.stars")
            .font(.caption.weight(.semibold)).foregroundStyle(Palette.warning)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Palette.warning.opacity(0.14), in: Capsule())
    }
}
