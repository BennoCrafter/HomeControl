import SwiftUI

@main
struct HomeControlApp: App {
    @State private var store = HomeStore()
    @State private var showingSettings = false

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
