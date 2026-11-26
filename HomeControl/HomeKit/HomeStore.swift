import HomeKit
import SQLiteData
import SwiftUI
import WidgetKit

enum HomeAccess {
    case notRequested, pending, authorized, denied
}

/// A home the user can switch to in Settings.
struct HomeOption: Identifiable, Hashable {
    let id: String
    let name: String

    static let demo = HomeOption(id: "demo", name: "Demo Home")
}

/// Mirrors the selected Apple Home via HomeKit, or the built-in demo home.
@Observable
final class HomeStore: NSObject {
    static let shared = HomeStore()

    private(set) var devices: [Device] = [] {
        didSet {
            let old = Dictionary(oldValue.map { ($0.id, $0.currentState) }) { first, _ in first }
            for device in devices where old[device.id] != device.currentState {
                lastChanged[device.id] = .now
            }
            saveSnapshot()
        }
    }
    /// When an item's reported state last changed, while the app was running: HomeKit doesn't keep a history.
    private(set) var lastChanged: [UUID: Date] = [:]
    private(set) var homeName = "Home"
    private(set) var access = HomeAccess.notRequested
    private(set) var homes: [HomeOption] = [.demo]
    private(set) var currentHomeID: String?
    var message: String? = "Allow Home access in Settings to see your accessories."

    /// Created on demand: instantiating HMHomeManager is what triggers the system permission prompt.
    @ObservationIgnored private var manager: HMHomeManager?
    @ObservationIgnored private var services: [UUID: HMService] = [:]
    private(set) var cameras: [UUID: HMCameraProfile] = [:]
    @ObservationIgnored @FetchAll private var groupRows: [DeviceGroup]

    private static let requestedKey = "homeAccessRequested"
    private static let homeKey = "selectedHome"

    override init() {
        super.init()
        if UserDefaults.standard.string(forKey: Self.homeKey) == HomeOption.demo.id { reload() }
    }

    var isDemo: Bool { currentHomeID == HomeOption.demo.id }

    func requestAccess() {
        guard manager == nil else { return }
        UserDefaults.standard.set(true, forKey: Self.requestedKey)
        access = .pending
        if !isDemo { message = "Loading Home…" }
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    /// Reconnects on launch if access was requested before, without prompting users who chose "Not Now".
    func reconnect() {
        if UserDefaults.standard.bool(forKey: Self.requestedKey) { requestAccess() }
    }

    func selectHome(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.homeKey)
        reload()
    }

    var rooms: [String] {
        devices.reduce(into: []) { if !$0.contains($1.room) { $0.append($1.room) } }
    }

    func binding(for device: Device) -> Binding<Device> {
        Binding(
            get: { (self.devices + self.groupDevices).first { $0.id == device.id } ?? device },
            set: { self.update($0) }
        )
    }

    // MARK: - Groups

    /// This home's groups, collections and folders.
    func groups(_ kind: DeviceGroup.Kind) -> [DeviceGroup] {
        groupRows.filter { $0.homeID == currentHomeID && $0.kind == kind }
    }

    var allGroups: [DeviceGroup] {
        groupRows.filter { $0.homeID == currentHomeID }
    }

    func group(id: Int) -> DeviceGroup? {
        groupRows.first { $0.id == id }
    }

    /// The group an item stands in for.
    func group(for deviceID: UUID) -> DeviceGroup? {
        groups(.group).first { $0.deviceID == deviceID }
    }

    func members(of group: DeviceGroup) -> [Device] {
        group.memberIDs.compactMap { id in devices.first { $0.id == id } }
    }

    /// The items of a room, with groups standing in for their members.
    func items(in room: String) -> [Device] {
        let grouped = groupedIDs
        return groupDevices.filter { $0.room == room } + devices.filter { $0.room == room && !grouped.contains($0.id) }
    }

    /// Items that are in a group: the rooms show the group instead.
    var groupedIDs: Set<UUID> {
        Set(groups(.group).flatMap(\.memberIDs))
    }

    /// Each group as one item: the main member's state, or on when any member is.
    var groupDevices: [Device] {
        devices(for: groups(.group))
    }

    private func devices(for groups: [DeviceGroup]) -> [Device] {
        groups.compactMap { group in
            let members = members(of: group)
            guard let first = members.first else { return nil }
            let main = members.first { $0.id == group.mainID }
            var device = main ?? first.setting(active: members.contains(where: \.isActive))
            device.id = group.deviceID
            device.name = group.name.isEmpty ? first.accessoryName : group.name
            device.accessoryName = String(localized: "\(members.count) items")
            // In the room most of its members are in, where it takes their place.
            let rooms = members.map(\.room)
            device.room = rooms.max { a, b in rooms.count(of: a) < rooms.count(of: b) } ?? first.room
            device.isReachable = members.contains(where: \.isReachable)
            device.customIcon = group.icon
            return device
        }
    }

    /// The main member takes the group's new state; without one, every member is switched.
    private func update(group: DeviceGroup, to new: Device) -> [Task<Void, any Error>] {
        let members = members(of: group)
        if let main = members.first(where: { $0.id == group.mainID }) {
            var target = new
            (target.id, target.name, target.accessoryName, target.room, target.customIcon) = (main.id, main.name, main.accessoryName, main.room, nil)
            return update(target)
        }
        return members.filter(\.kind.isControllable).flatMap { update($0.setting(active: new.isActive)) }
    }

    fileprivate func reload() {
        if let manager {
            let status = manager.authorizationStatus
            access = status.contains(.authorized) ? .authorized : status.contains(.determined) ? .denied : .pending
            homes = manager.homes.map { HomeOption(id: $0.uniqueIdentifier.uuidString, name: $0.name) } + [.demo]
        }
        services = [:]
        cameras = [:]

        let selected = UserDefaults.standard.string(forKey: Self.homeKey)
        if selected == HomeOption.demo.id {
            currentHomeID = HomeOption.demo.id
            homeName = HomeOption.demo.name
            DemoHome.seedGroups()
            devices = DemoHome.devices()
            message = nil
            return
        }
        guard let manager else {
            currentHomeID = nil
            devices = []
            message = "Allow Home access in Settings to see your accessories."
            return
        }
        if access == .denied {
            currentHomeID = nil
            message = "Home access denied. Enable it in Settings › Privacy › HomeKit."
            devices = []
            return
        }
        guard let home = manager.homes.first(where: { $0.uniqueIdentifier.uuidString == selected }) ?? manager.homes.first else {
            currentHomeID = nil
            message = "No home found. Set one up in the Home app or try the Demo Home."
            devices = []
            return
        }
        currentHomeID = home.uniqueIdentifier.uuidString
        homeName = home.name
        var result: [Device] = []
        for accessory in home.accessories {
            accessory.delegate = self
            for service in accessory.services {
                guard let kind = DeviceKind(serviceType: service.serviceType) else { continue }
                services[service.uniqueIdentifier] = service
                result.append(Device(service: service, kind: kind))
                subscribe(to: service, kind: kind)
            }
            for camera in accessory.cameraProfiles ?? [] {
                cameras[camera.uniqueIdentifier] = camera
                result.append(Device(camera: camera, accessory: accessory))
            }
        }
        devices = result
        message = result.isEmpty ? "No supported accessories in \(home.name)." : nil
    }

    private func subscribe(to service: HMService, kind: DeviceKind) {
        for c in service.characteristics where kind.characteristicTypes.contains(c.characteristicType) {
            Task {
                if c.properties.contains(HMCharacteristicPropertySupportsEventNotification) {
                    try? await c.enableNotification(true)
                }
                try? await c.readValue()
                refresh(service)
            }
        }
    }

    fileprivate func refresh(_ service: HMService) {
        guard services[service.uniqueIdentifier] != nil,
              let i = devices.firstIndex(where: { $0.id == service.uniqueIdentifier }) else { return }
        devices[i] = Device(service: service, kind: devices[i].kind)
    }

    /// Optimistically updates the UI, then writes the changed characteristics to HomeKit.
    /// The writes, to wait for; they fail when HomeKit refuses, as it does for an app in the background.
    @discardableResult
    private func update(_ new: Device) -> [Task<Void, any Error>] {
        if let group = group(for: new.id) { return update(group: group, to: new) }
        guard let i = devices.firstIndex(where: { $0.id == new.id }) else { return [] }
        if isDemo {
            simulate(from: devices[i], to: new)
            return []
        }
        guard let service = services[new.id] else { return [] }
        let writes = new.writes(from: devices[i], on: service)
        devices[i] = new
        return [Task {
            defer { refresh(service) }
            do {
                for (characteristic, value) in writes { try await characteristic.writeValue(value) }
            } catch {
                message = "\(new.name): \(error.localizedDescription)"
                throw error
            }
        }]
    }

    /// Demo accessories react like real ones: the garage door takes a moment to move.
    private func simulate(from old: Device, to new: Device) {
        guard let i = devices.firstIndex(where: { $0.id == new.id }) else { return }
        var device = new
        switch device.kind {
        case .lock: device.currentState = device.isOn ? 1 : 0
        case .blinds: device.currentValue = device.value
        case .garage where old.isOn != new.isOn:
            device.currentState = device.isOn ? 3 : 2
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                guard let j = devices.firstIndex(where: { $0.id == new.id }), devices[j].currentState == 2 || devices[j].currentState == 3 else { return }
                devices[j].currentState = devices[j].isOn ? 1 : 0
            }
        case .plug where device.accessoryName == DemoHome.speaker && device.isOn && device.name != "Mute":
            // Play, Pause and Stop exclude each other, like the player behind them.
            for j in devices.indices where devices[j].accessoryName == DemoHome.speaker && !["Mute", device.name].contains(devices[j].name) {
                devices[j].isOn = false
            }
        default: break
        }
        devices[i] = device
    }
}

extension HomeStore {
    private var home: HMHome? {
        manager?.homes.first { $0.uniqueIdentifier.uuidString == currentHomeID }
    }

    /// Every room an item can move to, including empty ones.
    var allRooms: [String] {
        guard !isDemo, let home else { return rooms }
        return home.rooms.map(\.name)
    }

    /// Renames it in Apple Home too, so Siri and the Home app use the new name.
    func rename(_ device: Device, to name: String) {
        guard let i = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[i].name = name
        guard !isDemo, let service = services[device.id] else { return }
        Task {
            do {
                try await service.updateName(name)
            } catch {
                message = "\(device.name): \(error.localizedDescription)"
            }
            refresh(service)
        }
    }

    /// Moves the whole accessory: HomeKit puts accessories in rooms, not single services.
    func move(_ device: Device, to roomName: String) {
        guard let i = devices.firstIndex(where: { $0.id == device.id }) else { return }
        guard !isDemo else {
            devices[i].room = roomName
            return
        }
        guard let service = services[device.id], let accessory = service.accessory,
              let home, let room = home.rooms.first(where: { $0.name == roomName }) else { return }
        Task {
            do {
                try await home.assignAccessory(accessory, to: room)
            } catch {
                message = "\(device.name): \(error.localizedDescription)"
            }
            accessory.services.forEach(refresh)
        }
    }

    /// Apple's own screen for inviting people to the home and setting what they may do.
    func manageMembers() {
        guard let home else { return }
        home.manageUsers { error in
            if let error { logger.error("Managing members failed: \(error)") }
        }
    }

    /// From a widget or control: waits for HomeKit to load the home when the app was launched for it.
    func set(_ id: UUID, active: Bool) async throws {
        reconnect()
        for _ in 0 ..< 50 where !(devices + groupDevices).contains(where: { $0.id == id }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let device = (devices + groupDevices).first(where: { $0.id == id }), device.isActive != active else { return }
        for write in update(device.toggled()) {
            try await write.value
        }
    }

    /// The widgets read the home from here; reloaded at most every few seconds while sliders move.
    func saveSnapshot() {
        guard let currentHomeID else { return }
        @Dependency(\.defaultDatabase) var database
        do {
            // Read afresh: right after a group is saved, the fetched groups haven't caught up yet.
            let groups = try database.read { db in
                try DeviceGroup.where { $0.homeID.eq(currentHomeID) && $0.kind.eq(DeviceGroup.Kind.group) }.fetchAll(db)
            }
            let snapshot = try Snapshot(id: currentHomeID, homeName: homeName, devicesJSON: JSONEncoder().encode(devices + devices(for: groups)), updatedAt: .now)
            try database.write { db in try Snapshot.upsert { snapshot }.execute(db) }
        } catch {
            logger.error("Saving the widget snapshot failed: \(error)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension HomeStore: @MainActor HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { reload() }
    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) { reload() }
}

// HomeKit delivers delegate callbacks on the main queue.
extension HomeStore: HMAccessoryDelegate {
    nonisolated func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        MainActor.assumeIsolated { refresh(service) }
    }

    nonisolated func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        MainActor.assumeIsolated { accessory.services.forEach(refresh) }
    }

    nonisolated func accessoryDidUpdateName(_ accessory: HMAccessory) {
        MainActor.assumeIsolated { accessory.services.forEach(refresh) }
    }

    nonisolated func accessoryDidUpdateServices(_ accessory: HMAccessory) {
        MainActor.assumeIsolated { reload() }
    }
}

private extension Array where Element: Equatable {
    func count(of element: Element) -> Int { count { $0 == element } }
}
