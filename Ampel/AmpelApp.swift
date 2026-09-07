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

        observeAggregate()

        let watcher = EventWatcher(store: store)
        watcher.start()
        self.watcher = watcher

        sweep = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [store] _ in
            MainActor.assumeIsolated { store.sweepStale() }
        }
    }

    /// `withObservationTracking` fires once, so it re-arms itself each time.
    private func observeAggregate() {
        withObservationTracking {
            controller?.update(store.aggregate)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAggregate() }
        }
    }
}
