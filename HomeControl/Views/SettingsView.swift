import SwiftUI

struct SettingsView: View {
    @AppStorage("controlStyle.light") private var lightStyle: ControlStyle = .dial
    @AppStorage("controlStyle.shutter") private var shutterStyle: ControlStyle = .pill
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(CardIcons.key) private var iconScale = 1.0
    @State private var inviting = false
    @State private var renamingHome: HomeOption?
    @State private var newHomeName = ""
    @State private var showingDiagnostics = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                    stylePicker("Lights", selection: $lightStyle, look: .light)
                    stylePicker("Shutters", selection: $shutterStyle, look: .shutter)
                } header: {
                    Text("Control Style")
                } footer: {
                    Text("How brightness and shutter position are adjusted in the device details.")
                }
                Section {
                    Picker("Icon Size", selection: $iconScale.animation(.snappy)) {
                        ForEach(CardIcons.scales, id: \.scale) { Text($0.title).tag($0.scale) }
                    }
                    .pickerStyle(.segmented)
                    // The first room as a dashboard card, just tall enough for one row at the chosen size.
                    if let room = store.allRooms.first {
                        RoomCard(title: room, icon: ContentView.icon(forRoom: room), items: store.items(in: room), large: false) {} openItem: { _ in }
                            .frame(height: CardIcons.cardHeight(large: false, scale: iconScale))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                } header: {
                    Text("Card Icons").id("cards")
                } footer: {
                    Text("How big the icons on room and group cards are, on the dashboard and in Rooms.")
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
            #if DEBUG
            // Screenshots: `-settingsCards YES` opens scrolled to the control and card settings.
            .task {
                guard UserDefaults.standard.bool(forKey: "settingsCards") else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo("cards", anchor: .top)
            }
            #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    /// Both styles drawn side by side, tap one to pick it.
    private func stylePicker(_ title: LocalizedStringKey, selection: Binding<ControlStyle>, look: LevelControl.Look) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
            HStack(spacing: 12) {
                ForEach(ControlStyle.allCases) { style in
                    let selected = selection.wrappedValue == style
                    Button { selection.wrappedValue = style } label: {
                        VStack(spacing: 6) {
                            ControlStylePreview(style: style, look: look)
                                .frame(height: 72)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5)
                                }
                            Text(style.title).font(.caption).foregroundStyle(selected ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(PressScale())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.4), value: selection.wrappedValue)
        }
        .padding(.vertical, 4)
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
