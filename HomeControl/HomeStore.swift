import SwiftUI
import HomeKit

enum DeviceKind {
    case light, thermostat, lock, plug, blinds

    init?(serviceType: String) {
        switch serviceType {
        case HMServiceTypeLightbulb: self = .light
        case HMServiceTypeThermostat: self = .thermostat
        case HMServiceTypeLockMechanism: self = .lock
        case HMServiceTypeOutlet, HMServiceTypeSwitch: self = .plug
        case HMServiceTypeWindowCovering: self = .blinds
        default: return nil
        }
    }

    /// Characteristic behind `Device.isOn` (read and written).
    var powerType: String? {
        switch self {
        case .light, .plug: HMCharacteristicTypePowerState
        case .thermostat: HMCharacteristicTypeTargetHeatingCooling
        case .lock: HMCharacteristicTypeTargetLockMechanismState
        case .blinds: nil
        }
    }

    /// Characteristic behind `Device.value` (read and written).
    var valueType: String? {
        switch self {
        case .light: HMCharacteristicTypeBrightness
        case .thermostat: HMCharacteristicTypeTargetTemperature
        case .blinds: HMCharacteristicTypeTargetPosition
        case .lock, .plug: nil
        }
    }

    var icon: String {
        switch self {
        case .light: "lightbulb.fill"
        case .thermostat: "thermometer.medium"
        case .lock: "lock.fill"
        case .plug: "powerplug.fill"
        case .blinds: "blinds.horizontal.closed"
        }
    }

    var tint: Color {
        switch self {
        case .light: .yellow
        case .thermostat: .orange
        case .lock: .teal
        case .plug: .green
        case .blinds: .indigo
        }
    }
}

struct Device: Identifiable {
    let id: UUID
    var name: String
    var room: String
    var kind: DeviceKind
    var isOn: Bool
    /// Brightness, blinds position (0...1) or target temperature (°C), depending on kind.
    var value: Double

    var status: String {
        switch kind {
        case .light: isOn ? "\(Int(value * 100))%" : "Off"
        case .thermostat: isOn ? String(format: "%.1f °C", value) : "Off"
        case .lock: isOn ? "Locked" : "Unlocked"
        case .plug: isOn ? "On" : "Off"
        case .blinds: value == 0 ? "Closed" : "\(Int(value * 100))% open"
        }
    }
}

/// Mirrors the Apple Home app's primary home via HomeKit.
@Observable
final class HomeStore: NSObject {
    var devices: [Device] = []
    var homeName = "Home"
    var message: String? = "Loading Home…"

    @ObservationIgnored private let manager = HMHomeManager()
    @ObservationIgnored private var services: [UUID: HMService] = [:]

    override init() {
        super.init()
        manager.delegate = self
    }

    var rooms: [String] {
        devices.reduce(into: []) { if !$0.contains($1.room) { $0.append($1.room) } }
    }

    func binding(for device: Device) -> Binding<Device> {
        Binding(
            get: { self.devices.first { $0.id == device.id } ?? device },
            set: { new in self.update(new) }
        )
    }

    private func reload() {
        if manager.authorizationStatus.contains(.determined), !manager.authorizationStatus.contains(.authorized) {
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
                result.append(device(from: service, kind: kind))
                let relevant = service.characteristics.filter { [kind.powerType, kind.valueType].contains($0.characteristicType) }
                for c in relevant {
                    Task {
                        try? await c.enableNotification(true)
                        try? await c.readValue()
                        refresh(service)
                    }
                }
            }
        }
        devices = result
        message = result.isEmpty ? "No supported accessories in \(home.name)." : nil
    }

    private func device(from service: HMService, kind: DeviceKind) -> Device {
        let power = characteristic(kind.powerType, in: service)?.value as? NSNumber
        let raw = (characteristic(kind.valueType, in: service)?.value as? NSNumber)?.doubleValue ?? 0
        let value = kind == .thermostat ? raw : raw / 100
        return Device(
            id: service.uniqueIdentifier,
            name: service.accessory?.name ?? service.name,
            room: service.accessory?.room?.name ?? "Default Room",
            kind: kind,
            isOn: kind == .blinds ? value > 0 : (power?.intValue ?? 0) != 0,
            value: value
        )
    }

    private func characteristic(_ type: String?, in service: HMService) -> HMCharacteristic? {
        service.characteristics.first { $0.characteristicType == type }
    }

    private func refresh(_ service: HMService) {
        guard let i = devices.firstIndex(where: { $0.id == service.uniqueIdentifier }) else { return }
        devices[i] = device(from: service, kind: devices[i].kind)
    }

    /// Optimistically updates the UI, then writes changed characteristics to HomeKit.
    private func update(_ new: Device) {
        guard let i = devices.firstIndex(where: { $0.id == new.id }),
              let service = services[new.id] else { return }
        let old = devices[i]
        devices[i] = new
        Task {
            do {
                if old.isOn != new.isOn, let c = characteristic(new.kind.powerType, in: service) {
                    // PowerState is a Bool; heating mode 1 = heat, lock state 1 = secured.
                    try await c.writeValue(new.kind == .light || new.kind == .plug ? new.isOn as NSNumber : (new.isOn ? 1 : 0) as NSNumber)
                }
                if old.value != new.value, let c = characteristic(new.kind.valueType, in: service) {
                    try await c.writeValue(new.kind == .thermostat ? new.value as NSNumber : Int((new.value * 100).rounded()) as NSNumber)
                }
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

extension HomeStore: HMAccessoryDelegate {
    nonisolated func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        // HomeKit delivers delegate callbacks on the main queue.
        MainActor.assumeIsolated { refresh(service) }
    }
}
