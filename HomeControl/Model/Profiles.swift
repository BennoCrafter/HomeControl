import Foundation
import SQLiteData

/// Whose dashboard is showing. Everyone in the home's iCloud share has their own, keyed by their iCloud user;
/// "Me" comes first. Added ones, like "Shared", follow.
@Observable
final class Profiles {
    struct Profile: Identifiable, Hashable {
        var id: String
        var name: String
    }

    let homeID: String
    let all: [Profile]
    /// Empty when every dashboard was deleted.
    var selected: String {
        didSet { UserDefaults.standard.set(selected, forKey: Self.key(homeID)) }
    }

    init(homeID: String, all: [Profile] = [Profile(id: "", name: String(localized: "Me"))]) {
        self.homeID = homeID
        self.all = all
        let saved = UserDefaults.standard.string(forKey: Self.key(homeID))
        selected = all.first { $0.id == saved }?.id ?? all.first?.id ?? ""
    }

    static func key(_ homeID: String) -> String { "profile.\(homeID)" }

    func name(of id: String) -> String {
        all.first { $0.id == id }?.name ?? String(localized: "Me")
    }

    /// Everyone's own, as renamed, then the added ones; deleted ones left out.
    static func list(people: [Profile], dashboards: [Dashboard]) -> [Profile] {
        let rows = Dictionary(dashboards.map { ($0.id, $0) }) { first, _ in first }
        let own = people.compactMap { person -> Profile? in
            guard let row = rows[person.id] else { return person }
            return row.isDeleted ? nil : Profile(id: person.id, name: row.name.isEmpty ? person.name : row.name)
        }
        return own + dashboards.filter { !$0.isPerson && !$0.isDeleted }.map { Profile(id: $0.id, name: $0.name) }
    }
}

/// Adds, renames and deletes dashboards, for everyone in the home.
@MainActor
enum Dashboards {
    /// Adds one and switches this device to it.
    static func add(named name: String, homeID: String) {
        let row = Dashboard(id: UUID().uuidString, homeID: homeID, name: name.isEmpty ? String(localized: "Dashboard") : name)
        UserDefaults.standard.set(row.id, forKey: Profiles.key(homeID))
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in try Dashboard.insert { row }.execute(db) }
        } catch {
            HomeStore.shared.report(error, saving: "dashboard \(name)")
        }
    }

    static func rename(_ id: String, to name: String, homeID: String, isPerson: Bool) {
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in
                try Dashboard.upsert { Dashboard(id: id, homeID: homeID, name: name, isPerson: isPerson) }.execute(db)
            }
        } catch {
            HomeStore.shared.report(error, saving: "dashboard \(name)")
        }
    }

    /// Gone for everyone with its cards. A person's stays behind as a mark, so it doesn't come back for them.
    static func delete(_ id: String, homeID: String, isPerson: Bool) {
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in
                if isPerson {
                    try Dashboard.upsert { Dashboard(id: id, homeID: homeID, isPerson: true, isDeleted: true) }.execute(db)
                } else {
                    try Dashboard.find(id).delete().execute(db)
                }
                try DashboardCard.where { $0.homeID.eq(homeID) && $0.memberID.eq(id) }.delete().execute(db)
                // A collection or folder lives in its cards; gone once no dashboard shows it any more.
                let shown = Set(try DashboardCard.where { $0.homeID.eq(homeID) }.select(\.ref).fetchAll(db).compactMap(UUID.init(uuidString:)))
                try DeviceGroup.where { $0.homeID.eq(homeID) && ($0.kind.eq(DeviceGroup.Kind.collection) || $0.kind.eq(DeviceGroup.Kind.folder)) }
                    .fetchAll(db)
                    .filter { !shown.contains($0.id) }
                    .forEach { try DeviceGroup.find($0.id).delete().execute(db) }
            }
            HomeStore.shared.saveSnapshot()
        } catch {
            HomeStore.shared.report(error, saving: "the deletion of a dashboard")
        }
    }
}
