import SwiftUI

struct RoomView: View {
    @Environment(HomeStore.self) private var store
    let title: String
    let devices: [Device]
    let showRoom: Bool
    @State private var selected: Device?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(devices) { device in
                    DeviceTile(device: device, showRoom: showRoom) { selected = device }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        #if DEBUG
        // Screenshots: `-open "Front Door"` opens that item's details.
        .task {
            if let name = UserDefaults.standard.string(forKey: "open") {
                selected = devices.first { $0.name == name }
            }
        }
        #endif
        .sheet(item: $selected) { DeviceDetailView(device: $0).environment(store) }
    }
}
