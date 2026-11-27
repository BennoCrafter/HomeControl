import Foundation
import SQLiteData
import TipKit

/// Writes groups, collections and folders, and tells the widgets about them.
@MainActor
enum Groups {
    /// Inserts a new one or replaces an existing one; returns its id.
    @discardableResult
    static func save(_ group: DeviceGroup.Draft) -> UUID? {
        @Dependency(\.defaultDatabase) var database
        do {
            let id = try database.write { db in try DeviceGroup.upsert { group }.returning(\.id).fetchOne(db) }
            switch group.kind {
            case .group: GroupTip().invalidate(reason: .actionPerformed)
            case .folder: FolderTip().invalidate(reason: .actionPerformed)
            case .collection: break
            }
            HomeStore.shared.saveSnapshot()
            return id
        } catch {
            logger.error("Saving group \(group.name) failed: \(error)")
            return nil
        }
    }

    /// Removes it, and every dashboard card showing it or sitting in it.
    static func delete(_ id: UUID) {
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in
                try DeviceGroup.find(id).delete().execute(db)
                try DashboardCard.where { $0.folderID.eq(id) }.delete().execute(db)
            }
            HomeStore.shared.saveSnapshot()
        } catch {
            logger.error("Deleting group \(id) failed: \(error)")
        }
    }
}
