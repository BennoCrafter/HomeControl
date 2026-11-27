import SQLiteData
import SwiftUI

/// Writes to the user's arrangement of the home: icons, order, pins, hidden items.
/// Rows are created on first change; a missing row means "as it comes from HomeKit".
@MainActor
enum Prefs {
    static func update(room name: String, in homeID: String, _ change: (inout RoomPref) -> Void) {
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in
                var room = try RoomPref.where { $0.homeID.eq(homeID) && $0.name.eq(name) }.fetchOne(db)
                    ?? RoomPref.insert { RoomPref.Draft(homeID: homeID, name: name, position: Int.max / 2) }
                    .returning(\.self).fetchOne(db)!
                change(&room)
                try RoomPref.update(room).execute(db)
            }
        } catch {
            HomeStore.shared.report(error, saving: "room \(name)")
        }
    }

    static func update(item id: UUID, in homeID: String, _ change: (inout ItemPref) -> Void) {
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in
                var item = try ItemPref.where { $0.deviceID.eq(id) }.fetchOne(db)
                    ?? ItemPref.insert { ItemPref.Draft(homeID: homeID, deviceID: id) }.returning(\.self).fetchOne(db)!
                change(&item)
                try ItemPref.update(item).execute(db)
            }
        } catch {
            HomeStore.shared.report(error, saving: "item \(id)")
        }
    }

    /// Saves `names` as the new order of the rooms.
    static func reorder(rooms names: [String], in homeID: String) {
        for (position, name) in names.enumerated() {
            update(room: name, in: homeID) { $0.position = position }
        }
    }
}

extension EnvironmentValues {
    /// The user's arrangement of the items, by device id.
    @Entry var itemPrefs: [UUID: ItemPref] = [:]
    /// Custom room icons, by room name.
    @Entry var roomIcons: [String: String] = [:]
}

extension Device {
    /// The custom icon, if any; lights keep showing on/off through `.fill`.
    func icon(_ prefs: [UUID: ItemPref]) -> String {
        guard let custom = prefs[id]?.icon else { return icon }
        guard kind.isControllable, !isActive else { return custom }
        let outline = custom.replacingOccurrences(of: ".fill", with: "")
        return UIImage(systemName: outline) == nil ? custom : outline
    }
}
