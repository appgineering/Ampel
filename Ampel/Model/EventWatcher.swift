import Foundation
import os

/// Watches ~/.ampel/events via DispatchSource and feeds envelopes into AmpelStore.
/// See SPEC §4: drain on launch AND on every directory change; write-then-rename
/// on the hook side means files are complete when visible; skip ".tmp-*";
/// delete each file after applying; delete-and-log malformed files.
final class EventWatcher {
    private let store: AmpelStore
    private let log = Logger(subsystem: "com.appgineering.ampel", category: "watcher")

    static var eventsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ampel/events", isDirectory: true)
    }

    init(store: AmpelStore) {
        self.store = store
    }

    func start() {
        // TODO(M2): open eventsDirectory with O_EVTONLY, create a
        // DispatchSource.makeFileSystemObjectSource(eventMask: .write),
        // drain once immediately, then drain on every event.
    }

    func drain() {
        // TODO(M2): list *.json sorted ascending by filename, decode HookEnvelope,
        // hop to MainActor to store.apply(_:), then delete the file.
    }
}
