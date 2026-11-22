import SwiftUI

struct ContentView: View {
    @Environment(HomeStore.self) private var store
    @Binding var showingSettings: Bool
    @State private var selectedRoom: String? = "All"
    @AppStorage("hasOnboarded") private var hasOnboarded = false

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

    private var home: some View {
        @Bindable var store = store
        return NavigationSplitView {
            List(selection: $selectedRoom) {
                Label("All Devices", systemImage: "house.fill")
                    .badge(store.devices.count)
                    .tag("All")
                Section("Rooms") {
                    ForEach(store.rooms, id: \.self) { room in
                        Label(room, systemImage: Self.icon(forRoom: room))
                            .badge(store.devices.count { $0.room == room })
                            .tag(room)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(store.homeName)
            #if !targetEnvironment(macCatalyst)
            // On the Mac, Settings lives in the app menu (⌘,).
            .toolbar {
                Button("Settings", systemImage: "gear") { showingSettings = true }
            }
            #endif
            .sheet(isPresented: $showingSettings) { SettingsView().environment(store) }
        } detail: {
            let room = selectedRoom ?? "All"
            RoomView(title: room == "All" ? "All Devices" : room,
                     devices: store.devices.filter { room == "All" || $0.room == room },
                     showRoom: room == "All")
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
