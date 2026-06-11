import Foundation
import CoreLocation
import Combine

// MARK: - Geographic scope

/// The level of locality a local-news scan targets. Broadens top → bottom.
enum LocationScope: String, CaseIterable, Identifiable, Codable {
    case community     // barangay / neighborhood (subLocality)
    case locality      // city / municipality / township
    case region        // region / province (administrativeArea)
    case country

    var id: String { rawValue }

    var label: String {
        switch self {
        case .community: return "Community"
        case .locality:  return "City / Municipality"
        case .region:    return "Region / Province"
        case .country:   return "Country"
        }
    }

    var symbol: String {
        switch self {
        case .community: return "house.fill"
        case .locality:  return "building.2.fill"
        case .region:    return "map.fill"
        case .country:   return "globe.americas.fill"
        }
    }
}

// MARK: - Resolved place

/// The names of the place the device is in, at each scope, from reverse geocoding.
struct PlaceContext: Equatable {
    var community: String?
    var locality: String?
    var region: String?
    var country: String?

    /// The name of just this level (for display under the toggle).
    func name(for scope: LocationScope) -> String? {
        switch scope {
        case .community: return community
        case .locality:  return locality
        case .region:    return region
        case .country:   return country
        }
    }

    /// The Google News query for this level, qualified with the next-broader name
    /// where available to cut down on ambiguous same-named places elsewhere.
    func query(for scope: LocationScope) -> String? {
        switch scope {
        case .community:
            guard let community else { return nil }
            return [community, locality].compactMap { $0 }.joined(separator: ", ")
        case .locality:
            guard let locality else { return nil }
            return [locality, region].compactMap { $0 }.joined(separator: ", ")
        case .region:
            return region
        case .country:
            return country
        }
    }
}

// MARK: - Local-news manager

/// Resolves the device's place and keeps a set of auto-managed "local" topics in
/// sync with the scopes the user enabled. Those topics ride the normal scan/seed/
/// dedupe pipeline, so local matches land in Recent matches like any other.
@MainActor
final class LocalNewsManager: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case denied
        case unavailable
        case loaded
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var place: PlaceContext?

    /// Resolve the place, then reconcile managed topics to the enabled scopes.
    func refresh() async {
        if place == nil { phase = .loading }

        let status = await LocationService.shared.requestAuthorization()
        switch status {
        case .denied:
            phase = .denied
            return
        case .restricted:
            phase = .unavailable
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            phase = .denied
            return
        }

        guard let resolved = await LocationService.shared.resolve(),
              let context = Self.placeContext(from: resolved.placemark) else {
            phase = place == nil ? .unavailable : .loaded
            return
        }

        place = context
        phase = .loaded
        syncTopics()
    }

    /// Called when the user toggles a scope. Ensures we have a place, reconciles
    /// the managed topics, then runs a scan so local results appear promptly.
    func applyScopeChange() async {
        if place == nil {
            await refresh()
        } else {
            syncTopics()
        }
        await ScanService.runScan()
    }

    // MARK: - Internals

    /// Reconcile Store's managed (scoped) topics with the user's enabled scopes and
    /// the currently-resolved place. Adds/updates/removes as needed.
    private func syncTopics() {
        guard let place else { return }
        let enabled = AppSettings.shared.localScopes
        let desired: [(scope: LocationScope, query: String)] =
            LocationScope.allCases
                .filter { enabled.contains($0) }
                .compactMap { scope in
                    place.query(for: scope).map { (scope, $0) }
                }
        Store.shared.syncLocalTopics(desired)
    }

    private static func placeContext(from mark: CLPlacemark?) -> PlaceContext? {
        guard let mark else { return nil }
        return PlaceContext(
            community: mark.subLocality,
            locality: mark.locality ?? mark.subAdministrativeArea,
            region: mark.administrativeArea,
            country: mark.country)
    }
}
