import XCTest
@testable import Ampel

/// The SPEC section 3 transition table, which is what decides the colour.
@MainActor
final class StoreTests: XCTestCase {
    private func envelope(_ event: String, _ id: String, cwd: String = "/tmp/proj",
                          message: String? = nil, notificationType: String? = nil,
                          at: Int = 1_000) throws -> HookEnvelope {
        var payload: [String: Any] = ["session_id": id, "cwd": cwd]
        if let message { payload["message"] = message }
        if let notificationType { payload["notification_type"] = notificationType }
        let root: [String: Any] = ["event": event, "received_at": at, "payload": payload]
        let data = try JSONSerialization.data(withJSONObject: root)
        return try JSONDecoder().decode(HookEnvelope.self, from: data)
    }

    func testStartsOff() {
        XCTAssertEqual(AmpelStore().aggregate, .off)
        XCTAssertEqual(AmpelStore().summary, "No active sessions")
    }

    func testTransitionTable() throws {
        let store = AmpelStore()
        store.apply(try envelope("SessionStart", "a"))
        XCTAssertEqual(store.aggregate, .idle)

        for working in ["UserPromptSubmit", "PreToolUse", "PostToolUse"] {
            store.apply(try envelope(working, "a"))
            XCTAssertEqual(store.aggregate, .working, working)
        }

        store.apply(try envelope("Notification", "a", message: "needs you"))
        XCTAssertEqual(store.aggregate, .attention)
        XCTAssertEqual(store.sessions["a"]?.lastMessage, "needs you")

        for idle in ["Stop", "SubagentStop"] {
            store.apply(try envelope("Notification", "a", message: "again"))
            store.apply(try envelope(idle, "a"))
            XCTAssertEqual(store.aggregate, .idle, idle)
        }
        XCTAssertNil(store.sessions["a"]?.lastMessage,
                     "a green row must not keep the message that made it red")

        store.apply(try envelope("SessionEnd", "a"))
        XCTAssertNil(store.sessions["a"])
        XCTAssertEqual(store.aggregate, .off)
    }

    /// Claude Code fires Notification when a session merely sits at a prompt.
    /// Treating that as attention pinned the icon red whenever one was open.
    func testOnlyBlockingNotificationsRaiseAttention() throws {
        let store = AmpelStore()
        store.apply(try envelope("SessionStart", "a"))

        for quiet in ["idle_prompt", "auth_success", "quota_auto_resume_fired",
                      "elicitation_complete", "elicitation_response"] {
            store.apply(try envelope("Notification", "a", notificationType: quiet))
            XCTAssertEqual(store.aggregate, .idle, quiet)
        }

        for blocking in ["permission_prompt", "agent_needs_input", "elicitation_dialog"] {
            store.apply(try envelope("Stop", "a"))
            store.apply(try envelope("Notification", "a", notificationType: blocking))
            XCTAssertEqual(store.aggregate, .attention, blocking)
        }

        // An unknown type must surface rather than be swallowed.
        store.apply(try envelope("Stop", "a"))
        store.apply(try envelope("Notification", "a", notificationType: "something_new"))
        XCTAssertEqual(store.aggregate, .attention)
    }

    func testQuietNotificationStillRefreshesLiveness() throws {
        let store = AmpelStore()
        store.apply(try envelope("SessionStart", "a", at: 1_000))
        store.apply(try envelope("Notification", "a", notificationType: "idle_prompt", at: 5_000))
        XCTAssertEqual(store.sessions["a"]?.lastActivity,
                       Date(timeIntervalSince1970: 5_000))
    }

    func testAggregateIsWorstCase() throws {
        let store = AmpelStore()
        store.apply(try envelope("SessionStart", "a"))
        store.apply(try envelope("UserPromptSubmit", "b", cwd: "/tmp/other"))
        XCTAssertEqual(store.aggregate, .working)
        XCTAssertEqual(store.summary, "1 session working")

        store.apply(try envelope("Notification", "b", cwd: "/tmp/other"))
        XCTAssertEqual(store.aggregate, .attention)
        XCTAssertEqual(store.summary, "1 session needs attention")
        XCTAssertEqual(store.sortedSessions.first?.id, "b", "attention sorts first")
        XCTAssertEqual(store.sortedSessions.first?.displayName, "other")
    }

    func testSummaryPluralises() throws {
        let store = AmpelStore()
        store.apply(try envelope("UserPromptSubmit", "a"))
        store.apply(try envelope("UserPromptSubmit", "b"))
        XCTAssertEqual(store.summary, "2 sessions working")
        store.apply(try envelope("Notification", "a"))
        store.apply(try envelope("Notification", "b"))
        XCTAssertEqual(store.summary, "2 sessions need attention")
        store.apply(try envelope("Stop", "a"))
        store.apply(try envelope("Stop", "b"))
        XCTAssertEqual(store.summary, "All quiet")
    }

    func testAttentionFiresOncePerEntry() throws {
        let store = AmpelStore()
        var fired: [String] = []
        store.onAttention = { fired.append($0.id) }

        store.apply(try envelope("Notification", "a"))
        store.apply(try envelope("Notification", "a"))
        XCTAssertEqual(fired, ["a"], "already red, must not fire again")

        store.apply(try envelope("Stop", "a"))
        store.apply(try envelope("Notification", "a"))
        XCTAssertEqual(fired, ["a", "a"], "re-entering attention fires again")
    }

    func testMalformedEventsAreIgnored() throws {
        let store = AmpelStore()
        store.apply(try envelope("SessionStart", "a"))

        store.apply(try envelope("PreCompact", "a"))
        let noSession = try JSONDecoder().decode(HookEnvelope.self, from: Data(
            #"{"event":"Stop","received_at":1,"payload":{}}"#.utf8))
        store.apply(noSession)
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testStaleSessionsAreSwept() throws {
        let store = AmpelStore()
        store.apply(try envelope("SessionStart", "a", at: Int(Date().timeIntervalSince1970)))
        store.sweepStale(olderThan: 3600)
        XCTAssertEqual(store.sessions.count, 1, "a fresh session must survive")
        store.sweepStale(olderThan: 0)
        XCTAssertEqual(store.aggregate, .off)
    }

    func testCwdUpdatesButIsNotClearedByEventsWithout() throws {
        let store = AmpelStore()
        store.apply(try envelope("SessionStart", "a", cwd: "/tmp/first"))
        XCTAssertEqual(store.sessions["a"]?.displayName, "first")
        store.apply(try envelope("PreToolUse", "a", cwd: "/tmp/second"))
        XCTAssertEqual(store.sessions["a"]?.displayName, "second")
    }
}
