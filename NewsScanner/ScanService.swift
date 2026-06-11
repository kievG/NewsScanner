import Foundation

/// The core scan loop, ported from the extension's `background.js`:
/// fetch each enabled topic, dedupe against the seen set, sort, surface genuinely
/// new articles (notify), and silently seed a topic's backlog on its first scan.
///
/// Operates entirely on the on-device `Store` — no database, no server.
@MainActor
enum ScanService {

    /// Runs one full scan across all enabled topics.
    /// - Returns: the number of genuinely new articles surfaced.
    @discardableResult
    static func runScan() async -> Int {
        let store = Store.shared
        let enabled = store.topics.filter { $0.isEnabled }
        guard !enabled.isEmpty else {
            AppSettings.shared.lastScan = .now
            return 0
        }

        var newlySurfaced: [RecentMatch] = []

        for topic in enabled {
            guard let url = FeedURLBuilder.url(for: topic.query) else { continue }
            let items = await FeedService.fetch(url: url)
            guard !items.isEmpty else { continue }

            // Sort newest-published first, undated last (mirrors the extension).
            let sorted = items.sorted { lhs, rhs in
                switch (lhs.pubDate, rhs.pubDate) {
                case let (l?, r?): return l > r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return false
                }
            }

            // First scan of a topic: show the current articles in Recent right away
            // (up to the cap) and mark everything seen — but DON'T notify. Adding a
            // topic shouldn't fire a burst of alerts for news that already existed.
            if topic.needsSeeding {
                for item in sorted { store.markSeen(item.link) }
                for item in sorted.prefix(Caps.recent) {
                    store.addRecent(RecentMatch(
                        link: item.link,
                        title: item.title,
                        topicQuery: topic.query,
                        source: item.source,
                        publishedAt: item.pubDate,
                        scope: topic.scope))
                }
                store.updateTopic(id: topic.id) { $0.needsSeeding = false }
                continue
            }

            for item in sorted where !store.isSeen(item.link) {
                store.markSeen(item.link)
                let match = RecentMatch(
                    link: item.link,
                    title: item.title,
                    topicQuery: topic.query,
                    source: item.source,
                    publishedAt: item.pubDate,
                    scope: topic.scope)
                store.addRecent(match)
                newlySurfaced.append(match)
            }
        }

        store.enforceCapsAndSave()

        // Notify after persisting, newest first.
        for match in newlySurfaced.sorted(by: {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }) {
            NotificationManager.shared.notify(
                title: match.title,
                body: notificationBody(for: match),
                url: match.url)
        }

        AppSettings.shared.lastScan = .now
        return newlySurfaced.count
    }

    private static func notificationBody(for match: RecentMatch) -> String {
        if let source = match.source, !source.isEmpty {
            return "\(match.topicQuery) · \(source)"
        }
        return match.topicQuery
    }
}
