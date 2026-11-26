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
    /// The item's id or the room's name; empty for the status card.
    var ref: String = ""
    var x = 0
    var y = 0
    var width = 2
    var height = 2
    /// The grid it was arranged on: phones (4) and wide screens (8) each keep their own layout.
    var columns = 4
    /// Whose dashboard: a profile's id, the same on every device of one Home member.
    var memberID = ""
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
        return migrator
    }
}
