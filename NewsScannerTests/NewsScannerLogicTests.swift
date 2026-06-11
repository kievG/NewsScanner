import XCTest
@testable import NewsScanner

/// Unit tests for the pure, bug-prone logic: dedupe-key normalization, the recency
/// window, RSS parsing, the cold-severity bands, and match sorting.
final class NewsScannerLogicTests: XCTestCase {

    // MARK: - LinkKey (URL-normalized dedupe)

    func testLinkKeyDropsGoogleNewsTrackingParams() {
        let a = LinkKey.normalize("https://news.google.com/rss/articles/ABC?oc=5&hl=en-US&gl=US&ceid=US:en")
        XCTAssertEqual(a, "https://news.google.com/rss/articles/ABC")
    }

    func testLinkKeyDropsUTMAndKeepsMeaningfulQuery() {
        let key = LinkKey.normalize("https://example.com/story?utm_source=x&utm_medium=y&id=123")
        XCTAssertEqual(key, "https://example.com/story?id=123")
    }

    func testLinkKeyLowercasesHostStripsFragmentAndTrailingSlash() {
        let key = LinkKey.normalize("https://News.Example.COM/a/#section")
        XCTAssertEqual(key, "https://news.example.com/a")
    }

    func testLinkKeyTreatsTrackingVariantsAsTheSameArticle() {
        let one = LinkKey.normalize("https://example.com/a?utm_source=twitter")
        let two = LinkKey.normalize("https://example.com/a?fbclid=999")
        XCTAssertEqual(one, two, "Same article via different shares must dedupe to one key")
    }

    func testLinkKeyKeepsDistinctArticlesDistinct() {
        XCTAssertNotEqual(
            LinkKey.normalize("https://example.com/a"),
            LinkKey.normalize("https://example.com/b"))
    }

    // MARK: - RecencyWindow

    func testRecencyWindowLabels() {
        XCTAssertEqual(RecencyWindow(value: 24, unit: .hours).shortLabel, "24h")
        XCTAssertEqual(RecencyWindow(value: 2, unit: .weeks).shortLabel, "2w")
        XCTAssertEqual(RecencyWindow(value: 24, unit: .hours).longLabel, "Past 24 hours")
        XCTAssertEqual(RecencyWindow(value: 1, unit: .days).longLabel, "Past 1 day")
        XCTAssertEqual(RecencyWindow(value: 1, unit: .months).longLabel, "Past 1 month")
    }

    func testRecencyWindowCutoffApproxOneDayBack() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = RecencyWindow(value: 1, unit: .days).cutoff(now: now)
        XCTAssertNotNil(cutoff)
        XCTAssertEqual(now.timeIntervalSince(cutoff!), 86_400, accuracy: 3_600)
    }

    func testRecencyWindowCutoffApproxThreeHoursBack() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = RecencyWindow(value: 3, unit: .hours).cutoff(now: now)!
        XCTAssertEqual(now.timeIntervalSince(cutoff), 3 * 3_600, accuracy: 60)
    }

    // MARK: - RSSParser

    func testRSSParserParsesItem() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss><channel>
          <item>
            <title>Headline One</title>
            <link>https://example.com/a</link>
            <pubDate>Mon, 09 Jun 2025 12:00:00 GMT</pubDate>
            <source url="https://pub.example">Publisher</source>
          </item>
          <item>
            <title>Headline Two</title>
            <link>https://example.com/b</link>
          </item>
        </channel></rss>
        """
        let items = RSSParser().parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Headline One")
        XCTAssertEqual(items[0].link, "https://example.com/a")
        XCTAssertEqual(items[0].source, "Publisher")
        XCTAssertNotNil(items[0].pubDate)
        XCTAssertNil(items[1].pubDate)
    }

    func testRSSParserSkipsItemsWithoutLink() {
        let xml = "<rss><channel><item><title>No link</title></item></channel></rss>"
        XCTAssertTrue(RSSParser().parse(Data(xml.utf8)).isEmpty)
    }

    // MARK: - ColdLevel bands (graduated extreme cold)

    func testColdLevelBands() {
        XCTAssertNil(ColdLevel.band(forC: 5))
        XCTAssertEqual(ColdLevel.band(forC: -7), .cold)
        XCTAssertEqual(ColdLevel.band(forC: -20), .veryCold)
        XCTAssertEqual(ColdLevel.band(forC: -35), .extremeCold)   // ≤ -30, not yet ≤ -40
        XCTAssertEqual(ColdLevel.band(forC: -45), .severeCold)
        XCTAssertEqual(ColdLevel.band(forC: -50), .lifeThreatening, "Canadian-Prairies cold")
    }

    func testCurrentWeatherAlert() {
        func weather(_ t: Double) -> CurrentWeather {
            CurrentWeather(temperatureC: t, apparentC: t, code: 0, isDay: true, windKmh: 0)
        }
        XCTAssertEqual(weather(40).alert, .heat)
        XCTAssertNil(weather(20).alert)
        XCTAssertEqual(weather(-50).alert, .cold(.lifeThreatening))
    }

    // MARK: - Sorting

    func testSortedNewestPutsDatedFirstUndatedLast() {
        let old = RecentMatch(link: "1", title: "old", topicQuery: "q", source: nil,
                              publishedAt: Date(timeIntervalSince1970: 1000))
        let new = RecentMatch(link: "2", title: "new", topicQuery: "q", source: nil,
                              publishedAt: Date(timeIntervalSince1970: 2000))
        let undated = RecentMatch(link: "3", title: "undated", topicQuery: "q", source: nil,
                                  publishedAt: nil)
        let sorted = [undated, old, new].sortedNewest()
        XCTAssertEqual(sorted.map(\.title), ["new", "old", "undated"])
    }
}
