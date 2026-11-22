import SwiftUI

enum ControlStyle: String, CaseIterable, Identifiable {
    case pill, dial

    var id: Self { self }
    var title: String { self == .pill ? "Pill" : "Dial" }
}

/// Big touch control for a 0...1 level (light brightness or shutter opening), drawn as a pill or a dial.
/// Sends changes live while dragging (throttled) and ticks haptically every 10%.
struct LevelControl: View {
    enum Look { case light, shutter }

    @Binding var level: Double
    let look: Look
    let tint: Color
    let icon: String
    let onTap: () -> Void

    @AppStorage("controlStyle.light") private var lightStyle: ControlStyle = .dial
    @AppStorage("controlStyle.shutter") private var shutterStyle: ControlStyle = .pill
    @State private var draft: Double?
    @State private var dragStart: Double?
    @State private var lastSent = Date.distantPast
    @State private var lastAngle: Double?

    private var shown: Double { draft ?? level }

    private var label: String {
        switch look {
        case .light: shown == 0 ? "Off" : shown.formatted(.percent.precision(.fractionLength(0)))
        case .shutter: shown == 0 ? "Closed" : "\(shown.formatted(.percent.precision(.fractionLength(0)))) open"
        }
    }

    var body: some View {
        Group {
            switch look == .light ? lightStyle : shutterStyle {
            case .pill: pill
            case .dial: dial
            }
        }
        .sensoryFeedback(trigger: draft.map { Int(($0 * 10).rounded()) }) { _, step in
            guard let step else { return nil }
            return step == 0 || step == 10 ? .impact(weight: .heavy) : .selection
        }
        .accessibilityElement()
        .accessibilityLabel(look == .light ? "Brightness" : "Shutter position")
        .accessibilityValue(label)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: level = min(1, level + 0.1)
            case .decrement: level = max(0, level - 0.1)
            @unknown default: break
            }
        }
        .accessibilityAction { onTap() }
    }

    private func drag(to value: Double) {
        let value = min(max(value, 0), 1)
        draft = value
        // shortcut: fixed 0.1 s throttle, slow accessories may lag behind; the final value is always sent on release
        if Date.now.timeIntervalSince(lastSent) > 0.1 {
            lastSent = .now
            level = value
        }
    }

    private func endDrag() {
        if let draft { level = draft }
        draft = nil
        dragStart = nil
        lastAngle = nil
    }

    private var badge: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title2)
            Text(label)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText(value: shown))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
    }

    // MARK: Pill

    private var pill: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .bottom) {
                Rectangle().fill(.quaternary)
                switch look {
                case .light:
                    Rectangle().fill(tint.gradient).frame(height: height * shown)
                case .shutter:
                    Rectangle().fill(tint.opacity(0.2))
                    ShutterSlats()
                        .fill(tint.gradient)
                        .frame(height: height * (1 - shown))
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                badge.frame(maxHeight: .infinity)
            }
            .clipShape(.rect(cornerRadius: 40))
            .contentShape(.rect(cornerRadius: 40))
            .onTapGesture(perform: onTap)
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { gesture in
                        let start = dragStart ?? shown
                        dragStart = start
                        drag(to: start - gesture.translation.height / height)
                    }
                    .onEnded { _ in endDrag() }
            )
            .animation(.interactiveSpring, value: shown)
        }
        .frame(width: 130, height: 300)
    }

    // MARK: Dial

    private var dial: some View {
        let size: CGFloat = 260
        let lineWidth: CGFloat = 30
        let radius = (size - lineWidth) / 2
        let angle = Angle.degrees(-135 + 270 * shown).radians // 0 = 12 o'clock, clockwise
        return ZStack {
            DialArc(fraction: 1).stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            DialArc(fraction: shown).stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .fill(.white)
                .shadow(radius: 3)
                .frame(width: lineWidth - 4, height: lineWidth - 4)
                .offset(x: radius * sin(angle), y: -radius * cos(angle))
            Button(action: onTap) { badge }
                .buttonStyle(.plain)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .contentShape(.circle)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let dx = gesture.location.x - size / 2, dy = gesture.location.y - size / 2
                    guard hypot(dx, dy) > radius * 0.4 else { return } // the centre is the tap target
                    // Relative turning: follow how far the finger rotates, wherever it starts, so the knob never jumps or gets stuck.
                    let angle = atan2(dx, -dy) * 180 / .pi
                    if let lastAngle {
                        var delta = angle - lastAngle
                        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
                        drag(to: shown + delta / 270)
                    }
                    lastAngle = angle
                }
                .onEnded { _ in endDrag() }
        )
        .animation(.interactiveSpring, value: shown)
    }
}

/// 270° arc with the gap at the bottom, filled clockwise up to `fraction`.
nonisolated private struct DialArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                        startAngle: .degrees(135), endAngle: .degrees(135 + 270 * fraction), clockwise: false)
        }
    }
}

/// Horizontal shutter slats, anchored at the bottom edge so they slide down as the shutter closes.
nonisolated private struct ShutterSlats: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var bottom = rect.maxY
        while bottom > rect.minY {
            let top = max(rect.minY, bottom - 12)
            path.addRoundedRect(in: CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top),
                                cornerSize: CGSize(width: 2, height: 2))
            bottom -= 15
        }
        return path
    }
}
