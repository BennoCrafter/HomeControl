import SwiftUI

struct DeviceTile: View {
    private var pref: ItemPref? { prefs[device.id] }
    private var homeID: String { store.currentHomeID ?? "" }

    @Environment(HomeStore.self) private var store
    let device: Device
    let showRoom: Bool
    let openDetail: () -> Void
    @State private var confirming = false
    @State private var toggles = 0
    @State private var choosingIcon = false
    @State private var opens = 0
    @State private var editingGroup = false
    @Environment(\.tileOpacity) private var tileOpacity
    @Environment(\.itemPrefs) private var prefs

    var body: some View {
        let binding = store.binding(for: device)
        let current = binding.wrappedValue
        // Split tile: the round icon toggles, the rest of the tile opens the details.
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
                    .font(.title2.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: toggles)
                    .foregroundStyle(current.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 50, height: 50)
                    .background(current.isActive ? AnyShapeStyle(current.kind.tint.gradient) : AnyShapeStyle(.quaternary), in: .circle)
                    .shadow(color: current.isActive ? current.kind.tint.opacity(0.5) : .clear, radius: 8, y: 3)
            }
            .buttonStyle(PressScale(scale: 0.82))
            .disabled(!current.isReachable || !current.kind.isControllable)
            .accessibilityLabel("Toggle \(current.name)")
            VStack(alignment: .leading, spacing: 2) {
                if showRoom {
                    Text(current.room).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                // Shrinks to fit rather than cutting the name off.
                Text(current.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(current.status)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(current.isReachable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Image(systemName: current.isReachable ? "chevron.right" : "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(current.isReachable ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.orange))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(current.isActive ? AnyShapeStyle(current.kind.tint.opacity(0.22)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground).opacity(tileOpacity)))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(current.isActive ? current.kind.tint.opacity(0.35) : .white.opacity(0.08))
                }
        }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: current.isActive)
        .contentShape(.rect(cornerRadius: 20))
        .keyframeAnimator(initialValue: 1.0, trigger: opens) { $0.scaleEffect($1) } keyframes: { _ in
            SpringKeyframe(0.95, duration: 0.08)
            SpringKeyframe(1, duration: 0.3, spring: .bouncy)
        }
        .onTapGesture {
            opens += 1
            openDetail()
        }
        .overlay(alignment: .topLeading) {
            if pref?.isPinned == true {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange).padding(10)
            }
        }
        .opacity(pref?.isHidden == true ? 0.45 : 1)
        .contextMenu {
            Button(pref?.isPinned == true ? "Unpin" : "Pin to Top", systemImage: pref?.isPinned == true ? "pin.slash" : "pin") {
                withAnimation(.snappy) { Prefs.update(item: device.id, in: homeID) { $0.isPinned.toggle() } }
            }
            if store.group(for: device.id) == nil {
                Button("Change Icon", systemImage: "square.grid.2x2") { choosingIcon = true }
            }
            Button(store.group(for: device.id) == nil ? "Group With…" : "Edit Group…", systemImage: "square.stack.3d.up") { editingGroup = true }
            Button(pref?.isHidden == true ? "Show" : "Hide", systemImage: pref?.isHidden == true ? "eye" : "eye.slash") {
                withAnimation(.snappy) { Prefs.update(item: device.id, in: homeID) { $0.isHidden.toggle() } }
            }
        }
        .sheet(isPresented: $choosingIcon) {
            IconPicker(title: current.name, current: pref?.icon, tint: current.kind.tint) { icon in
                Prefs.update(item: device.id, in: homeID) { $0.icon = icon }
            }
        }
        .sheet(isPresented: $editingGroup) {
            GroupEditor(kind: .group, existing: store.group(for: device.id), preselected: [device.id]).environment(store)
        }
        .confirmationDialog("\(current.confirmationAction ?? "") \(current.name)?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(current.confirmationAction ?? "OK") {
                binding.wrappedValue = binding.wrappedValue.toggled()
                toggles += 1
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: toggles)
        .sensoryFeedback(.impact(weight: .light), trigger: opens)
    }
}
