import Foundation

/// Sample accessories for trying the app without HomeKit access.
enum DemoHome {
    static func devices() -> [Device] {
        [
            Device(id: id("Ceiling Light"), name: "Ceiling Light", accessoryName: "Ceiling Light", room: "Living Room", kind: .light,
                   isOn: true, value: 0.8),
            Device(id: id("Floor Lamp"), name: "Floor Lamp", accessoryName: "Floor Lamp", room: "Living Room", kind: .light,
                   isOn: false, value: 0.5),
            Device(id: id("Shutters"), name: "Shutters", accessoryName: "Shutters", room: "Living Room", kind: .blinds,
                   value: 0.6, currentValue: 0.6),
            Device(id: id("Thermostat"), name: "Thermostat", accessoryName: "Thermostat", room: "Living Room", kind: .thermostat,
                   isOn: true, value: 21.5, currentValue: 20.8),
            Device(id: id("Apple TV"), name: "Apple TV", accessoryName: "Smart Plug", room: "Living Room", kind: .plug,
                   isOn: true),
            Device(id: id("Pendant Lights"), name: "Pendant Lights", accessoryName: "Pendant Lights", room: "Kitchen", kind: .light,
                   isOn: true, value: 1),
            Device(id: id("Coffee Machine"), name: "Coffee Machine", accessoryName: "Smart Plug", room: "Kitchen", kind: .plug),
            Device(id: id("Kitchen Window"), name: "Kitchen Window", accessoryName: "Contact Sensor", room: "Kitchen", kind: .contact,
                   currentState: 0),
            Device(id: id("Bedside Lamp"), name: "Bedside Lamp", accessoryName: "Bedside Lamp", room: "Bedroom", kind: .light,
                   value: 0.3),
            Device(id: id("Bedroom Shutters"), name: "Bedroom Shutters", accessoryName: "Shutters", room: "Bedroom", kind: .blinds,
                   value: 0, currentValue: 0),
            Device(id: id("Front Door"), name: "Front Door", accessoryName: "Smart Lock", room: "Hallway", kind: .lock,
                   isOn: true, currentState: 1),
            Device(id: id("Terrace Door"), name: "Terrace Door", accessoryName: "Contact Sensor", room: "Hallway", kind: .contact,
                   currentState: 1),
            Device(id: id("Hallway Light"), name: "Hallway Light", accessoryName: "Switch", room: "Hallway", kind: .light,
                   hasValue: false),
            Device(id: id("Garage Door"), name: "Garage Door", accessoryName: "Garage Door Opener", room: "Garage", kind: .garage,
                   isOn: true, currentState: 1),
            Device(id: id("Front Yard"), name: "Front Yard", accessoryName: "Camera", room: "Hallway", kind: .camera, hasValue: false),
            Device(id: id("Garage Light"), name: "Garage Light", accessoryName: "Switch", room: "Garage", kind: .light,
                   hasValue: false),
        ]
    }

    /// The same id every launch, so pins, icons and dashboard cards stick to demo items too.
    private static func id(_ name: String) -> UUID {
        let bytes = Array(name.utf8)
        var raw = [UInt8](repeating: 0, count: 16)
        for (index, byte) in bytes.enumerated() { raw[index % 16] = raw[index % 16] &* 31 &+ byte }
        return NSUUID(uuidBytes: raw) as UUID
    }
}
