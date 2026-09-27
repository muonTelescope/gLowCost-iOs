import Foundation

/// Detect missing intervals without treating setup/settling minutes as missing data.
enum RunRecovery {
    static func hasGap(_ records: [MinuteRecord]) -> Bool {
        let sorted = records.sorted { $0.epoch < $1.epoch }
        return zip(sorted, sorted.dropFirst()).contains { a, b in
            if !a.bootID.isEmpty, a.bootID == b.bootID, a.sequence >= 0, b.sequence >= 0 {
                return b.sequence > a.sequence + 1
            }
            return b.epoch - a.epoch > max(90, Double(b.intervalMS) / 1000 + 30)
        }
    }
    static func series(_ records: [MinuteRecord], count: Int, value: (MinuteRecord) -> Int) -> [Int] {
        guard count > 0, let end = records.map(\.epoch).max() else { return [] }
        var result = Array(repeating: -1, count: count)
        for r in records.sorted(by: { $0.epoch < $1.epoch }) where r.physics {
            let index = count - 1 - Int(((end - r.epoch) / 60).rounded())
            if result.indices.contains(index) { result[index] = max(value(r), 0) }
        }
        return result
    }
}
