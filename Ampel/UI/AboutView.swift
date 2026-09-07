import SwiftUI

struct AboutView: View {
    var showSetupGuide: (() -> Void)?

    @State private var copied = false

    static let repository = URL(string: "https://github.com/appgineering/Ampel")!

    /// Tagged per surface, so the app and the README can be told apart.
    static let website = URL(
        string: "https://appgineering.com/?utm_source=ampel&utm_medium=app&utm_campaign=about")!

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

            LegendView()

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("How it works").font(.caption).fontWeight(.medium)
                Text("Claude Code hooks write one small file per event into ~/.ampel/events. Ampel watches that folder and keeps a state machine per session. Cost estimates come from ccusage; the plan percentages come from Claude Code itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnostics").font(.caption).fontWeight(.medium)
                Text("If something misbehaves, copy this and include it in the report. It lists the version, whether setup completed, what is in ~/.ampel, and the tail of the log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(copied ? "Copied" : "Copy diagnostics") {
                        Diagnostics.copyToClipboard()
                        copied = true
                    }
                    Button("Show log file") { Diagnostics.revealLog() }
                }
                .controlSize(.small)
            }

            if let showSetupGuide {
                Button("Show setup guide again", action: showSetupGuide)
                    .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("© 2026")
                    Link("Appgineering", destination: Self.website)
                    Text("· MIT licensed ·")
                    Link("Source", destination: Self.repository)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                // Neither the licence nor the copyright line grants trademark
                // rights, and this app sits right next to Anthropic's name.
                Text("Not affiliated with, endorsed by, or sponsored by Anthropic. Claude and Claude Code are trademarks of Anthropic, PBC.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Usage estimates come from ccusage, a separately licensed tool (MIT) that Ampel runs but does not bundle.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Ampel collects nothing and makes no network requests of its own.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct LegendView: View {
    var body: some View {
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
    }
}

enum Legend {
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
