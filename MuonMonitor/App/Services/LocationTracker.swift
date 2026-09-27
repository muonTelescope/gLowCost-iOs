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
        manager.distanceFilter = 5
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

    func start() {
        running = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { resume() }
    }
    func stop() { running = false; manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false }
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
        if let l = locations.last, l.horizontalAccuracy >= 0 { latest = l }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}

    /// The fix to attach to a minute that ended at `date`.
    func fix(for date: Date) -> CLLocation? {
        guard let l = latest, abs(l.timestamp.timeIntervalSince(date)) < 120 else { return nil }
        return l
    }
}
