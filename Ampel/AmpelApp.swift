import SwiftUI

@main
struct AmpelApp: App {
    @State private var store = AmpelStore()

    // TODO(M2): create EventWatcher(store:) here, call start() on launch,
    // and drain the spool once per SPEC §4.

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(nsImage: StatusIcon.image(for: store.aggregate))
        }
        .menuBarExtraStyle(.window)
    }
}
