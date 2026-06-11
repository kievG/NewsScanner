import Foundation

/// A single parsed RSS entry.
struct FeedItem {
    let title: String
    let link: String
    let source: String?
    let pubDate: Date?
}

/// Builds the Google News RSS query URL. Ports directly from the extension:
/// https://news.google.com/rss/search?q=<topic>&hl=en-US&gl=US&ceid=US:en
enum FeedURLBuilder {
    static func url(for topic: String) -> URL? {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://news.google.com/rss/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en"),
        ]
        return components?.url
    }
}

enum FeedService {
    /// Fetch and parse a feed. Returns [] on any failure (network, parse, etc.).
    static func fetch(url: URL) async -> [FeedItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // A browser-like UA reduces the chance of being served a blocked/empty page.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return []
            }
            return RSSParser().parse(data)
        } catch {
            return []
        }
    }
}

/// Native XMLParser-based RSS reader. Replaces the regex workaround the MV3
/// service worker forced (see APPLE_APP_PORT.md §3).
final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [FeedItem] = []

    private var inItem = false
    private var element = ""
    private var buffer = ""

    private var curTitle = ""
    private var curLink = ""
    private var curPubDate = ""
    private var curSource = ""

    // RFC 822 date format used by RSS pubDate, e.g. "Mon, 09 Jun 2026 12:00:00 GMT".
    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    func parse(_ data: Data) -> [FeedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        element = elementName
        buffer = ""
        if elementName == "item" {
            inItem = true
            curTitle = ""; curLink = ""; curPubDate = ""; curSource = ""
        }
        // <source url="...">Publisher</source> — capture publisher text in characters.
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let str = String(data: CDATABlock, encoding: .utf8) {
            buffer += str
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        guard inItem else { return }
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title":   curTitle = text
        case "link":    curLink = text
        case "pubDate": curPubDate = text
        case "source":  curSource = text
        case "item":
            inItem = false
            let link = curLink.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !link.isEmpty else { break }
            let date = Self.rfc822.date(from: curPubDate)
            items.append(FeedItem(
                title: curTitle.isEmpty ? link : curTitle,
                link: link,
                source: curSource.isEmpty ? nil : curSource,
                pubDate: date))
        default:
            break
        }
        buffer = ""
    }
}
