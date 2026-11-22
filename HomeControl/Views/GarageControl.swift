import SwiftUI

/// Garage door drawn as a door that slides up into its frame, with an Open/Close button.
/// Opening asks for confirmation; the door animates towards the target state while the accessory moves.
struct GarageControl: View {
    @Binding var device: Device
    @State private var confirming = false

    /// How far the door is drawn open (0 closed ... 1 open).
    private var openFraction: Double {
        if device.currentState == 4 { return 0.5 } // stopped midway
        return device.isOn ? 0 : 1
    }

    private var isMoving: Bool {
        device.currentState == 2 || device.currentState == 3
    }

    var body: some View {
        VStack(spacing: 20) {
            door
                .onTapGesture(perform: toggle)
                .accessibilityElement()
                .accessibilityLabel("Garage door")
                .accessibilityValue(device.status)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggle() }

            Button(action: toggle) {
                Label(device.isOn ? "Open" : "Close",
                      systemImage: device.isOn ? "arrow.up" : "arrow.down")
                    .font(.headline)
                    .frame(minWidth: 140)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(device.kind.tint)
        }
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 2.2), value: openFraction)
        .sensoryFeedback(.impact(weight: .medium), trigger: device.isOn)
        .sensoryFeedback(.warning, trigger: device.isObstructed) { _, obstructed in obstructed }
        .confirmationDialog("Open \(device.name)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Open") { device.isOn = false }
        }
    }

    private func toggle() {
        if device.isOn { confirming = true } else { device.isOn = true }
    }

    private var door: some View {
        let width: CGFloat = 240, height: CGFloat = 190, panels = 5
        return ZStack(alignment: .top) {
            // Interior, revealed as the door rises.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(device.kind.tint.opacity(0.18))
                .overlay(alignment: .bottom) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 18)
                }

            // The door: stacked panels that slide up out of the frame.
            VStack(spacing: 4) {
                ForEach(0..<panels, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.tertiary)
                        .overlay(alignment: .top) {
                            Rectangle().fill(.white.opacity(0.15)).frame(height: 1.5)
                        }
                }
            }
            .padding(6)
            .frame(height: height)
            .offset(y: -height * openFraction)

            if device.isObstructed {
                Label("Obstructed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.top, 70)
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        // Frame with a roof line, like the opening of a garage.
        .padding(12)
        .background(.quaternary, in: UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 8,
                                                            bottomTrailingRadius: 8, topTrailingRadius: 28,
                                                            style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isMoving {
                ProgressView()
                    .padding(8)
                    .background(.ultraThinMaterial, in: .circle)
                    .padding(-10)
            }
        }
        .contentShape(.rect)
    }
}
