import SwiftUI

/// A room, group or collection: its name, what's on, and a quick toggle per item.
struct RoomCard: View {
    let title: String
    let icon: String
    let items: [Device]
    let large: Bool
    let open: () -> Void

    @Environment(HomeStore.self) private var store
    @Environment(\.itemPrefs) private var prefs
    @Environment(\.tileOpacity) private var tileOpacity
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
                        Text(title).font(.headline).lineLimit(1)
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
                let size: CGFloat = large ? 54 : 42
                let perRow = max(1, Int((geometry.size.width + 8) / (size + 8)))
                let rows = max(1, Int((geometry.size.height + 8) / (size + (large ? 22 : 8))))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: 8), count: perRow), alignment: .leading, spacing: 8) {
                    ForEach(devices.prefix(perRow * rows)) { device in
                        toggle(device, size: size)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground).opacity(tileOpacity), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)) }
        .sensoryFeedback(.impact(weight: .medium), trigger: toggles)
    }

    private func toggle(_ device: Device, size: CGFloat) -> some View {
        Button {
            guard device.kind.isControllable, device.confirmationAction == nil else {
                open()
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
                    Text(device.name).font(.caption2).lineLimit(1).frame(width: size + 6)
                }
            }
        }
        .buttonStyle(PressScale(scale: 0.8))
        .animation(.spring(duration: 0.3, bounce: 0.4), value: device.isActive)
        .accessibilityLabel("\(device.name), \(device.status)")
    }
}

/// What needs attention: lights left on, open doors and windows, unlocked locks, the temperature.
struct StatusCard: View {
    let compact: Bool
    @Environment(HomeStore.self) private var store
    @Environment(\.tileOpacity) private var tileOpacity
    @State private var allOff = 0

    var body: some View {
        let lights = store.devices.filter { $0.kind == .light && $0.isOn }
        let open = store.devices.filter { ($0.kind == .contact && $0.isContactOpen) || ($0.kind == .garage && !$0.isOn) }
        let unlocked = store.devices.filter { $0.kind == .lock && !$0.isOn }
        let temperatures = store.devices.compactMap { $0.kind == .thermostat ? $0.currentValue : nil }
        let chips: [(String, String, Color, Int?)] = [
            ("lightbulb.fill", lights.isEmpty ? String(localized: "Lights off") : String(localized: "\(lights.count) on"), .yellow, lights.count),
            ("door.left.hand.open", open.isEmpty ? String(localized: "All closed") : String(localized: "\(open.count) open"), .mint, open.count),
            ("lock.open.fill", unlocked.isEmpty ? String(localized: "Locked") : String(localized: "\(unlocked.count) unlocked"), .red, unlocked.count),
            ("thermometer.medium", temperatures.isEmpty ? "–" : Device.celsius(temperatures.reduce(0, +) / Double(temperatures.count)), .orange, nil),
        ]
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { ForEach(chips.indices, id: \.self) { chip(chips[$0], lights: lights) } }
            HStack(spacing: 8) { ForEach(chips.prefix(2).indices, id: \.self) { chip(chips[$0], lights: lights) } }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground).opacity(tileOpacity), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)) }
        .sensoryFeedback(.success, trigger: allOff)
    }

    private func chip(_ chip: (String, String, Color, Int?), lights: [Device]) -> some View {
        let (icon, text, tint, count) = chip
        let alert = (count ?? 0) > 0
        return Button {
            // The lights chip turns every light off: the one thing you want from it on the way out.
            guard icon == "lightbulb.fill", !lights.isEmpty else { return }
            for light in lights {
                store.binding(for: light).wrappedValue.isOn = false
            }
            allOff += 1
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .symbolEffect(.bounce, value: count)
                    .foregroundStyle(alert ? tint : .secondary)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(alert ? tint.opacity(0.18) : Color.primary.opacity(0.05), in: .capsule)
        }
        .buttonStyle(PressScale(scale: 0.9))
        .fixedSize()
        .animation(.spring(duration: 0.3), value: text)
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
                Text(name).font(.headline).lineLimit(1)
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
