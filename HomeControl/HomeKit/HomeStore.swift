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
    private(set) var devices: [Device] = [] {
        didSet { saveSnapshot() }
    }
    private(set) var homeName = "Home"
    private(set) var access = HomeAccess.notRequested
    private(set) var homes: [HomeOption] = [.demo]
    private(set) var currentHomeID: String?
    var message: String? = "Allow Home access in Settings to see your accessories."

    /// Created on demand: instantiating HMHomeManager is what triggers the system permission prompt.
    @ObservationIgnored private var manager: HMHomeManager?
    @ObservationIgnored private var services: [UUID: HMService] = [:]

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
            get: { self.devices.first { $0.id == device.id } ?? device },
            set: { self.update($0) }
        )
    }

    fileprivate func reload() {
        if let manager {
            let status = manager.authorizationStatus
            access = status.contains(.authorized) ? .authorized : status.contains(.determined) ? .denied : .pending
            homes = manager.homes.map { HomeOption(id: $0.uniqueIdentifier.uuidString, name: $0.name) } + [.demo]
        }
        services = [:]

        let selected = UserDefaults.standard.string(forKey: Self.homeKey)
        if selected == HomeOption.demo.id {
            currentHomeID = HomeOption.demo.id
            homeName = HomeOption.demo.name
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
    private func update(_ new: Device) {
        guard let i = devices.firstIndex(where: { $0.id == new.id }) else { return }
        if isDemo {
            simulate(from: devices[i], to: new)
            return
        }
        guard let service = services[new.id] else { return }
        let writes = new.writes(from: devices[i], on: service)
        devices[i] = new
        Task {
            do {
                for (characteristic, value) in writes { try await characteristic.writeValue(value) }
            } catch {
                message = "\(new.name): \(error.localizedDescription)"
            }
            refresh(service)
        }
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
        default: break
        }
        devices[i] = device
    }
}

extension HomeStore {
    /// The widgets read the home from here; reloaded at most every few seconds while sliders move.
    private func saveSnapshot() {
        guard let currentHomeID else { return }
        @Dependency(\.defaultDatabase) var database
        do {
            let snapshot = try Snapshot(id: currentHomeID, homeName: homeName, devicesJSON: JSONEncoder().encode(devices), updatedAt: .now)
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
