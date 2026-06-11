import SwiftUI

/// The "Weather" section rendered inside ContentView's List: current conditions
/// for the device location, an extreme-temperature banner, and the flag toggle.
struct WeatherSection: View {
    @ObservedObject var weather: WeatherManager
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Section {
            content
            Toggle("Flag extreme temperatures", isOn: $settings.flagExtremeTemps)
        } header: {
            Text("Weather")
        } footer: {
            // Open-Meteo is CC BY 4.0 — attribution required.
            Text("Weather by Open‑Meteo (CC BY 4.0)")
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch weather.phase {
            case .loading where weather.current == nil:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Fetching weather…").foregroundStyle(.secondary)
                }

            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Location access is off")
                    Text("Enable location to see your local temperature and weather.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open Settings", action: openSettings)
                        .font(.footnote)
                }

            case .unavailable where weather.current == nil:
                Text("Weather unavailable. Pull to refresh or tap the refresh button.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)

            default:
                if let alert = weather.current?.alert, settings.flagExtremeTemps {
                    alertBanner(alert)
                }
                if let current = weather.current {
                    weatherRow(current)
                }
            }
        }
    }

    // MARK: - Rows

    private func weatherRow(_ current: CurrentWeather) -> some View {
        HStack(spacing: 16) {
            Image(systemName: current.condition.symbol)
                .font(.system(size: 38))
                .symbolRenderingMode(.multicolor)
                .frame(width: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(weather.placeName ?? "Current location")
                    .font(.headline)
                Text(current.condition.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Feels \(TempFormat.string(celsius: current.apparentC)) · Wind \(Int(current.windKmh.rounded())) km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(TempFormat.string(celsius: current.temperatureC))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(current.alert.map(tint(for:)) ?? .primary)
        }
        .padding(.vertical, 4)
    }

    private func alertBanner(_ alert: TempAlert) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.symbol)
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(alert.advice)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            // Graduated cold shows where this reading sits on the 5-band scale.
            if case .cold(let level) = alert {
                severityGauge(level)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint(for: alert), in: RoundedRectangle(cornerRadius: 12))
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }

    private func severityGauge(_ level: ColdLevel) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("LEVEL \(level.rawValue)/\(ColdLevel.allCases.count)")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.95))
            HStack(spacing: 3) {
                ForEach(ColdLevel.allCases, id: \.self) { band in
                    Circle()
                        .fill(.white.opacity(band <= level ? 1 : 0.3))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }

    // MARK: - Styling

    /// Heat is red; cold ramps from blue through indigo to near-black as it worsens.
    private func tint(for alert: TempAlert) -> Color {
        switch alert {
        case .heat:
            return .red
        case .cold(let level):
            switch level {
            case .cold:            return .blue
            case .veryCold:        return Color(red: 0.00, green: 0.30, blue: 0.70)
            case .extremeCold:     return .indigo
            case .severeCold:      return Color(red: 0.36, green: 0.00, blue: 0.60)
            case .lifeThreatening: return Color(red: 0.12, green: 0.12, blue: 0.22)
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
