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
    }

    var cards: [Card]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
            .suggestedFileName("Dashboard.json")
    }

    init(cards: [DashboardCard], devices: [Device]) {
        self.cards = cards.map { card in
            let device = devices.first { $0.id.uuidString == card.ref }
            return Card(kind: card.kind, ref: card.ref, name: device?.name, room: device?.room,
                        x: card.x, y: card.y, width: card.width, height: card.height, columns: card.columns)
        }
    }

    /// Replaces `memberID`'s dashboard in `homeID` with this one, for both screen sizes it holds.
    @MainActor
    func install(homeID: String, memberID: String, devices: [Device]) throws {
        @Dependency(\.defaultDatabase) var database
        try database.write { db in
            for columns in Set(cards.map(\.columns)) {
                try DashboardCard.where { $0.homeID.eq(homeID) && $0.memberID.eq(memberID) && $0.columns.eq(columns) }.delete().execute(db)
            }
            for card in cards {
                var ref = card.ref
                if card.kind == .item || card.kind == .camera, !devices.contains(where: { $0.id.uuidString == ref }),
                   let match = devices.first(where: { $0.name == card.name && $0.room == card.room }) {
                    ref = match.id.uuidString
                }
                try DashboardCard.insert {
                    DashboardCard.Draft(homeID: homeID, kind: card.kind, ref: ref, x: card.x, y: card.y,
                                        width: card.width, height: card.height, columns: card.columns, memberID: memberID)
                }.execute(db)
            }
        }
        for columns in Set(cards.map(\.columns)) {
            UserDefaults.standard.set(true, forKey: "dashboardSeeded.\(homeID).\(columns).\(memberID)")
        }
    }
}
