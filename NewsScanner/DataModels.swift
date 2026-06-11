import Foundation
import Combine

// MARK: - Caps (mirrors the extension's SEEN_CAP / RECENT_CAP)

enum Caps {
    static let seen = 500
    static let recent = 30
}

// MARK: - Per-topic recency filter

/// Time unit for a topic's "only show results newer than" window.
enum RecencyUnit: String, Codable, CaseIterable, Identifiable {
    case hours, days, weeks, months

    var id: String { rawValue }
    var singular: String { String(rawValue.dropLast()) }      // "hour", "day", …
    var plural: String { rawValue }                            // "hours", "days", …
    var abbrev: String {
        switch self {
        case .hours: return "h"
        case .days:  return "d"
        case .weeks: return "w"
        case .months: return "mo"
        }
    }
    var component: Calendar.Component {
        switch self {
        case .hours: return .hour
        case .days:  return .day
        case .weeks: return .weekOfYear
        case .months: return .month
        }
    }
}

/// A topic's recency window: show only articles published within the last
/// `value` × `unit`. Absence of a window (nil) means "all time".
struct RecencyWindow: Codable, Equatable, Hashable {
    var value: Int
    var unit: RecencyUnit

    /// Articles published at/after this cutoff are kept.
    func cutoff(now: Date = .now) -> Date? {
        Calendar.current.date(byAdding: unit.component, value: -value, to: now)
    }

    var shortLabel: String { "\(value)\(unit.abbrev)" }                       // "24h"
    var longLabel: String { "Past \(value) \(value == 1 ? unit.singular : unit.plural)" }

    /// Light, fixed presets spanning all four units (plus per-topic Custom).
    static let presets: [RecencyWindow] = [
        .init(value: 6, unit: .hours),
        .init(value: 12, unit: .hours),
        .init(value: 24, unit: .hours),
        .init(value: 3, unit: .days),
        .init(value: 7, unit: .days),
        .init(value: 2, unit: .weeks),
        .init(value: 1, unit: .months),
        .init(value: 3, unit: .months),
    ]
}

// MARK: - Plain on-device models (Codable — no database, no server)

/// A user-defined topic. Each becomes a Google News RSS query.
struct Topic: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var query: String
    var createdAt: Date = .now
    /// True until the topic's first scan completes. The first scan shows the
    /// existing articles in Recent matches (so results appear right away) and marks
    /// them seen, but doesn't notify — so the user isn't flooded with old news.
    var needsSeeding: Bool = true
    var isEnabled: Bool = true
    /// Non-nil for auto-managed "local news" topics (derived from the device's
    /// location at this scope). nil for normal user-entered topics. Hidden from the
    /// manual Topics list and reconciled by `LocalNewsManager`.
    var scope: LocationScope? = nil
    /// Optional per-topic recency filter for *display* (nil = show all time).
    var window: RecencyWindow? = nil
}

/// A genuinely new article surfaced to the user. Capped at `Caps.recent`.
struct RecentMatch: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var link: String
    var title: String
    var topicQuery: String
    var source: String?
    var publishedAt: Date?
    var matchedAt: Date = .now
    /// The scope of the local-news topic that surfaced this, or nil for a user topic.
    var scope: LocationScope? = nil

    var url: URL? { URL(string: link) }
}

extension Array where Element == RecentMatch {
    /// Newest published first, undated last (then by when we matched it).
    func sortedNewest() -> [RecentMatch] {
        sorted { lhs, rhs in
            switch (lhs.publishedAt, rhs.publishedAt) {
            case let (l?, r?): return l > r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return lhs.matchedAt > rhs.matchedAt
            }
        }
    }
}

/// An entry in the dedupe set. Capped at `Caps.seen`, oldest dropped first.
struct SeenLink: Codable, Equatable {
    var link: String
    var seenAt: Date = .now
}

// MARK: - On-device store

/// Holds all app data in memory and persists it to a single JSON file inside the
/// app's own sandbox (Application Support). Nothing leaves the device; there is no
/// database to connect to. Observable so SwiftUI views update live.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var topics: [Topic] = []
    @Published private(set) var recent: [RecentMatch] = []

    /// Dedupe set. Kept as an array for cap/ordering, plus a Set for O(1) lookup.
    private var seen: [SeenLink] = []
    private var seenIndex: Set<String> = []

    private let fileURL: URL

    // Snapshot persisted to disk.
    private struct Snapshot: Codable {
        var topics: [Topic]
        var recent: [RecentMatch]
        var seen: [SeenLink]
    }

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NewsScanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("store.json")
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        topics = snapshot.topics
        recent = snapshot.recent
        seen = snapshot.seen
        seenIndex = Set(seen.map { LinkKey.normalize($0.link) })
    }

    private func save() {
        let snapshot = Snapshot(topics: topics, recent: recent, seen: seen)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Topics

    func addTopic(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !topics.contains(where: { $0.query.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        topics.append(Topic(query: trimmed))
        save()
    }

    /// User-entered topics only (excludes auto-managed local-news topics).
    var userTopics: [Topic] { topics.filter { $0.scope == nil } }

    /// Recent matches from user topics, newest first.
    var topicMatches: [RecentMatch] { recent.filter { $0.scope == nil }.sortedNewest() }

    /// Recent matches for a single user topic, newest first, with the topic's
    /// recency window applied (if any).
    func matches(for topic: Topic) -> [RecentMatch] {
        let base = recent.filter { $0.scope == nil && $0.topicQuery == topic.query }
        return Self.within(topic.window, base).sortedNewest()
    }

    /// Keep only matches published within `window` (nil = keep all). Undated
    /// articles are dropped when a window is set, since recency can't be verified.
    static func within(_ window: RecencyWindow?, _ matches: [RecentMatch]) -> [RecentMatch] {
        guard let window, let cutoff = window.cutoff() else { return matches }
        return matches.filter { ($0.publishedAt ?? .distantPast) >= cutoff }
    }

    /// Recent matches from local-news scopes, newest first.
    var localMatches: [RecentMatch] { recent.filter { $0.scope != nil }.sortedNewest() }

    func removeTopics(ids: [UUID]) {
        topics.removeAll { ids.contains($0.id) }
        save()
    }

    func remove(_ topic: Topic) {
        topics.removeAll { $0.id == topic.id }
        save()
    }

    /// Reconcile the auto-managed local-news topics to match `desired` (one entry
    /// per enabled scope, with its current place query). Removes managed topics
    /// whose scope was turned off or whose place changed; adds any that are missing.
    /// User-entered topics are never touched.
    func syncLocalTopics(_ desired: [(scope: LocationScope, query: String)]) {
        let wanted = Dictionary(desired.map { ($0.scope, $0.query) },
                                uniquingKeysWith: { first, _ in first })

        topics.removeAll { topic in
            guard let scope = topic.scope else { return false }   // keep user topics
            return wanted[scope] != topic.query                   // stale → drop
        }

        for (scope, query) in wanted where !topics.contains(where: { $0.scope == scope }) {
            topics.append(Topic(query: query, scope: scope))
        }
        save()
    }

    func setEnabled(_ enabled: Bool, for topic: Topic) {
        guard let idx = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[idx].isEnabled = enabled
        save()
    }

    /// Set (or clear, with nil) a topic's per-topic recency filter.
    func setWindow(_ window: RecencyWindow?, for topic: Topic) {
        guard let idx = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[idx].window = window
        save()
    }

    // MARK: Dedupe set

    func isSeen(_ link: String) -> Bool { seenIndex.contains(LinkKey.normalize(link)) }

    func markSeen(_ link: String) {
        let key = LinkKey.normalize(link)
        guard !seenIndex.contains(key) else { return }
        seen.append(SeenLink(link: key))
        seenIndex.insert(key)
    }

    // MARK: Recent matches

    func addRecent(_ match: RecentMatch) {
        recent.append(match)
    }

    func clearRecent() {
        recent.removeAll()
        save()
    }

    // MARK: Used by ScanService

    /// Mutate `topics` in place by id (e.g. to clear `needsSeeding` after seeding).
    func updateTopic(id: UUID, _ mutate: (inout Topic) -> Void) {
        guard let idx = topics.firstIndex(where: { $0.id == id }) else { return }
        mutate(&topics[idx])
    }

    /// Trim seen/recent to caps (oldest first) and persist. Called at end of a scan.
    func enforceCapsAndSave() {
        if seen.count > Caps.seen {
            seen.sort { $0.seenAt < $1.seenAt }
            seen.removeFirst(seen.count - Caps.seen)
            seenIndex = Set(seen.map { LinkKey.normalize($0.link) })
        }
        // Cap recent matches per topic (grouped by query) so topics and local-news
        // scopes don't starve each other — each is surfaced as its own list.
        let grouped = Dictionary(grouping: recent, by: \.topicQuery)
        var capped: [RecentMatch] = []
        for (_, group) in grouped {
            if group.count > Caps.recent {
                capped += group.sorted { $0.matchedAt < $1.matchedAt }.suffix(Caps.recent)
            } else {
                capped += group
            }
        }
        if capped.count != recent.count { recent = capped }
        save()
    }
}
