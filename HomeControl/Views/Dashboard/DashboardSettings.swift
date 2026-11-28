import SQLiteData
import SwiftUI

/// Settings' list of dashboards: everyone's own and the added ones.
struct DashboardsSection: View {
    @Environment(HomeStore.self) private var store
    @FetchAll private var rows: [Dashboard]

    var body: some View {
        let homeID = store.currentHomeID ?? ""
        Section {
            ForEach(Profiles.list(people: store.people, dashboards: rows.filter { $0.homeID == homeID })) { profile in
                NavigationLink(profile.name) { DashboardDetail(id: profile.id) }
            }
            NewDashboardButton()
        } header: {
            Text("Dashboards")
        } footer: {
            Text("Everyone in \(store.homeName) can switch to these and edit them.")
        }
    }
}

/// Asks for a name, then adds one for everyone and switches to it.
struct NewDashboardButton: View {
    @Environment(HomeStore.self) private var store
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        Button("New Dashboard…", systemImage: "plus") { naming = true }
            .alert("New Dashboard", isPresented: $naming) {
                TextField("Shared", text: $name)
                Button("Add") {
                    Dashboards.add(named: name.trimmingCharacters(in: .whitespaces), homeID: store.currentHomeID ?? "")
                    name = ""
                }
                Button("Cancel", role: .cancel) { name = "" }
            } message: {
                Text("It starts with the usual layout. Everyone in the home can see and edit it.")
            }
    }
}

/// One dashboard: rename it, fill it from another one or a file, send it, or delete it.
private struct DashboardDetail: View {
    let id: String
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FetchAll private var rows: [Dashboard]
    @FetchAll private var allCards: [DashboardCard]
    @State private var renaming = false
    @State private var newName = ""
    @State private var replacement: Replacement?
    @State private var importing = false
    @State private var importError: String?
    @State private var confirmingDelete = false

    /// What's about to replace this dashboard's cards, waiting for the go-ahead.
    private struct Replacement {
        var source: String
        var file: DashboardFile
    }

    private var homeID: String { store.currentHomeID ?? "" }
    private var all: [Profiles.Profile] { Profiles.list(people: store.people, dashboards: rows.filter { $0.homeID == homeID }) }
    private var name: String { all.first { $0.id == id }?.name ?? "" }
    private var isPerson: Bool { store.people.contains { $0.id == id } }

    private func file(of member: String) -> DashboardFile {
        DashboardFile(cards: allCards.filter { $0.homeID == homeID && $0.memberID == member }, devices: store.devices, groups: store.allGroups)
    }

    var body: some View {
        Form {
            Section {
                Button("Rename…", systemImage: "pencil") {
                    newName = name
                    renaming = true
                }
                let others = all.filter { $0.id != id }
                if !others.isEmpty {
                    Menu("Copy From", systemImage: "doc.on.doc") {
                        ForEach(others) { profile in
                            Button(profile.name) { replacement = Replacement(source: profile.name, file: file(of: profile.id)) }
                        }
                    }
                }
                ShareLink(item: file(of: id), preview: SharePreview(name, image: Image(systemName: "square.grid.2x2")))
                Button("Import Dashboard…", systemImage: "square.and.arrow.down") { importing = true }
            }
            Section {
                Button("Delete Dashboard", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(name)
        .alert("Rename Dashboard", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { Dashboards.rename(id, to: name, homeID: homeID, isPerson: isPerson) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone in the home sees the new name.")
        }
        .confirmationDialog("Replace “\(name)” with “\(replacement?.source ?? "")”?", isPresented: Binding(get: { replacement != nil }, set: { if !$0 { replacement = nil } }),
                            titleVisibility: .visible, presenting: replacement) { replacement in
            Button("Replace", role: .destructive) {
                try? replacement.file.install(homeID: homeID, memberID: id, devices: store.devices)
            }
        } message: { _ in
            Text("Its cards are replaced for everyone. This can't be undone.")
        }
        .confirmationDialog("Delete “\(name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Dashboard", role: .destructive) {
                Dashboards.delete(id, homeID: homeID, isPerson: isPerson)
                dismiss()
            }
        } message: {
            Text("It's removed with its cards for everyone in the home. This can't be undone.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let file = try JSONDecoder().decode(DashboardFile.self, from: Data(contentsOf: url))
                replacement = Replacement(source: url.deletingPathExtension().lastPathComponent, file: file)
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Couldn't Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }
}
