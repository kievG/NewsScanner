import Foundation
import BackgroundTasks

/// Schedules opportunistic background scans via BGAppRefreshTask.
///
/// IMPORTANT (see APPLE_APP_PORT.md §2): iOS does NOT allow fixed-interval polling
/// in the background. `earliestBeginDate` is only a hint — the system decides when
/// (and whether) to run the task, typically based on usage patterns, often only
/// every few hours. There is no guaranteed "every 5 minutes" in the background.
/// Precise intervals only hold while the app is in the foreground (see ContentView).
enum BackgroundScanner {
    static let refreshIdentifier = "com.newsscanner.app.refresh"

    /// Register the task handler. Call once at launch, before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Ask the system to run a refresh no sooner than the chosen interval from now.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        // Clamp to a sane minimum; the system enforces its own floor (~15 min) regardless.
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(AppSettings.shared.interval, 60))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Common in the simulator (no background task support) — safe to ignore.
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Always queue the next refresh first, so the chain continues.
        schedule()

        let work = Task { @MainActor in
            let count = await ScanService.runScan()
            task.setTaskCompleted(success: true)
            _ = count
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
