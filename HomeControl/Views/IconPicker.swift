import SwiftUI

/// A searchable grid of home-related SF Symbols. `nil` goes back to the automatic icon.
struct IconPicker: View {
    let title: String
    let current: String?
    let tint: Color
    let pick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var picked: String?

    static let groups: [(name: LocalizedStringKey, symbols: [String])] = [
        ("Lights", ["lightbulb.fill", "lightbulb.led.fill", "lamp.desk.fill", "lamp.floor.fill", "lamp.table.fill",
                    "lamp.ceiling.fill", "chandelier.fill", "light.recessed.fill", "light.strip.2.fill", "light.panel.fill",
                    "lightspectrum.horizontal", "sun.max.fill", "moon.stars.fill", "sparkles"]),
        ("Climate", ["thermometer.medium", "heater.vertical.fill", "fan.fill", "fan.ceiling.fill", "air.conditioner.horizontal.fill",
                     "humidifier.fill", "dehumidifier.fill", "air.purifier.fill", "snowflake", "flame.fill", "drop.fill", "wind"]),
        ("Security", ["lock.fill", "lock.open.fill", "door.left.hand.closed", "door.garage.closed", "door.sliding.left.hand.closed",
                      "window.vertical.closed", "web.camera.fill", "video.doorbell.fill", "sensor.fill", "light.beacon.max.fill",
                      "exclamationmark.shield.fill", "key.fill"]),
        ("Appliances", ["powerplug.fill", "poweroutlet.type.f.fill", "tv.fill", "hifispeaker.fill", "homepod.fill", "appletv.fill",
                        "washer.fill", "dryer.fill", "dishwasher.fill", "refrigerator.fill", "oven.fill", "microwave.fill",
                        "cup.and.saucer.fill", "robotic.vacuum.fill", "printer.fill", "gamecontroller.fill", "desktopcomputer",
                        "laptopcomputer", "bolt.car.fill", "ev.charger.fill", "spigot.fill", "shower.fill"]),
        ("Covers", ["blinds.horizontal.closed", "blinds.vertical.closed", "roller.shade.closed", "curtains.closed",
                    "window.shade.closed", "window.awning.closed"]),
        ("Rooms", ["house.fill", "sofa.fill", "bed.double.fill", "bathtub.fill", "fork.knife", "toilet.fill", "stairs",
                   "car.fill", "leaf.fill", "tree.fill", "figure.and.child.holdinghands", "dumbbell.fill", "book.fill",
                   "teddybear.fill", "pawprint.fill", "tent.fill", "sun.horizon.fill", "building.2.fill"]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(filtered, id: \.symbols) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.name).font(.headline).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                                ForEach(group.symbols, id: \.self, content: cell)
                            }
                        }
                    }
                }
                .padding()
            }
            .searchable(text: $search, prompt: "Search icons")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Automatic") {
                        pick(nil)
                        dismiss()
                    }
                    .disabled(current == nil)
                }
            }
            .sensoryFeedback(.selection, trigger: picked)
        }
        .presentationDetents([.medium, .large])
    }

    private var filtered: [(name: LocalizedStringKey, symbols: [String])] {
        let query = search.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Self.groups }
        return Self.groups.compactMap { group in
            let symbols = group.symbols.filter { $0.replacingOccurrences(of: ".", with: " ").contains(query) }
            return symbols.isEmpty ? nil : (group.name, symbols)
        }
    }

    private func cell(_ symbol: String) -> some View {
        let isCurrent = (picked ?? current) == symbol
        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.5)) { picked = symbol }
            pick(symbol)
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                dismiss()
            }
        } label: {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(isCurrent ? .white : tint)
                .frame(width: 56, height: 56)
                .background(isCurrent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.quinary), in: .rect(cornerRadius: 14))
                .scaleEffect(isCurrent ? 1.1 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
    }
}
