import SwiftUI

struct DeviceDetailView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let device: Device

    var body: some View {
        let binding = store.binding(for: device)
        let current = binding.wrappedValue
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: current.icon)
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
            Toggle("Locked", isOn: $device.isOn)
        case .garage:
            GarageControl(device: $device)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        case .contact:
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
                Circle().stroke(.quaternary, lineWidth: 30)
                Circle()
                    .trim(from: 0, to: isOn ? 1 : 0)
                    .rotation(.degrees(-90))
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 30, lineCap: .round))
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
            .padding(15)
            .frame(width: 230, height: 230)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.5, bounce: 0.2), value: isOn)
        .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
        .accessibilityLabel("Power")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
