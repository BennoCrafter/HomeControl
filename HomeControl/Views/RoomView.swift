import SwiftUI

struct RoomView: View {
    @Environment(HomeStore.self) private var store
    let title: String
    let devices: [Device]
    let showRoom: Bool
    @State private var selected: Device?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(devices) { device in
                    DeviceTile(device: device, showRoom: showRoom) { selected = device }
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .sheet(item: $selected) { DeviceDetailView(device: $0).environment(store) }
    }
}
