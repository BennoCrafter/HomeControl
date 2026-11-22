import SwiftUI

@main
struct HomeControlApp: App {
    @State private var store = HomeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}

struct ContentView: View {
    @Environment(HomeStore.self) private var store
    @State private var selectedRoom: String? = "All"

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedRoom) {
                Label("All Devices", systemImage: "house.fill").tag("All")
                Section("Rooms") {
                    ForEach(store.rooms, id: \.self) { room in
                        Label(room, systemImage: "square.split.bottomrightquarter").tag(room)
                    }
                }
            }
            .navigationTitle(store.homeName)
        } detail: {
            let room = selectedRoom ?? "All"
            RoomView(title: room == "All" ? "All Devices" : room,
                     devices: store.devices.filter { room == "All" || $0.room == room })
                .overlay {
                    if store.devices.isEmpty, let message = store.message {
                        ContentUnavailableView(message, systemImage: "house")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !store.devices.isEmpty, let message = store.message {
                        Button(message, systemImage: "exclamationmark.triangle") { store.message = nil }
                            .padding()
                            .background(.thinMaterial, in: .capsule)
                            .padding()
                    }
                }
        }
    }
}

struct RoomView: View {
    let title: String
    let devices: [Device]
    @State private var editing: Device?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(devices) { device in
                    DeviceTile(device: device) { editing = device }
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .sheet(item: $editing) { DeviceDetail(device: $0) }
    }
}

struct DeviceTile: View {
    @Environment(HomeStore.self) private var store
    let device: Device
    let openDetail: () -> Void

    var body: some View {
        let d = store.binding(for: device)
        let active = d.wrappedValue.isOn
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Tapping the icon toggles, tapping elsewhere opens details (like the Home app).
                Button {
                    // Blinds have no power characteristic: the icon opens or closes them.
                    if device.kind == .blinds { d.wrappedValue.value = d.wrappedValue.isOn ? 0 : 1 }
                    d.wrappedValue.isOn.toggle()
                } label: {
                    Image(systemName: device.kind.icon)
                        .font(.title2)
                        .foregroundStyle(active ? device.kind.tint : .secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle \(device.name)")
                Spacer()
            }
            Text(device.name).font(.headline).lineLimit(1)
            Text(d.wrappedValue.status).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? AnyShapeStyle(device.kind.tint.opacity(0.25)) : AnyShapeStyle(.quinary),
                    in: .rect(cornerRadius: 16))
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture(perform: openDetail)
    }
}

struct DeviceDetail: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let device: Device

    var body: some View {
        let d = store.binding(for: device)
        NavigationStack {
            Form {
                Section {
                    Label(device.room, systemImage: device.kind.icon)
                        .foregroundStyle(device.kind.tint)
                }
                Section("Control") {
                    switch device.kind {
                    case .light:
                        Toggle("Power", isOn: d.isOn)
                        Slider(value: d.value, in: 0.05...1) { Text("Brightness") }
                            .disabled(!d.wrappedValue.isOn)
                    case .thermostat:
                        Toggle("Heating", isOn: d.isOn)
                        Stepper(String(format: "Target %.1f °C", d.wrappedValue.value),
                                value: d.value, in: 10...30, step: 0.5)
                    case .lock:
                        Toggle("Locked", isOn: d.isOn)
                    case .plug:
                        Toggle("Power", isOn: d.isOn)
                    case .blinds:
                        Slider(value: d.value, in: 0...1) { Text("Position") }
                        HStack {
                            Button("Close") { d.wrappedValue.value = 0 }
                            Spacer()
                            Button("Open") { d.wrappedValue.value = 1 }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Section { LabeledContent("Status", value: d.wrappedValue.status) }
            }
            .formStyle(.grouped)
            .navigationTitle(device.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
