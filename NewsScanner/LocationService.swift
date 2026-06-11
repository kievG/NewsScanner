import Foundation
import CoreLocation

/// A single shared entry point for "where is the device, and what place is that".
///
/// Both the weather and local-news features need the same one-shot fix and reverse
/// geocode. Before this, each owned its own `LocationProvider` + `CLGeocoder`, so a
/// launch fired two location requests and two geocodes for the same coordinate.
/// This service coalesces concurrent callers into one request and caches the result
/// briefly, so the work happens once.
@MainActor
final class LocationService {
    static let shared = LocationService()

    /// A resolved fix plus its reverse-geocoded placemark.
    struct Resolved {
        let location: CLLocation
        let placemark: CLPlacemark?
    }

    private let provider = LocationProvider()
    private let geocoder = CLGeocoder()

    private var cached: (resolved: Resolved, at: Date)?
    private var inFlight: Task<Resolved?, Never>?
    private var authTask: Task<CLAuthorizationStatus, Never>?

    private init() {}

    var authorizationStatus: CLAuthorizationStatus { provider.status }

    /// Request "when in use" authorization, coalescing concurrent callers so the
    /// provider's single continuation isn't clobbered by a second simultaneous call.
    func requestAuthorization() async -> CLAuthorizationStatus {
        if provider.status != .notDetermined { return provider.status }
        if let authTask { return await authTask.value }
        let task = Task { await provider.requestAuthorization() }
        authTask = task
        let status = await task.value
        authTask = nil
        return status
    }

    /// One-shot resolve (location + placemark). Reuses a fix younger than `maxAge`,
    /// and coalesces concurrent callers onto a single in-flight request + geocode.
    func resolve(maxAge: TimeInterval = 120) async -> Resolved? {
        if let cached, Date().timeIntervalSince(cached.at) < maxAge {
            return cached.resolved
        }
        if let inFlight { return await inFlight.value }

        let task = Task { () -> Resolved? in
            guard let location = await provider.requestLocation() else { return nil }
            let placemark = (try? await geocoder.reverseGeocodeLocation(location))?.first
            return Resolved(location: location, placemark: placemark)
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        if let result { cached = (result, Date()) }
        return result
    }
}
