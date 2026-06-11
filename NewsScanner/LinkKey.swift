import Foundation

/// Normalizes an article URL into a stable dedupe key.
///
/// Google News RSS links carry volatile query params (`oc`, `hl`, `gl`, `ceid`, …)
/// and tracking params (`utm_*`, `fbclid`, …), and differ in case/trailing slashes.
/// Without normalizing, the same article can slip through as "new" or re-notify.
/// The original link is still stored on the match for display/opening — only the
/// *dedupe key* is normalized.
enum LinkKey {
    /// Query parameters that don't identify the article and should be dropped.
    private static let dropParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "oc", "hl", "gl", "ceid", "guccounter", "fbclid", "gclid", "ref", "ref_src",
    ]

    static func normalize(_ link: String) -> String {
        guard var comps = URLComponents(string: link) else {
            return link.lowercased()
        }
        comps.scheme = comps.scheme?.lowercased()
        comps.host = comps.host?.lowercased()
        comps.fragment = nil

        if let items = comps.queryItems {
            let kept = items.filter { !dropParams.contains($0.name.lowercased()) }
            comps.queryItems = kept.isEmpty ? nil : kept
        }

        // Drop a trailing slash on the path so "/a/" and "/a" match.
        if comps.path.count > 1, comps.path.hasSuffix("/") {
            comps.path.removeLast()
        }

        return comps.string ?? link.lowercased()
    }
}
