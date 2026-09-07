import XCTest
@testable import Ampel

/// The spool drain: ordering, malformed files, and replaying what arrived
/// while the app was closed.
final class WatcherTests: XCTestCase {
    private var home: URL!
    private var events: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ampel-watcher-\(UUID().uuidString)")
        events = home.appendingPathComponent(".ampel/events")
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// Written the way the hook writes them, including the whole second
    /// filename stamp that makes collisions routine.
    @discardableResult
    private func spool(_ event: String, _ id: String, name: String,
                       mtime: Date? = nil) throws -> URL {
        let json = """
        {"event":"\(event)","received_at":1000,"payload":{"session_id":"\(id)","cwd":"/tmp/p"}}
        """
        let url = events.appendingPathComponent(name)
        try json.write(to: url, atomically: true, encoding: .utf8)
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime],
                                                  ofItemAtPath: url.path)
        }
        return url
    }

    private func drain() async -> AmpelStore {
        let store = await AmpelStore()
        let watcher = EventWatcher(store: store, eventsDirectory: events)
        watcher.drain()
        // The drain hands work to the main queue; let it land.
        await MainActor.run { }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return store
    }

    /// Filenames carry whole seconds only, so several events share one. Sorting
    /// by name alone can apply Stop before PreToolUse and strand the icon.
    func testOrdersBySubSecondModificationTime() async throws {
        let base = Date()
        try spool("Stop", "a", name: "1000-1-9.json", mtime: base.addingTimeInterval(0.3))
        try spool("SessionStart", "a", name: "1000-2-1.json", mtime: base)
        try spool("UserPromptSubmit", "a", name: "1000-3-5.json", mtime: base.addingTimeInterval(0.1))

        let store = await drain()
        let aggregate = await store.aggregate
        XCTAssertEqual(aggregate, .idle, "Stop was last in time, so idle must win")
    }

    func testAppliesEverythingAndDeletesTheSpool() async throws {
        try spool("SessionStart", "a", name: "1000-1-1.json")
        try spool("SessionStart", "b", name: "1000-1-2.json")
        let store = await drain()

        let count = await store.sessions.count
        XCTAssertEqual(count, 2, "replays everything queued while the app was closed")
        let left = try FileManager.default.contentsOfDirectory(atPath: events.path)
        XCTAssertEqual(left, [], "applied files must be deleted")
    }

    func testMalformedFilesAreDeletedNotFatal() async throws {
        try "not json at all".write(to: events.appendingPathComponent("1000-1-1.json"),
                                    atomically: true, encoding: .utf8)
        try spool("SessionStart", "a", name: "1000-1-2.json")

        let store = await drain()
        let count = await store.sessions.count
        XCTAssertEqual(count, 1, "one bad file must not stop the good ones")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: events.path), [])
    }

    /// The hook writes to .tmp then renames, so a .tmp file is half written.
    func testIgnoresPartiallyWrittenFiles() async throws {
        try "{".write(to: events.appendingPathComponent(".tmp-123"),
                      atomically: true, encoding: .utf8)
        try spool("SessionStart", "a", name: "1000-1-1.json")

        let store = await drain()
        let count = await store.sessions.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: events.path), [".tmp-123"],
                       "an in-flight file must be left alone, not consumed")
    }

    func testSurvivesAMissingDirectory() async throws {
        try FileManager.default.removeItem(at: events)
        let store = await AmpelStore()
        EventWatcher(store: store, eventsDirectory: events).drain()
        let aggregate = await store.aggregate
        XCTAssertEqual(aggregate, .off)
    }
}
