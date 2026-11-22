import SwiftUI

@main
struct HomeControlApp: App {
    @State private var store = HomeStore()
    @State private var showingSettings = false

    var body: some Scene {
        WindowGroup {
            ContentView(showingSettings: $showingSettings)
                .environment(store)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { showingSettings = true }
                    .keyboardShortcut(",")
            }
        }
    }
}
