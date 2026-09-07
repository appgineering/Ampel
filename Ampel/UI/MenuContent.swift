import SwiftUI

struct MenuContent: View {
    var store: AmpelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headerText)
                .font(.headline)

            // TODO(M3): session rows per SPEC §6 — colored dot, displayName,
            // state label, relative time, lastMessage as secondary line.
            // TODO(M4): usage section fed by UsageProvider.

            Divider()

            // TODO(M3): "Launch at Login" toggle via SMAppService.mainApp.
            // TODO(M5): "Install hooks…" button when HookInstaller.isInstalled == false.

            Button("Quit Ampel") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private var headerText: String {
        switch store.aggregate {
        case .off: "No active sessions"
        case .idle: "All quiet"
        case .working: "Claude is working"
        case .attention: "Claude needs your attention"
        }
    }
}
