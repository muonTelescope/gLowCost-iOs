import Foundation
import CoreLocation
import Observation

/// GPS while logging. Each detector minute takes the most recent fix if it is
/// less than two minutes old, so every minute carries its own position.
@Observable
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private(set) var latest: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var reducedAccuracy = false
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var running = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
    }

    var permissionText: String {
        switch authorization {
        case .authorizedAlways: reducedAccuracy ? "Always · approximate" : "Always · precise"
        case .authorizedWhenInUse: reducedAccuracy ? "While logging · approximate" : "While logging · precise"
        case .denied, .restricted: "Off"
        default: "Not asked yet"
        }
    }

    private struct SavedFix: Codable {
        let time: Double
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let horizontal: Double
        let vertical: Double
        var location: CLLocation {
            CLLocation(coordinate: .init(latitude: latitude, longitude: longitude), altitude: altitude,
                       horizontalAccuracy: horizontal, verticalAccuracy: vertical,
                       timestamp: Date(timeIntervalSince1970: time))
        }
    }
    private var fixes: [String: SavedFix] = [:]
    private var historyURL: URL?
    private var savedMinute: Int?

    func start(runID: UUID) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocationHistory", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            historyURL = directory.appendingPathComponent(runID.uuidString + ".json")
            fixes = historyURL.flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode([String: SavedFix].self, from: $0) } ?? [:]
        } catch { historyURL = nil; fixes = [:] }
        latest = nil; savedMinute = nil
        running = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { resume() }
    }
    func stop() { saveHistory(); running = false; manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false }
    func requestAlways() { manager.requestAlwaysAuthorization() }

    private func resume() {
        guard running else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        authorization = m.authorizationStatus
        reducedAccuracy = m.accuracyAuthorization == .reducedAccuracy
        resume()
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running else { return }
        for l in locations where l.horizontalAccuracy >= 0 {
            latest = l
            let minute = Int(l.timestamp.timeIntervalSince1970 / 60)
            fixes[String(minute)] = SavedFix(time: l.timestamp.timeIntervalSince1970,
                latitude: l.coordinate.latitude, longitude: l.coordinate.longitude, altitude: l.altitude,
                horizontal: l.horizontalAccuracy, vertical: l.verticalAccuracy)
            if savedMinute != minute { saveHistory(); savedMinute = minute }
        }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}

    private func saveHistory() {
        guard let historyURL, let data = try? JSONEncoder().encode(fixes) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    /// The fix to attach to a minute that ended at `date`.
    func fix(for date: Date) -> CLLocation? {
        let minute = Int(date.timeIntervalSince1970 / 60)
        let nearby = (minute-1...minute+1).compactMap { fixes[String($0)]?.location }
        return (nearby + (latest.map { [$0] } ?? []))
            .filter { abs($0.timestamp.timeIntervalSince(date)) < 120 }
            .min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
    }
}
