import SwiftUI

/// Make your own grainy gradient: pattern, colors, grain, softness and angle, previewed live.
struct GradientEditor: View {
    @State var style: GradientStyle
    let save: (GradientStyle) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shuffles = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GrainyGradient(style: style)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.15))
                    }
                    .shadow(color: (style.swiftUIColors.last ?? .clear).opacity(0.35), radius: 24, y: 10)
                    .padding()
                    .frame(maxHeight: 360)
                    .animation(.smooth(duration: 0.5), value: style)
                    .keyframeAnimator(initialValue: 1.0, trigger: shuffles) { $0.scaleEffect($1) } keyframes: { _ in
                        SpringKeyframe(0.95, duration: 0.1)
                        SpringKeyframe(1, duration: 0.5, spring: .bouncy)
                    }
                Form {
                    Section("Pattern") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(GradientStyle.Pattern.allCases) { pattern in
                                    patternButton(pattern)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section {
                        HStack(spacing: 10) {
                            ForEach(style.colors.indices, id: \.self) { index in
                                ColorPicker("Color \(index + 1)", selection: Binding(
                                    get: { Color(hex: style.colors[index]) },
                                    set: { style.colors[index] = $0.hex }
                                ), supportsOpacity: false)
                                .labelsHidden()
                                .scaleEffect(1.25)
                                .frame(width: 40, height: 40)
                                .contextMenu {
                                    if style.colors.count > 2 {
                                        Button("Remove", systemImage: "trash", role: .destructive) {
                                            withAnimation(.snappy) { _ = style.colors.remove(at: index) }
                                        }
                                    }
                                }
                            }
                            if style.colors.count < 5 {
                                Button {
                                    withAnimation(.snappy) { style.colors.append(GradientStyle.palettes.randomElement()!.randomElement()!) }
                                } label: {
                                    Image(systemName: "plus").font(.headline).frame(width: 40, height: 40).background(.quaternary, in: .circle)
                                }
                                .buttonStyle(PressScale(scale: 0.85))
                                .accessibilityLabel("Add Color")
                            }
                            Spacer()
                            Button {
                                shuffles += 1
                                withAnimation(.smooth(duration: 0.5)) {
                                    style.colors = GradientStyle.palettes.filter { $0 != style.colors }.randomElement() ?? style.colors
                                }
                            } label: {
                                Image(systemName: "dice.fill").font(.title3).symbolEffect(.bounce, value: shuffles)
                            }
                            .buttonStyle(PressScale(scale: 0.8))
                            .accessibilityLabel("Shuffle Colors")
                        }
                    } header: {
                        Text("Colors")
                    } footer: {
                        Text("The first color is the backdrop. Touch and hold a color to remove it.")
                    }
                    Section("Look") {
                        slider("Grain", value: $style.noise, systemImage: "circle.dotted")
                        slider("Softness", value: $style.softness, systemImage: "aqi.medium")
                        LabeledContent {
                            Slider(value: $style.angle, in: -180 ... 180, step: 5)
                        } label: {
                            Label("Angle", systemImage: "angle")
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: style.pattern)
                .sensoryFeedback(.impact(weight: .light), trigger: shuffles)
            }
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        save(style)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func patternButton(_ pattern: GradientStyle.Pattern) -> some View {
        let selected = style.pattern == pattern
        var preview = style
        preview.pattern = pattern
        return Button {
            withAnimation(.smooth(duration: 0.4)) { style.pattern = pattern }
        } label: {
            VStack(spacing: 6) {
                GrainyGradient(style: preview)
                    .frame(width: 70, height: 96)
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                    }
                    .scaleEffect(selected ? 1.05 : 1)
                Text(pattern.title).font(.caption).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(PressScale())
        .animation(.spring(duration: 0.3, bounce: 0.5), value: selected)
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, systemImage: String) -> some View {
        LabeledContent {
            Slider(value: value, in: 0 ... 1)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
