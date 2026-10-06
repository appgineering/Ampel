import AppKit

/// Brings the app a session runs in to the front.
@MainActor
enum TerminalJump {
    // ponytail: activates the app, not the window or tab the session is in.
    // Exact focus needs per-terminal scripting and an Automation prompt; add
    // it per terminal if landing in the wrong tab turns out to matter.
    static func activate(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
