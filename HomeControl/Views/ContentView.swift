import SQLiteData
import SwiftUI

struct ContentView: View {
    @Environment(HomeStore.self) private var store
    @Binding var showingSettings: Bool
    @State private var roomPath: [String] = []
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @FetchAll private var roomPrefs: [RoomPref]
    @FetchAll private var itemPrefs: [ItemPref]
    @FetchAll private var appearances: [Appearance]
    @FetchAll private var homes: [Home]
    @Environment(\.scenePhase) private var scenePhase
    @State private var iconRoom: String?
    @State private var tab = "Dashboard"
    /// Opened from a widget.
    @State private var linkedItem: Device?

    var body: some View {
        // Onboarding replaces the whole window so nothing of the main UI shows behind it.
        ZStack {
            if hasOnboarded {
                home
                    .onAppear { store.reconnect() }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .animation(.smooth(duration: 0.45), value: hasOnboarded)
    }

    private var homeID: String { store.currentHomeID ?? "" }

    private var appearance: Appearance {
        // Until HomeKit has loaded the home, last time's: otherwise the default background flashes first.
        let id = store.currentHomeID ?? UserDefaults.standard.string(forKey: HomeStore.lastHomeKey) ?? ""
        return appearances.first { $0.id == id } ?? Appearance(id: id)
    }

    /// Pinned first, then the user's order, then HomeKit's.
    private var rooms: [String] {
        let prefs = Dictionary(roomPrefs.filter { $0.homeID == homeID }.map { ($0.name, $0) }) { first, _ in first }
        return store.rooms.enumerated().sorted { a, b in
            let pa = prefs[a.element], pb = prefs[b.element]
            return ((pa?.isPinned ?? false) ? 0 : 1, pa?.position ?? Int.max / 2, a.offset)
                < ((pb?.isPinned ?? false) ? 0 : 1, pb?.position ?? Int.max / 2, b.offset)
        }.map(\.element)
    }

    private var roomIcons: [String: String] {
        Dictionary(roomPrefs.filter { $0.homeID == homeID }.compactMap { pref in pref.icon.map { (pref.name, $0) } }) { first, _ in first }
    }

    private var prefsByItem: [UUID: ItemPref] {
        Dictionary(itemPrefs.map { ($0.deviceID, $0) }) { first, _ in first }
    }

    private func isPinned(_ room: String) -> Bool {
        roomPrefs.contains { $0.homeID == homeID && $0.name == room && $0.isPinned }
    }

    private func visible(_ devices: [Device]) -> [Device] {
        let prefs = prefsByItem
        let grouped = store.groupedIDs
        return devices
            .filter { !grouped.contains($0.id) }
            .enumerated()
            .sorted { a, b in
                ((prefs[a.element.id]?.isPinned ?? false) ? 0 : 1, a.offset) < ((prefs[b.element.id]?.isPinned ?? false) ? 0 : 1, b.offset)
            }
            .map(\.element)
    }

    private var home: some View {
        TabView(selection: $tab) {
            Tab("Dashboard", systemImage: "square.grid.2x2.fill", value: "Dashboard") { DashboardView(openSettings: { showingSettings = true }) }
            Tab("Rooms", systemImage: "house.fill", value: "Rooms") { roomsView }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.itemPrefs, prefsByItem)
        .environment(\.roomIcons, roomIcons)
        .environment(\.appearance, appearance)
        .environment(\.tileOpacity, appearance.tileOpacity)
        #if DEBUG
        // Screenshots: `-tab Rooms` starts on that tab.
        .task { if let start = UserDefaults.standard.string(forKey: "tab") { tab = start } }
        // Screenshots: `-gradientEditor YES` opens the background editor.
        .sheet(isPresented: .constant(UserDefaults.standard.bool(forKey: "gradientEditor"))) {
            GradientEditor(style: appearance.gradient) { _ in }
        }
        #endif
        .onOpenURL(perform: open)
        .onChange(of: homes) { store.homesChanged() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.readAll() } }
        .sheet(item: $linkedItem) { DeviceDetailView(device: $0).environment(store) }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(store)
                .environment(\.appearance, appearance)
        }
    }

    /// Widget links: `homecontrol://item/<id>` opens an item's details, `homecontrol://room/<name>` a room.
    private func open(_ url: URL) {
        guard url.scheme == "homecontrol", let value = url.pathComponents.dropFirst().first else { return }
        switch url.host() {
        case "item":
            Task {
                // Launched by the tap: give HomeKit a moment to hand over the home.
                for _ in 0 ..< 50 where !(store.devices + store.groupDevices).contains(where: { $0.id.uuidString == value }) {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                linkedItem = (store.devices + store.groupDevices).first { $0.id.uuidString == value }
            }
        case "room":
            tab = "Rooms"
            roomPath = [value]
        default:
            break
        }
    }

    /// Every room as a card, like the dashboard's: switch from here, tap the name to go in, drag to reorder.
    private var roomsView: some View {
        NavigationStack(path: $roomPath) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(rooms, id: \.self) { room in
                        RoomCard(title: room, icon: roomIcons[room] ?? Self.icon(forRoom: room), items: visible(store.items(in: room)),
                                 large: true) { roomPath.append(room) } openItem: { linkedItem = $0 }
                            .frame(height: 148)
                            .overlay(alignment: .topTrailing) {
                                if isPinned(room) {
                                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange).padding(10)
                                }
                            }
                            .contextMenu {
                                Button(isPinned(room) ? "Unpin" : "Pin to Top", systemImage: isPinned(room) ? "pin.slash" : "pin") {
                                    withAnimation(.snappy) { Prefs.update(room: room, in: homeID) { $0.isPinned.toggle() } }
                                }
                                Button("Change Icon", systemImage: "square.grid.2x2") { iconRoom = room }
                            }
                            .draggable(room)
                            .dropDestination(for: String.self) { dropped, _ in
                                guard let moved = dropped.first, moved != room, let to = rooms.firstIndex(of: room) else { return false }
                                var order = rooms.filter { $0 != moved }
                                order.insert(moved, at: min(to, order.count))
                                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { Prefs.reorder(rooms: order, in: homeID) }
                                return true
                            }
                    }
                }
                .padding()
            }
            .background(HomeBackground())
            .navigationTitle(store.homeName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { room in
                RoomView(title: room == "All" ? String(localized: "All Devices") : room,
                         devices: visible(room == "All" ? store.groupDevices + store.devices : store.items(in: room)),
                         showRoom: room == "All")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("All Devices", systemImage: "square.grid.3x3.fill") { roomPath.append("All") }
                }
                #if !targetEnvironment(macCatalyst)
                // On the Mac, Settings lives in the app menu (⌘,).
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                #endif
            }
            .sheet(item: Binding(get: { iconRoom.map(IdentifiedString.init) }, set: { iconRoom = $0?.id })) { room in
                IconPicker(title: room.id, current: roomIcons[room.id], tint: .accentColor) { icon in
                    Prefs.update(room: room.id, in: homeID) { $0.icon = icon }
                }
            }
            .overlay {
                if store.devices.isEmpty, let message = store.message {
                    ContentUnavailableView(message, systemImage: "house")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !store.devices.isEmpty, let message = store.message {
                    Button(message, systemImage: "exclamationmark.triangle") { store.message = nil }
                        .padding()
                        .background(.thinMaterial, in: .capsule)
                        .padding()
                }
            }
        }
    }

    /// Best-effort SF Symbol for a room name (German and English keywords).
    static func icon(forRoom room: String) -> String {
        let name = room.lowercased()
        let symbols: [([String], String)] = [
            (["wohn", "living", "lounge"], "sofa.fill"),
            (["bad", "bath", "wc", "dusch"], "bathtub.fill"),
            (["küche", "kitchen"], "fork.knife"),
            (["schlaf", "bed"], "bed.double.fill"),
            (["büro", "office", "arbeit", "study"], "desktopcomputer"),
            (["garage", "carport"], "car.fill"),
            (["keller", "basement", "cellar"], "stairs"),
            (["flur", "diele", "hall", "eingang", "entrance"], "door.left.hand.open"),
            (["garten", "garden", "terrasse", "balkon", "terrace", "balcony"], "leaf.fill"),
            (["ess", "dining"], "fork.knife.circle.fill"),
            (["kinder", "kid", "zimmer", "room"], "bed.double.fill"),
            (["zuhause", "home", "haus"], "house"),
        ]
        return symbols.first { keys, _ in keys.contains { name.contains($0) } }?.1 ?? "square.split.bottomrightquarter"
    }
}
