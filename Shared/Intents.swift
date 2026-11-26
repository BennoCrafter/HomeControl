import AppIntents
import SQLiteData
import WidgetKit

/// The home as the app last saw it. Widgets can't talk to HomeKit; they read this.
enum WidgetData {
    private static let database: (any DatabaseWriter)? = try? Schema.database()

    /// The home the app showed last.
    static func snapshot() -> Snapshot? {
        try? database?.read { db in try Snapshot.order { $0.updatedAt.desc() }.fetchOne(db) }
    }

    private static func cameraURL(_ id: UUID) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(path: "camera-\(id.uuidString).jpg")
    }

    /// A camera's latest still, written by the app for the camera widget.
    static func saveCameraImage(_ data: Data, for id: UUID) {
        guard let url = cameraURL(id) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func cameraImage(for id: UUID) -> (data: Data, date: Date)? {
        guard let url = cameraURL(id), let data = try? Data(contentsOf: url),
              let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        return (data, date)
    }

    /// Flips an item in the snapshot right away, so the widget answers the tap before HomeKit does.
    static func update(_ id: UUID, _ change: (inout Device) -> Void) {
        guard var snapshot = snapshot() else { return }
        var devices = snapshot.devices
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        change(&devices[index])
        guard let json = try? JSONEncoder().encode(devices) else { return }
        snapshot.devicesJSON = json
        try? database?.write { db in try Snapshot.upsert { snapshot }.execute(db) }
    }
}

/// Set by the app at launch: writes to HomeKit. Nil in the widget's own process.
enum DeviceActions {
    nonisolated(unsafe) static var setOn: (@MainActor (UUID, Bool) async throws -> Void)?
}

struct DeviceEntity: AppEntity {
    let id: String
    let name: String
    let room: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Accessory"
    static let defaultQuery = DeviceQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(room)")
    }

    init(_ device: Device) {
        id = device.id.uuidString
        name = device.name
        room = device.room
    }
}

struct DeviceQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [DeviceEntity] {
        (WidgetData.snapshot()?.devices ?? []).filter { identifiers.contains($0.id.uuidString) }.map(DeviceEntity.init)
    }

    @MainActor func suggestedEntities() async throws -> [DeviceEntity] {
        (WidgetData.snapshot()?.devices ?? []).filter { $0.kind.isControllable }.map(DeviceEntity.init)
    }
}

struct RoomEntity: AppEntity {
    let id: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Room"
    static let defaultQuery = RoomQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct RoomQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [RoomEntity] {
        identifiers.map(RoomEntity.init)
    }

    @MainActor func suggestedEntities() async throws -> [RoomEntity] {
        let devices = WidgetData.snapshot()?.devices ?? []
        return devices.reduce(into: [String]()) { if !$0.contains($1.room) { $0.append($1.room) } }.map(RoomEntity.init)
    }
}

/// A live activity intent runs in the app's process, which is the one that can reach HomeKit.
struct ToggleDeviceIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Accessory"
    static let isDiscoverable = false

    @Parameter(title: "Accessory ID")
    var id: String

    init() {}

    init(id: UUID) {
        self.id = id.uuidString
    }

    @MainActor func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: id), let device = WidgetData.snapshot()?.devices.first(where: { $0.id == uuid }) else {
            return .result()
        }
        let target = device.toggled()
        WidgetData.update(uuid) { $0 = target }
        WidgetCenter.shared.reloadAllTimelines()
        try await setInForegroundIfNeeded(uuid, target.isActive)
        return .result()
    }

    @available(iOS 26, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
}

extension AppIntent {
    /// HomeKit only takes writes from an app on screen; when it refuses in the background, the app comes forward and tries again.
    @MainActor func setInForegroundIfNeeded(_ id: UUID, _ active: Bool) async throws {
        do {
            try await DeviceActions.setOn?(id, active)
        } catch {
            guard #available(iOS 26, *) else { throw error }
            try await continueInForeground(alwaysConfirm: false)
            try await DeviceActions.setOn?(id, active)
        }
    }
}

/// The Control Center toggle's action.
struct SetDeviceIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn Accessory On or Off"
    static let isDiscoverable = false

    @Parameter(title: "Accessory")
    var device: DeviceEntity?

    @Parameter(title: "On")
    var value: Bool

    init() {}

    @MainActor func perform() async throws -> some IntentResult {
        guard let id = device.flatMap({ UUID(uuidString: $0.id) }) else { return .result() }
        WidgetData.update(id) { device in
            if device.kind == .blinds { device.value = value ? 1 : 0 } else { device.isOn = device.kind == .garage ? !value : value }
        }
        ControlCenter.shared.reloadAllControls()
        try await setInForegroundIfNeeded(id, value)
        return .result()
    }

    @available(iOS 26, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
}
