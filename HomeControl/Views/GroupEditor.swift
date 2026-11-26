import SwiftUI

/// Picks the members, name, icon and main action of a group or a collection.
struct GroupEditor: View {
    let kind: DeviceGroup.Kind
    /// The group being edited; nil makes a new one.
    let existing: DeviceGroup?
    let saved: (Int) -> Void

    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String?
    @State private var selected: [UUID]
    @State private var mainID: UUID?
    @State private var choosingIcon = false
    @State private var picks = 0

    init(kind: DeviceGroup.Kind, existing: DeviceGroup? = nil, preselected: [UUID] = [], saved: @escaping (Int) -> Void = { _ in }) {
        self.kind = kind
        self.existing = existing
        self.saved = saved
        _name = State(initialValue: existing?.name ?? "")
        _icon = State(initialValue: existing?.icon)
        _selected = State(initialValue: existing?.memberIDs ?? preselected)
        _mainID = State(initialValue: existing?.mainID)
    }

    /// Cameras have nothing to switch; groups can't hold groups.
    private var candidates: [Device] {
        store.devices.filter { $0.kind != .camera } + (kind == .collection ? store.groupDevices : [])
    }

    private var members: [Device] {
        selected.compactMap { id in candidates.first { $0.id == id } }
    }

    /// Items already in another group: one group each, so the rooms know which tile stands for them.
    private func otherGroup(of device: Device) -> DeviceGroup? {
        guard kind == .group else { return nil }
        return store.groups(.group).first { $0.id != existing?.id && $0.memberIDs.contains(device.id) }
    }

    private var suggestedName: String {
        let accessories = Set(members.map(\.accessoryName))
        return accessories.count == 1 ? accessories.first! : String(localized: kind == .group ? "Group" : "Collection")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Button { choosingIcon = true } label: {
                            Image(systemName: icon ?? members.first?.icon ?? (kind == .group ? "square.stack.3d.up.fill" : "square.grid.2x2.fill"))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background((members.first?.kind.tint ?? .accentColor).gradient, in: .circle)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(PressScale(scale: 0.85))
                        .accessibilityLabel("Change Icon")
                        TextField(suggestedName, text: $name)
                            .font(.title3.weight(.semibold))
                    }
                }
                if kind == .group, members.count > 1 {
                    Section {
                        Picker("Icon Tap", selection: $mainID) {
                            Text("Switches All").tag(UUID?.none)
                            ForEach(members) { member in
                                Label(member.name, systemImage: member.icon).tag(UUID?.some(member.id))
                            }
                        }
                    } footer: {
                        Text("What the round icon of the group's tile does. Tap the rest of the tile for every member's control.")
                    }
                }
                ForEach(rooms, id: \.self) { room in
                    Section(room) {
                        ForEach(candidates.filter { $0.room == room }) { device in
                            row(device)
                        }
                    }
                }
                if let existing {
                    Section {
                        Button(kind == .group ? "Ungroup" : "Delete Collection", role: .destructive) {
                            Groups.delete(existing.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? (kind == .group ? "New Group" : "New Collection") : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(selected.isEmpty)
                }
            }
            .sheet(isPresented: $choosingIcon) {
                IconPicker(title: name.isEmpty ? suggestedName : name, current: icon, tint: members.first?.kind.tint ?? .accentColor) { icon = $0 }
            }
            .sensoryFeedback(.selection, trigger: picks)
        }
    }

    private var rooms: [String] {
        candidates.reduce(into: []) { if !$0.contains($1.room) { $0.append($1.room) } }
    }

    private func row(_ device: Device) -> some View {
        let isSelected = selected.contains(device.id)
        let taken = otherGroup(of: device)
        return Button {
            picks += 1
            withAnimation(.snappy) {
                if isSelected {
                    selected.removeAll { $0 == device.id }
                    if mainID == device.id { mainID = nil }
                } else {
                    selected.append(device.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: device.icon)
                    .foregroundStyle(device.kind.tint)
                    .frame(width: 28)
                VStack(alignment: .leading) {
                    Text(device.name).foregroundStyle(.primary)
                    if let taken {
                        Text("In \(taken.name)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .disabled(taken != nil)
    }

    private func save() {
        var group = DeviceGroup.Draft(id: existing?.id, homeID: store.currentHomeID ?? "", kind: kind,
                                      name: name.trimmingCharacters(in: .whitespaces), icon: icon, mainID: mainID)
        if group.name.isEmpty { group.name = suggestedName }
        group.members = selected.map(\.uuidString).joined(separator: ",")
        if let id = Groups.save(group) { saved(id) }
        dismiss()
    }
}
