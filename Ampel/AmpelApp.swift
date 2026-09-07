import AppKit
import SwiftUI

@main
struct AmpelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar item is an NSStatusItem owned by AppDelegate; see
        // StatusItemController for why. This scene exists only to satisfy App.
        SwiftUI.Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AmpelStore()
    private let settings = Settings()
    private let notifier = Notifier()
    private var controller: StatusItemController?
    private var watcher: EventWatcher?
    private var sweep: Timer?
    private var observation: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(store: store, settings: settings)
        self.controller = controller

        notifier.requestAuthorization()
        store.onAttention = { [notifier, settings] session in
            guard settings.notifyOnAttention else { return }
            notifier.notify(session)
        }

        // Deleting ~/.ampel leaves settings.json pointing at scripts that are
        // gone. Put them back before anything else runs.
        HookInstaller().repairIfNeeded()
        StatuslineInstaller().repairIfNeeded()

        observeAggregate()

        let watcher = EventWatcher(store: store)
        watcher.start()
        self.watcher = watcher

        controller.showOnboardingIfNeeded()

        sweep = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [store] _ in
            MainActor.assumeIsolated { store.sweepStale() }
        }
    }

    /// `withObservationTracking` fires once, so it re-arms itself each time.
    private func observeAggregate() {
        withObservationTracking {
            // Touch everything the icon reads, so the tracker re-arms on any of it.
            _ = store.aggregate
            _ = store.sessions.count
            _ = settings.iconStyle
            _ = settings.pulseOnAttention
            // The ring style draws usage, so a refreshed snapshot must redraw.
            _ = controller?.usage.snapshot
            controller?.update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAggregate() }
        }
    }
}
