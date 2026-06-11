import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter: authorization, posting alerts for new articles,
/// and routing a tapped notification to the in-app browser.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private static let urlKey = "articleURL"

    override private init() { super.init() }

    func configure() {
        center.delegate = self
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Post a notification for a genuinely new article.
    func notify(title: String, body: String, url: URL?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url { content.userInfo[Self.urlKey] = url.absoluteString }

        // nil trigger = deliver immediately.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        center.add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Tap → open the article in the in-app browser.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info[Self.urlKey] as? String, let url = URL(string: raw) else { return }
        await MainActor.run {
            AppRouter.shared.pendingURL = url
        }
    }
}
