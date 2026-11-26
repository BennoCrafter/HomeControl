import SQLiteData
import SwiftUI

@main
struct HomeControlApp: App {
    @State private var store: HomeStore
    @State private var showingSettings = false

    init() {
        #if DEBUG
            checkDashboardEngine()
        #endif
        do {
            try prepareDependencies { $0.defaultDatabase = try Schema.database() }
        } catch {
            // Preferences are a nicety: without them the app still controls the home.
            logger.error("Opening the database failed: \(error)")
        }
        // After the database: the store reads its groups from it.
        _store = State(initialValue: HomeStore.shared)
        #if DEBUG
            checkDashboardSharing()
        #endif
        setUpWidgetActions()
    }

    private func setUpWidgetActions() {
        DeviceActions.setOn = { id, active in try await HomeStore.shared.set(id, active: active) }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showingSettings: $showingSettings)
                .environment(store)
                #if targetEnvironment(macCatalyst)
                .onAppear {
                    // The window title duplicates the sidebar's home name; keep the title bar clean.
                    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                        scene.titlebar?.titleVisibility = .hidden
                    }
                }
                #endif
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { showingSettings = true }
                    .keyboardShortcut(",")
            }
        }
    }
}
