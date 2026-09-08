import AppKit

/// Gatekeeper runs a downloaded app from a read-only mount under
/// /private/var/folders. When that mount goes away (the DMG is ejected, the
/// zip's temp copy is cleaned up) every page the app has yet to fault in is
/// gone with it, and the next one it touches is a SIGBUS. Say so before that
/// happens instead of shipping a crash report about it.
@MainActor
enum TranslocationPrompt {
    // ponytail: path prefix, not SecTranslocateIsTranslocatedURL. Same answer,
    // no private API. Revisit if Gatekeeper ever moves the mount point.
    static var isTranslocated: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/private/var/folders/")
    }

    static func showIfNeeded() {
        guard isTranslocated else { return }
        Log("ui").error("running translocated from \(Bundle.main.bundleURL.path)")

        let alert = NSAlert()
        alert.messageText = "Move Ampel to Applications"
        alert.informativeText = "Ampel is running from a temporary read-only copy macOS made because it was launched straight out of the download. It will crash as soon as that copy is cleaned up. Quit, drag Ampel.app to your Applications folder, and launch it from there."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Run anyway")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }
}
