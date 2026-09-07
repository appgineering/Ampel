import SwiftUI

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? StatusIcon.image(for: .idle))
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ampel").font(.title2).fontWeight(.semibold)
                    Text(version).font(.caption).foregroundStyle(.secondary)
                    Text("A traffic light for your Claude Code sessions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Legend.all, id: \.label) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(Color(entry.color))
                            .frame(width: 8, height: 8)
                        Text(entry.label).fontWeight(.medium)
                        Text(entry.meaning).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("How it works").font(.caption).fontWeight(.medium)
                Text("Claude Code hooks write one small file per event into ~/.ampel/events. Ampel watches that folder and keeps a state machine per session. Cost estimates come from ccusage; the plan percentages come from Claude Code itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("© 2026 Appgineering GbR")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private enum Legend {
    struct Entry {
        let color: NSColor
        let label: String
        let meaning: String
    }

    static let all = [
        Entry(color: AggregateState.attention.color, label: "Red",
              meaning: "blocked on you, a permission prompt or a tool asking for input"),
        Entry(color: AggregateState.working.color, label: "Yellow",
              meaning: "working, tools running or a response streaming"),
        Entry(color: AggregateState.idle.color, label: "Green",
              meaning: "idle, the last turn finished"),
        Entry(color: AggregateState.off.color, label: "Gray",
              meaning: "no active sessions"),
    ]
}
