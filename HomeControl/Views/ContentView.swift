import SQLiteData
import SwiftUI

struct ContentView: View {
    @Environment(HomeStore.self) private var store
    @Binding var showingSettings: Bool
    @State private var selectedRoom: String? = "All"
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @FetchAll private var roomPrefs: [RoomPref]
    @FetchAll private var itemPrefs: [ItemPref]
    @FetchAll private var appearances: [Appearance]
    @State private var iconRoom: String?
    @State private var showingHidden = false

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
        appearances.first { $0.id == homeID } ?? Appearance(id: homeID)
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
        return devices
            .filter { showingHidden || !(prefs[$0.id]?.isHidden ?? false) }
            .enumerated()
            .sorted { a, b in
                ((prefs[a.element.id]?.isPinned ?? false) ? 0 : 1, a.offset) < ((prefs[b.element.id]?.isPinned ?? false) ? 0 : 1, b.offset)
            }
            .map(\.element)
    }

    private var home: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2.fill") { DashboardView() }
            Tab("Rooms", systemImage: "house.fill") { roomsView }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.itemPrefs, prefsByItem)
        .environment(\.roomIcons, roomIcons)
        .environment(\.appearance, appearance)
        .environment(\.tileOpacity, appearance.tileOpacity)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environment(store)
                .environment(\.appearance, appearance)
        }
    }

    private var roomsView: some View {
        @Bindable var store = store
        return NavigationSplitView {
            List(selection: $selectedRoom) {
                Label("All Devices", systemImage: "house.fill")
                    .badge(visible(store.devices).count)
                    .tag("All")
                Section("Rooms") {
                    ForEach(rooms, id: \.self) { room in
                        Label {
                            Text(room)
                        } icon: {
                            Image(systemName: roomIcons[room] ?? Self.icon(forRoom: room))
                                .overlay(alignment: .topTrailing) {
                                    if isPinned(room) {
                                        Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange).offset(x: 6, y: -4)
                                    }
                                }
                        }
                        .badge(visible(store.devices).count { $0.room == room })
                        .tag(room)
                        .contextMenu {
                            Button(isPinned(room) ? "Unpin" : "Pin to Top", systemImage: isPinned(room) ? "pin.slash" : "pin") {
                                withAnimation(.snappy) { Prefs.update(room: room, in: homeID) { $0.isPinned.toggle() } }
                            }
                            Button("Change Icon", systemImage: "square.grid.2x2") { iconRoom = room }
                        }
                    }
                    .onMove { from, to in
                        var order = rooms
                        order.move(fromOffsets: from, toOffset: to)
                        withAnimation(.snappy) { Prefs.reorder(rooms: order, in: homeID) }
                    }
                }
            }
            .sheet(item: Binding(get: { iconRoom.map(IdentifiedString.init) }, set: { iconRoom = $0?.id })) { room in
                IconPicker(title: room.id, current: roomIcons[room.id], tint: .accentColor) { icon in
                    Prefs.update(room: room.id, in: homeID) { $0.icon = icon }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedRoom)
            .listStyle(.sidebar)
            .navigationTitle(store.homeName)
            #if !targetEnvironment(macCatalyst)
            // On the Mac, Settings lives in the app menu (⌘,).
            .toolbar {
                Button("Settings", systemImage: "gear") { showingSettings = true }
            }
            #endif
        } detail: {
            let room = selectedRoom ?? "All"
            RoomView(title: room == "All" ? "All Devices" : room,
                     devices: visible(store.devices.filter { room == "All" || $0.room == room }),
                     showRoom: room == "All")
                .toolbar {
                    Toggle(isOn: $showingHidden.animation(.snappy)) {
                        Label("Show Hidden", systemImage: showingHidden ? "eye.fill" : "eye.slash")
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
