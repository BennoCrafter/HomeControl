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
                    .foregroundStyle(.white)
                    .frame(minWidth: 140)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(device.kind.tint)
        }
        .padding(.vertical, 12)
        .animation(.timingCurve(0.45, 0, 0.3, 1, duration: 2.2), value: openFraction)
        .animation(.spring(duration: 0.4, bounce: 0.4), value: device.isObstructed)
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
        let width: CGFloat = 240, height: CGFloat = 190
        return ZStack(alignment: .top) {
            // Interior, revealed as the door rises.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [device.kind.tint.opacity(0.08), device.kind.tint.opacity(0.28)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottom) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 18)
                        .scaleEffect(openFraction > 0.5 ? 1 : 0.92)
                        .opacity(openFraction)
                }
            SectionalDoor(fraction: openFraction, obstructed: device.isObstructed)

            if device.isObstructed {
                Label("Obstructed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.red.gradient, in: .capsule)
                    .padding(.top, 70)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        // Frame with a roof line, like the opening of a garage.
        .padding(12)
        .background(.quaternary, in: UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 8,
                                                            bottomTrailingRadius: 8, topTrailingRadius: 28,
                                                            style: .continuous))
        .overlay(alignment: .top) { warningLight }
        .keyframeAnimator(initialValue: 0.0, trigger: device.isObstructed) { $0.offset(x: $1) } keyframes: { _ in
            KeyframeTrack {
                for offset in [10.0, -9, 7, -5, 3, 0] { SpringKeyframe(offset, duration: 0.07) }
            }
        }
        .contentShape(.rect)
    }

    /// Blinks amber while the door moves, like the light on a real opener.
    private var warningLight: some View {
        Capsule()
            .fill(isMoving ? Color.orange : Color.secondary.opacity(0.3))
            .frame(width: 44, height: 7)
            .shadow(color: isMoving ? .orange : .clear, radius: 8)
            .phaseAnimator([false, true], trigger: isMoving) { light, lit in
                light.opacity(isMoving && !lit ? 0.35 : 1)
            } animation: { _ in .easeInOut(duration: 0.45) }
            .padding(.top, 3)
    }
}

/// Five panels that slide up and tip back into the ceiling one after another, like a sectional door.
/// Animatable so every panel's tilt follows the door's position frame by frame.
private struct SectionalDoor: View, Animatable {
    var fraction: Double
    let obstructed: Bool

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    private static let panels = 5
    /// Opaque in both modes: the system grays are translucent enough to show the car through.
    private static let panelColor = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 0.86, alpha: 1) })

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let panel = height / CGFloat(Self.panels)
            ZStack(alignment: .top) {
                ForEach(0 ..< Self.panels, id: \.self) { index in
                    let top = CGFloat(index) * panel - height * fraction
                    // Above the opening the panel runs along the ceiling track: tilted back, up to flat.
                    let tilt = top < 0 ? min(88, Double(-top / panel) * 88) : 0
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(obstructed ? AnyShapeStyle(Color.red.mix(with: .gray, by: 0.4).gradient) : AnyShapeStyle(Self.panelColor.gradient))
                        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.25)).frame(height: 1.5) }
                        .overlay {
                            HStack(spacing: 6) {
                                ForEach(0 ..< 4, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.07), lineWidth: 1.5)
                                }
                            }
                            .padding(6)
                        }
                        .frame(height: panel - 2)
                        .rotation3DEffect(.degrees(tilt), axis: (1, 0, 0), anchor: .bottom, perspective: 0.4)
                        .offset(y: max(top, -panel))
                        .opacity(tilt > 80 ? 0 : 1)
                }
            }
            .padding(.horizontal, 6)
        }
    }
}
