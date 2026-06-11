import SwiftUI
import SafariServices

/// Wraps SFSafariViewController so tapped links open in-app (mirrors the
/// extension's "open article" behavior).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
