import SwiftUI

enum DeviceKind {
    case light, thermostat, lock, garage, plug, blinds, contact

    /// Sensors only report state; everything else can be switched.
    var isControllable: Bool { self != .contact }

    var tint: Color {
        switch self {
        case .light: .yellow
        case .thermostat: .orange
        case .lock: .teal
        case .garage: .red
        case .plug: .green
        case .blinds: .indigo
        case .contact: .mint
        }
    }
}

/// Snapshot of one controllable service, independent of HomeKit types.
struct Device: Identifiable {
    let id: UUID
    var name: String
    var accessoryName: String
    var room: String
    var kind: DeviceKind
    var isReachable = true
    /// Target state: power on, heating on, locked, or garage door closed.
    var isOn = false
    /// Target brightness or blinds position (0...1), or target temperature (°C).
    var value: Double = 0
    /// Whether `value` is adjustable, e.g. false for lights without dimming.
    var hasValue = true
    /// Reported enum state (lock: 0 unlocked, 1 locked, 2 jammed; garage: 0 open, 1 closed, 2 opening, 3 closing, 4 stopped;
    /// contact: 0 closed, 1 open).
    var currentState: Int?
    /// Reported reading: room temperature (°C) or blinds position (0...1).
    var currentValue: Double?
    var isObstructed = false

    /// Whether the tile is highlighted. An open garage door counts as active, like in the Home app.
    var isActive: Bool {
        switch kind {
        case .garage: !isOn
        case .blinds: value > 0
        case .contact: isContactOpen
        default: isOn
        }
    }

    var icon: String {
        switch kind {
        case .light: isOn ? "lightbulb.fill" : "lightbulb"
        case .thermostat: "thermometer.medium"
        case .lock: isOn ? "lock.fill" : "lock.open.fill"
        case .garage: isOn ? "door.garage.closed" : "door.garage.open"
        case .plug: "powerplug.fill"
        case .blinds: value > 0 ? "blinds.horizontal.open" : "blinds.horizontal.closed"
        case .contact: isContactOpen ? "door.left.hand.open" : "door.left.hand.closed"
        }
    }

    var status: String {
        guard isReachable else { return "No Response" }
        switch kind {
        case .light:
            guard isOn else { return "Off" }
            return hasValue ? "On · \(value.formatted(.percent.precision(.fractionLength(0))))" : "On"
        case .plug:
            return isOn ? "On" : "Off"
        case .thermostat:
            let now = currentValue.map(Self.celsius) ?? "–"
            return isOn ? "\(now) → \(Self.celsius(value))" : "Off · \(now)"
        case .lock:
            if currentState == 2 { return "Jammed" }
            if let state = currentState, state <= 1, (state == 1) != isOn { return isOn ? "Locking…" : "Unlocking…" }
            return isOn ? "Locked" : "Unlocked"
        case .garage:
            if isObstructed { return "Obstructed" }
            switch currentState {
            case 0: return "Open"
            case 1: return "Closed"
            case 2: return "Opening…"
            case 3: return "Closing…"
            case 4: return "Stopped"
            default: return isOn ? "Closed" : "Open"
            }
        case .blinds:
            let position = currentValue ?? value
            return position == 0 ? "Closed" : "\(position.formatted(.percent.precision(.fractionLength(0)))) open"
        case .contact:
            return isContactOpen ? "Open" : "Closed"
        }
    }

    /// Contact sensors report 0 when contact is detected (closed) and 1 when it is broken (open).
    var isContactOpen: Bool { kind == .contact && currentState == 1 }

    /// Button title to confirm before a tile tap unlocks or opens something, nil if no confirmation is needed.
    var confirmationAction: String? {
        switch kind {
        case .lock where isOn: "Unlock"
        case .garage where isOn: "Open"
        default: nil
        }
    }

    /// The state a tap on the tile icon switches to.
    func toggled() -> Device {
        var device = self
        if kind == .blinds { device.value = isActive ? 0 : 1 } else { device.isOn.toggle() }
        return device
    }

    static func celsius(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " °C"
    }
}
