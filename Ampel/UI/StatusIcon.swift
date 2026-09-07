import AppKit

/// What the icon needs to know. More than the aggregate, because some styles
/// show per-session detail or usage.
struct IconContext {
    var aggregate: AggregateState = .off
    /// One colour per session, worst first, for the styles that show each one.
    var sessionColors: [NSColor] = []
    /// How far through the rate limit window, 0...1, for the ring.
    var progress: Double?
    /// Sessions currently blocked on the user.
    var attentionCount: Int = 0
}

enum IconStyle: String, CaseIterable, Identifiable, Sendable {
    case dot, horizontal, lamp, ring, bars, badge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dot: "Dot"
        case .horizontal: "Traffic light"
        case .lamp: "Single lamp"
        case .ring: "Ring"
        case .bars: "Session bars"
        case .badge: "Dot with count"
        }
    }

    var detail: String {
        switch self {
        case .dot: "One filled circle. The most visible option at a glance."
        case .horizontal: "Three lamps, the active one lit. State is shown by position as well as colour, which survives red and green colour blindness."
        case .lamp: "One lit lamp in a housing. Keeps the traffic light look but spends the space on the lit lamp."
        case .ring: "Colour is the state, the arc is how far through the current rate limit window you are."
        case .bars: "One bar per session, coloured individually, so several sessions read as several bars."
        case .badge: "A dot with the number of sessions waiting on you."
        }
    }
}

/// Renders the menu bar icon. Colored, therefore explicitly NOT a template
/// image (template images get tinted monochrome by the system).
enum StatusIcon {
    static let size = NSSize(width: 18, height: 18)

    static func image(_ style: IconStyle, _ context: IconContext) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            switch style {
            case .dot: drawDot(rect, context)
            case .horizontal: drawHorizontal(rect, context)
            case .lamp: drawLamp(rect, context)
            case .ring: drawRing(rect, context)
            case .bars: drawBars(rect, context)
            case .badge: drawBadge(rect, context)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func image(for state: AggregateState) -> NSImage {
        image(.dot, IconContext(aggregate: state))
    }

    // MARK: - Styles

    private static func drawDot(_ rect: NSRect, _ context: IconContext) {
        context.aggregate.color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 3.5, dy: 3.5)).fill()
    }

    private static func drawHorizontal(_ rect: NSRect, _ context: IconContext) {
        let body = NSRect(x: rect.minX + 0.5, y: rect.midY - 4, width: rect.width - 1, height: 8)
        housingColor.setFill()
        NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4).fill()

        let lamps: [(AggregateState, NSColor)] = [
            (.attention, .systemRed), (.working, .systemYellow), (.idle, .systemGreen),
        ]
        let diameter: CGFloat = 4.6
        for (index, lamp) in lamps.enumerated() {
            let x = body.minX + 1.2 + CGFloat(index) * (diameter + 0.85)
            let lit = lamp.0 == context.aggregate
            lamp.1.withAlphaComponent(lit ? 1 : 0.22).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: body.midY - diameter / 2,
                                        width: diameter, height: diameter)).fill()
        }
    }

    private static func drawLamp(_ rect: NSRect, _ context: IconContext) {
        let body = rect.insetBy(dx: 2, dy: 1)
        housingColor.setFill()
        NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4).fill()
        context.aggregate.color.setFill()
        NSBezierPath(ovalIn: NSRect(x: body.midX - 4, y: body.midY - 4,
                                    width: 8, height: 8)).fill()
    }

    private static func drawRing(_ rect: NSRect, _ context: IconContext) {
        let box = rect.insetBy(dx: 2.5, dy: 2.5)
        let center = NSPoint(x: box.midX, y: box.midY)
        let radius = box.width / 2 - 1.2
        let color = context.aggregate.color

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2.4
        color.withAlphaComponent(0.25).setStroke()
        track.stroke()

        // With no usage figure yet, a full ring beats a misleading empty one.
        let progress = context.progress ?? 1
        guard progress > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                      endAngle: 90 - 360 * progress, clockwise: true)
        arc.lineWidth = 2.4
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    private static func drawBars(_ rect: NSRect, _ context: IconContext) {
        let colors = Array(context.sessionColors.prefix(4))
        guard !colors.isEmpty else {
            AggregateState.off.color.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.midX - 1.4, y: rect.midY - 4,
                                             width: 2.8, height: 8),
                         xRadius: 1.4, yRadius: 1.4).fill()
            return
        }
        let width: CGFloat = 2.8, gap: CGFloat = 1.6
        let total = CGFloat(colors.count) * width + CGFloat(colors.count - 1) * gap
        for (index, color) in colors.enumerated() {
            let x = rect.midX - total / 2 + CGFloat(index) * (width + gap)
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: rect.midY - 5, width: width, height: 10),
                         xRadius: 1.4, yRadius: 1.4).fill()
        }
    }

    private static func drawBadge(_ rect: NSRect, _ context: IconContext) {
        let count = context.attentionCount
        guard count > 0 else { return drawDot(rect, context) }

        context.aggregate.color.setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 1.5, y: rect.minY + 1.5,
                                    width: 11, height: 11)).fill()

        // The badge has to be big enough to read at 18pt, which means letting
        // it overhang the dot rather than sitting politely beside it.
        let badge = NSRect(x: rect.maxX - 11, y: rect.maxY - 11, width: 10.5, height: 10.5)
        NSColor.black.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: badge.insetBy(dx: -1.1, dy: -1.1)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: badge).fill()

        let text = (count > 9 ? "9+" : "\(count)") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: count > 9 ? 6.5 : 8.5, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: badge.midX - textSize.width / 2,
                              y: badge.midY - textSize.height / 2),
                  withAttributes: attributes)
    }

    private static let housingColor = NSColor(white: 0.35, alpha: 0.85)
}
