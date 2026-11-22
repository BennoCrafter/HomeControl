import SwiftUI

struct DeviceTile: View {
    @Environment(HomeStore.self) private var store
    let device: Device
    let showRoom: Bool
    let openDetail: () -> Void
    @State private var confirming = false
    @State private var toggles = 0

    var body: some View {
        let binding = store.binding(for: device)
        let current = binding.wrappedValue
        VStack(spacing: 4) {
            // Tapping the icon toggles, tapping elsewhere opens details (like the Home app).
            Button {
                if current.confirmationAction != nil {
                    confirming = true
                } else {
                    binding.wrappedValue = current.toggled()
                    toggles += 1
                }
            } label: {
                Image(systemName: current.icon)
                    .font(.title)
                    .foregroundStyle(current.isActive ? current.kind.tint : .secondary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .disabled(!current.isReachable || !current.kind.isControllable)
            .accessibilityLabel("Toggle \(current.name)")
            Spacer(minLength: 4)
            if showRoom {
                Text(current.room).font(.caption).foregroundStyle(.secondary)
            }
            Text(current.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(current.status)
                .font(.subheadline)
                .foregroundStyle(current.isReachable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if !current.isReachable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(10)
            }
        }
        .background(current.isActive ? AnyShapeStyle(current.kind.tint.opacity(0.25)) : AnyShapeStyle(.quinary),
                    in: .rect(cornerRadius: 16))
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture(perform: openDetail)
        .confirmationDialog("\(current.confirmationAction ?? "") \(current.name)?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(current.confirmationAction ?? "OK") {
                binding.wrappedValue = binding.wrappedValue.toggled()
                toggles += 1
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: toggles)
    }
}
