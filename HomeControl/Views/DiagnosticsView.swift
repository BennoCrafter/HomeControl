import SwiftUI

/// Behind a long press on the version in Settings: what the app sees, and the Demo Home switch.
struct DiagnosticsView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        Form {
            Section {
                Toggle("Demo Home", isOn: Binding(get: { store.showsDemoHome }, set: { shown in
                    withAnimation { shown ? store.showsDemoHome = true : store.removeDemoHome() }
                }))
            } footer: {
                Text("Shows the Demo Home in Settings again.")
            }
            Section("Home") {
                // Raw values on purpose: this is for finding out what's wrong, not for reading.
                row("Access", "\(store.access)")
                row("Home", store.homeName)
                row("Home ID", store.currentHomeID ?? "–")
                row("HomeKit ID", store.homeKitID ?? "–")
                row("Apple homes", "\(store.appleHomes.count)")
                row("Items", "\(store.devices.count)")
                row("Groups", "\(store.allGroups.count)")
            }
            Section("iCloud") {
                row("User", store.meID.isEmpty ? "–" : store.meID)
                row("Shared", store.homeShare() == nil ? "no" : "yes")
                row("People", "\(store.people.count)")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(title) {
            Text(verbatim: value).font(.footnote.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
    }
}
