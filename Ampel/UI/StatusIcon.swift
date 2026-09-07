import AppKit

/// Renders the menu bar traffic light. Colored, therefore explicitly
/// NOT a template image (template images get tinted monochrome by the system).
enum StatusIcon {
    static func image(for state: AggregateState, alpha: CGFloat = 1.0) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = rect.insetBy(dx: 3.5, dy: 3.5)
            state.color.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: circle).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// One second of ease-in-out from full opacity down to half and back,
    /// pre-rendered so the pulse costs a dictionary lookup per frame rather
    /// than a redraw. See SPEC §5.
    static let pulseFrames: [NSImage] = (0..<pulseFrameCount).map { frame in
        let phase = Double(frame) / Double(pulseFrameCount)
        // A raised cosine is the ease-in-out; no easing curve object needed.
        let eased = (1 - cos(2 * .pi * phase)) / 2
        return image(for: .attention, alpha: 1.0 - 0.5 * eased)
    }

    static let pulseFrameCount = 8
    static let pulseInterval = 1.0 / Double(pulseFrameCount)
}
