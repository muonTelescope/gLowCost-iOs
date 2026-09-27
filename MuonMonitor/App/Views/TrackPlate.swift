import SwiftUI

/// The hero of the Now screen: one straight line per coincidence in the last
/// completed minute. Angles follow the roughly cos²θ zenith distribution of
/// cosmic muons, so most lines are close to vertical. The minute is replayed
/// over 60 s so the plate feels live; with Reduce Motion it is static.
struct TrackPlate: View {
    let count: Int
    let seed: UInt64
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Track { let x: CGFloat; let slope: CGFloat; let at: Double; let bright: Bool }

    private var tracks: [Track] {
        var g = SplitMix(seed: seed)
        return (0..<max(0, min(count, 400))).map { i in
            // Box–Muller: zenith angle ~ N(0, 0.35 rad), a fair stand-in for cos²θ within the acceptance.
            let u1 = max(g.nextDouble(), 1e-9), u2 = g.nextDouble()
            let theta = min(1.2, max(-1.2, 0.35 * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)))
            return Track(x: CGFloat(g.nextDouble()) * 1.2 - 0.1, slope: CGFloat(tan(theta)), at: Double(i) / Double(max(count, 1)), bright: i >= count - 7)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion || !animated)) { ctx in
            Canvas { g, size in
                let still = reduceMotion || !animated
                let progress = still ? 1.0 : ctx.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) / 60
                for t in tracks {
                    let age = progress - t.at
                    let alpha: Double = still ? (t.bright ? 0.95 : 0.35) : (age < 0 ? 0.12 : max(0.18, 1 - age * 1.6))
                    var p = Path()
                    let x0 = t.x * size.width
                    p.move(to: CGPoint(x: x0, y: -4))
                    p.addLine(to: CGPoint(x: x0 + t.slope * size.height, y: size.height + 4))
                    g.stroke(p, with: .color(Palette.track.opacity(alpha)), lineWidth: t.bright ? 1.6 : 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Small deterministic RNG so the same minute always draws the same plate.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextDouble() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
