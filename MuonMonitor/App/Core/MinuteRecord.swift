import Foundation

/// One completed detector minute, independent of storage. Counts are raw and
/// never corrected; temperature and pressure travel alongside them.
struct MinuteRecord: Codable, Equatable, Sendable {
    var epoch: Double            // sample end, Unix seconds (phone clock if the detector clock was unset)
    var sequence: Int            // detector completed-minute sequence, -1 if unknown (older SD files)
    var bootID: String           // detector boot/session id, "" if unknown
    var intervalMS: Int          // actual integration time
    var physics: Bool            // physics-valid minute
    var counts: [Int]            // CH01, CH02, CH12, CH012, GPIO6, GPIO5, GPIO16 (-1 = not recorded)
    var temperature: Double?
    var pressure: Double?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var horizontalAccuracy: Double?
    var fromSD: Bool
    var diagnostics: [String: String]? = nil

    static let channelNames = ["CH01", "CH02", "CH12", "CH012", "GPIO6", "GPIO5", "GPIO16"]

    /// Sum of the three pair coincidences (the headline number).
    var coincidences: Int { counts.prefix(3).reduce(0) { $0 + max($1, 0) } }
    /// Counts per minute for a channel (-1 = sum of pairs), using the real interval.
    func rate(_ channel: Int) -> Double? {
        guard intervalMS > 0 else { return nil }
        let n = channel < 0 ? coincidences : (counts.indices.contains(channel) ? counts[channel] : -1)
        guard n >= 0 else { return nil }
        return Double(n) * 60000 / Double(intervalMS)
    }
    var date: Date { Date(timeIntervalSince1970: epoch) }
}

/// Mirrors the firmware's sanitize_run_label() so the app can show the exact
/// SD filename label before sending it.
enum RunLabel {
    static let maxLength = 32
    static func sanitize(_ input: String) -> String {
        var out: [Character] = []
        for scalar in input.unicodeScalars {
            if out.count >= maxLength { break }
            let c = Character(scalar)
            if scalar.isASCII, (c.isLetter || c.isNumber || c == "-" || c == "_") {
                out.append(c)
            } else if (c == " " || c == "." || c == ","), let last = out.last, last != "_" {
                out.append("_")
            }
        }
        while out.last == "_" { out.removeLast() }
        return String(out)
    }
}
