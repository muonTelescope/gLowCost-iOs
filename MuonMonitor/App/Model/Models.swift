import Foundation
import SwiftData

@Model
final class Run {
    @Attribute(.unique) var id: UUID
    var name: String
    var detectorLabel: String?      // label currently on the detector / in the SD filename
    var deviceID: String?
    var start: Date
    var end: Date?
    var isLive: Bool
    var tags: [String]
    var notes: String
    var source: String              // "phone" or "sd"
    var sdFileName: String?
    var stationaryData: Data? = nil
    var exportedAt: Date?
    var exportFolder: String?       // folder name under cosmic/phone
    @Relationship(deleteRule: .cascade, inverse: \Minute.run) var minutes: [Minute] = []
    @Relationship(deleteRule: .cascade, inverse: \RunEvent.run) var events: [RunEvent] = []

    init(name: String, start: Date, source: String = "phone", tags: [String] = []) {
        id = UUID(); self.name = name; self.start = start; self.source = source; self.tags = tags
        isLive = false; notes = ""
    }

    var stationaryLocations: [StationaryLocation] {
        get { stationaryData.flatMap { try? JSONDecoder().decode([StationaryLocation].self, from: $0) } ?? [] }
        set { stationaryData = try? JSONEncoder().encode(newValue) }
    }
    var sortedMinutes: [Minute] { minutes.sorted { $0.epoch < $1.epoch } }
    var records: [MinuteRecord] { sortedMinutes.map(\.record) }
    var physicsMinutes: Int { minutes.filter(\.physics).count }
    var duration: TimeInterval { (end ?? minutes.map(\.epoch).max().map { Date(timeIntervalSince1970: $0) } ?? start).timeIntervalSince(start) }
    var meanRate: Double? {
        let v = minutes.filter(\.physics).compactMap { $0.record.rate(-1) }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
}

@Model
final class Minute {
    var epoch: Double
    var sequence: Int
    var bootID: String
    var intervalMS: Int
    var physics: Bool
    var counts: [Int]
    var temperature: Double?
    var pressure: Double?
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var horizontalAccuracy: Double?
    var fromSD: Bool
    var diagnosticData: Data? = nil
    var locationSyncedRevision: String? = nil
    var run: Run?

    init(_ r: MinuteRecord) {
        epoch = r.epoch; sequence = r.sequence; bootID = r.bootID; intervalMS = r.intervalMS; physics = r.physics
        counts = r.counts; temperature = r.temperature; pressure = r.pressure; latitude = r.latitude; longitude = r.longitude
        altitude = r.altitude; horizontalAccuracy = r.horizontalAccuracy; fromSD = r.fromSD
        diagnosticData = r.diagnostics.flatMap { try? JSONEncoder().encode($0) }
    }
    var diagnostics: [String: String] {
        get { diagnosticData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:] }
        set { diagnosticData = try? JSONEncoder().encode(newValue) }
    }
    var record: MinuteRecord {
        MinuteRecord(epoch: epoch, sequence: sequence, bootID: bootID, intervalMS: intervalMS, physics: physics, counts: counts,
                     temperature: temperature, pressure: pressure, latitude: latitude, longitude: longitude, altitude: altitude,
                     horizontalAccuracy: horizontalAccuracy, fromSD: fromSD, diagnostics: diagnosticData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) })
    }
}

/// Things that happened during a run, drawn as markers on the charts.
@Model
final class RunEvent {
    var date: Date
    var kind: String        // EventKind.rawValue
    var detail: String
    var run: Run?
    init(date: Date, kind: EventKind, detail: String) { self.date = date; self.kind = kind.rawValue; self.detail = detail }
    var eventKind: EventKind { EventKind(rawValue: kind) ?? .note }
}

enum EventKind: String, CaseIterable, Codable {
    case reboot, wifiOn, wifiOff, hvChange, settling, gap, sdFilled, sdProblem, jump, stuckZero, label, note
    var title: String {
        switch self {
        case .reboot: "Detector rebooted"
        case .wifiOn: "Wi‑Fi on"
        case .wifiOff: "Wi‑Fi off"
        case .hvChange: "High voltage changed"
        case .settling: "HV settling"
        case .gap: "Missed minutes"
        case .sdFilled: "Filled from SD card"
        case .sdProblem: "SD card problem"
        case .jump: "Sudden rate change"
        case .stuckZero: "No coincidences"
        case .label: "Renamed"
        case .note: "Note"
        }
    }
    var symbol: String {
        switch self {
        case .reboot: "arrow.clockwise"
        case .wifiOn, .wifiOff: "wifi"
        case .hvChange, .settling: "bolt"
        case .gap: "ellipsis"
        case .sdFilled: "sdcard"
        case .sdProblem: "exclamationmark.triangle"
        case .jump: "waveform.path.ecg"
        case .stuckZero: "0.circle"
        case .label: "pencil"
        case .note: "note.text"
        }
    }
}
