import SwiftUI

struct RoomView: View {
    @Environment(HomeStore.self) private var store
    let title: String
    let devices: [Device]
    let showRoom: Bool
    @Environment(\.itemPrefs) private var prefs
    @State private var selected: Device?
    /// Hold the title to edit: hidden items show again, and tapping items picks them for a group.
    @State private var isSelecting = false
    @State private var picked: [UUID] = []
    @State private var grouping = false

    /// Hidden stays hidden, except while editing.
    private var shown: [Device] {
        isSelecting ? devices : devices.filter { !(prefs[$0.id]?.isHidden ?? false) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(shown) { device in
                    DeviceTile(device: device, showRoom: showRoom) { selected = device }
                        .overlay { if isSelecting { selectionOverlay(device) } }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            // Prefs arrive from the database after the write, outside any withAnimation; animate on the result instead.
            .animation(.snappy, value: shown.map(\.id))
            .padding()
        }
        .background(HomeBackground())
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
                    .onLongPressGesture(minimumDuration: 0.4) { setEditing(true) }
            }
            if isSelecting {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { setEditing(false) }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isSelecting)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                Button {
                    grouping = true
                } label: {
                    Label(picked.count < 2 ? "Tap Items to Group Them" : "Group \(picked.count) Items", systemImage: "square.stack.3d.up.fill")
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(picked.count < 2)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .contentTransition(.numericText())
            }
        }
        .sheet(isPresented: $grouping) {
            GroupEditor(kind: .group, preselected: picked) { _ in
                withAnimation(.snappy) {
                    isSelecting = false
                    picked = []
                }
            }
            .environment(store)
        }
        .sensoryFeedback(.selection, trigger: picked)
        #if DEBUG
        // Screenshots: `-open "Front Door"` opens that item's details.
        .task {
            if let name = UserDefaults.standard.string(forKey: "open") {
                selected = devices.first { $0.name == name }
                // `-toggle YES`: flips it a moment later, to catch an animation mid-way.
                if UserDefaults.standard.bool(forKey: "toggle"), let device = selected {
                    try? await Task.sleep(for: .seconds(1.5))
                    let binding = store.binding(for: device)
                    binding.wrappedValue = binding.wrappedValue.toggled()
                }
            }
        }
        #endif
        .sheet(item: $selected) { DeviceDetailView(device: $0).environment(store) }
    }

    private func setEditing(_ editing: Bool) {
        withAnimation(.snappy) {
            isSelecting = editing
            picked = []
        }
    }

    /// Covers the tile while selecting, so a tap picks it instead of switching it.
    private func selectionOverlay(_ device: Device) -> some View {
        let isPicked = picked.contains(device.id)
        let canGroup = device.kind != .camera && store.group(for: device.id) == nil && !store.groupedIDs.contains(device.id)
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(isPicked ? Color.accentColor.opacity(0.15) : .clear)
            .strokeBorder(isPicked ? Color.accentColor : .clear, lineWidth: 2)
            .contentShape(.rect(cornerRadius: 20))
            .overlay(alignment: .topTrailing) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPicked ? Color.accentColor : .secondary)
                    .background(.background, in: .circle)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(8)
                    .opacity(canGroup ? 1 : 0)
            }
            .onTapGesture {
                guard canGroup else { return }
                withAnimation(.spring(duration: 0.25, bounce: 0.4)) {
                    if isPicked { picked.removeAll { $0 == device.id } } else { picked.append(device.id) }
                }
            }
            .transition(.opacity)
    }
}
