import SwiftUI

/// A glass sheet with one small header and the item's control in the middle; editing waits behind "…".
struct DeviceDetailView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let device: Device
    /// Pushed onto the dashboard's navigation instead of shown as a sheet.
    var isPushed = false
    @Environment(\.itemPrefs) private var prefs
    @State private var renaming = false
    @State private var newName = ""
    @State private var choosingIcon = false
    @State private var grouping = false

    private var homeID: String { store.currentHomeID ?? "" }

    var body: some View {
        if let group = store.group(for: device.id) {
            GroupDetailView(group: group, isPushed: isPushed)
        } else if isPushed {
            details.background(HomeBackground())
        } else {
            NavigationStack { details }
                // Below full height the sheet stays glass and the home shows through; full height turns it opaque.
                .presentationDetents([.fraction(0.72), .large])
                .presentationSizing(.page) // the default form sheet on Mac/iPad is too short for the dial
        }
    }

    private var details: some View {
        let binding = store.binding(for: device)
        let current = binding.wrappedValue
        return ScrollView {
                VStack(spacing: 24) {
                    if !current.isReachable {
                        ContentUnavailableView("No Response", systemImage: "exclamationmark.triangle",
                                               description: Text("\(current.name) can't be reached. Check its power and network."))
                    } else if current.kind == .camera {
                        CameraCard(device: current)
                            .aspectRatio(16 / 9, contentMode: .fit)
                    } else if current.kind == .contact {
                        ContactView(device: current, since: store.lastChanged[current.id])
                    } else {
                        DeviceControls(device: binding)
                    }
                }
                .frame(maxWidth: 520)
                .padding(.horizontal)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .containerBackground(.clear, for: .navigation) // let the sheet's glass through
            .scrollBounceBehavior(.basedOnSize)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { header(current) }
                ToolbarItem(placement: isPushed ? .topBarTrailing : .topBarLeading) { editMenu(current) }
                if !isPushed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "xmark") { dismiss() }
                    }
                }
            }
            .alert("Rename", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { store.rename(current, to: name) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Also renames it in Apple Home and for Siri.")
            }
            .sheet(isPresented: $choosingIcon) {
                IconPicker(title: current.name, current: prefs[current.id]?.icon, tint: current.kind.tint) { icon in
                    Prefs.update(item: current.id, in: homeID) { $0.icon = icon }
                }
            }
            .sheet(isPresented: $grouping) {
                GroupEditor(kind: .group, preselected: [current.id]).environment(store)
            }
    }

    /// Icon, name, and room with state, in one line's height.
    private func header(_ current: Device) -> some View {
        HStack(spacing: 8) {
            Image(systemName: current.icon(prefs))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(current.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 30)
                .background(current.isActive ? AnyShapeStyle(current.kind.tint.gradient) : AnyShapeStyle(.quaternary), in: .circle)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 0) {
                Text(current.name).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(current.room) · \(current.status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .animation(.smooth, value: current.status)
    }

    private func editMenu(_ current: Device) -> some View {
        let pref = prefs[current.id]
        return Menu {
            Button("Rename…", systemImage: "pencil") {
                newName = current.name
                renaming = true
            }
            Picker(selection: Binding(get: { current.room }, set: { store.move(current, to: $0) })) {
                ForEach(store.allRooms, id: \.self) { Text($0).tag($0) }
            } label: {
                Label("Room", systemImage: "square.split.bottomrightquarter")
            }
            .pickerStyle(.menu)
            Button("Change Icon", systemImage: "square.grid.2x2") { choosingIcon = true }
            Divider()
            Button(pref?.isPinned == true ? "Unpin" : "Pin to Top", systemImage: pref?.isPinned == true ? "pin.slash" : "pin") {
                Prefs.update(item: current.id, in: homeID) { $0.isPinned.toggle() }
            }
            Button(pref?.isHidden == true ? "Show" : "Hide", systemImage: pref?.isHidden == true ? "eye" : "eye.slash") {
                Prefs.update(item: current.id, in: homeID) { $0.isHidden.toggle() }
            }
            if current.kind != .camera {
                Button("Group With…", systemImage: "square.stack.3d.up") { grouping = true }
            }
        } label: {
            Label("Edit", systemImage: "ellipsis")
        }
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
            VStack(spacing: 14) {
                Toggle("Heating", isOn: $device.isOn)
                Divider()
                Stepper("Target \(Device.celsius(device.value))", value: $device.value, in: 10...30, step: 0.5)
            }
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 20, style: .continuous))
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
