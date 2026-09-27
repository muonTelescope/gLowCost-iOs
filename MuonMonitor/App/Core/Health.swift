import Foundation

/// Detector health from raw minute counts. A clean counter behaves like a
/// Poisson process: after removing slow drift, variance ≈ mean (Fano ≈ 1).
/// Electrical pickup, a noisy threshold or radio interference add variance.
enum Health {
    enum Level: String, Codable { case good, watch, poor, unknown }

    struct ChannelReport: Identifiable {
        var id: Int { channel }
        let channel: Int            // 0...2 pairs, -1 sum
        let minutes: Int
        let mean: Double
        let fano: Double            // detrended variance / mean
        let tolerance: Double       // ~2σ of Fano for a Poisson series of this length
        var level: Level {
            guard minutes >= 30 else { return .unknown }
            if fano <= 1 + tolerance { return .good }
            if fano <= 1 + 3 * tolerance { return .watch }
            return .poor
        }
    }

    /// The three pairs share muons, so the sum is over-dispersed by construction;
    /// only the individual pairs are judged.
    static func report(_ minutes: [MinuteRecord]) -> [ChannelReport] {
        let valid = minutes.filter { $0.physics && $0.intervalMS > 0 }
        return (0..<3).map { ch in
            let n = valid.compactMap { $0.rate(ch) }
            return channelReport(ch, n)
        }
    }

    static func channelReport(_ ch: Int, _ n: [Double]) -> ChannelReport {
        guard n.count >= 3 else { return ChannelReport(channel: ch, minutes: n.count, mean: n.first ?? 0, fano: .nan, tolerance: .nan) }
        let trend = rollingMean(n, half: 15)
        var ss = 0.0, mean = 0.0
        for i in n.indices { ss += (n[i] - trend[i]) * (n[i] - trend[i]) / max(trend[i], 0.5); mean += n[i] }
        mean /= Double(n.count)
        let fano = ss / Double(n.count - 1)
        return ChannelReport(channel: ch, minutes: n.count, mean: mean, fano: fano, tolerance: 2 * (2 / Double(n.count - 1)).squareRoot())
    }

    static func rollingMean(_ x: [Double], half: Int) -> [Double] {
        var prefix = [0.0]; prefix.reserveCapacity(x.count + 1)
        for v in x { prefix.append(prefix.last! + v) }
        return x.indices.map { i in
            let a = max(0, i - half), b = min(x.count - 1, i + half)
            return (prefix[b + 1] - prefix[a]) / Double(b - a + 1)
        }
    }

    // MARK: live checks used for alerts

    /// Latest physics minute is more than `sigmas` from the median of the previous 30.
    static func isJump(latest: MinuteRecord, recent: [MinuteRecord], sigmas: Double = 6) -> Bool {
        let prior = recent.filter(\.physics).suffix(30).map(\.coincidences)
        guard latest.physics, prior.count >= 10 else { return false }
        let med = Double(prior.sorted()[prior.count / 2])
        return abs(Double(latest.coincidences) - med) > sigmas * max(med, 1).squareRoot()
    }

    /// Three consecutive physics minutes with zero coincidences while HV is on.
    static func isStuckAtZero(_ recent: [MinuteRecord]) -> Bool {
        let last = recent.filter(\.physics).suffix(3)
        return last.count == 3 && last.allSatisfy { $0.coincidences == 0 }
    }
}
