import Foundation

/// Time bins of physics minutes for charts. Bins with less than half their
/// minutes are dropped, and a missing bin breaks the line (gaps stay gaps).
struct RateBin: Identifiable, Equatable {
    let id: Int              // bin index from run start
    let date: Date           // bin centre
    let rate: Double         // counts per minute
    let error: Double        // Poisson 1σ on the mean rate
    let minutes: Int
    let pressure: Double?
    let temperature: Double?
    let altitude: Double?
    let segment: Int         // increments after each gap, for separate line series
}

enum Binning {
    static func bins(_ records: [MinuteRecord], channel: Int, minutes: Int) -> [RateBin] {
        let phys = records.filter { $0.physics && $0.rate(channel) != nil }
        guard let t0 = records.first?.epoch else { return [] }
        let width = Double(max(minutes, 1)) * 60
        var groups: [Int: [MinuteRecord]] = [:]
        for r in phys { groups[Int((r.epoch - t0) / width), default: []].append(r) }
        var out: [RateBin] = []
        var segment = 0, lastIndex: Int?
        for k in groups.keys.sorted() {
            let g = groups[k]!
            guard g.count * 2 >= max(minutes, 1) || minutes == 1 else { continue }
            if let lastIndex, k != lastIndex + 1 { segment += 1 }
            lastIndex = k
            let exposure = g.reduce(0.0) { $0 + Double($1.intervalMS) / 60000 }
            let counts = g.reduce(0.0) { $0 + ($1.rate(channel)! * Double($1.intervalMS) / 60000) }
            func mean(_ f: (MinuteRecord) -> Double?) -> Double? {
                let v = g.compactMap(f); return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
            }
            out.append(RateBin(id: k, date: Date(timeIntervalSince1970: t0 + (Double(k) + 0.5) * width),
                               rate: counts / exposure, error: counts.squareRoot() / exposure, minutes: g.count,
                               pressure: mean(\.pressure), temperature: mean(\.temperature), altitude: mean(\.altitude), segment: segment))
        }
        return out
    }
}
