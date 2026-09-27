import SwiftUI

/// Channel notation: CH with the first paddle as superscript and the second as
/// subscript (CH⁰₁, CH⁰₂, CH¹₂), ΣCH for the sum of the three pairs.
///
/// Built from separate Text runs rather than Unicode super/subscript glyphs
/// (Plex Mono has none). Review fix 2: the digits never go below `minDigit`
/// points, so the label stays legible in pair tiles, the expert table, the Lock
/// Screen and the Dynamic Island.
struct ChannelLabel: View {
    /// -1 = sum (ΣCH), 0 = CH⁰₁, 1 = CH⁰₂, 2 = CH¹₂, 3 = CH⁰₁₂ (triple), 4…6 = GPIO inputs.
    let channel: Int
    var size: CGFloat = 15
    var color: Color = Palette.muted
    var weight: Typography.MonoWeight = .medium
    var fixed = false
    static let minDigit: CGFloat = 11

    static func paddles(_ channel: Int) -> (String, String)? {
        switch channel {
        case 0: ("0", "1")
        case 1: ("0", "2")
        case 2: ("1", "2")
        case 3: ("0", "12")
        default: nil
        }
    }
    static let gpioNames = [4: "GPIO6", 5: "GPIO5", 6: "GPIO16"]

    /// Spoken name for VoiceOver and plain-text contexts (charts legends, notifications).
    static func spoken(_ channel: Int) -> String {
        switch channel {
        case -1: "sum of pairs"
        case 0...3: "channel " + (paddles(channel).map { "\($0.0) \($0.1)" } ?? "")
        default: gpioNames[channel] ?? "channel"
        }
    }
    /// Unicode approximation for strings that cannot hold views (share sheet text, notifications).
    static func plain(_ channel: Int) -> String {
        let sup: [Character: String] = ["0": "⁰", "1": "¹", "2": "²"], sub: [Character: String] = ["0": "₀", "1": "₁", "2": "₂"]
        guard let pair = paddles(channel) else { return channel == -1 ? "ΣCH" : gpioNames[channel] ?? "CH" }
        let (a, b) = pair
        return "CH" + a.map { sup[$0] ?? String($0) }.joined() + b.map { sub[$0] ?? String($0) }.joined()
    }

    private func font(_ s: CGFloat) -> Font { fixed ? Typography.monoFixed(s, weight) : Typography.mono(s, weight, relativeTo: .caption) }

    var body: some View {
        let digit = max(Self.minDigit, (size * 0.72).rounded())
        Group {
            if let pair = Self.paddles(channel) {
                let (sup, sub) = pair
                HStack(alignment: .center, spacing: 1) {
                    Text("CH").font(font(size))
                    VStack(alignment: .leading, spacing: -digit * 0.28) {
                        Text(sup).font(font(digit))
                        Text(sub).font(font(digit))
                    }
                }
            } else if channel == -1 {
                Text("ΣCH").font(font(size))
            } else {
                Text(Self.gpioNames[channel] ?? "CH").font(font(size))
            }
        }
        .foregroundStyle(color)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(channel))
    }
}

/// App glyph: two muon tracks crossing a detector paddle, drawn as a Shape so it
/// renders in widgets, the Live Activity and the Dynamic Island (replaces the
/// generic `line.diagonal` SF Symbol).
struct MuonGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // two near-vertical tracks
        p.move(to: CGPoint(x: rect.minX + w * 0.22, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + w * 0.40, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + w * 0.52, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + w * 0.78, y: rect.maxY))
        // paddle tick across the middle
        p.move(to: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.52)); p.addLine(to: CGPoint(x: rect.minX + w * 0.92, y: rect.minY + h * 0.52))
        return p
    }
}

struct MuonMark: View {
    var size: CGFloat = 16
    var color: Color = Palette.lilac
    var body: some View {
        MuonGlyph()
            .stroke(color, style: StrokeStyle(lineWidth: max(1.4, size / 9), lineCap: .square))
            .frame(width: size * 0.8, height: size)
            .accessibilityHidden(true)
    }
}

/// Line chart of the three coincidence pairs, one line per pair, built from
/// Paths so it renders on the Lock Screen and in widgets. Values < 0 are gaps.
struct PairLines: View {
    let series: [[Int]]           // [CH⁰₁, CH⁰₂, CH¹₂], each oldest first
    var colors: [Color] = Palette.pairs
    var lineWidth: CGFloat = 1.6

    var body: some View {
        GeometryReader { geo in
            let all = series.flatMap { $0.filter { $0 >= 0 } }
            let lo = CGFloat(all.min() ?? 0), hi = CGFloat(max((all.max() ?? 1), Int(lo) + 1))
            ZStack {
                ForEach(Array(series.enumerated()), id: \.offset) { i, values in
                    Path { p in
                        let n = max(values.count - 1, 1)
                        var penDown = false
                        for (k, v) in values.enumerated() {
                            guard v >= 0 else { penDown = false; continue }
                            let pt = CGPoint(x: geo.size.width * CGFloat(k) / CGFloat(n),
                                             y: geo.size.height * (1 - (CGFloat(v) - lo) / (hi - lo)))
                            if penDown { p.addLine(to: pt) } else { p.move(to: pt); penDown = true }
                        }
                    }
                    .stroke(colors[i % colors.count], style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Coincidences per minute for the three pairs")
        .accessibilityValue(series.enumerated().map { i, v in "\(ChannelLabel.spoken(i)) \(v.last(where: { $0 >= 0 }).map(String.init) ?? "none")" }.joined(separator: ", "))
    }
}
