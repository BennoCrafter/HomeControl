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
    @State private var lastSent = Date.distantPast
    @State private var jumps = 0
    /// The level as drawn. Animated locally so taps spring immediately, independent of HomeKit round-trips.
    @State private var displayed: Double?
    @State private var lastLocalChange = Date.distantPast
    @State private var springTask: Task<Void, Never>?
    @State private var dialAreaWidth: CGFloat = 0

    private static let spring = Spring(duration: 0.55, bounce: 0.35)
    /// Drags may start this far outside the control, and anywhere across the row, so the finger needn't hit it.
    private static let dragSlop: CGFloat = 40

    private var shown: Double { draft ?? displayed ?? level }

    /// What the label reads: the target, never the spring's in-between or overshoot values.
    private var labelValue: Double { draft ?? level }

    private var label: String {
        let value = labelValue
        switch look {
        case .light: return value == 0 ? "Off" : value.formatted(.percent.precision(.fractionLength(0)))
        case .shutter: return value == 0 ? "Closed" : "\(value.formatted(.percent.precision(.fractionLength(0)))) open"
        }
    }

    var body: some View {
        Group {
            switch look == .light ? lightStyle : shutterStyle {
            case .pill: pill
            case .dial: dial
            }
        }
        .onChange(of: level) { _, new in
            // Ignore echoes of our own writes (HomeKit refreshes can briefly report older values).
            guard draft == nil, Date.now.timeIntervalSince(lastLocalChange) > 1.2 else { return }
            animate(to: new)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: jumps)
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
        .accessibilityAction { toggle() }
    }

    private func drag(to value: Double) {
        let value = min(max(value, 0), 1)
        springTask?.cancel()
        draft = value
        lastLocalChange = .now
        // shortcut: fixed 0.1 s throttle, slow accessories may lag behind; the final value is always sent on release
        if Date.now.timeIntervalSince(lastSent) > 0.1 {
            lastSent = .now
            level = value
        }
    }

    /// On/off tap: animate here, since `onChange` drops level changes right after a drag as echoes.
    private func toggle() {
        onTap()
        lastLocalChange = .now
        animate(to: level)
    }

    /// Tap on a spot: springs straight to that level.
    private func jump(to value: Double) {
        let value = min(max(value, 0), 1)
        lastLocalChange = .now
        animate(to: value)
        level = value
        jumps += 1
    }

    /// Steps the spring frame by frame, so the bounce shows no matter which transaction the update arrives in.
    private func animate(to target: Double) {
        let start = shown
        springTask?.cancel()
        springTask = Task {
            let clock = ContinuousClock(), began = clock.now
            while !Task.isCancelled {
                let time = (clock.now - began) / .seconds(1)
                guard time < Self.spring.settlingDuration else { break }
                displayed = start + (target - start) * Self.spring.value(target: 1.0, time: time)
                try? await Task.sleep(for: .milliseconds(8))
            }
            if !Task.isCancelled { displayed = target }
        }
    }

    private func endDrag() {
        // A dial touch that never moved sets no draft; it must not freeze a running spring mid-bounce.
        if let draft {
            springTask?.cancel()
            level = draft
            displayed = draft
            lastLocalChange = .now
        }
        draft = nil
    }

    private var badge: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title2)
            Text(label)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText(value: labelValue))
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
                    // max(0, …): the spring overshoots past the ends; negative heights would break the animation.
                    Rectangle().fill(tint.gradient).frame(height: max(0, height * shown))
                case .shutter:
                    Rectangle().fill(tint.opacity(0.2))
                    ShutterSlats()
                        .fill(tint.gradient)
                        .frame(height: max(0, height * (1 - shown)))
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                Button(action: toggle) { badge }
                    .buttonStyle(.plain)
                    .frame(maxHeight: .infinity)
            }
            .clipShape(.rect(cornerRadius: 40))
            .contentShape(.rect(cornerRadius: 40))
            .gesture(SpatialTapGesture().onEnded { tap in jump(to: 1 - tap.location.y / height) })
        }
        .frame(width: 130, height: 300)
        .padding(.vertical, Self.dragSlop)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .highPriorityGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { gesture in
                    drag(to: 1 - (gesture.location.y - Self.dragSlop) / 300) // the fill edge follows the finger
                }
                .onEnded { _ in endDrag() }
        )
    }

    // MARK: Dial

    /// 270° arc with the gap at the bottom, filled clockwise up to `fraction`.
    /// Trim clamps to 0...1, so spring overshoot past either end animates cleanly in both directions.
    private func dialArc(_ fraction: Double) -> some Shape {
        Circle()
            .trim(from: 0, to: 0.75 * min(max(fraction, 0), 1))
            .rotation(.degrees(135))
    }

    /// Level under a point relative to the dial centre; below 0 / above 1 inside the bottom gap.
    private func dialValue(dx: CGFloat, dy: CGFloat) -> Double {
        (atan2(dx, -dy) * 180 / .pi + 135) / 270
    }

    private var dial: some View {
        let size: CGFloat = 260
        let lineWidth: CGFloat = 30
        let radius = (size - lineWidth) / 2
        let angle = Angle.degrees(-135 + 270 * shown).radians // 0 = 12 o'clock, clockwise
        return ZStack {
            dialArc(1).stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            dialArc(shown).stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .fill(.white)
                .shadow(radius: 3)
                .frame(width: lineWidth - 4, height: lineWidth - 4)
                // Knob grows while held and pops on a tap, before the offset so it scales in place.
                .scaleEffect(draft != nil ? 1.25 : 1)
                .animation(.spring(duration: 0.3, bounce: 0.5), value: draft != nil)
                .keyframeAnimator(initialValue: 1.0, trigger: jumps) { $0.scaleEffect($1) } keyframes: { _ in
                    SpringKeyframe(1.4, duration: 0.1)
                    SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                }
                .offset(y: -radius)
                .rotationEffect(.radians(angle)) // rotating (not offsetting) keeps the knob on the arc while animating
            Button(action: toggle) { badge }
                .buttonStyle(.plain)
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .contentShape(.circle)
        .gesture(SpatialTapGesture().onEnded { tap in
            let dx = tap.location.x - size / 2, dy = tap.location.y - size / 2
            guard hypot(dx, dy) > radius * 0.4 else { return } // the centre is the toggle button
            jump(to: dialValue(dx: dx, dy: dy))
        })
        .padding(.vertical, Self.dragSlop)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { dialAreaWidth = $0 }
        .highPriorityGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { gesture in
                    let dx = gesture.location.x - dialAreaWidth / 2, dy = gesture.location.y - (Self.dragSlop + size / 2)
                    guard hypot(dx, dy) > radius * 0.4 else { return }
                    // The knob points where the finger is; crossing the bottom gap must not flip between 0 and 1.
                    // Only inside the gap; elsewhere (e.g. sweeping across the centre) big jumps are intended.
                    let raw = dialValue(dx: dx, dy: dy), value = min(max(raw, 0), 1)
                    if raw != value, let draft, abs(value - draft) > 0.5 { return }
                    drag(to: value)
                }
                .onEnded { _ in endDrag() }
        )
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
