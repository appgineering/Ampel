import ServiceManagement
import SwiftUI

struct MenuContent: View {
    var store: AmpelStore
    var settings: Settings
    var provider: UsageProvider

    var openSettings: () -> Void
    var openAbout: () -> Void

    private let installer = HookInstaller()
    @State private var installState: InstallState = .ready

    /// Project names shared by more than one live session. Those rows get a
    /// short session id so parallel sessions in one repo stay tellable apart.
    private var ambiguousNames: Set<String> {
        var seen: Set<String> = [], dupes: Set<String> = []
        for session in store.sessions.values where !seen.insert(session.displayName).inserted {
            dupes.insert(session.displayName)
        }
        return dupes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.summary)
                .font(.headline)

            if store.sessions.isEmpty {
                Text("Start a Claude Code session to see it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Relative times are only correct at the moment they render, so
                // re-render once a second. The menu content exists only while
                // the popover is open, so this costs nothing when it is closed.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.sortedSessions) { session in
                            SessionRow(session: session,
                                       now: context.date,
                                       disambiguate: ambiguousNames.contains(session.displayName))
                        }
                    }
                }
            }

            Divider()

            if settings.usageStyle != .hidden {
                UsageSection(provider: provider, style: settings.usageStyle)
            }

            Divider()


            InstallStatusView(state: installState, install: installHooks)

            HStack {
                Button("Settings…", action: openSettings)
                Button("About", action: openAbout)
                Spacer()
                Button("Quit Ampel") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
        // Must live on a view that always renders. Hanging it off the button
        // itself never ran, because that button is absent precisely when the
        // check still needs to happen.
        .task {
            if case .ready = installState {
                installState = installer.isInstalled ? .ready : .needed
            }
        }
    }

    private func installHooks() {
        installState = .installing
        do {
            let backup = try installer.install()
            guard installer.isInstalled else {
                installState = .failed("Install ran but the hooks are still missing.")
                return
            }
            installState = .done(backedUp: backup != nil)
        } catch {
            installState = .failed(error.localizedDescription)
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let now: Date
    let disambiguate: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color(session.activity.color))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(session.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text(session.lastActivity.formatted(
                        .relative(presentation: .named, unitsStyle: .wide)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(disambiguate ? "\(session.activity.label) · \(session.id.prefix(6))" : session.activity.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let message = session.lastMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .help(session.cwd)
    }
}

private struct UsageSection: View {
    let provider: UsageProvider
    let style: Settings.UsageStyle

    private var usage: UsageSnapshot? { provider.snapshot }
    private var failed: Bool { provider.failed }
    /// Only before the very first successful run. Once anything is cached, a
    /// refresh happens behind the numbers already on screen.
    private var loading: Bool { usage == nil && !failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if failed {
                Text("Usage unavailable. Install it with brew install ccusage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if style == .text {
                ForEach(planLines ?? estimateLines, id: \.self) { line in
                    Text(line).font(.caption)
                        .redacted(reason: loading ? .placeholder : [])
                }
            } else if let plan = usage?.plan {
                // Real limits beat estimates, so they take the space.
                if let five = plan.fiveHour {
                    UsageBar(title: "Session \(UsageProvider.percent(five.usedPercentage))",
                             progress: five.usedPercentage / 100,
                             caption: five.resetsAt.map { "resets \($0.formatted(.dateTime.hour().minute()))" },
                             tint: .accentColor,
                             loading: false,
                             refreshing: provider.isRefreshing)
                }
                if let seven = plan.sevenDay {
                    UsageBar(title: "This week \(UsageProvider.percent(seven.usedPercentage))",
                             progress: seven.usedPercentage / 100,
                             caption: seven.resetsAt.map { "resets \($0.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" },
                             tint: .accentColor,
                             loading: false)
                }
                if let spend = plan.spendLimit {
                    UsageBar(title: "Spend limit \(UsageProvider.percent(spend.usedPercentage))",
                             progress: min(spend.usedPercentage / 100, 1),
                             caption: nil, tint: .secondary, loading: false)
                }
            } else {
                UsageBar(title: usage?.blockLabel ?? "Current block: $00.00 · 00M tokens",
                         progress: usage?.blockProgress,
                         caption: resetCaption,
                         tint: .accentColor,
                         loading: loading,
                         refreshing: provider.isRefreshing)
                UsageBar(title: usage?.todayLine ?? "Today: $00.00",
                         progress: usage?.todayProgress,
                         caption: peakCaption,
                         tint: .secondary,
                         loading: loading)
            }
        }
        .foregroundStyle(.secondary)
        // Reserved so the popover does not resize when the numbers land.
        .frame(height: reservedHeight, alignment: .top)
        .task { provider.refresh() }
    }

    /// Reserved so the popover does not resize when the numbers land. Plan
    /// usage can show a third bar, so it gets measured rather than guessed.
    private var reservedHeight: CGFloat {
        if style == .text { return CGFloat((planLines ?? estimateLines).count) * 17 }
        let bars = usage?.plan.map { plan in
            [plan.fiveHour, plan.sevenDay, plan.spendLimit].compactMap { $0 }.count
        } ?? 2
        return CGFloat(max(bars, 2)) * 31
    }

    /// Real plan figures as plain lines, for the numbers-only style.
    private var planLines: [String]? {
        guard let plan = usage?.plan else { return nil }
        var lines: [String] = []
        if let five = plan.fiveHour {
            lines.append("Session \(UsageProvider.percent(five.usedPercentage))"
                + (five.resetsAt.map { ", resets \($0.formatted(.dateTime.hour().minute()))" } ?? ""))
        }
        if let seven = plan.sevenDay {
            lines.append("This week \(UsageProvider.percent(seven.usedPercentage))"
                + (seven.resetsAt.map { ", resets \($0.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" } ?? ""))
        }
        return lines.isEmpty ? nil : lines
    }

    private var estimateLines: [String] {
        [usage?.currentBlockLine ?? "Current block: $00.00 · 00M tokens",
         usage?.todayLine ?? "Today: $00.00"]
    }

    private var resetCaption: String? {
        guard let resets = usage?.blockResets else { return nil }
        return "resets \(resets.formatted(.dateTime.hour().minute()))"
    }

    private var peakCaption: String? {
        guard let peak = usage?.todayPeak else { return nil }
        return "7-day peak \(UsageProvider.money(peak))"
    }
}

/// A labelled bar. With no progress value it renders an empty track, which is
/// what keeps the section the same height while ccusage is still running.
private struct UsageBar: View {
    let title: String
    let progress: Double?
    let caption: String?
    let tint: Color
    let loading: Bool
    var refreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption)
                    .redacted(reason: loading ? .placeholder : [])
                Spacer(minLength: 8)
                if let caption {
                    Text(caption).font(.caption2).foregroundStyle(.tertiary)
                } else if loading {
                    Text("loading").font(.caption2).foregroundStyle(.tertiary)
                        .redacted(reason: .placeholder)
                }
                if refreshing {
                    ProgressView().controlSize(.mini).scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                }
            }
            if loading {
                // Indeterminate: ccusage takes a beat, and an empty track that
                // suddenly fills reads as "zero usage" rather than "not known yet".
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .frame(height: 4)
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(tint)
                            .frame(width: geometry.size.width * (progress ?? 0))
                    }
                }
                .frame(height: 4)
            }
        }
        .foregroundStyle(.secondary)
    }
}

enum InstallState {
    case ready                      // hooks are in place, say nothing
    case needed
    case installing
    case done(backedUp: Bool)
    case failed(String)
}

private struct InstallStatusView: View {
    let state: InstallState
    let install: () -> Void

    var body: some View {
        switch state {
        case .ready:
            EmptyView()
        case .needed:
            VStack(alignment: .leading, spacing: 2) {
                Button("Install hooks…", action: install)
                Text("Ampel needs Claude Code hooks to see your sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing hooks…").font(.caption)
            }
        case .done(let backedUp):
            Label {
                Text(backedUp
                     ? "Hooks installed. Your previous settings.json was backed up."
                     : "Hooks installed.")
                .font(.caption)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .failed(let message):
            Label {
                Text(message).font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}
