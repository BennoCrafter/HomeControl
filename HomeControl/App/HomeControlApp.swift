import CloudKit
import SQLiteData
import SwiftUI
import TipKit

@main
struct HomeControlApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store: HomeStore
    @State private var showingSettings = false

    init() {
        #if DEBUG
            checkDashboardEngine()
        #endif
        do {
            try prepareDependencies {
                $0.defaultDatabase = try Schema.database(syncMetadata: true)
                // The whole setup syncs through iCloud and can be shared with family; the widget snapshot stays local.
                $0.defaultSyncEngine = try SyncEngine(
                    for: $0.defaultDatabase,
                    tables: Home.self, RoomPref.self, ItemPref.self, DashboardCard.self, DeviceGroup.self, Appearance.self, HomeItem.self, ItemEvent.self, Dashboard.self,
                    containerIdentifier: Schema.iCloudContainer
                )
            }
        } catch {
            // Preferences are a nicety: without them the app still controls the home.
            logger.error("Opening the database failed: \(error)")
        }
        // After the database: the store reads its groups from it.
        _store = State(initialValue: HomeStore.shared)
        #if DEBUG
            checkDashboardSharing()
            checkHistoryRuns()
        #endif
        setUpWidgetActions()
        #if DEBUG
            // Screenshots: `-showTips YES` shows every tip again.
            if UserDefaults.standard.bool(forKey: "showTips") { Tips.showAllTipsForTesting() }
        #endif
        try? Tips.configure()
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

/// Hands the scene a delegate that can accept iCloud share invitations.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, configurationForConnecting session: UISceneSession,
                     options _: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Someone tapped a family member's invitation: join their home's setup.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    private weak var windowScene: UIWindowScene?

    /// SwiftUI's window. System screens, like HomeKit's for people, look for it here to present on.
    var window: UIWindow? {
        get { windowScene?.keyWindow ?? windowScene?.windows.first }
        set {} // SwiftUI owns the window
    }

    func windowScene(_: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        accept(metadata)
    }

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options: UIScene.ConnectionOptions) {
        windowScene = scene as? UIWindowScene
        if let metadata = options.cloudKitShareMetadata { accept(metadata) }
    }

    private func accept(_ metadata: CKShare.Metadata) {
        @Dependency(\.defaultSyncEngine) var syncEngine
        Task {
            do {
                try await syncEngine.acceptShare(metadata: metadata)
            } catch {
                logger.error("Accepting the share failed: \(error)")
                HomeStore.shared.joinFailure = error.localizedDescription
            }
        }
    }
}
