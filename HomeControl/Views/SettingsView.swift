import SwiftUI

struct SettingsView: View {
    @AppStorage("controlStyle.light") private var lightStyle: ControlStyle = .dial
    @AppStorage("controlStyle.shutter") private var shutterStyle: ControlStyle = .pill
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("cardIconsPerRow") private var iconsPerRow = 0
    @State private var inviting = false
    @State private var renamingHome: HomeOption?
    @State private var newHomeName = ""
    @State private var showingDiagnostics = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.homes) { home in
                        Button { store.selectHome(home.id) } label: {
                            HStack {
                                Label(home.name, systemImage: home == .demo ? "sparkles" : "house")
                                Spacer()
                                if home.id == store.homeKitID {
                                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions { homeActions(home) }
                        .contextMenu { homeActions(home) }
                    }
                } header: {
                    Text("Home")
                } footer: {
                    if store.showsDemoHome {
                        Text("The Demo Home lets you try every control without connecting to Apple Home.")
                    }
                }
                if let homeID = store.currentHomeID {
                    AppearanceSection(homeID: homeID)
                }
                if !store.isDemo, store.currentHomeID != nil {
                    Section {
                        // Once shared, the same screen manages who's in.
                        Button(store.homeShare() == nil ? "Invite to Home…" : "Manage Sharing…", systemImage: "person.2.badge.plus") { inviting = true }
                            .sheet(isPresented: $inviting) { InviteView().environment(store) }
                    } header: {
                        Text("People")
                    } footer: {
                        Text("Share this setup through iCloud and give HomeKit access, so everyone in \(store.homeName) has their own dashboard.")
                    }
                }
                Section {
                    LabeledContent("Status", value: accessText)
                    switch store.access {
                    case .notRequested:
                        Button("Request Home Access", systemImage: "homekit") { store.requestAccess() }
                    case .denied:
                        Button("Open Privacy Settings", systemImage: "gear") { openURL(.homeAccessSettings) }
                    case .pending, .authorized:
                        EmptyView()
                    }
                } header: {
                    Text("Home Access")
                } footer: {
                    Text("HomeControl reads and controls your accessories through Apple Home.")
                }
                Section {
                    Picker("Lights", selection: $lightStyle) {
                        ForEach(ControlStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Shutters", selection: $shutterStyle) {
                        ForEach(ControlStyle.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Control Style")
                } footer: {
                    Text("How brightness and shutter position are adjusted in the device details.")
                }
                Section {
                    Stepper(value: $iconsPerRow.animation(.snappy), in: 0 ... 8) {
                        HStack {
                            Text("Icons per Row")
                            Spacer()
                            Text(iconsPerRow == 0 ? String(localized: "Auto") : "\(iconsPerRow)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .lineLimit(1)
                    }
                    // The first room as it shows on the dashboard, following the stepper live.
                    if let room = store.allRooms.first {
                        RoomCard(title: room, icon: ContentView.icon(forRoom: room), items: store.items(in: room), large: false) {} openItem: { _ in }
                            .frame(height: 160)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                } header: {
                    Text("Cards")
                } footer: {
                    Text("Fewer icons per row make them bigger, on room and group cards.")
                }
                Section {
                    Button("Show Onboarding", systemImage: "sparkles") {
                        dismiss()
                        // Let the settings sheet finish dismissing before the onboarding cover presents.
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            withAnimation(.smooth(duration: 0.45)) { hasOnboarded = false }
                        }
                    }
                } footer: {
                    Text(verbatim: "HomeControl \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .frame(maxWidth: .infinity)
                        .onLongPressGesture { showingDiagnostics = true }
                }
            }
            .formStyle(.grouped)
            // Hidden on purpose: holding the version opens it.
            .navigationDestination(isPresented: $showingDiagnostics) { DiagnosticsView() }
            .alert("Rename Home", isPresented: Binding(get: { renamingHome != nil }, set: { if !$0 { renamingHome = nil } })) {
                TextField("Name", text: $newHomeName)
                Button("Rename") {
                    let name = newHomeName.trimmingCharacters(in: .whitespaces)
                    if let home = renamingHome, !name.isEmpty { store.renameHome(home.id, to: name) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Also renames it in Apple Home, for everyone in it.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func homeActions(_ home: HomeOption) -> some View {
        if home == .demo {
            Button("Remove", systemImage: "trash", role: .destructive) { withAnimation { store.removeDemoHome() } }
        } else {
            Button("Rename…", systemImage: "pencil") {
                newHomeName = home.name
                renamingHome = home
            }
        }
    }

    private var accessText: String {
        switch store.access {
        case .notRequested: String(localized: "Not requested")
        case .pending: String(localized: "Waiting…")
        case .authorized: String(localized: "Allowed")
        case .denied: String(localized: "Denied")
        }
    }
}
