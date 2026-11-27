import SwiftUI

/// A room, group or collection: its name, what's on, and a quick toggle per item.
struct RoomCard: View {
    let title: String
    let icon: String
    let items: [Device]
    let large: Bool
    let open: () -> Void
    /// Sensors and items that ask first open here instead of switching.
    let openItem: (Device) -> Void

    @Environment(HomeStore.self) private var store
    @Environment(\.itemPrefs) private var prefs
    @Environment(\.tileOpacity) private var tileOpacity
    @AppStorage("cardIconsPerRow") private var iconsPerRow = 0
    @State private var toggles = 0

    private var devices: [Device] {
        items.map { store.binding(for: $0).wrappedValue }.filter { !(prefs[$0.id]?.isHidden ?? false) }
    }

    var body: some View {
        let active = devices.count(where: \.isActive)
        VStack(alignment: .leading, spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                        Text(active == 0 ? "All off" : "\(active) on")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(PressScale(scale: 0.97))
            GeometryReader { geometry in
                // Automatic: a fixed icon size, as many as fit; otherwise that many, sized to the width.
                let size: CGFloat = iconsPerRow == 0 ? (large ? 54 : 42)
                    : max(24, (geometry.size.width - 8 * CGFloat(iconsPerRow - 1)) / CGFloat(iconsPerRow))
                let perRow = iconsPerRow == 0 ? max(1, Int((geometry.size.width + 8) / (size + 8))) : iconsPerRow
                let rows = max(1, Int((geometry.size.height + 8) / (size + (large ? 24 : 8))))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: 8), count: perRow), alignment: .leading, spacing: 8) {
                    ForEach(devices.prefix(perRow * rows)) { device in
                        toggle(device, size: size)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: devices.map(\.id))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground).opacity(tileOpacity), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)) }
        // The empty space opens it too; the toggles are buttons and keep their taps.
        .contentShape(.rect(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: open)
        .sensoryFeedback(.impact(weight: .medium), trigger: toggles)
    }

    private func toggle(_ device: Device, size: CGFloat) -> some View {
        Button {
            guard device.kind.isControllable, device.confirmationAction == nil else {
                openItem(device)
                return
            }
            let binding = store.binding(for: device)
            binding.wrappedValue = binding.wrappedValue.toggled()
            toggles += 1
        } label: {
            VStack(spacing: 4) {
                Image(systemName: MediaButton.icon(for: device) ?? device.icon(prefs))
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(device.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: size, height: size)
                    .background(device.isActive ? AnyShapeStyle(device.kind.tint.gradient) : AnyShapeStyle(.quaternary), in: .circle)
                    .shadow(color: device.isActive ? device.kind.tint.opacity(0.45) : .clear, radius: 6, y: 2)
                if large {
                    Text(device.name).font(.caption2).lineLimit(1).minimumScaleFactor(0.4)
                        .frame(width: size + 6)
                }
            }
        }
        .buttonStyle(PressScale(scale: 0.8))
        .animation(.spring(duration: 0.3, bounce: 0.4), value: device.isActive)
        .accessibilityLabel("\(device.name), \(device.status)")
    }
}

/// What needs attention: lights left on, open doors and windows, unlocked locks, the temperature.
/// Each chip opens its items.
struct StatusCard: View {
    let compact: Bool
    @Environment(HomeStore.self) private var store
    @Environment(\.tileOpacity) private var tileOpacity
    @State private var opened: StatusCategory?

    var body: some View {
        let chips = StatusCategory.allCases.map { ($0, $0.items(in: store.devices)) }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { ForEach(chips, id: \.0) { chip($0.0, $0.1) } }
            HStack(spacing: 8) { ForEach(chips.prefix(2), id: \.0) { chip($0.0, $0.1) } }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground).opacity(tileOpacity), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)) }
        .sheet(item: $opened) { StatusSheet(category: $0).environment(store) }
        .sensoryFeedback(.impact(weight: .light), trigger: opened)
    }

    private func chip(_ category: StatusCategory, _ items: [Device]) -> some View {
        let count = items.count(where: category.needsAttention)
        let alert = category != .climate && count > 0
        return Button { opened = category } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .symbolEffect(.bounce, value: count)
                    .foregroundStyle(alert ? category.tint : .secondary)
                Text(category.summary(items))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(alert ? category.tint.opacity(0.18) : Color.primary.opacity(0.05), in: .capsule)
        }
        .buttonStyle(PressScale(scale: 0.9))
        .fixedSize()
        .disabled(items.isEmpty)
        .animation(.spring(duration: 0.3), value: count)
    }
}

enum StatusCategory: String, CaseIterable, Identifiable {
    case lights, openings, locks, climate

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .lights: "lightbulb.fill"
        case .openings: "door.left.hand.open"
        case .locks: "lock.open.fill"
        case .climate: "thermometer.medium"
        }
    }

    var tint: Color {
        switch self {
        case .lights: .yellow
        case .openings: .mint
        case .locks: .red
        case .climate: .orange
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .lights: "Lights"
        case .openings: "Doors & Windows"
        case .locks: "Locks"
        case .climate: "Climate"
        }
    }

    func items(in devices: [Device]) -> [Device] {
        devices.filter { device in
            switch self {
            case .lights: device.kind == .light
            case .openings: device.kind == .contact || device.kind == .garage
            case .locks: device.kind == .lock
            case .climate: device.kind == .thermostat
            }
        }
    }

    /// On, open or unlocked.
    func needsAttention(_ device: Device) -> Bool {
        switch self {
        case .lights: device.isOn
        case .openings: device.isActive
        case .locks: !device.isOn
        case .climate: false
        }
    }

    func summary(_ items: [Device]) -> String {
        let count = items.count(where: needsAttention)
        switch self {
        case .lights: return count == 0 ? String(localized: "Lights off") : String(localized: "\(count) on")
        case .openings: return count == 0 ? String(localized: "All closed") : String(localized: "\(count) open")
        case .locks: return count == 0 ? String(localized: "Locked") : String(localized: "\(count) unlocked")
        case .climate:
            let temperatures = items.compactMap(\.currentValue)
            return temperatures.isEmpty ? "–" : Device.celsius(temperatures.reduce(0, +) / Double(temperatures.count))
        }
    }
}

/// Every item behind a status chip, the ones needing attention first, with the obvious action on top.
struct StatusSheet: View {
    let category: StatusCategory
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var done = 0
    /// Fixed when the sheet opens: re-sorting as things switch would move the row from under the finger.
    @State private var order: [UUID] = []
    @State private var openedItem: Device?

    var body: some View {
        let items = category.items(in: store.devices)
        let attention = items.filter(category.needsAttention)
        let sorted = items.sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        NavigationStack {
            Form {
                // Always there, greyed out when there's nothing to do: appearing would push the rows down.
                if let action = action() {
                    Section {
                        Button(action.title, systemImage: action.icon) {
                            for device in attention {
                                store.binding(for: device).wrappedValue = device.setting(active: category == .locks)
                            }
                            done += 1
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .disabled(attention.isEmpty)
                    }
                }
                Section {
                    ForEach(sorted) { MemberRow(device: $0) { openedItem = $0 } }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .containerBackground(.clear, for: .navigation)
            .navigationDestination(item: $openedItem) { DeviceDetailView(device: $0, isPushed: true) }
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: done)
        .onAppear {
            // The ones needing attention first, once.
            order = (attention + items.filter { !category.needsAttention($0) }).map(\.id)
        }
    }

    private func action() -> (title: LocalizedStringKey, icon: String)? {
        switch category {
        case .lights: return ("Turn All Off", "lightbulb.slash")
        case .locks: return ("Lock All", "lock.fill")
        case .openings, .climate: return nil
        }
    }
}

/// A folder of cards, drawn like a Home Screen folder: the icons of what's inside.
struct FolderCard: View {
    let name: String
    let icons: [(symbol: String, tint: Color)]
    @Environment(\.tileOpacity) private var tileOpacity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let size = min((geometry.size.width - 16) / 3, (geometry.size.height - 16) / 3)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: 8), count: 3), alignment: .leading, spacing: 8) {
                    ForEach(icons.prefix(9).indices, id: \.self) { index in
                        Image(systemName: icons[index].symbol)
                            .font(.system(size: size * 0.45, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: size, height: size)
                            .background(icons[index].tint.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
                    }
                }
            }
            HStack {
                Text(name).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Text("\(icons.count)").font(.caption.bold()).foregroundStyle(.secondary).contentTransition(.numericText())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial.opacity(tileOpacity), in: .rect(cornerRadius: 24, style: .continuous))
        .background(Color(.secondarySystemGroupedBackground).opacity(tileOpacity * 0.5), in: .rect(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12)) }
    }
}
