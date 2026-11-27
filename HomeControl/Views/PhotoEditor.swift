import SwiftUI

/// Fits a photo to the screen before it becomes the background: pan, pinch, turn, dim and blur, previewed phone-shaped.
struct PhotoEditor: View {
    let save: (UIImage) -> Void
    @State private var image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pan: CGSize = .zero
    @State private var dim = 0.0
    @State private var blur = 0.0
    @State private var turns = 0

    init(image: UIImage, save: @escaping (UIImage) -> Void) {
        _image = State(initialValue: image)
        self.save = save
    }

    private var screen: CGSize { ScreenPreview<EmptyView>.screen }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    // Gestures move the screen-sized canvas: finger distance divided by how much smaller it's drawn.
                    let shown = min(geometry.size.width / screen.width, geometry.size.height / screen.height)
                    ScreenPreview { canvas(zoom: zoom * pinch, offset: offset + pan / shown) }
                        .frame(width: screen.width * shown, height: screen.height * shown)
                        .clipShape(.rect(cornerRadius: 28, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.15)) }
                        .contentShape(.rect)
                        .gesture(
                            DragGesture()
                                .updating($pan) { value, state, _ in state = value.translation }
                                .onEnded { offset = clamped(offset + $0.translation / shown, zoom: zoom) }
                                .simultaneously(with: MagnifyGesture()
                                    .updating($pinch) { value, state, _ in state = value.magnification }
                                    .onEnded {
                                        zoom = min(max(zoom * $0.magnification, 1), 5)
                                        offset = clamped(offset, zoom: zoom)
                                    })
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding()
                Form {
                    LabeledContent {
                        Slider(value: $dim, in: 0 ... 0.7)
                    } label: {
                        Label("Dim", systemImage: "sun.min")
                    }
                    LabeledContent {
                        Slider(value: $blur, in: 0 ... 1)
                    } label: {
                        Label("Blur", systemImage: "drop")
                    }
                }
                .frame(height: 150)
                .scrollDisabled(true)
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Rotate", systemImage: "rotate.right") {
                        image = image.turnedRight()
                        turns += 1
                        zoom = 1
                        offset = .zero
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        let renderer = ImageRenderer(content: canvas(zoom: zoom, offset: offset).frame(width: screen.width, height: screen.height))
                        renderer.scale = 2
                        if let edited = renderer.uiImage { save(edited) }
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: turns)
        }
    }

    /// The background exactly as it's saved: the photo filling the screen, moved, zoomed, blurred and dimmed.
    private func canvas(zoom: CGFloat, offset: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: screen.width, height: screen.height)
            .scaleEffect(zoom)
            .offset(offset)
            .blur(radius: blur * 30, opaque: true)
            .overlay(Color.black.opacity(dim))
            .clipped()
    }

    /// Keeps the photo covering the screen: it may move only as far as it overhangs.
    private func clamped(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let fill = max(screen.width / image.size.width, screen.height / image.size.height) * zoom
        let maxX = max(0, (image.size.width * fill - screen.width) / 2)
        let maxY = max(0, (image.size.height * fill - screen.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }
}

private func + (a: CGSize, b: CGSize) -> CGSize { CGSize(width: a.width + b.width, height: a.height + b.height) }
private func / (a: CGSize, b: CGFloat) -> CGSize { CGSize(width: a.width / b, height: a.height / b) }

private extension UIImage {
    /// A quarter turn clockwise.
    func turnedRight() -> UIImage {
        let turned = CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        return UIGraphicsImageRenderer(size: turned, format: format).image { context in
            context.cgContext.translateBy(x: turned.width / 2, y: turned.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
