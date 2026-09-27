import Foundation

/// An explicit user assertion, never a GPS observation or an interpolation.
struct StationaryLocation: Codable {
    var start: Double
    var end: Double
    var latitude: Double
    var longitude: Double

    func apply(to row: inout MinuteRecord) {
        guard row.latitude == nil, row.longitude == nil, (start...end).contains(row.epoch) else { return }
        row.latitude = latitude; row.longitude = longitude
        if row.diagnostics == nil { row.diagnostics = [:] }
        row.diagnostics?["location_source"] = "manual_stationary"
        row.diagnostics?["location_revision"] = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        row.diagnostics?["fix_epoch_ms"] = String(Int64(row.epoch * 1000))
    }
}
