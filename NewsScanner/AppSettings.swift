import Foundation
import Combine

/// Scan schedule presets, mirroring the extension's dropdown:
/// every 1 min / 5 min / 1 hr / daily at a set time / custom interval.
enum SchedulePreset: String, CaseIterable, Identifiable, Codable {
    case oneMinute
    case fiveMinutes
    case oneHour
    case daily
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneMinute:   return "Every 1 minute"
        case .fiveMinutes: return "Every 5 minutes"
        case .oneHour:     return "Every hour"
        case .daily:       return "Daily at a set time"
        case .custom:      return "Custom interval"
        }
    }
}

/// User settings, persisted to UserDefaults. Observable so views update live.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let preset = "schedule.preset"
        static let dailyHour = "schedule.dailyHour"
        static let dailyMinute = "schedule.dailyMinute"
        static let customMinutes = "schedule.customMinutes"
        static let lastScan = "scan.lastScan"
        static let flagExtremeTemps = "weather.flagExtremeTemps"
        static let localScopes = "localnews.scopes"
        static let resultsPerSection = "display.resultsPerSection"
    }

    /// How many matches each section shows before "View all" (clamped 1…3).
    static let minResults = 1
    static let maxResults = 3

    @Published var preset: SchedulePreset {
        didSet { defaults.set(preset.rawValue, forKey: Key.preset) }
    }
    @Published var dailyHour: Int {
        didSet { defaults.set(dailyHour, forKey: Key.dailyHour) }
    }
    @Published var dailyMinute: Int {
        didSet { defaults.set(dailyMinute, forKey: Key.dailyMinute) }
    }
    @Published var customMinutes: Int {
        didSet { defaults.set(max(1, customMinutes), forKey: Key.customMinutes) }
    }
    @Published var lastScan: Date? {
        didSet { defaults.set(lastScan?.timeIntervalSince1970 ?? 0, forKey: Key.lastScan) }
    }
    /// When on, an extreme reading shows a banner and posts a one-off notification.
    @Published var flagExtremeTemps: Bool {
        didSet { defaults.set(flagExtremeTemps, forKey: Key.flagExtremeTemps) }
    }
    /// Geographic levels the user wants local news for (empty = local news off).
    @Published var localScopes: Set<LocationScope> {
        didSet { defaults.set(localScopes.map(\.rawValue), forKey: Key.localScopes) }
    }
    /// Inline matches shown per section before "View all" (1…3).
    @Published var resultsPerSection: Int {
        didSet {
            let clamped = min(Self.maxResults, max(Self.minResults, resultsPerSection))
            if clamped != resultsPerSection { resultsPerSection = clamped; return }
            defaults.set(resultsPerSection, forKey: Key.resultsPerSection)
        }
    }

    private init() {
        self.preset = SchedulePreset(rawValue: defaults.string(forKey: Key.preset) ?? "")
            ?? .fiveMinutes
        self.dailyHour = defaults.object(forKey: Key.dailyHour) as? Int ?? 9
        self.dailyMinute = defaults.object(forKey: Key.dailyMinute) as? Int ?? 0
        self.customMinutes = defaults.object(forKey: Key.customMinutes) as? Int ?? 15
        let ts = defaults.double(forKey: Key.lastScan)
        self.lastScan = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        self.flagExtremeTemps = defaults.object(forKey: Key.flagExtremeTemps) as? Bool ?? true
        let scopeRaw = defaults.stringArray(forKey: Key.localScopes) ?? []
        self.localScopes = Set(scopeRaw.compactMap(LocationScope.init(rawValue:)))
        self.resultsPerSection = defaults.object(forKey: Key.resultsPerSection) as? Int ?? Self.maxResults
    }

    /// The requested interval in seconds. Used for the in-app foreground timer and
    /// as the `earliestBeginDate` hint for background refresh.
    ///
    /// Note: on iOS, intervals shorter than ~15 min are honored only while the app
    /// is in the foreground. In the background, `BGAppRefreshTask` is opportunistic —
    /// the system decides when (see APPLE_APP_PORT.md §2).
    var interval: TimeInterval {
        switch preset {
        case .oneMinute:   return 60
        case .fiveMinutes: return 300
        case .oneHour:     return 3600
        case .custom:      return TimeInterval(max(1, customMinutes) * 60)
        case .daily:       return secondsUntilNextDaily()
        }
    }

    private func secondsUntilNextDaily(now: Date = .now) -> TimeInterval {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.hour = dailyHour
        comps.minute = dailyMinute
        let next = cal.nextDate(after: now,
                                matching: comps,
                                matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        return max(60, next.timeIntervalSince(now))
    }
}

/// Drives in-app presentation of an article URL (e.g. from a tapped notification).
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var pendingURL: URL?
    private init() {}
}
