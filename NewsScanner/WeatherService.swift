import Foundation

// MARK: - Temperature alerts (graduated)

/// Heat threshold (°C). Heat is a single band; cold is graduated (see `ColdLevel`).
/// Evaluated in Celsius so the flag is independent of the unit the user sees.
enum ExtremeThreshold {
    static let hotC: Double = 35   // ≈ 95°F — extreme heat
}

/// Graduated cold-severity bands. A temperature at or below a band's `ceilingC`
/// falls into that band, and the *coldest* matching band wins. Thresholds and the
/// frostbite guidance follow Environment Canada wind-chill risk levels, so places
/// like the Canadian Prairies (down to ≈ -50°C) light up the most severe bands.
enum ColdLevel: Int, CaseIterable, Comparable {
    case cold = 1          // ≤  -6°C  (≈  21°F)
    case veryCold          // ≤ -18°C  (≈   0°F)
    case extremeCold       // ≤ -30°C  (≈ -22°F)
    case severeCold        // ≤ -40°C  (≈ -40°F)
    case lifeThreatening   // ≤ -48°C  (≈ -54°F)

    /// Highest temperature (°C) still inside this band.
    var ceilingC: Double {
        switch self {
        case .cold:            return -6
        case .veryCold:        return -18
        case .extremeCold:     return -30
        case .severeCold:      return -40
        case .lifeThreatening: return -48
        }
    }

    var title: String {
        switch self {
        case .cold:            return "Cold"
        case .veryCold:        return "Very cold"
        case .extremeCold:     return "Extreme cold"
        case .severeCold:      return "Severe cold"
        case .lifeThreatening: return "Life-threatening cold"
        }
    }

    var symbol: String {
        switch self {
        case .cold:                         return "thermometer.low"
        case .veryCold, .extremeCold:       return "thermometer.snowflake"
        case .severeCold, .lifeThreatening: return "snowflake"
        }
    }

    /// Frostbite-risk guidance, escalating with severity.
    var advice: String {
        switch self {
        case .cold:            return "Dress warmly — a light jacket isn't enough."
        case .veryCold:        return "Cover exposed skin; frostbite possible within 30 min."
        case .extremeCold:     return "Limit time outdoors; frostbite in 10–30 min."
        case .severeCold:      return "Frostbite in 5–10 min. Avoid going outside."
        case .lifeThreatening: return "Frostbite in under 5 min. Stay indoors."
        }
    }

    static func < (lhs: ColdLevel, rhs: ColdLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The coldest band `temperatureC` falls into, or nil if above the first ceiling.
    static func band(forC temperatureC: Double) -> ColdLevel? {
        allCases.last { temperatureC <= $0.ceilingC }
    }
}

/// A temperature alert surfaced to the UI: a single heat band, or a graduated
/// cold band. Equatable so the notifier can re-alert when the band escalates.
enum TempAlert: Equatable {
    case heat
    case cold(ColdLevel)

    var title: String {
        switch self {
        case .heat:            return "Extreme heat"
        case .cold(let level): return level.title
        }
    }

    var symbol: String {
        switch self {
        case .heat:            return "thermometer.sun.fill"
        case .cold(let level): return level.symbol
        }
    }

    var advice: String {
        switch self {
        case .heat:            return "Stay hydrated and limit time outdoors."
        case .cold(let level): return level.advice
        }
    }
}

// MARK: - Weather conditions (WMO code mapping)

/// A human-readable condition plus an SF Symbol, derived from a WMO weather code.
struct WeatherCondition {
    let text: String
    let symbol: String

    /// Maps an Open-Meteo / WMO weather code to a description and icon.
    /// `isDay` swaps day/night glyphs where it matters (clear sky).
    init(code: Int, isDay: Bool) {
        switch code {
        case 0:
            text = "Clear sky"
            symbol = isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:
            text = "Partly cloudy"
            symbol = isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:
            text = "Overcast"
            symbol = "cloud.fill"
        case 45, 48:
            text = "Fog"
            symbol = "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            text = "Drizzle"
            symbol = "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67:
            text = "Rain"
            symbol = "cloud.rain.fill"
        case 71, 73, 75, 77:
            text = "Snow"
            symbol = "cloud.snow.fill"
        case 80, 81, 82:
            text = "Rain showers"
            symbol = "cloud.heavyrain.fill"
        case 85, 86:
            text = "Snow showers"
            symbol = "cloud.snow.fill"
        case 95:
            text = "Thunderstorm"
            symbol = "cloud.bolt.rain.fill"
        case 96, 99:
            text = "Thunderstorm, hail"
            symbol = "cloud.bolt.rain.fill"
        default:
            text = "—"
            symbol = "thermometer.medium"
        }
    }
}

// MARK: - Current weather (display-ready model)

/// The current conditions for a location. Temperatures are stored in Celsius;
/// `TempFormat` handles locale-aware display.
struct CurrentWeather: Equatable {
    let temperatureC: Double
    let apparentC: Double
    let code: Int
    let isDay: Bool
    let windKmh: Double

    var condition: WeatherCondition { WeatherCondition(code: code, isDay: isDay) }

    /// Non-nil when the temperature crosses the heat or a graduated-cold threshold.
    var alert: TempAlert? {
        if temperatureC >= ExtremeThreshold.hotC { return .heat }
        if let band = ColdLevel.band(forC: temperatureC) { return .cold(band) }
        return nil
    }

    static func == (lhs: CurrentWeather, rhs: CurrentWeather) -> Bool {
        lhs.temperatureC == rhs.temperatureC && lhs.code == rhs.code
            && lhs.isDay == rhs.isDay
    }
}

// MARK: - Locale-aware temperature formatting

enum TempFormat {
    /// Display Fahrenheit in US-style locales, Celsius otherwise.
    static var useFahrenheit: Bool {
        Locale.current.measurementSystem == .us
    }

    /// e.g. "21°C" or "70°F".
    static func string(celsius: Double) -> String {
        let value = useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°\(useFahrenheit ? "F" : "C")"
    }

    static var unitSuffix: String { useFahrenheit ? "°F" : "°C" }
}

// MARK: - Open-Meteo fetch (free, keyless, on-device)

enum WeatherService {
    /// Fetches current conditions for a coordinate from Open-Meteo.
    /// Returns nil on any failure (network, parse). No API key required.
    static func fetch(lat: Double, lon: Double) async -> CurrentWeather? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current",
                         value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let c = decoded.current
            return CurrentWeather(
                temperatureC: c.temperature_2m,
                apparentC: c.apparent_temperature,
                code: c.weather_code,
                isDay: c.is_day == 1,
                windKmh: c.wind_speed_10m)
        } catch {
            return nil
        }
    }

    // Matches the Open-Meteo `current` block we requested.
    private struct OpenMeteoResponse: Decodable {
        let current: Current
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
            let wind_speed_10m: Double
        }
    }
}
