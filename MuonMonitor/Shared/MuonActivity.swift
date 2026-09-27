import ActivityKit
import Foundation

struct MuonActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: Phase
        var runName: String
        var pairs: [Int]            // CH01, CH02, CH12 for the last completed minute
        var recent: [Int]           // last 30 minute totals, oldest first; -1 = missed/setup minute
        var temperature: Double?
        var pressure: Double?
        var sampleDate: Date?       // end of the last completed minute
        var setupEnds: Date?        // Wi‑Fi auto-off / first physics minute estimate
        var loggingSince: Date

        var total: Int? { pairs.count == 3 ? pairs.reduce(0, +) : nil }
        static func waiting(_ name: String, since: Date) -> Self {
            .init(phase: .searching, runName: name, pairs: [], recent: [], sampleDate: nil, setupEnds: nil, loggingSince: since)
        }
    }
    var detectorName: String = "MuonP4"
}
