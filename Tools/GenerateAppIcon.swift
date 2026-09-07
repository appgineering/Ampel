// Renders Ampel's app icon at every size macOS asks for.
// Run: ./Tools/make-icon.sh  (writes Ampel/Assets.xcassets/AppIcon.appiconset)
//
// Drawn rather than generated: the icon must stay crisp at 16pt, where an
// illustrative image turns to mush, and it should be regenerable from source.
import AppKit

@main enum GenerateAppIcon {
    /// A traffic light in a rounded square: red lit, amber and green dim, which
    /// matches what the menu bar shows when a session is blocked on you.
    static func draw(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let s = size
            // macOS icon grid: the art sits inside about 80% of the canvas.
            let inset = s * 0.10
            let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
            let corner = body.width * 0.2237   // Apple's squircle-ish radius ratio

            let background = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)
            NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.11, alpha: 1)])?
                .draw(in: background, angle: -90)

            // A hairline lip so the icon reads on both light and dark walls.
            NSColor(white: 1, alpha: 0.10).setStroke()
            background.lineWidth = max(s * 0.006, 0.5)
            background.stroke()

            // Lamps must not touch: diameter stays well under the spacing.
            let lampDiameter = body.width * 0.26
            let spacing = body.height * 0.295
            let centerX = body.midX
            let lamps: [(NSColor, Bool)] = [
                (.systemRed, true), (.systemYellow, false), (.systemGreen, false),
            ]

            for (index, lamp) in lamps.enumerated() {
                let centerY = body.midY + spacing - CGFloat(index) * spacing
                let rect = NSRect(x: centerX - lampDiameter / 2,
                                  y: centerY - lampDiameter / 2,
                                  width: lampDiameter, height: lampDiameter)
                let (color, lit) = lamp

                if lit {
                    // Glow, so the lit lamp reads as lit and not merely coloured.
                    // Clipped to the body, or it bleeds past the rounded corners,
                    // and kept tight enough not to tint the lamps below.
                    NSGraphicsContext.saveGraphicsState()
                    background.setClip()
                    let glow = rect.insetBy(dx: -lampDiameter * 0.45, dy: -lampDiameter * 0.45)
                    NSGradient(colors: [color.withAlphaComponent(0.38),
                                        color.withAlphaComponent(0)])?
                        .draw(in: NSBezierPath(ovalIn: glow), relativeCenterPosition: .zero)
                    NSGraphicsContext.restoreGraphicsState()
                }

                color.withAlphaComponent(lit ? 1.0 : 0.20).setFill()
                NSBezierPath(ovalIn: rect).fill()

                if lit {
                    // Highlight in the upper left, where the light would fall.
                    let shine = NSRect(x: rect.minX + lampDiameter * 0.24,
                                       y: rect.minY + lampDiameter * 0.55,
                                       width: lampDiameter * 0.30,
                                       height: lampDiameter * 0.20)
                    NSColor(white: 1, alpha: 0.38).setFill()
                    NSBezierPath(ovalIn: shine).fill()
                }
            }
            return true
        }
    }

    static func png(_ image: NSImage, pixels: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // Every size macOS asks a Mac app for, at both scales.
        let points = [16, 32, 128, 256, 512]
        var entries: [[String: String]] = []

        for point in points {
            for scale in [1, 2] {
                let pixels = point * scale
                let name = "icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png"
                try png(draw(size: CGFloat(pixels)), pixels: pixels)
                    .write(to: out.appendingPathComponent(name))
                entries.append(["size": "\(point)x\(point)", "idiom": "mac",
                                "filename": name, "scale": "\(scale)x"])
            }
        }

        let contents: [String: Any] = [
            "images": entries,
            "info": ["version": 1, "author": "Tools/GenerateAppIcon.swift"],
        ]
        try JSONSerialization.data(withJSONObject: contents,
                                   options: [.prettyPrinted, .sortedKeys])
            .write(to: out.appendingPathComponent("Contents.json"))
        print("wrote \(entries.count) images to \(out.path)")
    }
}
