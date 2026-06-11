import SwiftUI

@main
struct NewsScannerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = Store.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var router = AppRouter.shared

    init() {
        // Must register BG task handlers before the app finishes launching.
        BackgroundScanner.register()
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(router)
                .task {
                    await NotificationManager.shared.requestAuthorization()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // Queue an opportunistic refresh for while we're away.
                BackgroundScanner.schedule()
            }
        }
    }
}
