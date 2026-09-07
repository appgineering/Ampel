import AppKit

/// If Ampel died last time, say so and offer the evidence, rather than hoping
/// someone thinks to go looking in Library/Logs.
@MainActor
enum CrashPrompt {
    static func showIfNeeded() {
        guard let name = Diagnostics.unreportedCrash() else { return }
        Log("ui").error("previous run left a crash report: \(name)")

        let alert = NSAlert()
        alert.messageText = "Ampel quit unexpectedly"
        alert.informativeText = "A crash report from the last run is on this Mac. Copying the diagnostics puts it, along with the version and recent log, on your clipboard so it can be pasted into a bug report."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Copy diagnostics")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Ignore")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Diagnostics.copyToClipboard()
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting(
                [Diagnostics.crashDirectory.appendingPathComponent(name)])
        default:
            break
        }
    }
}
