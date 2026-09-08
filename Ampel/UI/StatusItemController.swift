import AppKit
import QuartzCore
import SwiftUI

/// Owns the menu bar item directly rather than through `MenuBarExtra`.
///
/// SPEC §5 called for SwiftUI's MenuBarExtra, but two requirements it cannot
/// meet forced the change: it exposes no right-click, and swapping its label
/// image runs a full SwiftUI scene update, which made the attention pulse cost
/// 23% CPU at 20fps. An NSStatusItem image swap is a plain layer redraw.
/// The menu content itself is unchanged SwiftUI, hosted in an NSPopover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let store: AmpelStore
    private let settings: Settings
    private let settingsWindow: SettingsWindow
    /// Owned here, not by the popover content, which is rebuilt on every open.
    /// A per-open provider threw away its cache and reloaded from scratch.
    let usage = UsageProvider()

    private var rendered: RenderKey?
    private var monitor: Any?

    init(store: AmpelStore, settings: Settings) {
        self.store = store
        self.settings = settings
        self.settingsWindow = SettingsWindow(settings: settings)
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        if let button = statusItem.button {
            button.image = StatusIcon.image(settings.iconStyle, IconContext(), scale: settings.iconScale)
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - Icon

    /// Everything the icon depends on, so a redraw only happens when one of
    /// them actually changed.
    private struct RenderKey: Equatable {
        var style: IconStyle
        var scale: Double
        var aggregate: AggregateState
        var colors: [NSColor]
        var progress: Double?
        var attention: Int
        var pulsing: Bool
    }

    func showOnboardingIfNeeded() {
        guard !settings.hasOnboarded else { return }
        settingsWindow.showOnboarding()
    }

    func update() {
        let sessions = store.sortedSessions
        let key = RenderKey(
            style: settings.iconStyle,
            scale: settings.iconScale,
            aggregate: store.aggregate,
            colors: sessions.map(\.activity.color),
            progress: progress,
            attention: sessions.filter { $0.activity == .attention }.count,
            pulsing: store.aggregate == .attention && settings.pulseOnAttention)
        guard key != rendered else { return }
        let wasPulsing = rendered?.pulsing ?? false
        rendered = key

        guard let button = statusItem.button else { return }
        button.image = StatusIcon.image(key.style, IconContext(
            aggregate: key.aggregate,
            sessionColors: key.colors,
            progress: key.progress,
            attentionCount: key.attention), scale: key.scale)

        guard key.pulsing != wasPulsing else { return }
        button.layer?.removeAnimation(forKey: Self.pulseKey)
        guard key.pulsing else { return }

        // A repeating layer animation is driven by the compositor, so the pulse
        // costs no CPU at all. Swapping pre-rendered images on a timer cost 23%
        // through MenuBarExtra and 10% here, for the same 1s fade.
        button.wantsLayer = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.5
        fade.duration = 0.5
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        button.layer?.add(fade, forKey: Self.pulseKey)
    }

    /// The closed popover kept its hosting controller, whose 1s TimelineView
    /// went on re-rendering session rows for nobody.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    /// The ring shows the real five hour limit when we have it, and falls back
    /// to elapsed time through the ccusage block when we do not.
    private var progress: Double? {
        if let five = usage.snapshot?.plan?.fiveHour { return five.usedPercentage / 100 }
        return usage.snapshot?.blockProgress
    }

    private static let pulseKey = "ampel.pulse"

    // MARK: - Clicks

    /// Left and right click do the same thing. A separate right-click menu was
    /// tried and dropped: two different surfaces for one icon confuses more
    /// than the shortcut is worth.
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Rebuilt on every open so the usage section's .task actually runs
            // again. A hosting controller kept alive across opens loads once,
            // which meant a setting changed after launch never took effect.
            popover.contentViewController = NSHostingController(
                rootView: MenuContent(store: store,
                                      settings: settings,
                                      provider: usage,
                                      openSettings: { [settingsWindow] in settingsWindow.show() },
                                      openAbout: { [settingsWindow] in settingsWindow.showAbout() }))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

