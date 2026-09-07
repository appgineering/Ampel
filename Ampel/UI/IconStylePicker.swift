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

    private static let script: [IconContext] = [
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
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let step = Int(elapsed / 1.2) % Self.script.count
            let context = Self.script[step]
            // Same 1s ease-in-out down to half opacity as the real pulse.
            let pulse = context.aggregate == .attention
                ? 1 - 0.5 * (1 - cos(2 * .pi * elapsed.truncatingRemainder(dividingBy: 1))) / 2
                : 1

            Image(nsImage: StatusIcon.image(style, context))
                .resizable()
                .interpolation(.high)
                .opacity(pulse)
        }
    }
}
