import HomeKit

extension DeviceKind {
    init?(serviceType: String) {
        switch serviceType {
        case HMServiceTypeLightbulb: self = .light
        case HMServiceTypeThermostat: self = .thermostat
        case HMServiceTypeLockMechanism: self = .lock
        case HMServiceTypeGarageDoorOpener: self = .garage
        case HMServiceTypeOutlet, HMServiceTypeSwitch: self = .plug
        case HMServiceTypeWindowCovering: self = .blinds
        case HMServiceTypeContactSensor: self = .contact
        default: return nil
        }
    }

    /// Characteristic behind `Device.isOn`.
    var targetStateType: String? {
        switch self {
        case .light, .plug: HMCharacteristicTypePowerState
        case .thermostat: HMCharacteristicTypeTargetHeatingCooling
        case .lock: HMCharacteristicTypeTargetLockMechanismState
        case .garage: HMCharacteristicTypeTargetDoorState
        case .blinds, .contact, .camera: nil
        }
    }

    /// Characteristic behind `Device.value`.
    var targetValueType: String? {
        switch self {
        case .light: HMCharacteristicTypeBrightness
        case .thermostat: HMCharacteristicTypeTargetTemperature
        case .blinds: HMCharacteristicTypeTargetPosition
        case .lock, .garage, .plug, .contact, .camera: nil
        }
    }

    /// Characteristic behind `Device.currentState`.
    var currentStateType: String? {
        switch self {
        case .lock: HMCharacteristicTypeCurrentLockMechanismState
        case .garage: HMCharacteristicTypeCurrentDoorState
        case .contact: HMCharacteristicTypeContactState
        default: nil
        }
    }

    /// Characteristic behind `Device.currentValue`.
    var currentValueType: String? {
        switch self {
        case .thermostat: HMCharacteristicTypeCurrentTemperature
        case .blinds: HMCharacteristicTypeCurrentPosition
        default: nil
        }
    }

    /// Every characteristic a `Device` of this kind is built from.
    var characteristicTypes: [String] {
        [targetStateType, targetValueType, currentStateType, currentValueType,
         self == .garage ? HMCharacteristicTypeObstructionDetected : nil].compactMap { $0 }
    }

    /// HomeKit stores brightness and position as 0...100, temperatures as °C.
    var valueScale: Double { self == .thermostat ? 1 : 100 }
}

extension HMService {
    func characteristic(_ type: String?) -> HMCharacteristic? {
        characteristics.first { $0.characteristicType == type }
    }
}

extension Device {
    init(service: HMService, kind: DeviceKind) {
        func number(_ type: String?) -> Double? {
            (service.characteristic(type)?.value as? NSNumber)?.doubleValue
        }
        let accessory = service.accessory
        self.init(
            id: service.uniqueIdentifier,
            name: service.name,
            accessoryName: accessory?.name ?? service.name,
            room: accessory?.room?.name ?? "Default Room",
            kind: kind,
            isReachable: accessory?.isReachable ?? false,
            isOn: (number(kind.targetStateType) ?? 0) != 0,
            value: (number(kind.targetValueType) ?? 0) / kind.valueScale,
            hasValue: service.characteristic(kind.targetValueType) != nil,
            currentState: number(kind.currentStateType).map { Int($0) },
            currentValue: number(kind.currentValueType).map { $0 / kind.valueScale },
            isObstructed: number(HMCharacteristicTypeObstructionDetected) == 1
        )
    }

    /// HomeKit writes needed to move a device from `old` to this state.
    func writes(from old: Device, on service: HMService) -> [(HMCharacteristic, NSNumber)] {
        var writes: [(HMCharacteristic, NSNumber)] = []
        if isOn != old.isOn, let c = service.characteristic(kind.targetStateType) {
            // PowerState is a Bool; the others are enums where 1 = heat / secured / closed.
            let isBool = c.metadata?.format == HMCharacteristicMetadataFormatBool
            writes.append((c, isBool ? NSNumber(value: isOn) : NSNumber(value: isOn ? 1 : 0)))
        }
        if value != old.value, let c = service.characteristic(kind.targetValueType) {
            let raw = value * kind.valueScale
            writes.append((c, kind == .thermostat ? NSNumber(value: raw) : NSNumber(value: Int(raw.rounded()))))
        }
        return writes
    }
}

extension Device {
    /// Cameras aren't services; HomeKit hands them out as profiles of their accessory.
    init(camera: HMCameraProfile, accessory: HMAccessory) {
        self.init(id: camera.uniqueIdentifier, name: accessory.name, accessoryName: accessory.name,
                  room: accessory.room?.name ?? "Default Room", kind: .camera,
                  isReachable: accessory.isReachable, hasValue: false)
    }
}
