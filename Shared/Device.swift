import SwiftUI

enum DeviceKind: String, Codable, CaseIterable {
    case light, thermostat, lock, garage, plug, blinds, contact, camera

    /// Sensors only report state; everything else can be switched.
    var isControllable: Bool { self != .contact && self != .camera }

    var tint: Color {
        switch self {
        case .light: .yellow
        case .thermostat: .orange
        case .lock: .teal
        case .garage: .red
        case .plug: .green
        case .blinds: .indigo
        case .contact: .mint
        case .camera: .blue
        }
    }
}

/// Snapshot of one controllable service, independent of HomeKit types.
struct Device: Identifiable, Codable, Hashable {
    var id: UUID
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
    /// A group's own icon.
    var customIcon: String?

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
        if let customIcon { return customIcon }
        return switch kind {
        case .light: isOn ? "lightbulb.fill" : "lightbulb"
        case .thermostat: "thermometer.medium"
        case .lock: isOn ? "lock.fill" : "lock.open.fill"
        case .garage: isOn ? "door.garage.closed" : "door.garage.open"
        case .plug: "powerplug.fill"
        case .blinds: value > 0 ? "blinds.horizontal.open" : "blinds.horizontal.closed"
        case .contact where isWindow: isContactOpen ? "window.vertical.open" : "window.vertical.closed"
        case .contact: isContactOpen ? "door.left.hand.open" : "door.left.hand.closed"
        case .camera: "web.camera.fill"
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
        case .camera:
            return "Camera"
        }
    }

    /// What `isActive` means for this kind, for "Open for 5 minutes" and the history.
    func stateName(active: Bool) -> String {
        switch kind {
        case .lock: active ? "Locked" : "Unlocked"
        case .garage, .blinds, .contact: active ? "Open" : "Closed"
        default: active ? "On" : "Off"
        }
    }

    /// A contact sensor on a window rather than a door, going by its name.
    var isWindow: Bool {
        ["window", "fenster"].contains { name.lowercased().contains($0) }
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

    /// Switched on or off the way a tap on the icon would.
    func setting(active: Bool) -> Device {
        isActive == active ? self : toggled()
    }

    static func celsius(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " °C"
    }
}
