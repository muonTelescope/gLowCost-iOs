import Foundation

/// Parses detector SD-card logs (muon_*.csv and env_*.csv) from every firmware
/// generation seen so far. Column order changed between versions, so columns
/// are always located by header name.
enum SDLog {
    struct EnvRow: Equatable { var epoch: Double; var temperature: Double; var pressure: Double; var humidity: Double? }

    struct ParseResult {
        var minutes: [MinuteRecord]
        var label: String?          // label parsed from the file name, if any
        var startEpoch: Double?
        var hasValidityColumn: Bool
    }

    /// Channel order used everywhere in the app → header names in the SD file.
    static let channelHeaders = ["ch01_p13", "ch02_p12", "ch12_p11", "ch012_p22", "gpio6_p31", "gpio5_p29", "gpio16_p36"]

    static func splitLines(_ text: String) -> [[String]] {
        text.split(whereSeparator: \.isNewline).map { $0.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) } }
    }

    static func parseEnv(_ text: String) -> [EnvRow] {
        let rows = splitLines(text)
        guard let header = rows.first else { return [] }
        func idx(_ n: String) -> Int? { header.firstIndex(of: n) }
        guard let e = idx("epoch"), let t = idx("temp_c_avg"), let p = idx("pressure_hpa_avg") else { return [] }
        let h = idx("humidity_pct_avg")
        return rows.dropFirst().compactMap { r in
            guard r.count > max(e, t, p), let ep = Double(r[e]), ep > 1.6e9, let tv = Double(r[t]), let pv = Double(r[p]) else { return nil }
            return EnvRow(epoch: ep, temperature: tv, pressure: pv, humidity: h.flatMap { r.count > $0 ? Double(r[$0]) : nil })
        }.sorted { $0.epoch < $1.epoch }
    }

    /// Linear interpolation of the 5-minute environment averages; allows 330 s past either end.
    static func interpolate(_ env: [EnvRow], at epoch: Double) -> (t: Double, p: Double)? {
        guard let first = env.first, let last = env.last else { return nil }
        if epoch < first.epoch - 330 || epoch > last.epoch + 330 { return nil }
        if epoch <= first.epoch { return (first.temperature, first.pressure) }
        if epoch >= last.epoch { return (last.temperature, last.pressure) }
        var lo = 0, hi = env.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if env[m].epoch <= epoch { lo = m } else { hi = m } }
        let a = env[lo], b = env[hi], f = (epoch - a.epoch) / (b.epoch - a.epoch)
        return (a.temperature + (b.temperature - a.temperature) * f, a.pressure + (b.pressure - a.pressure) * f)
    }

    /// Parses a muon CSV. Older firmware has no validity/interval columns: the
    /// first three minutes (Wi-Fi setup and HV cycling) and any interval outside
    /// 59–62 s are then marked non-physics.
    static func parseMuon(_ text: String, fileName: String, env: [EnvRow] = []) -> ParseResult {
        let rows = splitLines(text)
        guard let header = rows.first, let e = header.firstIndex(of: "epoch") else {
            return ParseResult(minutes: [], label: labelFromFileName(fileName), startEpoch: nil, hasValidityColumn: false)
        }
        func idx(_ n: String) -> Int? { header.firstIndex(of: n) }
        let chIdx = channelHeaders.map { idx($0) }
        let seq = idx("sequence"), interval = idx("interval_ms"), valid = idx("physics_valid")
        let temp = idx("temp_c"), press = idx("pressure_hpa")
        var out: [MinuteRecord] = []
        var previousEpoch: Double?
        var index = 0
        for r in rows.dropFirst() {
            guard r.count > e, let epoch = Double(r[e]) else { continue }
            defer { index += 1 }
            guard epoch > 1.6e9 else { previousEpoch = nil; continue }   // unsynced clock rows cannot be placed in time
            func int(_ i: Int?) -> Int? { guard let i, r.count > i else { return nil }; return Int(r[i]) }
            func dbl(_ i: Int?) -> Double? { guard let i, r.count > i, !r[i].isEmpty else { return nil }; return Double(r[i]) }
            let counts = chIdx.map { int($0) ?? -1 }
            let dt = previousEpoch.map { epoch - $0 }
            let intervalMS = int(interval) ?? Int(((dt ?? 60) * 1000).rounded())
            var physics: Bool
            if let v = int(valid) { physics = v == 1 } else { physics = index >= 3 && (59_000...62_000).contains(intervalMS) }
            var t = dbl(temp), p = dbl(press)
            if p == nil, let env = interpolate(env, at: epoch) { t = env.t; p = env.p }
            out.append(MinuteRecord(epoch: epoch, sequence: int(seq) ?? -1, bootID: "", intervalMS: intervalMS, physics: physics,
                                    counts: counts, temperature: t, pressure: p, latitude: nil, longitude: nil, altitude: nil,
                                    horizontalAccuracy: nil, fromSD: true))
            previousEpoch = epoch
        }
        // Older files: flag isolated outliers (e.g. a 0-count minute during an HV transition) as non-physics.
        if valid == nil { markOutliers(&out) }
        return ParseResult(minutes: out, label: labelFromFileName(fileName), startEpoch: out.first?.epoch, hasValidityColumn: valid != nil)
    }

    static func markOutliers(_ m: inout [MinuteRecord]) {
        let totals = m.map { $0.coincidences }
        for i in m.indices where m[i].physics {
            let w = Array(totals[max(0, i - 15)...min(totals.count - 1, i + 15)]).sorted()
            let med = Double(w[w.count / 2])
            if abs(Double(totals[i]) - med) > 6 * max(1, med).squareRoot() { m[i].physics = false }
        }
    }

    /// muon_20260924_144029_magnoliaUS-extBattery-wifiAuto.csv → "magnoliaUS-extBattery-wifiAuto"
    static func labelFromFileName(_ name: String) -> String? {
        let stem = (name as NSString).deletingPathExtension
        let parts = stem.split(separator: "_").map(String.init)
        guard parts.count > 3, parts[0] == "muon" || parts[0] == "env" else { return nil }
        var rest = Array(parts.dropFirst(3))
        if parts[1] == "unsynced" { rest = Array(parts.dropFirst(2)) }
        if let last = rest.last, last.count == 2, Int(last) != nil { rest.removeLast() } // collision suffix _01
        let label = rest.joined(separator: "_")
        return label.isEmpty ? nil : label
    }

    /// Fills gaps in a phone-recorded run with SD minutes. A phone minute and an
    /// SD minute are the same minute when their end times are within 20 s.
    /// Returns only the SD minutes that were missing.
    static func missingMinutes(phone: [MinuteRecord], sd: [MinuteRecord]) -> [MinuteRecord] {
        let have = phone.map(\.epoch).sorted()
        guard let lo = have.first, let hi = have.last else { return sd }
        return sd.filter { s in
            guard s.epoch >= lo - 90, s.epoch <= hi + 90 else { return false }
            var a = 0, b = have.count - 1
            while b - a > 1 { let m = (a + b) / 2; if have[m] <= s.epoch { a = m } else { b = m } }
            return min(abs(have[a] - s.epoch), abs(have[b] - s.epoch)) > 20
        }
    }
}
