import Foundation
import SwiftData

/// `--demo` launch argument: synthetic, clearly labelled data for the Simulator
/// and screenshots. Never used by a normal launch.
extension AppModel {
    func loadDemo() {
        var rng = SystemRandomNumberGenerator()
        func poisson(_ mean: Double) -> Int {           // Knuth, fine for small means
            let l = exp(-mean); var k = 0; var p = 1.0
            repeat { k += 1; p *= Double.random(in: 0..<1, using: &rng) } while p > l
            return k - 1
        }
        let now = Date().timeIntervalSince1970
        // A stationary 18-hour run, like the Sep 24 external-battery run.
        let run = Run(name: "External battery (demo)", start: Date(timeIntervalSince1970: now - 1064 * 60))
        run.tags = ["Power bank", "Wi‑Fi auto-off", "Indoors"]; run.isLive = true; run.detectorLabel = "demo"
        context.insert(run)
        var records: [MinuteRecord] = []
        for i in 0..<1064 {
            let t = now - Double(1064 - i) * 60
            if (700...701).contains(i) { continue }         // a 2-minute gap the phone "missed"
            let phase = Double(i) / 1064 * 2 * .pi
            records.append(MinuteRecord(epoch: t, sequence: i + 1, bootID: "demo", intervalMS: 60_000, physics: i >= 3,
                                        counts: [poisson(20.9), poisson(15.0), poisson(21.1), 0, poisson(430), poisson(400), poisson(495)],
                                        temperature: 24.6 + 0.5 * sin(phase * 1.3), pressure: 983.1 + 1.2 * cos(phase),
                                        latitude: 30.2100 + Double.random(in: -0.00005...0.00005), longitude: -95.7500 + Double.random(in: -0.00005...0.00005),
                                        altitude: 60, horizontalAccuracy: 5, fromSD: false))
        }
        for r in records { let m = Minute(r); context.insert(m); m.run = run }
        let e1 = RunEvent(date: Date(timeIntervalSince1970: now - 1062 * 60), kind: .wifiOff, detail: "Wi‑Fi switched off for quiet counting."); context.insert(e1); e1.run = run
        let e2 = RunEvent(date: Date(timeIntervalSince1970: now - 363 * 60), kind: .gap, detail: "2 minutes not received by the phone."); context.insert(e2); e2.run = run

        // A short moving run, to show the GPS track and altitude.
        let flight = Run(name: "Drive up the hill (demo)", start: Date(timeIntervalSince1970: now - 86_400 * 3))
        flight.end = Date(timeIntervalSince1970: now - 86_400 * 3 + 120 * 60); flight.tags = ["Vehicle", "Power bank"]
        context.insert(flight)
        for i in 0..<120 {
            let f = Double(i) / 119
            let alt = 100 + 2400 * sin(f * .pi)
            let rate = 57 * exp(alt / 4500)                   // illustrative altitude scaling only
            let r = MinuteRecord(epoch: flight.start.timeIntervalSince1970 + Double(i + 1) * 60, sequence: i + 1, bootID: "demo2", intervalMS: 60_000,
                                 physics: true, counts: [poisson(rate * 0.37), poisson(rate * 0.26), poisson(rate * 0.37), 0, 400, 380, 470],
                                 temperature: 22, pressure: 1000 * exp(-alt / 8400), latitude: 30.21 + f * 0.25, longitude: -95.75 + 0.1 * sin(f * 6),
                                 altitude: alt, horizontalAccuracy: 8, fromSD: false)
            let m = Minute(r); context.insert(m); m.run = flight
        }
        try? context.save()
        currentRun = run
        recent = Array(records.suffix(240)); lastMinuteEnd = recent.last?.date; lastSeen = Date().addingTimeInterval(-14); phase = .physics
    }
}
