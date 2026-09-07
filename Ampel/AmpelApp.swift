import SwiftUI

@main
struct AmpelApp: App {
    @State private var store = AmpelStore()
    @State private var watcher: EventWatcher?

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(nsImage: StatusIcon.image(for: store.aggregate))
                .onAppear {
                    guard watcher == nil else { return }
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
