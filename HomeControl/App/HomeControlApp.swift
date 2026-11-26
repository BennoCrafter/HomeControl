import SQLiteData
import SwiftUI

@main
struct HomeControlApp: App {
    @State private var store = HomeStore()
    @State private var showingSettings = false

    init() {
        do {
            try prepareDependencies { $0.defaultDatabase = try Schema.database() }
        } catch {
            // Preferences are a nicety: without them the app still controls the home.
            logger.error("Opening the database failed: \(error)")
        }
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
