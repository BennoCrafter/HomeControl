import CloudKit
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
            recordChanges()
            // Debounced: a slider changes this ten times a second, and each snapshot reloads every widget.
            snapshotTask?.cancel()
            snapshotTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                if !Task.isCancelled { saveSnapshot() }
            }
        }
    }
    /// Each item's latest saved state change, read from the history once per home: HomeKit keeps none.
    private(set) var since: [UUID: ItemEvent] = [:]
    @ObservationIgnored private var sinceHomeID: String?
    /// When the app became active; nil in the background, when HomeKit tells it nothing.
    @ObservationIgnored private var activeSince: Date? = .now
    /// When the app last watched the home, so a change found later happened sometime after it.
    @ObservationIgnored private var watchedUntil = UserDefaults.standard.object(forKey: "watchedUntil") as? Date
    private(set) var homeName = "Home"
    private(set) var access = HomeAccess.notRequested
    /// This person's Apple homes.
    private(set) var appleHomes: [HomeOption] = []
    /// Removed in Settings; Diagnostics brings it back.
    var showsDemoHome = UserDefaults.standard.object(forKey: "showsDemoHome") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsDemoHome, forKey: "showsDemoHome") }
    }
    var homes: [HomeOption] { appleHomes + (showsDemoHome ? [.demo] : []) }
    /// The home's id in this app's data: HomeKit's own, or the shared one when a family member shared theirs.
    private(set) var currentHomeID: String? {
        didSet { if let currentHomeID { UserDefaults.standard.set(currentHomeID, forKey: Self.lastHomeKey) } }
    }
    /// The home shown last time, for its look while HomeKit is still loading.
    static let lastHomeKey = "lastHomeID"
    /// HomeKit's id of the home on this device; differs per person.
    private(set) var homeKitID: String?
    var message: String? = "Allow Home access in Settings to see your accessories."

    /// Created on demand: instantiating HMHomeManager is what triggers the system permission prompt.
    @ObservationIgnored private var manager: HMHomeManager?
    @ObservationIgnored private var services: [UUID: HMService] = [:]
    /// When this app last asked an item to change; until then a differing current state is it still moving.
    @ObservationIgnored private var lastWrite: [UUID: Date] = [:]
    @ObservationIgnored private var pendingWidgetTaps = 0
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    /// One HomeKit write per item at a time: queued writes made a dragged light trail far behind the finger.
    @ObservationIgnored private var writing: [UUID: Task<Void, any Error>] = [:]
    /// What each item was last asked to become; a running write sends this next, not HomeKit's possibly older echo.
    @ObservationIgnored private var writeTargets: [UUID: Device] = [:]
    /// This device's HomeKit ids to the shared ids items are known by.
    @ObservationIgnored private var sharedIDs: [UUID: UUID] = [:]
    private(set) var cameras: [UUID: HMCameraProfile] = [:]
    @ObservationIgnored @FetchAll private var groupRows: [DeviceGroup]
    /// This person's iCloud user, whose dashboard is "Me"; empty without iCloud.
    private(set) var meID = UserDefaults.standard.string(forKey: "iCloudUserID") ?? ""
    /// Me, then everyone else in the home's iCloud share.
    private(set) var people: [Profiles.Profile] = []

    private static let requestedKey = "homeAccessRequested"
    private static let homeKey = "selectedHome"

    override init() {
        super.init()
        people = [Profiles.Profile(id: meID, name: String(localized: "Me"))]
        Task { await loadMe() }
        if UserDefaults.standard.string(forKey: Self.homeKey) == HomeOption.demo.id { reload() }
    }

    var isDemo: Bool { currentHomeID == HomeOption.demo.id }

    func requestAccess() {
        guard manager == nil else { return }
        UserDefaults.standard.set(true, forKey: Self.requestedKey)
        access = .pending
        if !isDemo { message = String(localized: "Loading Home…") }
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    /// Reconnects on launch if access was requested before, without prompting users who chose "Not Now".
    func reconnect() {
        if UserDefaults.standard.bool(forKey: Self.requestedKey) { requestAccess() }
    }

    func selectHome(_ id: String) {
        if id == HomeOption.demo.id { showsDemoHome = true }
        UserDefaults.standard.set(id, forKey: Self.homeKey)
        reload()
    }

    /// Takes the Demo Home out of the lists, moving to a real home if it was showing.
    func removeDemoHome() {
        showsDemoHome = false
        if isDemo { selectHome(appleHomes.first?.id ?? "") }
    }

    /// Renames it in Apple Home, so everyone in it and Siri see the new name.
    func renameHome(_ id: String, to name: String) {
        guard let home = manager?.homes.first(where: { $0.uniqueIdentifier.uuidString == id }) else { return }
        Task {
            do {
                try await home.updateName(name)
                reload()
            } catch {
                message = "\(home.name): \(error.localizedDescription)"
            }
        }
    }

    var rooms: [String] {
        devices.reduce(into: []) { if !$0.contains($1.room) { $0.append($1.room) } }
    }

    func binding(for device: Device) -> Binding<Device> {
        Binding(
            // Groups only when it isn't a plain item: building them is the slow part, and this runs per tile per frame.
            get: { self.devices.first { $0.id == device.id } ?? self.groupDevices.first { $0.id == device.id } ?? device },
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

    func group(id: UUID) -> DeviceGroup? {
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
            appleHomes = manager.homes.map { HomeOption(id: $0.uniqueIdentifier.uuidString, name: $0.name) }
        }
        services = [:]
        cameras = [:]
        sharedIDs = [:]

        let selected = UserDefaults.standard.string(forKey: Self.homeKey)
        if selected == HomeOption.demo.id {
            currentHomeID = HomeOption.demo.id
            homeKitID = HomeOption.demo.id
            homeName = HomeOption.demo.name
            saveHome()
            DemoHome.seedGroups()
            devices = DemoHome.devices()
            message = nil
            return
        }
        guard let manager else {
            (currentHomeID, homeKitID) = (nil, nil)
            devices = []
            message = String(localized: "Allow Home access in Settings to see your accessories.")
            return
        }
        if access == .denied {
            (currentHomeID, homeKitID) = (nil, nil)
            message = String(localized: "Home access denied. Enable it in Settings › Privacy › HomeKit.")
            devices = []
            return
        }
        guard let home = manager.homes.first(where: { $0.uniqueIdentifier.uuidString == selected }) ?? manager.homes.first else {
            (currentHomeID, homeKitID) = (nil, nil)
            message = String(localized: "No home found. Set one up in the Home app or try the Demo Home.")
            devices = []
            return
        }
        homeKitID = home.uniqueIdentifier.uuidString
        currentHomeID = sharedHomeID(named: home.name) ?? homeKitID
        homeName = home.name
        saveHome()
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
        sharedIDs = matchSharedIDs(result)
        services = Dictionary(services.map { (sharedIDs[$0.key] ?? $0.key, $0.value) }) { first, _ in first }
        cameras = Dictionary(cameras.map { (sharedIDs[$0.key] ?? $0.key, $0.value) }) { first, _ in first }
        devices = result.map { device in
            var device = device
            device.id = sharedIDs[device.id] ?? device.id
            return device
        }
        saveItemDirectory()
        loadPeople()
        message = result.isEmpty ? String(localized: "No supported accessories in \(home.name).") : nil
    }

    /// Reloads when a family member's shared home arrives, so its groups and dashboards line up with this device.
    func homesChanged() {
        loadPeople()
        guard !isDemo, let currentHomeID, sharedHomeID(named: homeName) ?? homeKitID != currentHomeID else { return }
        reload()
    }

    // MARK: - People

    private func loadMe() async {
        do {
            let id = try await CKContainer(identifier: Schema.iCloudContainer).userRecordID().recordName
            guard id != meID else { return }
            meID = id
            UserDefaults.standard.set(id, forKey: "iCloudUserID")
            claimDashboards()
            loadPeople()
        } catch {
            logger.info("No iCloud user: \(error)")
        }
    }

    /// Dashboards made before iCloud knew who's who become this person's.
    private func claimDashboards() {
        @Dependency(\.defaultDatabase) var database
        let me = meID
        try? database.write { db in
            try DashboardCard.where { $0.memberID.eq("") }.update { $0.memberID = me }.execute(db)
        }
    }

    /// The share of the current home, if it's shared either way.
    func homeShare() -> CKShare? {
        guard let currentHomeID else { return nil }
        @Dependency(\.defaultDatabase) var database
        return try? database.read { db in
            try SyncMetadata.where { $0.recordPrimaryKey.eq(currentHomeID) && $0.recordType.eq(Home.tableName) }.fetchOne(db)?.share
        }
    }

    func loadPeople() {
        let me = Profiles.Profile(id: meID, name: String(localized: "Me"))
        let others = (homeShare()?.participants ?? []).compactMap { participant -> Profiles.Profile? in
            guard participant.acceptanceStatus == .accepted, participant != homeShare()?.currentUserParticipant,
                  let id = participant.userIdentity.userRecordID?.recordName else { return nil }
            let name = participant.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            return Profiles.Profile(id: id == CKCurrentUserDefaultName ? meID : id, name: name ?? String(localized: "Someone"))
        }
        people = [me] + others
    }

    // MARK: - Shared ids

    /// A home with this name that someone else shared with this person's iCloud account.
    private func sharedHomeID(named name: String) -> String? {
        @Dependency(\.defaultDatabase) var database
        return try? database.read { db in
            let shared = try SyncMetadata
                .where { $0.recordType.eq(Home.tableName) && $0.ownerName.neq(CKCurrentUserDefaultName) }
                .select(\.recordPrimaryKey)
                .fetchAll(db)
            return try Home.where { $0.id.in(shared) && $0.name.eq(name) }.fetchOne(db)?.id
        }
    }

    /// Items already in the directory under another id, found by name, room and kind.
    private func matchSharedIDs(_ local: [Device]) -> [UUID: UUID] {
        guard let currentHomeID, currentHomeID != homeKitID else { return [:] }
        @Dependency(\.defaultDatabase) var database
        let known = (try? database.read { db in try HomeItem.where { $0.homeID.eq(currentHomeID) }.fetchAll(db) }) ?? []
        var taken = Set<UUID>()
        var result: [UUID: UUID] = [:]
        for device in local {
            guard let match = known.first(where: { !taken.contains($0.id) && $0.name == device.name && $0.room == device.room
                && $0.kind == device.kind.rawValue }) else { continue }
            taken.insert(match.id)
            result[device.id] = match.id
        }
        return result
    }

    /// Writes how this device names the items, so other people's devices can find theirs.
    private func saveItemDirectory() {
        guard let currentHomeID, !isDemo else { return }
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in
                for device in devices {
                    try HomeItem.upsert {
                        HomeItem(id: device.id, homeID: currentHomeID, name: device.name, room: device.room, kind: device.kind.rawValue)
                    }.execute(db)
                }
            }
        } catch {
            logger.error("Saving the item directory failed: \(error)")
        }
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
        let id = sharedIDs[service.uniqueIdentifier] ?? service.uniqueIdentifier
        guard services[id] != nil, let i = devices.firstIndex(where: { $0.id == id }) else { return }
        var device = Device(service: service, kind: devices[i].kind)
        device.id = id
        // Turned by hand or by another app, a lock or door often reports only its new current state; the old target
        // would then read as "Unlocking…" forever. A settled state nobody here asked for wins.
        if let current = device.currentState, current <= 1, (current == 1) != device.isOn,
           device.kind == .lock || device.kind == .garage,
           Date.now.timeIntervalSince(lastWrite[id] ?? .distantPast) > 30 {
            device.isOn = current == 1
        }
        devices[i] = device
    }

    /// HomeKit sends nothing while the app is in the background: read everything afresh on coming back.
    func readAll() {
        for (id, service) in services {
            guard let kind = devices.first(where: { $0.id == id })?.kind else { continue }
            subscribe(to: service, kind: kind)
        }
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
        let old = devices[i]
        devices[i] = new
        return [write(new, from: old, on: service)]
    }

    /// While a control is dragged: to HomeKit only. Changing `devices` redrew the whole app on every step, which made
    /// the drag stutter; the release goes through `update` like any change.
    func stream(_ new: Device) {
        guard !isDemo, group(for: new.id) == nil, let device = devices.first(where: { $0.id == new.id }),
              let service = services[new.id] else { return }
        write(new, from: device, on: service)
    }

    @discardableResult
    private func write(_ new: Device, from old: Device, on service: HMService) -> Task<Void, any Error> {
        let id = new.id
        var sent = old
        lastWrite[id] = .now
        writeTargets[id] = new
        if let running = writing[id] { return running }
        let task = Task {
            defer {
                writing[id] = nil
                writeTargets[id] = nil
                refresh(service)
            }
            // Sends whatever is newest each round; the in-between values of a drag are skipped, not queued.
            while let target = writeTargets[id], target != sent {
                do {
                    for (characteristic, value) in target.writes(from: sent, on: service) { try await characteristic.writeValue(value) }
                } catch {
                    message = "\(target.name): \(error.localizedDescription)"
                    throw error
                }
                sent = target
            }
        }
        writing[id] = task
        return task
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
        manager?.homes.first { $0.uniqueIdentifier.uuidString == homeKitID }
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

    /// Apple's own screen for inviting people to the home and setting what they may do. `done` runs when it closes.
    func manageMembers(done: @escaping @MainActor () -> Void = {}) {
        guard let home else {
            logger.error("Managing members: no HomeKit home \(self.homeKitID ?? "nil")")
            return done()
        }
        home.manageUsers { error in
            if let error { logger.error("Managing members failed: \(error)") }
            Task { @MainActor in done() }
        }
    }

    /// From a widget or control: waits for HomeKit to load the home when the app was launched for it.
    func set(_ id: UUID, active: Bool) async throws {
        // Until it's done, loading the home mustn't put the old state back into the widget the tap just flipped.
        pendingWidgetTaps += 1
        defer {
            pendingWidgetTaps -= 1
            saveSnapshot()
        }
        reconnect()
        // Launched in the background, HomeKit can take well over 5 s to load the home; an intent may run about 30.
        for _ in 0 ..< 250 where !(devices + groupDevices).contains(where: { $0.id == id }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard (devices + groupDevices).contains(where: { $0.id == id }) else {
            logger.error("Widget tap: \(id) didn't load in time")
            return
        }
        // Launched for a widget tap, HomeKit hands over the accessories before reading them: decided on that, an
        // "off" light would look off already and the tap would be dropped. Read first.
        let group = group(for: id)
        for member in group.map(members(of:)) ?? devices.filter({ $0.id == id }) {
            guard let service = services[member.id] else { continue }
            for characteristic in service.characteristics where member.kind.characteristicTypes.contains(characteristic.characteristicType) {
                try? await characteristic.readValue()
            }
            refresh(service)
        }
        guard let device = (devices + groupDevices).first(where: { $0.id == id }), device.isActive != active else { return }
        for write in update(device.toggled()) {
            try await write.value
        }
    }

    /// The row every preference of this home hangs off.
    private func saveHome() {
        guard let currentHomeID else { return }
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in try Schema.ensureHome(currentHomeID, name: homeName, in: db) }
        } catch {
            logger.error("Saving the home failed: \(error)")
        }
    }

    /// Called as the app comes and goes: changes found right after coming back happened while it wasn't watching.
    func watching(_ active: Bool) {
        if active {
            activeSince = .now
        } else {
            activeSince = nil
            watchedUntil = .now
            UserDefaults.standard.set(Date.now, forKey: "watchedUntil")
        }
    }

    /// Saves every item that switched since its last saved state; the history is what tells how long it's been.
    private func recordChanges() {
        guard let currentHomeID else { return }
        @Dependency(\.defaultDatabase) var database
        let loading = sinceHomeID != currentHomeID
        if loading {
            sinceHomeID = currentHomeID
            do {
                let events = try database.write { db in
                    try ItemEvent.where { $0.date.lt(Date.now.addingTimeInterval(-30 * 24 * 3600)) }.delete().execute(db)
                    return try ItemEvent.where { $0.homeID.eq(currentHomeID) }.order { $0.date.desc() }.fetchAll(db)
                }
                since = Dictionary(events.map { ($0.deviceID, $0) }) { newest, _ in newest }
            } catch {
                logger.error("Reading the history failed: \(error)")
            }
        }
        let now = Date.now
        // shortcut: values still arriving 5 s after coming back count as missed (unless this app just switched it);
        // a slow hub may stamp a live change as missed
        let missed = loading || activeSince.map { now.timeIntervalSince($0) < 5 } ?? true
        let events = devices
            .filter { $0.isReachable && $0.kind != .camera && since[$0.id]?.isActive != $0.isActive }
            .map { device in
                ItemEvent(id: UUID(), homeID: currentHomeID, deviceID: device.id, isActive: device.isActive, date: now,
                          notSeenSince: since[device.id] == nil ? .distantPast
                              : missed && now.timeIntervalSince(lastWrite[device.id] ?? .distantPast) > 5 ? (watchedUntil ?? .distantPast) : nil)
            }
        guard !events.isEmpty else { return }
        for event in events { since[event.deviceID] = event }
        do {
            try database.write { db in try ItemEvent.insert { events }.execute(db) }
        } catch {
            logger.error("Saving the history failed: \(error)")
        }
    }

    /// The widgets read the home from here; reloaded at most every few seconds while sliders move.
    func saveSnapshot() {
        guard let currentHomeID, pendingWidgetTaps == 0 else { return }
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
