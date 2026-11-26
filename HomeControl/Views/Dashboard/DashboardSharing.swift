import CoreTransferable
import SQLiteData
import UniformTypeIdentifiers

/// A dashboard as a file, to send to someone in the same home.
/// Items carry their name and room too: HomeKit ids aren't guaranteed to match on another person's device.
struct DashboardFile: Codable, Transferable {
    struct Card: Codable {
        var kind: DashboardCard.Kind
        var ref: String
        var name: String?
        var room: String?
        var x, y, width, height, columns: Int
        var folderID: Int?
    }

    /// An item by id, with its name and room to find it again in someone else's home.
    struct Member: Codable {
        var id: UUID
        var name: String?
        var room: String?
    }

    struct Group: Codable {
        var id: Int
        var kind: DeviceGroup.Kind
        var name: String
        var icon: String?
        var members: [Member]
        var mainID: UUID?
    }

    var cards: [Card]
    /// Older files have none.
    var groups: [Group]?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
            .suggestedFileName("Dashboard.json")
    }

    init(cards: [DashboardCard], devices: [Device], groups: [DeviceGroup]) {
        self.cards = cards.map { card in
            let device = devices.first { $0.id.uuidString == card.ref }
            return Card(kind: card.kind, ref: card.ref, name: device?.name, room: device?.room,
                        x: card.x, y: card.y, width: card.width, height: card.height, columns: card.columns, folderID: card.folderID)
        }
        // The groups the cards show, and the groups inside those collections.
        let shown = Set(cards.filter(\.kind.isGroup).compactMap { Int($0.ref) })
        let used = groups.filter { shown.contains($0.id) }
        let nested = Set(used.flatMap { $0.memberIDs })
        self.groups = groups.filter { shown.contains($0.id) || nested.contains($0.deviceID) }.map { group in
            Group(id: group.id, kind: group.kind, name: group.name, icon: group.icon, members: group.memberIDs.map { id in
                let device = devices.first { $0.id == id }
                return Member(id: id, name: device?.name, room: device?.room)
            }, mainID: group.mainID)
        }
    }

    /// Replaces `memberID`'s dashboard in `homeID` with this one, for both screen sizes it holds.
    @MainActor
    func install(homeID: String, memberID: String, devices: [Device]) throws {
        @Dependency(\.defaultDatabase) var database
        func match(_ id: UUID, name: String?, room: String?) -> UUID? {
            devices.contains { $0.id == id } ? id : devices.first { $0.name == name && $0.room == room }?.id
        }
        try database.write { db in
            // Groups first, so collections can point at them; one of the same kind and name is reused.
            var newIDs: [Int: Int] = [:]
            var newDeviceIDs: [UUID: UUID] = [:]
            for group in (groups ?? []).sorted(by: { ($0.kind == .group ? 0 : 1, $0.id) < ($1.kind == .group ? 0 : 1, $1.id) }) {
                let (kind, name) = (group.kind, group.name)
                let existing = try DeviceGroup.where { $0.homeID.eq(homeID) && $0.kind.eq(kind) && $0.name.eq(name) }.fetchOne(db)
                let members: [UUID] = group.members.compactMap { member in
                    newDeviceIDs[member.id] ?? match(member.id, name: member.name, room: member.room)
                }
                let main: Member? = group.members.first { $0.id == group.mainID }
                var draft = DeviceGroup.Draft(homeID: homeID, kind: kind, name: name, icon: group.icon)
                draft.members = members.map(\.uuidString).joined(separator: ",")
                draft.mainID = main.flatMap { match($0.id, name: $0.name, room: $0.room) }
                var id = existing?.id
                if id == nil { id = try DeviceGroup.insert { draft }.returning(\.self).fetchOne(db)?.id }
                guard let id else { continue }
                newIDs[group.id] = id
                let placeholder = DeviceGroup(id: group.id, homeID: "")
                newDeviceIDs[placeholder.deviceID] = DeviceGroup(id: id, homeID: "").deviceID
            }
            for columns in Set(cards.map(\.columns)) {
                try DashboardCard.where { $0.homeID.eq(homeID) && $0.memberID.eq(memberID) && $0.columns.eq(columns) }.delete().execute(db)
            }
            for card in cards {
                var ref = card.ref
                if card.kind == .item || card.kind == .camera, !devices.contains(where: { $0.id.uuidString == ref }),
                   let match = devices.first(where: { $0.name == card.name && $0.room == card.room }) {
                    ref = match.id.uuidString
                }
                if card.kind.isGroup {
                    guard let id = Int(card.ref).flatMap({ newIDs[$0] }) else { continue }
                    ref = "\(id)"
                }
                try DashboardCard.insert {
                    DashboardCard.Draft(homeID: homeID, kind: card.kind, ref: ref, x: card.x, y: card.y,
                                        width: card.width, height: card.height, columns: card.columns, memberID: memberID,
                                        folderID: card.folderID.flatMap { newIDs[$0] })
                }.execute(db)
            }
        }
        HomeStore.shared.saveSnapshot()
        for columns in Set(cards.map(\.columns)) {
            UserDefaults.standard.set(true, forKey: "dashboardSeeded.\(homeID).\(columns).\(memberID)")
        }
    }
}

extension DashboardCard.Kind {
    /// Its ref is a `DeviceGroup`'s id.
    var isGroup: Bool { self == .group || self == .collection || self == .folder }
}
