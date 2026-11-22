import SwiftUI

struct SettingsView: View {
    @AppStorage("controlStyle.light") private var lightStyle: ControlStyle = .dial
    @AppStorage("controlStyle.shutter") private var shutterStyle: ControlStyle = .pill
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Home", selection: Binding(get: { store.currentHomeID },
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
        case .notRequested: "Not requested"
        case .pending: "Waiting…"
        case .authorized: "Allowed"
        case .denied: "Denied"
        }
    }
}
