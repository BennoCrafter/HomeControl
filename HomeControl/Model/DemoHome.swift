import Foundation

/// Sample accessories for trying the app without HomeKit access.
enum DemoHome {
    static func devices() -> [Device] {
        [
            Device(id: UUID(), name: "Ceiling Light", accessoryName: "Ceiling Light", room: "Living Room", kind: .light,
                   isOn: true, value: 0.8),
            Device(id: UUID(), name: "Floor Lamp", accessoryName: "Floor Lamp", room: "Living Room", kind: .light,
                   isOn: false, value: 0.5),
            Device(id: UUID(), name: "Shutters", accessoryName: "Shutters", room: "Living Room", kind: .blinds,
                   value: 0.6, currentValue: 0.6),
            Device(id: UUID(), name: "Thermostat", accessoryName: "Thermostat", room: "Living Room", kind: .thermostat,
                   isOn: true, value: 21.5, currentValue: 20.8),
            Device(id: UUID(), name: "Apple TV", accessoryName: "Smart Plug", room: "Living Room", kind: .plug,
                   isOn: true),
            Device(id: UUID(), name: "Pendant Lights", accessoryName: "Pendant Lights", room: "Kitchen", kind: .light,
                   isOn: true, value: 1),
            Device(id: UUID(), name: "Coffee Machine", accessoryName: "Smart Plug", room: "Kitchen", kind: .plug),
            Device(id: UUID(), name: "Bedside Lamp", accessoryName: "Bedside Lamp", room: "Bedroom", kind: .light,
                   value: 0.3),
            Device(id: UUID(), name: "Bedroom Shutters", accessoryName: "Shutters", room: "Bedroom", kind: .blinds,
                   value: 0, currentValue: 0),
            Device(id: UUID(), name: "Front Door", accessoryName: "Smart Lock", room: "Hallway", kind: .lock,
                   isOn: true, currentState: 1),
            Device(id: UUID(), name: "Hallway Light", accessoryName: "Switch", room: "Hallway", kind: .light,
                   hasValue: false),
            Device(id: UUID(), name: "Garage Door", accessoryName: "Garage Door Opener", room: "Garage", kind: .garage,
                   isOn: true, currentState: 1),
            Device(id: UUID(), name: "Garage Light", accessoryName: "Switch", room: "Garage", kind: .light,
                   hasValue: false),
        ]
    }
}
