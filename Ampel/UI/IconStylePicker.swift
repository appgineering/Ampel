import SwiftUI

/// Each style previewed live, cycling through the states it would show in
/// practice, because these are impossible to judge from a static swatch.
struct IconStylePicker: View {
    @Binding var selection: IconStyle

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(IconStyle.allCases) { style in
                    StyleCard(style: style, selected: style == selection)
                        .onTapGesture { selection = style }
                }
            }
            Text(selection.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StyleCard: View {
    let style: IconStyle
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            AnimatedIcon(style: style)
                .frame(width: 36, height: 36)
            Text(style.label)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(Rectangle())
    }
}

/// Walks the same sequence a real session goes through, holding each state
/// briefly, and pulses on red exactly as the menu bar does.
private struct AnimatedIcon: View {
    let style: IconStyle

    static let script: [IconContext] = [
        IconContext(aggregate: .off, sessionColors: [], progress: 0.1, attentionCount: 0),
        IconContext(aggregate: .idle, sessionColors: [.systemGreen], progress: 0.3, attentionCount: 0),
        IconContext(aggregate: .working,
                    sessionColors: [.systemYellow, .systemGreen], progress: 0.55, attentionCount: 0),
        IconContext(aggregate: .attention,
                    sessionColors: [.systemRed, .systemYellow, .systemGreen],
                    progress: 0.8, attentionCount: 2),
        IconContext(aggregate: .idle,
                    sessionColors: [.systemGreen, .systemGreen], progress: 0.9, attentionCount: 0),
    ]

    var body: some View {
        // Steps once per state. The pulse is a repeating layer animation on an
        // NSImageView, as in the menu bar: SwiftUI's own opacity animation
        // re-rasterized every image each frame and cost 20-50% CPU.
        TimelineView(.periodic(from: .now, by: 1.2)) { timeline in
            let step = Int(timeline.date.timeIntervalSinceReferenceDate / 1.2) % Self.script.count
            PulsingImage(image: StatusIcon.image(style, Self.script[step]),
                         pulsing: Self.script[step].aggregate == .attention)
        }
    }
}

private struct PulsingImage: NSViewRepresentable {
    let image: NSImage
    let pulsing: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.wantsLayer = true
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = image
        let key = "ampel.pulse"
        if pulsing, view.layer?.animation(forKey: key) == nil {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.5
            fade.duration = 0.5
            fade.autoreverses = true
            fade.repeatCount = .infinity
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer?.add(fade, forKey: key)
        } else if !pulsing {
            view.layer?.removeAnimation(forKey: key)
        }
    }
}
