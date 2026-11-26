import CloudKit
import SQLiteData
import SwiftUI

/// Inviting family in two steps: share this app's setup through iCloud, then let them control the accessories in Apple Home.
struct InviteView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.defaultSyncEngine) private var syncEngine
    @State private var sharedRecord: SharedRecord?
    @State private var preparing = false
    @State private var error: String?

    var body: some View {
        let share = store.homeShare()
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image("ShareIcon")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(.rect(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "person.2.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor.gradient, in: .circle)
                                .overlay { Circle().strokeBorder(.background, lineWidth: 3) }
                                .offset(x: 8, y: 8)
                        }
                        .padding(.top, 8)
                    VStack(spacing: 4) {
                        Text("HomeControl Sharing")
                            .font(.title2.bold())
                        Text("Invite family to \(store.homeName)")
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    step(1, title: "Share this setup",
                         text: "Groups, dashboards, icons and backgrounds stay in sync for everyone through iCloud. Each person keeps their own dashboard.") {
                        Button {
                            Task { await shareHome() }
                        } label: {
                            Label(share == nil ? "Invite with iCloud" : "Manage Sharing", systemImage: "icloud.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isDemo || preparing)
                        if store.isDemo {
                            Text("Pick your own home in Settings to invite people.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    step(2, title: "Give HomeKit access",
                         text: "So they can switch the accessories too. Apple's Home screen for people opens.") {
                        Button {
                            // Apple's screen shows on its own; over this sheet it would sit behind our buttons.
                            dismiss()
                            Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                store.manageMembers()
                            }
                        } label: {
                            Label("Open Home Access", systemImage: "homekit")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isDemo)
                    }
                    if store.people.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("In this home").font(.headline)
                            ForEach(store.people) { person in
                                Label(person.name, systemImage: person.id == store.meID ? "person.crop.circle.fill" : "person.crop.circle")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 20, style: .continuous))
                    }
                }
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } }
            }
            .sheet(item: $sharedRecord, onDismiss: store.loadPeople) { CloudSharingView(sharedRecord: $0) }
            .alert("Couldn't Share", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func step(_ number: Int, title: LocalizedStringKey, text: LocalizedStringKey, @ViewBuilder actions: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor, in: .circle)
                Text(title).font(.headline)
            }
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func shareHome() async {
        guard let id = store.currentHomeID else { return }
        preparing = true
        defer { preparing = false }
        @Dependency(\.defaultDatabase) var database
        do {
            guard let home = try await database.read({ db in try Home.find(id).fetchOne(db) }) else { return }
            sharedRecord = try await syncEngine.share(record: home) { share in
                share[CKShare.SystemFieldKey.title] = String(localized: "Join \(store.homeName) in HomeControl")
                share[CKShare.SystemFieldKey.thumbnailImageData] = UIImage(named: "ShareIcon")?.pngData()
                share[CKShare.SystemFieldKey.shareType] = "de.bennowo.homecontrol.home"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
