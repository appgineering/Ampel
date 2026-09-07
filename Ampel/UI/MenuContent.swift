import ServiceManagement
import SwiftUI

struct MenuContent: View {
    var store: AmpelStore

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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.sortedSessions) { session in
                        SessionRow(session: session, disambiguate: ambiguousNames.contains(session.displayName))
                    }
                }
            }

            // TODO(M4): usage section fed by UsageProvider.

            Divider()

            LaunchAtLoginToggle()

            // TODO(M5): "Install hooks…" button when HookInstaller.isInstalled == false.

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
                    Text(session.lastActivity, format: .relative(presentation: .named))
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
