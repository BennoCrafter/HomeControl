import Foundation
import GRDB
import OSLog
import SQLiteData

let logger = Logger(subsystem: "de.bennowo.homecontrol", category: "HomeControl")

/// Shared with the widgets through this App Group.
let appGroup = "group.de.bennowo.homecontrol"

/// One home: the root everything else hangs off, and what gets shared with family through iCloud.
@Table("homes")
struct Home: Identifiable, Hashable, Sendable {
    /// HomeKit's id of the home, or "demo".
    let id: String
    var name = ""
}

/// A room's look and place: its icon, its order, and whether it's pinned to the top.
@Table("rooms")
struct RoomPref: Identifiable, Hashable, Sendable {
    let id: UUID
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
    let id: UUID
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
        case item, room, status, camera, group, collection, folder
    }

    let id: UUID
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
    var folderID: UUID?
}

/// Items gathered into one: a group (one tile in the rooms), a collection card, or a dashboard folder.
@Table("groups")
struct DeviceGroup: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, QueryBindable {
        case group, collection, folder
    }

    let id: UUID
    var homeID: String
    var kind = Kind.group
    var name = ""
    var icon: String?
    /// Member item ids, comma separated.
    var members = ""
    /// The member the tile's icon switches; nil switches all of them.
    var mainID: UUID?
    /// The tile's icon opens the group instead of switching anything.
    var iconOpens = false

    var memberIDs: [UUID] {
        get { members.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { members = newValue.map(\.uuidString).joined(separator: ",") }
    }

    /// Stands in for the group wherever an item goes: tiles, widgets, controls.
    var deviceID: UUID { id }
}

/// An item switching between its two states, for "Open for 5 minutes" and its history. Kept 30 days.
@Table("events")
struct ItemEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    var homeID: String
    var deviceID: UUID
    var isActive = false
    /// When the app saw it change, or first saw the new state.
    var date: Date
    /// Set when the app wasn't watching: it changed sometime after this. `distantPast` when nothing earlier is known.
    var notSeenSince: Date?
}

/// The home's background and how see-through the tiles are.
@Table("appearances")
struct Appearance: Identifiable, Hashable, Sendable {
    @Column(primaryKey: true)
    var id: String // the home's id
    /// A `BackgroundPreset` raw value, or "photo".
    var background = "plain"
    var photo: Data?
    /// 0 is clear, 1 is solid.
    var tileOpacity = 0.6
    /// The editor's grainy gradient as JSON, used when `background` is "custom".
    var gradientJSON: Data?
}

/// The home's items as one person's Apple Home names them. HomeKit gives every person other ids for the
/// same accessory; a family member's device finds its own by name, room and kind, and takes on these ids.
@Table("homeItems")
struct HomeItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var homeID: String
    var name = ""
    var room = ""
    var kind = ""
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

@DatabaseFunction
nonisolated func uuid() -> UUID {
    UUID()
}

enum Schema {
    nonisolated static let iCloudContainer = "iCloud.de.bennowo.homecontrol"

    /// `syncMetadata`: the app's connection also sees which rows came from someone else's share.
    static func configuration(syncMetadata: Bool = false) -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            // New rows get their id from SQLite.
            db.add(function: $uuid)
            if syncMetadata { try db.attachMetadatabase(containerIdentifier: iCloudContainer) }
        }
        return configuration
    }

    static func database(syncMetadata: Bool = false) throws -> any DatabaseWriter {
        let configuration = configuration(syncMetadata: syncMetadata)
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
        migrator.registerMigration("Make tables syncable", migrate: migrateToSyncableTables)
        migrator.registerMigration("Add home items") { db in
            try #sql(
                """
                CREATE TABLE "homeItems" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "homeID" TEXT NOT NULL REFERENCES "homes"("id") ON DELETE CASCADE,
                  "name" TEXT NOT NULL DEFAULT '',
                  "room" TEXT NOT NULL DEFAULT '',
                  "kind" TEXT NOT NULL DEFAULT ''
                ) STRICT
                """
            ).execute(db)
        }
        migrator.registerMigration("Add group icon opens") { db in
            try #sql(#"ALTER TABLE "groups" ADD COLUMN "iconOpens" INTEGER NOT NULL DEFAULT 0"#).execute(db)
        }
        migrator.registerMigration("Add events") { db in
            try #sql(
                """
                CREATE TABLE "events" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "homeID" TEXT NOT NULL REFERENCES "homes"("id") ON DELETE CASCADE,
                  "deviceID" TEXT NOT NULL,
                  "isActive" INTEGER NOT NULL DEFAULT 0,
                  "date" TEXT NOT NULL,
                  "notSeenSince" TEXT
                ) STRICT
                """
            ).execute(db)
            try #sql(#"CREATE INDEX "events_deviceID_date" ON "events"("deviceID", "date")"#).execute(db)
        }
        return migrator
    }

    /// iCloud needs ids that are unique everywhere and no other uniqueness rules, and a home every row belongs to.
    /// Integer ids become UUIDs; references to groups follow them.
    nonisolated private static func migrateToSyncableTables(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE "homes" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
              "name" TEXT NOT NULL DEFAULT ''
            ) STRICT;
            INSERT INTO "homes" ("id")
              SELECT "homeID" FROM "rooms" UNION SELECT "homeID" FROM "items" UNION SELECT "homeID" FROM "cards"
              UNION SELECT "homeID" FROM "groups" UNION SELECT "id" FROM "appearances";
            ALTER TABLE "rooms" RENAME TO "oldRooms";
            ALTER TABLE "items" RENAME TO "oldItems";
            ALTER TABLE "cards" RENAME TO "oldCards";
            ALTER TABLE "groups" RENAME TO "oldGroups";
            ALTER TABLE "appearances" RENAME TO "oldAppearances";
            CREATE TABLE "rooms" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "homeID" TEXT NOT NULL REFERENCES "homes"("id") ON DELETE CASCADE,
              "name" TEXT NOT NULL,
              "icon" TEXT,
              "position" INTEGER NOT NULL DEFAULT 0,
              "isPinned" INTEGER NOT NULL DEFAULT 0
            ) STRICT;
            INSERT INTO "rooms" ("homeID", "name", "icon", "position", "isPinned")
              SELECT "homeID", "name", "icon", "position", "isPinned" FROM "oldRooms";
            CREATE TABLE "items" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "homeID" TEXT NOT NULL REFERENCES "homes"("id") ON DELETE CASCADE,
              "deviceID" TEXT NOT NULL,
              "icon" TEXT,
              "position" INTEGER NOT NULL DEFAULT 0,
              "isPinned" INTEGER NOT NULL DEFAULT 0,
              "isHidden" INTEGER NOT NULL DEFAULT 0
            ) STRICT;
            INSERT INTO "items" ("homeID", "deviceID", "icon", "position", "isPinned", "isHidden")
              SELECT "homeID", "deviceID", "icon", "position", "isPinned", "isHidden" FROM "oldItems";
            CREATE TABLE "groups" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "homeID" TEXT NOT NULL REFERENCES "homes"("id") ON DELETE CASCADE,
              "kind" TEXT NOT NULL DEFAULT 'group',
              "name" TEXT NOT NULL DEFAULT '',
              "icon" TEXT,
              "members" TEXT NOT NULL DEFAULT '',
              "mainID" TEXT
            ) STRICT;
            CREATE TABLE "cards" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "homeID" TEXT NOT NULL REFERENCES "homes"("id") ON DELETE CASCADE,
              "kind" TEXT NOT NULL,
              "ref" TEXT NOT NULL DEFAULT '',
              "x" INTEGER NOT NULL DEFAULT 0,
              "y" INTEGER NOT NULL DEFAULT 0,
              "width" INTEGER NOT NULL DEFAULT 2,
              "height" INTEGER NOT NULL DEFAULT 2,
              "columns" INTEGER NOT NULL DEFAULT 4,
              "memberID" TEXT NOT NULL DEFAULT '',
              "folderID" TEXT
            ) STRICT;
            CREATE TABLE "appearances" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE REFERENCES "homes"("id") ON DELETE CASCADE,
              "background" TEXT NOT NULL DEFAULT 'aurora',
              "photo" BLOB,
              "tileOpacity" REAL NOT NULL DEFAULT 0.6,
              "gradientJSON" BLOB
            ) STRICT;
            INSERT INTO "appearances" SELECT "id", "background", "photo", "tileOpacity", "gradientJSON" FROM "oldAppearances";
            """)
        // Groups get new ids; collections listing a group, and cards showing one, follow.
        var newIDs: [Int64: String] = [:]
        var newItemIDs: [String: String] = [:]
        let groups = try Row.fetchAll(db, sql: #"SELECT * FROM "oldGroups""#)
        for row in groups {
            let id: Int64 = row["id"]
            newIDs[id] = UUID().uuidString
            newItemIDs[String(format: "00000000-0000-4000-8000-%012llX", id)] = newIDs[id]!
        }
        for row in groups {
            let members = (row["members"] as String).split(separator: ",").map { newItemIDs[String($0)] ?? String($0) }.joined(separator: ",")
            try db.execute(
                sql: #"INSERT INTO "groups" VALUES (?, ?, ?, ?, ?, ?, ?)"#,
                arguments: [newIDs[row["id"]]!.lowercased(), row["homeID"], row["kind"], row["name"], row["icon"], members, row["mainID"]]
            )
        }
        for row in try Row.fetchAll(db, sql: #"SELECT * FROM "oldCards""#) {
            let kind: String = row["kind"]
            var ref: String = row["ref"]
            if ["group", "collection", "folder"].contains(kind) {
                guard let id = Int64(ref).flatMap({ newIDs[$0] }) else { continue }
                ref = id
            }
            let folderID = (row["folderID"] as Int64?).flatMap { newIDs[$0]?.lowercased() }
            try db.execute(
                sql: #"INSERT INTO "cards" ("homeID", "kind", "ref", "x", "y", "width", "height", "columns", "memberID", "folderID") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"#,
                arguments: [row["homeID"], kind, ref, row["x"], row["y"], row["width"], row["height"], row["columns"], row["memberID"], folderID]
            )
        }
        try db.execute(sql: #"DROP TABLE "oldRooms"; DROP TABLE "oldItems"; DROP TABLE "oldCards"; DROP TABLE "oldGroups"; DROP TABLE "oldAppearances""#)
    }

    /// Every row belongs to a home; this makes sure the home's row is there.
    static func ensureHome(_ id: String, name: String, in db: Database) throws {
        try Home.upsert { Home(id: id, name: name) }.execute(db)
    }
}
