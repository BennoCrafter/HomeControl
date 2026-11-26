import SwiftUI

/// A grainy gradient background, made in the editor. Stored as JSON with the home's appearance.
nonisolated struct GradientStyle: Codable, Hashable, Sendable {
    enum Pattern: String, Codable, CaseIterable, Identifiable {
        case glow, aurora, orbs, linear

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .glow: "Glow"
            case .aurora: "Aurora"
            case .orbs: "Orbs"
            case .linear: "Linear"
            }
        }
    }

    var pattern = Pattern.glow
    /// Hex colors, 2 to 5. The first is the backdrop.
    var colors: [UInt32] = [0x2F5BEA, 0xB84FE0, 0xF2547D, 0xFFA21F]
    /// 0 is smooth, 1 is very grainy.
    var noise = 0.35
    /// How far the colors bleed into each other.
    var softness = 0.6
    /// Degrees: the direction of the linear gradient, where the glow rises from.
    var angle = 0.0

    @MainActor var swiftUIColors: [Color] { colors.map { Color(hex: $0) } }

    static let palettes: [[UInt32]] = [
        [0x2F5BEA, 0xB84FE0, 0xF2547D, 0xFFA21F],
        [0x0B1026, 0x3A1C71, 0xD76D77, 0xFFAF7B],
        [0x00C6FF, 0x0072FF, 0x7F00FF],
        [0x134E5E, 0x71B280, 0xE8F5C8],
        [0xFF5F6D, 0xFFC371, 0xFFF1C1],
        [0x1A1A2E, 0x16213E, 0x0F3460, 0xE94560],
        [0xF8C8DC, 0xB5DEFF, 0xCAB8FF, 0xFCFFA6],
        [0x000000, 0x434343, 0xC9D6FF],
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    var hex: UInt32 {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ value: CGFloat) -> UInt32 { UInt32(max(0, min(255, (value * 255).rounded()))) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

/// Draws a `GradientStyle`, grain on top.
struct GrainyGradient: View {
    let style: GradientStyle

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let colors = style.swiftUIColors
            // Relative to the size, so a thumbnail looks like the full background.
            let blur = min(size.width, size.height) * (0.08 + style.softness * 0.22)
            ZStack {
                (colors.first ?? .blue)
                switch style.pattern {
                case .glow:
                    // Rises from the bottom like a flame: each color a smaller, brighter glow inside the last.
                    ForEach(Array(colors.dropFirst().enumerated()), id: \.offset) { index, color in
                        let t = CGFloat(index + 1) / CGFloat(max(colors.count, 2))
                        Ellipse()
                            .fill(color)
                            .frame(width: size.width * (1.1 - t * 0.45), height: size.height * (1 - t * 0.35))
                            .offset(y: size.height * (0.15 + t * 0.2))
                            .blur(radius: blur * (1 - t * 0.4))
                    }
                    .rotationEffect(.degrees(style.angle))
                case .aurora:
                    MeshGradient(width: 3, height: 3, points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [Float(0.5 + 0.3 * sin(style.angle * .pi / 180)), Float(0.5 - 0.2 * style.softness)], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1],
                    ], colors: (0 ..< 9).map { colors[($0 * 2 + $0 / 3) % colors.count] })
                case .orbs:
                    ForEach(Array(colors.dropFirst().enumerated()), id: \.offset) { index, color in
                        let spot = Self.orbSpots[index % Self.orbSpots.count]
                        Circle()
                            .fill(color)
                            .frame(width: size.width * 0.75)
                            .position(x: size.width * spot.x, y: size.height * spot.y)
                            .blur(radius: blur)
                    }
                    .rotationEffect(.degrees(style.angle))
                case .linear:
                    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                        .scaleEffect(1.6)
                        .rotationEffect(.degrees(style.angle))
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay {
                Rectangle()
                    .fill(ImagePaint(image: Image(uiImage: Self.grain), scale: 0.5))
                    .blendMode(.overlay)
                    .opacity(style.noise)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Random gray pixels, tiled over the gradient: film grain without a Metal shader.
    private static let grain: UIImage = {
        let side = 256
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        var generator = SystemRandomNumberGenerator()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt8.random(in: 0 ... 255, using: &generator)
            (pixels[index], pixels[index + 1], pixels[index + 2]) = (value, value, value)
        }
        let image = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return image.map { UIImage(cgImage: $0) } ?? UIImage()
    }()

    private static let orbSpots: [CGPoint] = [CGPoint(x: 0.2, y: 0.25), CGPoint(x: 0.85, y: 0.45), CGPoint(x: 0.35, y: 0.85), CGPoint(x: 0.75, y: 0.1)]
}
