import SwiftUI
import HomeKit

enum HomeAccess {
    case notRequested, pending, authorized, denied
}

/// Mirrors the first home of the Apple Home app via HomeKit.
@Observable
final class HomeStore: NSObject {
    private(set) var devices: [Device] = []
    private(set) var homeName = "Home"
    private(set) var access = HomeAccess.notRequested
    var message: String? = "Allow Home access in Settings to see your accessories."

    /// Created on demand: instantiating HMHomeManager is what triggers the system permission prompt.
    @ObservationIgnored private var manager: HMHomeManager?
    @ObservationIgnored private var services: [UUID: HMService] = [:]

    private static let requestedKey = "homeAccessRequested"

    func requestAccess() {
        guard manager == nil else { return }
        UserDefaults.standard.set(true, forKey: Self.requestedKey)
        access = .pending
        message = "Loading Home…"
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    /// Reconnects on launch if access was requested before, without prompting users who chose "Not Now".
    func reconnect() {
        if UserDefaults.standard.bool(forKey: Self.requestedKey) { requestAccess() }
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
        guard let manager else { return }
        let status = manager.authorizationStatus
        access = status.contains(.authorized) ? .authorized : status.contains(.determined) ? .denied : .pending
        if access == .denied {
            message = "Home access denied. Enable it in Settings › Privacy › HomeKit."
            devices = []
            return
        }
        guard let home = manager.homes.first else {
            message = "No home found. Set one up in the Home app."
            devices = []
            return
        }
        homeName = home.name
        services = [:]
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
        guard let i = devices.firstIndex(where: { $0.id == service.uniqueIdentifier }) else { return }
        devices[i] = Device(service: service, kind: devices[i].kind)
    }

    /// Optimistically updates the UI, then writes the changed characteristics to HomeKit.
    private func update(_ new: Device) {
        guard let i = devices.firstIndex(where: { $0.id == new.id }),
              let service = services[new.id] else { return }
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
