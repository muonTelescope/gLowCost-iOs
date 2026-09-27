import Foundation

/// The detector preserves observations separately from immutable measurement rows.
enum LocationSidecar {
    struct Entry {
        let boot: String
        let sequence: Int
        let revision: String
        let latitude: Double
        let longitude: Double
        let epochMS: String
        let accuracy: Double?
        let altitude: Double?
        let source: String
    }
    static func parse(_ text: String) -> [Entry] {
        let rows = SDLog.splitLines(text)
        guard let header = rows.first else { return [] }
        var entries: [String: Entry] = [:]
        for row in rows.dropFirst() {
            let v = Dictionary(zip(header, row), uniquingKeysWith: { _, last in last })
            guard let boot = v["boot_id"], UInt64(boot) != nil,
                  let sequence = Int(v["sequence"] ?? ""), sequence > 0,
                  let revision = v["revision"], revision.count == 32, revision.allSatisfy({ $0.isHexDigit }),
                  let lat = Double(v["latitude_e7"] ?? ""), lat.isFinite, abs(lat) <= 900000000,
                  let lon = Double(v["longitude_e7"] ?? ""), lon.isFinite, abs(lon) <= 1800000000,
                  let source = v["location_source"], ["gps", "manual_stationary"].contains(source) else { continue }
            let accuracy = Double(v["h_accuracy_cm"] ?? ""), altitude = Double(v["altitude_cm"] ?? "")
            entries[boot + "-" + String(sequence)] = Entry(boot: boot, sequence: sequence, revision: revision,
                latitude: lat / 1e7, longitude: lon / 1e7, epochMS: v["fix_epoch_ms"] ?? "0",
                accuracy: accuracy.flatMap { $0.isFinite && $0 >= 0 ? $0 / 100 : nil },
                altitude: altitude.flatMap { $0.isFinite && $0 > -100000000 ? $0 / 100 : nil }, source: source)
        }
        return Array(entries.values)
    }
}
