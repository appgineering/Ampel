import AppKit
import SwiftUI

/// Real windows rather than panes inside the popover, which cannot be moved,
/// resized or left open while you work.
@MainActor
final class AuxiliaryWindows {
    private var windows: [String: NSWindow] = [:]
    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    func showSettings() {
        show(id: "settings", title: "Ampel Settings") {
            NSHostingController(rootView: SettingsView(settings: self.settings))
        }
    }

    func showAbout() {
        show(id: "about", title: "About Ampel") {
            NSHostingController(rootView: AboutView())
        }
    }

    private func show(id: String, title: String, content: () -> NSViewController) {
        let window = windows[id] ?? {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            window.title = title
            window.contentViewController = content()
            window.isReleasedWhenClosed = false
            window.center()
            windows[id] = window
            return window
        }()
        // An LSUIElement app is not activated by opening a window on its own.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
