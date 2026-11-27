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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Home", selection: Binding(get: { store.homeKitID },
                                                      set: { if let id = $0 { store.selectHome(id) } })) {
                        ForEach(store.homes) { home in
                            Label(home.name, systemImage: home == .demo ? "sparkles" : "house")
                                .tag(Optional(home.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Home")
                } footer: {
                    Text("The Demo Home lets you try every control without connecting to Apple Home.")
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
                    Stepper(value: $iconsPerRow, in: 0 ... 8) {
                        LabeledContent("Icons per Row on Cards", value: iconsPerRow == 0 ? String(localized: "Automatic") : "\(iconsPerRow)")
                    }
                } header: {
                    Text("Control Style")
                } footer: {
                    Text("How brightness and shutter position are adjusted in the device details, and how big the icons on room and group cards are: fewer per row are bigger.")
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
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
