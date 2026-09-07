import Foundation
import os

/// Watches ~/.ampel/events via DispatchSource and feeds envelopes into AmpelStore.
/// See SPEC §4: drain on launch AND on every directory change; write-then-rename
/// on the hook side means files are complete when visible; skip ".tmp-*";
/// delete each file after applying; delete-and-log malformed files.
/// Mutable state (`source`, `descriptor`) is written once in `start()` and read
/// only by the cancel handler, and draining happens exclusively on `queue`.
final class EventWatcher: @unchecked Sendable {
    private let store: AmpelStore
    private let log = Log("watcher")
    private let queue = DispatchQueue(label: "com.appgineering.ampel.watcher")
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1

    static var defaultEventsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ampel/events", isDirectory: true)
    }

    /// Injectable so tests can drain a throwaway spool.
    private let eventsDirectory: URL

    init(store: AmpelStore, eventsDirectory: URL = EventWatcher.defaultEventsDirectory) {
        self.store = store
        self.eventsDirectory = eventsDirectory
    }

    func start() {
        let dir = eventsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        queue.async { [weak self] in self?.drain() }

        descriptor = open(dir.path, O_EVTONLY)
        guard descriptor >= 0 else {
            log.error("cannot open \(dir.path) for watching")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        self.source = source
    }

    /// Applies and removes every complete spool file, oldest first.
    /// Ordered by mtime (nanosecond resolution) because the hook's filenames
    /// only carry whole seconds and collide routinely. See SPEC §4.
    func drain() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: eventsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles)) ?? []

        let files = urls.filter {
            $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".tmp-")
        }
        var stamped: [(url: URL, mtime: Date)] = []
        for url in files {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            stamped.append((url, values?.contentModificationDate ?? .distantPast))
        }
        let ordered = stamped.sorted { a, b in
            if a.mtime != b.mtime { return a.mtime < b.mtime }
            return a.url.lastPathComponent < b.url.lastPathComponent
        }

        var collected: [HookEnvelope] = []
        for (url, _) in ordered {
            defer { try? fm.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? JSONDecoder().decode(HookEnvelope.self, from: data) else {
                log.error("dropping malformed spool file \(url.lastPathComponent)")
                continue
            }
            collected.append(envelope)
        }
        let batch = collected
        guard !batch.isEmpty else { return }

        // One ordered hop for the whole drain. The main queue is the main
        // actor's executor, so the assumption holds; it is stated rather than
        // assumed anew for each event.
        DispatchQueue.main.async { [store] in
            MainActor.assumeIsolated {
                for envelope in batch { store.apply(envelope) }
            }
        }
    }
}
