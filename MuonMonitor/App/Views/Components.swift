import SwiftUI

// Cards (`.card()`, `.panel()`), buttons and glass live in Shared/Chamfer.swift;
// fonts in Shared/Typography.swift; colours in Shared/Palette.swift.

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).capsLabel()
            .padding(.horizontal, 2).padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PhaseBadge: View {
    let phase: Phase
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(phase.tint).frame(width: 7, height: 7).rotationEffect(.degrees(45))
            Text(phase.title).font(Typography.raleway(14, .bold, relativeTo: .subheadline))
        }
        .foregroundStyle(phase.tint)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(phase.tint.opacity(0.14), in: ChamferedShape.chip)
        .overlay { ChamferedShape.chip.strokeBorder(phase.tint.opacity(0.45), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Tag chip. Review fix 3: tags are violet, green or neutral, never pink.
struct TagChip: View {
    let tag: String
    var selected = true
    var body: some View {
        let tint = TagCatalog.tint(for: tag)
        Text(tag).font(Typography.raleway(12, .semibold, relativeTo: .caption))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(selected ? tint : Palette.secondaryText)
            .background(selected ? tint.opacity(0.14) : Palette.raised, in: ChamferedShape.chip)
            .overlay { ChamferedShape.chip.strokeBorder(selected ? tint.opacity(0.45) : Palette.hairline, lineWidth: 1) }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = Palette.ink
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(Typography.mono(18, .medium, relativeTo: .title3)).foregroundStyle(tint)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(Typography.caption).foregroundStyle(Palette.secondaryText).lineLimit(1).minimumScaleFactor(0.8)
        }
        .panel(padding: 10, cut: 10)
        .accessibilityElement(children: .combine)
    }
}

struct Sparkline: View {
    let values: [Double]
    var tint: Color = Palette.data
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

/// Custom segmented control with cut corners; the selected segment gets the bright edge.
struct ChamferSegmented<Value: Hashable, Label: View>: View {
    let options: [Value]
    @Binding var selection: Value
    @ViewBuilder let label: (Value, Bool) -> Label

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { v in
                let on = v == selection
                Button { selection = v } label: {
                    label(v, on).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(on ? Palette.raised : .clear, in: ChamferedShape.control(Chamfer.chip + 2))
                        .overlay { if on { ChamferedShape.control(Chamfer.chip + 2).strokeBorder(Palette.brightEdge, lineWidth: 1) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.panel, in: ChamferedShape.control(Chamfer.control))
        .overlay { ChamferedShape.control(Chamfer.control).strokeBorder(Palette.hairline, lineWidth: 1) }
    }
}

/// Settings-style row on a card: title, optional detail, trailing content.
struct CardRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.raleway(16, .semibold, relativeTo: .body)).foregroundStyle(Palette.ink)
                if let detail { Text(detail).font(Typography.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

extension CardRow where Trailing == EmptyView {
    init(title: String, detail: String? = nil) { self.init(title: title, detail: detail) { EmptyView() } }
}

/// Hairline between rows inside a card.
struct RowDivider: View {
    var leading: CGFloat = 14
    var body: some View { Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, leading) }
}

extension Double {
    var hpa: String { String(format: "%.1f", self) }
}

extension TimeInterval {
    /// 17 h 41 m
    var hoursMinutes: String {
        let m = Int(self / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

/// Marks synthetic data. Review fix 3: labels are violet, not pink.
struct DemoBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
            Text("Demo data · not a measurement")
        }
        .font(Typography.raleway(12, .bold, relativeTo: .caption)).foregroundStyle(Palette.violet)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Palette.violet.opacity(0.14), in: ChamferedShape.chip)
        .overlay { ChamferedShape.chip.strokeBorder(Palette.violet.opacity(0.45), lineWidth: 1) }
    }
}
