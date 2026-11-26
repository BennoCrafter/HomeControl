import SwiftUI

/// A big round lock: tap to lock, tap (and confirm) to unlock. Shows locking progress and jams.
struct LockControl: View {
    @Binding var device: Device
    @State private var confirming = false
    @State private var taps = 0

    private var isJammed: Bool { device.currentState == 2 }

    /// Target and reported state differ while the bolt moves.
    private var isMoving: Bool {
        guard let state = device.currentState, state <= 1 else { return false }
        return (state == 1) != device.isOn
    }

    private var color: Color {
        isJammed ? .orange : device.isOn ? device.kind.tint : .red
    }

    var body: some View {
        VStack(spacing: 18) {
            Button {
                taps += 1
                if device.isOn { confirming = true } else { device.isOn = true }
            } label: {
                ZStack {
                    Circle()
                        .fill(color.gradient.opacity(0.18))
                    Circle()
                        .strokeBorder(color.gradient, lineWidth: 10)
                    if isMoving {
                        Circle()
                            .trim(from: 0, to: 0.25)
                            .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .padding(5)
                            .rotationEffect(.degrees(isMoving ? 360 : 0))
                            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isMoving)
                    }
                    Image(systemName: isJammed ? "exclamationmark.lock.fill" : device.isOn ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 76, weight: .semibold))
                        .foregroundStyle(color.gradient)
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
                        .symbolEffect(.wiggle, value: isJammed)
                }
                .frame(width: 210, height: 210)
                .contentShape(.circle)
            }
            .buttonStyle(PressScale(scale: 0.9))
            .disabled(isJammed)
            .accessibilityLabel(device.isOn ? "Unlock" : "Lock")

            Text(device.status)
                .font(.title2.bold())
                .contentTransition(.interpolate)
            if isJammed {
                Label("The lock is jammed. Check the door, then try again in the Home app.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else {
                Text(device.isOn ? "Tap to unlock" : "Tap to lock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .animation(.spring(duration: 0.45, bounce: 0.35), value: device.isOn)
        .animation(.smooth, value: device.currentState)
        .sensoryFeedback(.impact(weight: .heavy), trigger: device.isOn)
        .sensoryFeedback(trigger: device.currentState) { _, state in state == 2 ? .error : state == 1 ? .success : nil }
        .confirmationDialog("Unlock \(device.name)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Unlock", role: .destructive) { device.isOn = false }
        }
    }
}

/// A door that swings open with the sensor, and when it last changed.
struct ContactView: View {
    let device: Device
    let since: Date?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(device.isContactOpen ? device.kind.tint.opacity(0.25) : Color.secondary.opacity(0.12))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.secondary).frame(width: 12).padding(.trailing, 14)
                    }
                    .rotation3DEffect(.degrees(device.isContactOpen ? -62 : 0), axis: (0, 1, 0), anchor: .leading, perspective: 0.5)
                    .shadow(color: .black.opacity(device.isContactOpen ? 0.25 : 0), radius: 10, x: 8)
            }
            .frame(width: 130, height: 210)
            .padding(10)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.spring(duration: 0.7, bounce: 0.35), value: device.isContactOpen)

            Text(device.isContactOpen ? "Open" : "Closed")
                .font(.largeTitle.bold())
                .foregroundStyle(device.isContactOpen ? device.kind.tint : .primary)
                .contentTransition(.interpolate)
            if let since {
                // Updates itself: "for 5 minutes".
                Text("\(device.isContactOpen ? "Open" : "Closed") for \(since, style: .relative)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .sensoryFeedback(.impact(weight: .medium), trigger: device.isContactOpen)
        .accessibilityElement(children: .combine)
    }
}
