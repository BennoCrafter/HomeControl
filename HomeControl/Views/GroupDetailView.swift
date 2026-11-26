import SwiftUI

/// Every member of a group, each with its own control. Members that work a player (Play, Pause, Mute…) become a remote.
struct GroupDetailView: View {
    let group: DeviceGroup
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        let members = store.members(of: group)
        let remote = MediaButton.remote(for: members)
        let others = members.filter { member in !remote.contains { $0.device.id == member.id } }
        let device = store.groupDevices.first { $0.id == group.deviceID }
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: device?.icon ?? "square.stack.3d.up.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(device?.isActive == true ? device!.kind.tint : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(height: 52)
                        Text(group.name).font(.title2.bold())
                        Text("\(members.count) items · \(members.count(where: \.isActive)) on")
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                if !remote.isEmpty {
                    Section { RemoteView(buttons: remote) }
                        .listRowBackground(Color.clear)
                }
                if !others.isEmpty {
                    Section("Items") {
                        ForEach(others) { MemberRow(device: $0) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Edit") { editing = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $editing) {
                GroupEditor(kind: .group, existing: group).environment(store)
            }
            .onChange(of: store.group(id: group.id) == nil) { _, gone in if gone { dismiss() } }
        }
        .presentationSizing(.page)
    }
}

/// A member item that switches part of a player, recognised by its name.
struct MediaButton: Identifiable {
    let device: Device
    let icon: String
    let order: Int
    var id: UUID { device.id }

    /// Keywords in English and German, in the order the buttons sit in the remote.
    private static let kinds: [(keys: [String], icon: String)] = [
        (["previous", "prev", "back", "zurück"], "backward.fill"),
        (["play/pause", "play pause", "playpause"], "playpause.fill"),
        (["play", "abspielen", "wiedergabe"], "play.fill"),
        (["pause"], "pause.fill"),
        (["stop"], "stop.fill"),
        (["next", "skip", "weiter", "nächst"], "forward.fill"),
        (["volume down", "leiser", "quieter"], "speaker.minus.fill"),
        (["mute", "stumm"], "speaker.slash.fill"),
        (["volume up", "lauter", "louder"], "speaker.plus.fill"),
    ]

    static func remote(for members: [Device]) -> [MediaButton] {
        members.compactMap { device in
            guard device.kind == .plug || device.kind == .light else { return nil }
            let name = device.name.lowercased()
            guard let index = kinds.firstIndex(where: { $0.keys.contains { name.contains($0) } }) else { return nil }
            return MediaButton(device: device, icon: kinds[index].icon, order: index)
        }
        .sorted { $0.order < $1.order }
    }
}

private struct RemoteView: View {
    let buttons: [MediaButton]
    @Environment(HomeStore.self) private var store
    @State private var presses: [UUID: Int] = [:]

    var body: some View {
        // A main row of up to four, the rest underneath.
        let rows = stride(from: 0, to: buttons.count, by: 4).map { Array(buttons[$0 ..< min($0 + 4, buttons.count)]) }
        VStack(spacing: 14) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 14) {
                    ForEach(rows[row]) { button(for: $0, large: row == 0) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func button(for media: MediaButton, large: Bool) -> some View {
        let device = store.binding(for: media.device).wrappedValue
        let size: CGFloat = large ? 68 : 54
        return Button {
            store.binding(for: device).wrappedValue = device.toggled()
            presses[device.id, default: 0] += 1
        } label: {
            VStack(spacing: 6) {
                Image(systemName: media.icon)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .symbolEffect(.bounce, value: presses[device.id])
                    .foregroundStyle(device.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: size, height: size)
                    .background(device.isActive ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.regularMaterial), in: .circle)
                    .shadow(color: device.isActive ? Color.accentColor.opacity(0.45) : .black.opacity(0.08), radius: 8, y: 3)
                Text(device.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: size + 16)
            }
        }
        .buttonStyle(PressScale(scale: 0.82))
        .disabled(!device.isReachable)
        .animation(.spring(duration: 0.3, bounce: 0.4), value: device.isActive)
        .sensoryFeedback(.impact(weight: .medium), trigger: presses[device.id])
        .accessibilityLabel(device.name)
        .accessibilityValue(device.status)
    }
}

/// One member: tap the icon to switch it, a slider when it dims or moves.
private struct MemberRow: View {
    let device: Device
    @Environment(HomeStore.self) private var store
    @Environment(\.itemPrefs) private var prefs
    @State private var confirming = false
    @State private var toggles = 0

    var body: some View {
        let binding = store.binding(for: device)
        let current = binding.wrappedValue
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    if current.confirmationAction != nil {
                        confirming = true
                    } else {
                        binding.wrappedValue = current.toggled()
                        toggles += 1
                    }
                } label: {
                    Image(systemName: current.icon(prefs))
                        .font(.body.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(current.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .frame(width: 40, height: 40)
                        .background(current.isActive ? AnyShapeStyle(current.kind.tint.gradient) : AnyShapeStyle(.quaternary), in: .circle)
                }
                .buttonStyle(PressScale(scale: 0.8))
                .disabled(!current.isReachable || !current.kind.isControllable)
                VStack(alignment: .leading, spacing: 1) {
                    Text(current.name).font(.headline)
                    Text("\(current.room) · \(current.status)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            if current.isReachable, current.hasValue, current.kind == .light || current.kind == .blinds {
                Slider(value: level(binding), in: 0 ... 1)
                    .tint(current.kind.tint)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.35), value: current.isActive)
        .sensoryFeedback(.impact(weight: .medium), trigger: toggles)
        .confirmationDialog("\(current.confirmationAction ?? "") \(current.name)?", isPresented: $confirming, titleVisibility: .visible) {
            Button(current.confirmationAction ?? "OK") {
                binding.wrappedValue = binding.wrappedValue.toggled()
                toggles += 1
            }
        }
    }

    /// Brightness where 0 is off, or the blinds' position.
    private func level(_ device: Binding<Device>) -> Binding<Double> {
        Binding {
            device.wrappedValue.kind == .light ? (device.wrappedValue.isOn ? device.wrappedValue.value : 0) : device.wrappedValue.value
        } set: { level in
            var updated = device.wrappedValue
            if updated.kind == .light {
                updated.isOn = level > 0.005
                if updated.isOn { updated.value = level }
            } else {
                updated.value = level
            }
            device.wrappedValue = updated
        }
    }
}
