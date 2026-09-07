import ServiceManagement
import SwiftUI

struct MenuContent: View {
    var store: AmpelStore
    var provider = UsageProvider()

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

            UsageSection(provider: provider)

            Divider()

            LaunchAtLoginToggle()

            InstallHooksButton()

            Button("Quit Ampel") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
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

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at Login", isOn: $enabled)
            .toggleStyle(.checkbox)
            .onChange(of: enabled) { _, on in
                do {
                    on ? try SMAppService.mainApp.register()
                       : try SMAppService.mainApp.unregister()
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

private struct UsageSection: View {
    let provider: UsageProvider
    @State private var usage: UsageSnapshot?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let usage {
                Text(usage.currentBlockLine)
                Text(usage.todayLine)
            } else if loaded {
                Text("Usage unavailable. Install it with brew install ccusage")
            } else {
                Text("Loading usage…")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .task {
            // Refreshes every time the menu opens; the provider caches for 60s.
            usage = await provider.fetch()
            loaded = true
        }
    }
}

/// Shown only until the hooks are in place. See SPEC §8.
private struct InstallHooksButton: View {
    private let installer = HookInstaller()
    @State private var installed = true
    @State private var failure: String?

    var body: some View {
        Group {
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            } else if !installed {
                Button("Install hooks…") {
                    do {
                        try installer.install()
                        installed = true
                    } catch {
                        failure = error.localizedDescription
                    }
                }
            }
        }
        .task { installed = installer.isInstalled }
    }
}
