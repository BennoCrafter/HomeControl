// Renders the app icon variants. Usage: swift Tools/render-icon.swift HomeControl/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Variant { case light, dark, tinted }

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

/// Draws a frosted "glass" shape: translucent white fill, soft shadow and a bright top edge fading downwards.
func drawGlass(_ ctx: CGContext, _ path: CGPath, fill: CGFloat, edge: CGFloat, shadow: CGFloat) {
    let box = path.boundingBoxOfPath
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 36, color: rgb(0x001A4D, shadow))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0xFFFFFF, fill))
    ctx.fillPath()
    ctx.restoreGState()

    // Light falls from the top: a subtle sheen inside and a crisp rim along the upper edges.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, fill * 0.9), rgb(0xFFFFFF, 0)]),
                           start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.midY), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, edge), rgb(0xFFFFFF, edge * 0.15)]),
                           start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.maxY), options: [])
    ctx.restoreGState()
}

/// Draws the full-bleed icon artwork in a 1024 × 1024, y-down coordinate space.
func drawArtwork(_ ctx: CGContext, _ variant: Variant) {
    let background: [CGColor] = switch variant {
    case .light: [rgb(0x63B3FF), rgb(0x2F7CF6)]
    case .dark: [rgb(0x232A38), rgb(0x0B0E15)]
    case .tinted: [rgb(0x000000), rgb(0x000000)]
    }
    ctx.drawLinearGradient(gradient(background), start: .zero, end: CGPoint(x: 0, y: 1024), options: [])
    let fill: CGFloat = variant == .light ? 0.30 : 0.20
    let edge: CGFloat = variant == .light ? 0.85 : 0.6
    let shadow: CGFloat = variant == .light ? 0.18 : 0.45

    // Back layer: house, corners softened by unioning a round-joined stroke.
    let pentagon = CGMutablePath()
    pentagon.addLines(between: [CGPoint(x: 452, y: 270), CGPoint(x: 676, y: 452), CGPoint(x: 676, y: 700),
                                CGPoint(x: 228, y: 700), CGPoint(x: 228, y: 452)])
    pentagon.closeSubpath()
    let house = pentagon.union(pentagon.copy(strokingWithWidth: 64, lineCap: .round, lineJoin: .round, miterLimit: 10))

    // Front layer: the app's 270° dial, overlapping the house's lower right.
    let center = CGPoint(x: 600, y: 640), radius: CGFloat = 168, level: CGFloat = 0.72
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: radius, startAngle: .pi * 0.75,
               endAngle: .pi * 0.75 + .pi * 1.5 * level, clockwise: false)
    let ring = arc.copy(strokingWithWidth: 96, lineCap: .round, lineJoin: .round, miterLimit: 10)
    let angle = CGFloat.pi * 0.75 + .pi * 1.5 * level
    let knob = CGRect(x: center.x + radius * cos(angle) - 50, y: center.y + radius * sin(angle) - 50,
                      width: 100, height: 100)

    // Centre the whole group on the canvas by its real bounds.
    let bounds = house.boundingBoxOfPath.union(ring.boundingBoxOfPath).union(knob)
    ctx.translateBy(x: 512 - bounds.midX, y: 512 - bounds.midY)

    drawGlass(ctx, house, fill: fill, edge: edge, shadow: shadow)
    drawGlass(ctx, ring, fill: fill + 0.08, edge: edge, shadow: shadow)

    // Focal point: the solid knob at the end of the dial.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0x001A4D, shadow + 0.1))
    ctx.setFillColor(variant == .dark ? rgb(0xEAF3FF) : rgb(0xFFFFFF))
    ctx.fillEllipse(in: knob)
    ctx.restoreGState()
}

func render(size: Int, mac: Bool, variant: Variant, to url: URL) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        // iOS icons must be opaque; macOS icons carry their own shape and shadow.
                        bitmapInfo: mac ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    let scale = CGFloat(size) / 1024
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: scale, y: -scale)
    if mac {
        // macOS grid: 824 pt rounded tile centred in the 1024 canvas, with a soft drop shadow.
        let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.3))
        ctx.addPath(tile)
        ctx.setFillColor(rgb(0x2F7CF6))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(tile)
        ctx.clip()
        ctx.translateBy(x: 100, y: 100)
        ctx.scaleBy(x: 824 / 1024, y: 824 / 1024)
    }
    drawArtwork(ctx, variant)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "failed to write \(url.path)")
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
render(size: 1024, mac: false, variant: .light, to: dir.appendingPathComponent("AppIcon.png"))
// App icons can't be loaded as images at runtime, so the onboarding gets its own copy.
render(size: 512, mac: false, variant: .light,
       to: dir.deletingLastPathComponent().appendingPathComponent("Logo.imageset/Logo.png"))
render(size: 1024, mac: false, variant: .dark, to: dir.appendingPathComponent("AppIcon-Dark.png"))
render(size: 1024, mac: false, variant: .tinted, to: dir.appendingPathComponent("AppIcon-Tinted.png"))
for size in [16, 32, 64, 128, 256, 512, 1024] {
    render(size: size, mac: true, variant: .light, to: dir.appendingPathComponent("AppIcon-Mac-\(size).png"))
}
