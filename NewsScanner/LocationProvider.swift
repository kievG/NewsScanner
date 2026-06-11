import Foundation
import CoreLocation

/// A thin async wrapper over `CLLocationManager` for one-shot location fixes.
/// Keeps no history and stores nothing — consistent with the app's on-device,
/// no-database design. The delegate runs on the main run loop (the manager is
/// created on the main actor), so continuation handoff is single-threaded.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    /// Requests "when in use" authorization if undetermined; resolves with the
    /// resulting status. Returns the existing status immediately if already decided.
    func requestAuthorization() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Requests a single location fix. Resolves nil on failure.
    func requestLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            locContinuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate
    // These callbacks arrive on the main run loop (the manager was created on the
    // main actor), so `assumeIsolated` is safe and lets us touch isolated state.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard let continuation = authContinuation else { return }
            authContinuation = nil
            continuation.resume(returning: manager.authorizationStatus)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let continuation = locContinuation else { return }
            locContinuation = nil
            continuation.resume(returning: locations.last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            guard let continuation = locContinuation else { return }
            locContinuation = nil
            continuation.resume(returning: nil)
        }
    }
}
