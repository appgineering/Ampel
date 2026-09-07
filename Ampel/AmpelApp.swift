import SwiftUI

@main
struct AmpelApp: App {
    @State private var store = AmpelStore()
    @State private var watcher: EventWatcher?
    @State private var notifier = Notifier()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(nsImage: StatusIcon.image(for: store.aggregate))
                .onAppear {
                    guard watcher == nil else { return }
                    notifier.requestAuthorization()
                    store.onAttention = { [notifier] session in notifier.notify(session) }
                    let watcher = EventWatcher(store: store)
                    watcher.start()
                    self.watcher = watcher
                    Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                        MainActor.assumeIsolated { store.sweepStale() }
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
