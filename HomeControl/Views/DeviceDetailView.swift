import SwiftUI

struct DeviceDetailView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let device: Device
    @Environment(\.itemPrefs) private var prefs

    var body: some View {
        if let group = store.group(for: device.id) {
            GroupDetailView(group: group)
        } else {
            details
        }
    }

    private var details: some View {
        let binding = store.binding(for: device)
        let current = binding.wrappedValue
        return NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: current.icon(prefs))
                            .font(.system(size: 40))
                            .foregroundStyle(current.isActive ? current.kind.tint : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(height: 52)
                        Text(current.name).font(.title2.bold())
                        if current.accessoryName != current.name {
                            Text(current.accessoryName).foregroundStyle(.secondary)
                        }
                        Text("\(current.room) · \(current.status)")
                            .foregroundStyle(.secondary)
                            .contentTransition(.interpolate)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .animation(.smooth, value: current.status)
                }
                if current.isReachable && current.kind.isControllable {
                    Section("Control") { DeviceControls(device: binding) }
                }
                if current.kind == .camera {
                    Section {
                        CameraCard(device: current)
                            .aspectRatio(16 / 9, contentMode: .fit)
                    }
                    .listRowInsets(EdgeInsets())
                }
                if current.kind == .contact {
                    Section { ContactView(device: current, since: store.lastChanged[current.id]) }
                        .listRowBackground(Color.clear)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationSizing(.page) // the default form sheet on Mac/iPad is too short for the dial
    }
}

struct DeviceControls: View {
    @Binding var device: Device

    var body: some View {
        switch device.kind {
        case .light where device.hasValue:
            LevelControl(level: brightness, look: .light, tint: device.kind.tint, icon: device.icon) {
                device.isOn.toggle()
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        case .light, .plug:
            PowerButton(isOn: $device.isOn, tint: device.kind.tint, icon: device.icon)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        case .thermostat:
            Toggle("Heating", isOn: $device.isOn)
            Stepper("Target \(Device.celsius(device.value))", value: $device.value, in: 10...30, step: 0.5)
        case .lock:
            LockControl(device: $device)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        case .garage:
            GarageControl(device: $device)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        case .contact, .camera:
            EmptyView()
        case .blinds:
            LevelControl(level: $device.value, look: .shutter, tint: device.kind.tint, icon: device.icon) {
                device.value = device.value > 0 ? 0 : 1
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            HStack {
                Button("Close", systemImage: "blinds.horizontal.closed") { device.value = 0 }
                Spacer()
                Button("Open", systemImage: "blinds.horizontal.open") { device.value = 1 }
            }
            .buttonStyle(.bordered)
        }
    }

    /// Brightness where 0 means off, so dragging to the bottom turns the light off and dragging up turns it on.
    private var brightness: Binding<Double> {
        Binding(
            get: { device.isOn ? device.value : 0 },
            set: { level in
                var updated = device
                updated.isOn = level > 0.005
                if updated.isOn { updated.value = level }
                device = updated
            }
        )
    }
}

/// On/off control for devices without an adjustable level, styled like the dial: the ring sweeps full when on.
struct PowerButton: View {
    @Binding var isOn: Bool
    let tint: Color
    let icon: String

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 44)
                // No sweep: a switch has no in-between, so the whole ring pulses on at once.
                Circle()
                    .stroke(tint.gradient, lineWidth: 44)
                    .opacity(isOn ? 1 : 0)
                    .scaleEffect(isOn ? 1 : 0.85)
                // A ripple that rings out each time it turns on.
                Circle()
                    .stroke(tint, lineWidth: 6)
                    .keyframeAnimator(initialValue: Ripple(), trigger: isOn) { ring, ripple in
                        ring.scaleEffect(ripple.scale).opacity(ripple.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(1, duration: 0.01)
                            CubicKeyframe(1.35, duration: 0.6)
                        }
                        KeyframeTrack(\.opacity) {
                            CubicKeyframe(isOn ? 0.8 : 0, duration: 0.01)
                            CubicKeyframe(0, duration: 0.6)
                        }
                    }
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isOn ? tint : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                    Text(isOn ? "On" : "Off")
                        .font(.headline)
                        .contentTransition(.interpolate)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            }
            .padding(22)
            .frame(width: 230, height: 230)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: 1.0, trigger: isOn) { $0.scaleEffect($1) } keyframes: { _ in
            SpringKeyframe(isOn ? 1.08 : 0.94, duration: 0.12)
            SpringKeyframe(1, duration: 0.5, spring: .bouncy)
        }
        .animation(.spring(duration: 0.35, bounce: 0.45), value: isOn)
        .sensoryFeedback(trigger: isOn) { _, on in on ? .impact(weight: .heavy) : .impact(weight: .light) }
        .accessibilityLabel("Power")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct Ripple {
    var scale = 1.0
    var opacity = 0.0
}
