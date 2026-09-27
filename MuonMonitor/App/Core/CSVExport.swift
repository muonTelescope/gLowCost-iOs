import Foundation

/// Writes the phone's copy of a run in a CSV that sits comfortably next to the
/// detector's own SD logs: raw counts, no corrections, environment and GPS per minute.
enum CSVExport {
    static let header = "epoch,iso,sequence,boot_id,interval_ms,physics_valid,ch01_p13,ch02_p12,ch12_p11,ch012_p22,gpio6_p31,gpio5_p29,gpio16_p36,temp_c,pressure_hpa,latitude,longitude,altitude_m,h_accuracy_m,source\n"

    static func csv(_ minutes: [MinuteRecord]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var s = header
        s.reserveCapacity(minutes.count * 120)
        for m in minutes.sorted(by: { $0.epoch < $1.epoch }) {
            func f(_ v: Double?, _ digits: Int) -> String { v.map { String(format: "%.\(digits)f", $0) } ?? "" }
            let counts = (0..<7).map { m.counts.indices.contains($0) && m.counts[$0] >= 0 ? String(m.counts[$0]) : "" }
            let fields: [String] = [
                String(Int(m.epoch.rounded())), iso.string(from: m.date), m.sequence >= 0 ? String(m.sequence) : "", m.bootID,
                String(m.intervalMS), m.physics ? "1" : "0",
            ] + counts + [
                f(m.temperature, 3), f(m.pressure, 3), f(m.latitude, 6), f(m.longitude, 6), f(m.altitude, 1), f(m.horizontalAccuracy, 1),
                m.fromSD ? "sd" : "phone",
            ]
            s += fields.joined(separator: ",") + "\n"
        }
        return s
    }

    /// Folder-safe name: 2026-09-24_1440_External-battery
    static func folderName(start: Date, name: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd_HHmm"
        let clean = RunLabel.sanitize(name.replacingOccurrences(of: "_", with: "-")).replacingOccurrences(of: "_", with: "-")
        return f.string(from: start) + (clean.isEmpty ? "" : "_" + clean)
    }
}
