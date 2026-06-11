import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

/// Which slice of matches to show.
enum MatchFilter {
    case all, topics, local
    case topic(String)   // a specific user-topic query

    var title: String {
        switch self {
        case .all:           return "Recent"
        case .topics:        return "Topic matches"
        case .local:         return "Local news"
        case .topic(let q):  return q
        }
    }

    /// Human label used to build export/share filenames.
    var fileLabel: String {
        switch self {
        case .all:           return "All matches"
        case .topics:        return "Topics"
        case .local:         return "Local news"
        case .topic(let q):  return q
        }
    }
}

/// A shareable, named HTML document of matches — gives "Share all" a real filename
/// (a plain-text share has none). Used by `ShareLink`.
struct MatchesExport: Transferable {
    let html: String
    let filename: String   // without extension

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .html) { Data($0.html.utf8) }
            .suggestedFileName { "\($0.filename).html" }
    }
}

/// One tappable match row, shared by the full list and the inline section lists.
/// `showsTopic` hides the topic label when the section header already names it.
struct MatchRow: View {
    @EnvironmentObject private var router: AppRouter
    let match: RecentMatch
    var showsTopic = true

    var body: some View {
        Button {
            if let url = match.url { router.pendingURL = url }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(match.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if showsTopic {
                        Text(match.topicQuery)
                    }
                    if let source = match.source, !source.isEmpty {
                        Text(showsTopic ? "· \(source)" : source).lineLimit(1)
                    }
                    Spacer()
                    if let date = match.publishedAt {
                        Text(date, style: .relative)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Recent matches list — newest-published first, each tappable. Plus bulk actions:
/// share all and export all (mirrors the extension's results page).
struct RecentMatchesView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: AppRouter

    var filter: MatchFilter = .all
    @State private var showExporter = false

    /// The filtered slice, newest published first.
    private var sorted: [RecentMatch] {
        switch filter {
        case .all:    return store.recent.sortedNewest()
        case .topics: return store.recent.filter { $0.scope == nil }.sortedNewest()
        case .local:  return store.recent.filter { $0.scope != nil }.sortedNewest()
        case .topic(let q):
            // Apply that topic's recency window so "View all" matches the section.
            if let topic = store.topics.first(where: { $0.scope == nil && $0.query == q }) {
                return store.matches(for: topic)
            }
            return store.recent.filter { $0.scope == nil && $0.topicQuery == q }.sortedNewest()
        }
    }

    /// Hide the per-row topic label when the whole list is already one topic.
    private var showsTopicLabel: Bool {
        if case .topic = filter { return false }
        return true
    }

    var body: some View {
        List {
            if sorted.isEmpty {
                Text("No matches yet. New articles will appear here after a scan.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sorted) { match in
                MatchRow(match: match, showsTopic: showsTopicLabel)
            }
        }
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !sorted.isEmpty {
                        ShareLink(
                            item: MatchesExport(html: exportHTML, filename: exportBaseName),
                            preview: SharePreview(exportBaseName)
                        ) {
                            Label("Share all", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showExporter = true
                        } label: {
                            Label("Export all", systemImage: "doc.text")
                        }
                        Button(role: .destructive) {
                            store.clearRecent()
                        } label: {
                            Label("Clear all", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(sorted.isEmpty)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: HTMLDocument(html: exportHTML),
            contentType: .html,
            defaultFilename: exportBaseName
        ) { _ in }
    }

    // MARK: - Filename + payloads

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"   // date + time so same-day exports don't collide
        return f
    }()

    /// e.g. "NewsScanner_TSLA_20260610-1432_30items" — topic, save date (YYYYMMDD),
    /// time (HHmm, avoids same-day overwrites), and the number of matches in the file.
    private var exportBaseName: String {
        let topic = Self.sanitize(filter.fileLabel)
        let stamp = Self.fileStampFormatter.string(from: Date())
        let count = sorted.count
        let items = "\(count)\(count == 1 ? "item" : "items")"
        return "NewsScanner_\(topic)_\(stamp)_\(items)"
    }

    /// Make a label safe for a filename: keep alphanumerics, join the rest with "-".
    private static func sanitize(_ s: String) -> String {
        let parts = s.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-")
        return joined.isEmpty ? "matches" : joined
    }

    private var exportHTML: String {
        let rows = sorted.map { match -> String in
            let meta = [match.topicQuery, match.source].compactMap { $0 }.joined(separator: " · ")
            return """
                <li><a href="\(match.link)">\(escape(match.title))</a><br>
                <small>\(escape(meta))</small></li>
            """
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>News Scanner — Matches</title></head>
        <body><h1>News Scanner — Matches</h1><ul>
        \(rows)
        </ul></body></html>
        """
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Minimal FileDocument wrapper so we can export an HTML file via the share sheet.
struct HTMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }
    var html: String

    init(html: String) { self.html = html }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            html = String(decoding: data, as: UTF8.self)
        } else {
            html = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(html.utf8))
    }
}
