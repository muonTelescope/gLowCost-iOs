import Foundation

// Host tests: C/Swift wire compatibility plus the app's pure logic (no UI frameworks).
// Run with tests/run-host-tests.sh on a Mac.

// MARK: telemetry wire format
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let t = Telemetry(data: data) else { fatalError("C packet rejected") }
assert(t.bootID == 0xFEDCBA9876543210)
assert(t.sequence == 4000000000)
assert(t.totals[6] == (1 << 40) + 6)
assert(t.counts == [100, 101, 102, 103, 104, 105, 106])
assert(t.temperature == -12.345 && t.pressure == 982.86)
assert(Telemetry(data: data.prefix(159)) == nil)
var invalid = data; invalid[2] = 9; assert(Telemetry(data: invalid) == nil)
func put(_ b: inout Data, _ at: Int, _ v: UInt64, _ n: Int) { for i in 0..<n { b[at + i] = UInt8(truncatingIfNeeded: v >> (i * 8)) } }
var next = data
put(&next, 12, 4000000002, 4); put(&next, 16, 240000, 8); put(&next, 146, 240010, 8); put(&next, 24, 180000, 8)
for i in 0..<7 { put(&next, 56 + i * 8, (1 << 40) + UInt64(i) + 60, 8) }
let n = Telemetry(data: next)!, delta = n.delta(from: t)!
assert(delta.counts == Array(repeating: 60, count: 7) && delta.exposureMS == 120000)
assert(delta.coincidencesPerMinute == 90)
put(&next, 4, 123, 8); assert(Telemetry(data: next)!.delta(from: t) == nil)
assert(t.delta(from: t) == nil)
var setup = data; setup[3] = 1; let s = Telemetry(data: setup)!
assert(s.temperature == nil && s.pressure == nil)

// MARK: run label mirrors firmware sanitize_run_label()
assert(RunLabel.sanitize("External battery, roof") == "External_battery_roof")
assert(RunLabel.sanitize("  Wi‑Fi on!! ") == "WiFi_on")
assert(RunLabel.sanitize("a..b") == "a_b")
assert(RunLabel.sanitize(String(repeating: "x", count: 40)).count == 32)

// MARK: SD logs, both firmware generations
let old = """
epoch,iso,gpio6_p31,gpio5_p29,ch01_p13,ch02_p12,ch12_p11,gpio16_p36
1790260891,2026-09-24T14:41:31,379,193,13,193,22,2663
1790260951,2026-09-24T14:42:31,11,9,0,0,2,12
1790261011,2026-09-24T14:43:31,222,223,15,10,12,233
1790261071,2026-09-24T14:44:31,222,211,23,16,21,286
1790261131,2026-09-24T14:45:31,230,215,21,15,20,290
"""
let env = SDLog.parseEnv("epoch,iso,samples,temp_c_avg,pressure_hpa_avg,humidity_pct_avg\n1790261000,x,30,25.0,984.0,60\n1790261300,x,30,24.0,983.0,61\n")
let parsedOld = SDLog.parseMuon(old, fileName: "muon_20260924_144029_magnoliaUS-extBattery-wifiAuto.csv", env: env)
assert(parsedOld.label == "magnoliaUS-extBattery-wifiAuto")
assert(parsedOld.minutes.count == 5)
assert(parsedOld.minutes[3].counts == [23, 16, 21, -1, 222, 211, 286])     // mapped by header, not position
assert(!parsedOld.minutes[0].physics && !parsedOld.minutes[2].physics && parsedOld.minutes[3].physics)
assert(abs(parsedOld.minutes[3].pressure! - (984.0 - 71.0 / 300)) < 1e-9)   // interpolated from env
let newer = """
epoch,iso,ch01_p13,ch02_p12,ch12_p11,ch012_p22,gpio6_p31,gpio5_p29,gpio16_p36,sequence,uptime_ms,interval_ms,physics_valid,wifi_off,hv_settled,time_set,env_valid,temp_c,pressure_hpa
1790461167,2026-09-26T22:19:27,17,11,27,0,144,138,150,2,184256,60000,1,1,1,1,1,28.630,975.588
1790461227,2026-09-26T22:20:27,21,15,19,0,156,133,150,3,244267,60011,1,1,1,1,1,28.573,975.584
"""
let parsedNew = SDLog.parseMuon(newer, fileName: "muon_20260926_221634.csv")
assert(parsedNew.label == nil && parsedNew.minutes.count == 2 && parsedNew.minutes[1].sequence == 3)
assert(parsedNew.minutes[1].intervalMS == 60011 && parsedNew.minutes[1].pressure == 975.584 && parsedNew.minutes.allSatisfy(\.physics))
assert(SDLog.labelFromFileName("muon_20260924_144029_label_01.csv") == "label")

// MARK: gap filling
let phoneMinutes = [parsedNew.minutes[0]]
let fill = SDLog.missingMinutes(phone: phoneMinutes.map { var m = $0; m.epoch += 4; m.fromSD = false; return m }, sd: parsedNew.minutes)
assert(fill.count == 1 && fill[0].sequence == 3)

// MARK: health: Poisson-like counts give Fano ≈ 1
struct Seeded: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s } }
var g = Seeded(s: 42)   // deterministic, so the statistical assertions cannot flake
func poisson(_ mean: Double) -> Int { let l = exp(-mean); var k = 0; var p = 1.0; repeat { k += 1; p *= Double.random(in: 0..<1, using: &g) } while p > l; return k - 1 }
let clean = (0..<600).map { i in MinuteRecord(epoch: Double(i) * 60, sequence: i, bootID: "x", intervalMS: 60000, physics: true,
    counts: [poisson(21), poisson(15), i % 2 == 0 ? poisson(10) : poisson(40), 0, 0, 0, 0], temperature: nil, pressure: nil,
    latitude: nil, longitude: nil, altitude: nil, horizontalAccuracy: nil, fromSD: false) }
let report = Health.report(clean)
assert(report[0].level != .poor && report[1].level != .poor, "Poisson channels should look clean: \(report.map(\.fano))")
assert(report[2].level == .poor, "alternating rates should be flagged")
assert(!Health.isStuckAtZero(clean))

// MARK: binning and export
let bins = Binning.bins(clean, channel: 0, minutes: 30)
assert(bins.count == 20 && bins.allSatisfy { $0.minutes == 30 })
let csv = CSVExport.csv(Array(parsedNew.minutes))
assert(csv.hasPrefix("epoch,iso,sequence") && csv.split(separator: "\n").count == 3)
assert(CSVExport.folderName(start: Date(timeIntervalSince1970: 1790260829), name: "External battery") == "2026-09-24_1440_External-battery")

print("PASS: wire format, run labels, SD parsing (old/new), gap fill, health, binning, CSV export")
