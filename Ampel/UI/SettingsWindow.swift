import AppKit
import SwiftUI

/// The settings window, in the toolbar style macOS uses for app preferences:
/// selectable toolbar items across the top, one pane each, window title and
/// size following the selection.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate, NSToolbarDelegate {
    struct Pane {
        let id: NSToolbarItem.Identifier
        let title: String
        let symbol: String
        let content: () -> NSViewController
    }

    private var window: NSWindow?
    private var onboarding: NSWindow?
    private let settings: Settings
    private var panes: [Pane]
    private var selected: NSToolbarItem.Identifier
    /// Built once each. Rebuilding on every click reset the pane's state and
    /// made the swap visibly flash.
    private var controllers: [NSToolbarItem.Identifier: NSViewController] = [:]

    init(settings: Settings) {
        self.settings = settings
        panes = [
            Pane(id: .init("general"), title: "General", symbol: "gearshape") {
                NSHostingController(rootView: GeneralSettingsView(settings: settings))
            },
            Pane(id: .init("usage"), title: "Usage", symbol: "chart.bar") {
                NSHostingController(rootView: UsageSettingsView(settings: settings))
            },
            Pane(id: .init("about"), title: "About", symbol: "info.circle") {
                NSHostingController(rootView: AboutView())
            },
        ]
        selected = panes[0].id
        super.init()

        // Replaced after init, where referring to self is allowed.
        panes[2] = Pane(id: .init("about"), title: "About", symbol: "info.circle") { [weak self] in
            NSHostingController(rootView: AboutView(showSetupGuide: { self?.showOnboarding() }))
        }
    }

    func show(pane id: NSToolbarItem.Identifier? = nil) {
        let window = window ?? makeWindow()
        self.window = window
        select(id ?? selected, in: window)
        // An LSUIElement app is not activated by opening a window on its own.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showAbout() { show(pane: .init("about")) }

    /// A window rather than a popover pane: the popover closes the moment you
    /// click away, which is what someone does the instant they read a step.
    func showOnboarding() {
        let window = onboarding ?? {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Welcome to Ampel"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.contentViewController = NSHostingController(
                rootView: OnboardingView(settings: settings) { [weak self] in
                    self?.settings.hasOnboarded = true
                    self?.onboarding?.close()
                })
            onboarding = window
            return window
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self

        let toolbar = NSToolbar(identifier: "settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        window.center()
        return window
    }

    private func select(_ id: NSToolbarItem.Identifier, in window: NSWindow) {
        guard let pane = panes.first(where: { $0.id == id }) ?? panes.first else { return }
        selected = pane.id
        window.toolbar?.selectedItemIdentifier = pane.id
        window.title = pane.title

        let controller = controllers[pane.id] ?? {
            let made = pane.content()
            controllers[pane.id] = made
            return made
        }()

        // Panes differ in height, so the window resizes to the content. No
        // animation: animating frame and content together scales the window
        // diagonally, and the resize is the only movement wanted here.
        let size = controller.view.fittingSize
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var target = window.frame
        // Grow and shrink downward, so the title bar stays put.
        target.origin.y += target.height - frame.height
        target.size = frame.size

        window.contentViewController = controller
        window.setFrame(target, display: true, animate: false)
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let window else { return }
        select(sender.itemIdentifier, in: window)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = panes.first(where: { $0.id == identifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    // MARK: - NSWindowDelegate

    /// A closed window still lays out its SwiftUI content: the icon preview's
    /// 20fps TimelineView kept the app at 20-40% CPU with nothing on screen.
    /// Drop the content so the tree is torn down, and rebuild it on next show.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        closing.contentViewController = nil
        if closing === window { controllers.removeAll() }
        if closing === onboarding { onboarding = nil }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map(\.id)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map(\.id)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map(\.id)
    }
}
