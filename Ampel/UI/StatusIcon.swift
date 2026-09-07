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

    // TODO(M5): pre-render pulse frames for .attention (alpha 1.0 ↔ 0.5,
    // 1s ease-in-out) and swap them via a timer that ONLY runs while red.
}
