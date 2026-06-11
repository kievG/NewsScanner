import Foundation
import CoreLocation
import Combine

/// Orchestrates the weather feature: permission → location → reverse-geocode →
/// current conditions. Observable so the UI updates live. Holds results only in
/// memory (nothing persisted), matching the app's on-device design.
@MainActor
final class WeatherManager: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case denied          // user declined location access
        case unavailable     // restricted, or no fix / fetch failed
        case loaded
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var current: CurrentWeather?
    @Published private(set) var placeName: String?

    /// Remembers the last alert we notified about so we don't re-notify on every
    /// refresh while conditions persist. Resets when conditions normalize. Because
    /// `TempAlert` is Equatable, a *change* of band (e.g. very cold → severe cold)
    /// counts as new and re-alerts — so escalating cold escalates the notification.
    private var lastAlert: TempAlert?

    /// Full refresh. Safe to call repeatedly (e.g. on appear and on manual scan).
    func refresh() async {
        if current == nil { phase = .loading }

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
            // .notDetermined shouldn't persist after requestAuthorization, but guard anyway.
            phase = .denied
            return
        }

        guard let resolved = await LocationService.shared.resolve() else {
            // Keep any previously loaded data on screen; only show error if we have none.
            phase = current == nil ? .unavailable : .loaded
            return
        }

        placeName = Self.placeName(from: resolved.placemark)

        guard let weather = await WeatherService.fetch(
            lat: resolved.location.coordinate.latitude,
            lon: resolved.location.coordinate.longitude) else {
            phase = current == nil ? .unavailable : .loaded
            return
        }

        current = weather
        phase = .loaded
        maybeNotifyExtreme(weather)
    }

    // MARK: - Helpers

    private static func placeName(from mark: CLPlacemark?) -> String? {
        guard let mark else { return nil }
        return mark.locality ?? mark.administrativeArea ?? mark.country
    }

    /// Fires a local notification the first time an extreme reading appears (and
    /// again only after conditions return to normal in between). Gated on the
    /// user's "Flag extreme temperatures" setting.
    private func maybeNotifyExtreme(_ weather: CurrentWeather) {
        guard AppSettings.shared.flagExtremeTemps else { return }

        guard let alert = weather.alert else {
            lastAlert = nil
            return
        }
        guard alert != lastAlert else { return }
        lastAlert = alert

        let place = placeName ?? "your area"
        NotificationManager.shared.notify(
            title: "\(alert.title) in \(place)",
            body: "\(TempFormat.string(celsius: weather.temperatureC)) — \(alert.advice)",
            url: nil)
    }
}
