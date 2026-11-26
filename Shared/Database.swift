import Foundation
import OSLog
import SQLiteData

let logger = Logger(subsystem: "de.bennowo.homecontrol", category: "HomeControl")

/// Shared with the widgets through this App Group.
let appGroup = "group.de.bennowo.homecontrol"

/// A room's look and place: its icon, its order, and whether it's pinned to the top.
@Table("rooms")
struct RoomPref: Identifiable, Hashable, Sendable {
    let id: Int
    var homeID: String
    var name: String
    /// An SF Symbol; nil: guessed from the name.
    var icon: String?
    var position = 0
    var isPinned = false
}

/// An item's look and place. Keyed by the HomeKit service's id.
@Table("items")
struct ItemPref: Identifiable, Hashable, Sendable {
    let id: Int
    var homeID: String
    var deviceID: UUID
    var icon: String?
    var position = 0
    var isPinned = false
    var isHidden = false
}

/// One card of the dashboard, on a grid of cells.
@Table("cards")
struct DashboardCard: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, QueryBindable, CaseIterable {
        case item, room, status, camera
    }

    let id: Int
    var homeID: String
    var kind: Kind
    /// The item's id, the room's name, or a `DeviceGroup`'s id; empty for the status card.
    var ref: String = ""
    var x = 0
    var y = 0
    var width = 2
    var height = 2
    /// The grid it was arranged on: phones (4) and wide screens (8) each keep their own layout.
    var columns = 4
    /// Whose dashboard: a profile's id, the same on every device of one Home member.
    var memberID = ""
    /// The folder card this card sits in; nil on the dashboard itself.
    var folderID: Int?
}

/// Items gathered into one: a group (one tile in the rooms), a collection card, or a dashboard folder.
@Table("groups")
struct DeviceGroup: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, QueryBindable {
        case group, collection, folder
    }

    let id: Int
    var homeID: String
    var kind = Kind.group
    var name = ""
    var icon: String?
    /// Member item ids, comma separated.
    var members = ""
    /// The member the tile's icon switches; nil switches all of them.
    var mainID: UUID?

    var memberIDs: [UUID] {
        get { members.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { members = newValue.map(\.uuidString).joined(separator: ",") }
    }

    /// Stands in for the group wherever an item goes: tiles, widgets, controls. Random HomeKit ids never look like this.
    var deviceID: UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", id))! }
}

/// The home's background and how see-through the tiles are.
@Table("appearances")
struct Appearance: Identifiable, Hashable, Sendable {
    @Column(primaryKey: true)
    var id: String // the home's id
    /// A `BackgroundPreset` raw value, or "photo".
    var background = "aurora"
    var photo: Data?
    /// 0 is clear, 1 is solid.
    var tileOpacity = 0.6
    /// The editor's grainy gradient as JSON, used when `background` is "custom".
    var gradientJSON: Data?
}

/// The latest state of every item, for the widgets, which can't reach HomeKit themselves.
@Table("snapshots")
struct Snapshot: Identifiable, Hashable, Sendable {
    @Column(primaryKey: true)
    var id: String // the home's id
    var homeName: String
    /// `[Device]` as JSON.
    var devicesJSON: Data
    var updatedAt: Date

    var devices: [Device] {
        (try? JSONDecoder().decode([Device].self, from: devicesJSON)) ?? []
    }
}

enum Schema {
    static func database() throws -> any DatabaseWriter {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "HomeControl.sqlite")
        // shortcut: without the App Group (unsigned builds) the database is the app's own, so widgets see nothing.
        let database = try url.map { try DatabasePool(path: $0.path(), configuration: configuration) }
            ?? defaultDatabase(configuration: configuration)
        logger.info("Open database: \(database.path)")
        try migrator().migrate(database)
        return database
    }

    /// Never edit a registered migration; append new ones.
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("Create tables") { db in
            try #sql(
                """
                CREATE TABLE "rooms" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "homeID" TEXT NOT NULL,
                  "name" TEXT NOT NULL,
                  "icon" TEXT,
                  "position" INTEGER NOT NULL DEFAULT 0,
                  "isPinned" INTEGER NOT NULL DEFAULT 0,
                  UNIQUE("homeID", "name")
                ) STRICT
                """
            ).execute(db)
            try #sql(
                """
                CREATE TABLE "items" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "homeID" TEXT NOT NULL,
                  "deviceID" TEXT NOT NULL UNIQUE,
                  "icon" TEXT,
                  "position" INTEGER NOT NULL DEFAULT 0,
                  "isPinned" INTEGER NOT NULL DEFAULT 0,
                  "isHidden" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """
            ).execute(db)
            try #sql(
                """
                CREATE TABLE "cards" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "homeID" TEXT NOT NULL,
                  "kind" TEXT NOT NULL,
                  "ref" TEXT NOT NULL DEFAULT '',
                  "x" INTEGER NOT NULL DEFAULT 0,
                  "y" INTEGER NOT NULL DEFAULT 0,
                  "width" INTEGER NOT NULL DEFAULT 2,
                  "height" INTEGER NOT NULL DEFAULT 2
                ) STRICT
                """
            ).execute(db)
            try #sql(
                """
                CREATE TABLE "appearances" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "background" TEXT NOT NULL DEFAULT 'aurora',
                  "photo" BLOB,
                  "tileOpacity" REAL NOT NULL DEFAULT 0.6
                ) STRICT
                """
            ).execute(db)
            try #sql(
                """
                CREATE TABLE "snapshots" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "homeName" TEXT NOT NULL,
                  "devicesJSON" BLOB NOT NULL,
                  "updatedAt" TEXT NOT NULL
                ) STRICT
                """
            ).execute(db)
        }
        migrator.registerMigration("Add card columns and member") { db in
            try #sql(#"ALTER TABLE "cards" ADD COLUMN "columns" INTEGER NOT NULL DEFAULT 4"#).execute(db)
            try #sql(#"ALTER TABLE "cards" ADD COLUMN "memberID" TEXT NOT NULL DEFAULT ''"#).execute(db)
        }
        migrator.registerMigration("Add appearance gradient") { db in
            try #sql(#"ALTER TABLE "appearances" ADD COLUMN "gradientJSON" BLOB"#).execute(db)
        }
        migrator.registerMigration("Add groups and folders") { db in
            try #sql(
                """
                CREATE TABLE "groups" (
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                  "homeID" TEXT NOT NULL,
                  "kind" TEXT NOT NULL DEFAULT 'group',
                  "name" TEXT NOT NULL DEFAULT '',
                  "icon" TEXT,
                  "members" TEXT NOT NULL DEFAULT '',
                  "mainID" TEXT
                ) STRICT
                """
            ).execute(db)
            try #sql(#"ALTER TABLE "cards" ADD COLUMN "folderID" INTEGER"#).execute(db)
        }
        return migrator
    }
}
