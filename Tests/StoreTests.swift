import XCTest
@testable import Ampel

/// The SPEC section 3 transition table, which is what decides the colour.
@MainActor
final class StoreTests: XCTestCase {
    private func envelope(_ event: String, _ id: String, cwd: String = "/tmp/proj",
                          message: String? = nil, notificationType: String? = nil,
                          tool: String? = nil, agent: String? = nil,
                          tasks: [[String: String]]? = nil, terminal: String? = nil,
                          at: Int = 1_000) throws -> HookEnvelope {
        var payload: [String: Any] = ["session_id": id, "cwd": cwd]
        if let message { payload["message"] = message }
        if let notificationType { payload["notification_type"] = notificationType }
        if let tool { payload["tool_name"] = tool }
        if let agent { payload["agent_id"] = agent }
        if let tasks { payload["background_tasks"] = tasks }
        var root: [String: Any] = ["event": event, "received_at": at, "payload": payload]
        if let terminal { root["terminal"] = terminal }
        let data = try JSONSerialization.data(withJSONObject: root)
        return try JSONDecoder().decode(HookEnvelope.self, from: data)
    }

    // MARK: - The terminal a session runs in

    /// A hook run outside a GUI app reports an empty string, and an envelope
    /// from an older script reports nothing. Neither may forget the terminal.
    func testRemembersTheTerminalAcrossEventsThatDoNotNameOne() throws {
        let store = AmpelStore()
        store.apply(try envelope("SessionStart", "a"))
        XCTAssertNil(store.sessions["a"]?.terminal)

        store.apply(try envelope("UserPromptSubmit", "a", terminal: "com.mitchellh.ghostty"))
        store.apply(try envelope("Stop", "a", terminal: ""))
        store.apply(try envelope("UserPromptSubmit", "a"))
        XCTAssertEqual(store.sessions["a"]?.terminal, "com.mitchellh.ghostty")
    }

    // MARK: - A long turn finishing

    private func finishes(in store: AmpelStore) -> () -> [TimeInterval] {
        final class Box { var durations: [TimeInterval] = [] }
        let box = Box()
        store.onFinished = { _, duration in box.durations.append(duration) }
        return { box.durations }
    }

    func testOnlyALongTurnAnnouncesThatItFinished() throws {
        let store = AmpelStore()
        let finished = finishes(in: store)
        store.apply(try envelope("UserPromptSubmit", "a", at: 1_000))
        store.apply(try envelope("Stop", "a", at: 1_100))
        XCTAssertEqual(finished(), [], "a short turn is one the person sat through")

        store.apply(try envelope("UserPromptSubmit", "a", at: 2_000))
        store.apply(try envelope("PreToolUse", "a", tool: "Bash", at: 2_100))
        store.apply(try envelope("Stop", "a", at: 2_300))
        XCTAssertEqual(finished(), [300], "timed from the prompt, not from the last stop")
        XCTAssertNil(store.sessions["a"]?.turnStarted)
    }

    /// A foreground agent's SubagentStop lands on idle in the middle of the
    /// turn. It must neither announce the turn nor restart its clock.
    func testAnAgentFinishingMidTurnIsNotTheTurnFinishing() throws {
        let store = AmpelStore()
        let finished = finishes(in: store)
        store.apply(try envelope("UserPromptSubmit", "a", at: 1_000))
        store.apply(try envelope("SubagentStop", "a", agent: "x", at: 1_400))
        XCTAssertEqual(finished(), [])
        store.apply(try envelope("PostToolUse", "a", tool: "Agent", at: 1_401))
        store.apply(try envelope("Stop", "a", at: 1_500))
        XCTAssertEqual(finished(), [500])
    }

    /// With background agents the turn stops early, the last agent leaves the
    /// session idle, and Claude Code then wakes the main turn to wrap up. One
    /// announcement, at the very end, for the whole stretch.
    func testATurnWaitingOnBackgroundAgentsFinishesWhenTheWrapUpDoes() throws {
        let store = AmpelStore()
        let finished = finishes(in: store)
        let running = [["id": "x", "type": "subagent", "status": "running"]]
        store.apply(try envelope("UserPromptSubmit", "a", at: 1_000))
        store.apply(try envelope("Stop", "a", tasks: running, at: 1_010))
        store.apply(try envelope("SubagentStop", "a", agent: "x", tasks: running, at: 1_600))
        XCTAssertEqual(finished(), [])
        store.apply(try envelope("UserPromptSubmit", "a", at: 1_603))
        store.apply(try envelope("Stop", "a", at: 1_620))
        XCTAssertEqual(finished(), [620])
    }

    /// If that wake-up never comes, the old start time must not be charged to
    /// whatever the person asks next.
    func testAStartTimeLeftBehindIsNotCarriedIntoTheNextTurn() throws {
        let store = AmpelStore()
        let finished = finishes(in: store)
        store.apply(try envelope("UserPromptSubmit", "a", at: 1_000))
        store.apply(try envelope("SubagentStop", "a", agent: "x", at: 1_400))
        store.apply(try envelope("UserPromptSubmit", "a", at: 5_000))
        store.apply(try envelope("Stop", "a", at: 5_010))
        XCTAssertEqual(finished(), [])
    }

    // MARK: - A question waiting on the person

    /// Claude Code sends no Notification when it puts a question on screen, so
    /// the only evidence is PreToolUse naming the tool. Before this, the
    /// session read "working" for as long as the prompt sat there unanswered.
    func testAQuestionOnScreenGoesRed() throws {
        let store = AmpelStore()
        store.apply(try envelope("PreToolUse", "a", tool: "Bash"))
        XCTAssertEqual(store.aggregate, .working)

        store.apply(try envelope("PreToolUse", "a", tool: "AskUserQuestion"))
        XCTAssertEqual(store.aggregate, .attention)

        store.apply(try envelope("PostToolUse", "a", tool: "AskUserQuestion"))
        XCTAssertEqual(store.aggregate, .working, "answering releases it")
    }

    /// The observed failure: a backgrounded agent finished while the question
    /// was still on screen, and SubagentStop turned the light green.
    func testABackgroundAgentFinishingDoesNotClearAPendingQuestion() throws {
        let store = AmpelStore()
        store.apply(try envelope("PreToolUse", "a", tool: "AskUserQuestion"))
        XCTAssertEqual(store.aggregate, .attention)

        // Everything a busy session emits while the person is still reading.
        store.apply(try envelope("SubagentStop", "a"))
        store.apply(try envelope("Stop", "a"))
        store.apply(try envelope("PreToolUse", "a", tool: "WebFetch"))
        store.apply(try envelope("PostToolUse", "a", tool: "WebFetch"))
        store.apply(try envelope("Notification", "a", notificationType: "idle_prompt"))
        XCTAssertEqual(store.aggregate, .attention, "the prompt is still waiting")

        store.apply(try envelope("PostToolUse", "a", tool: "AskUserQuestion"))
        XCTAssertEqual(store.aggregate, .working)
    }

    /// Escaping the prompt and typing instead never sends the PostToolUse that
    /// would release it, so the light would otherwise stay red for good.
    func testTypingInsteadOfAnsweringReleasesTheSession() throws {
        let store = AmpelStore()
        store.apply(try envelope("PreToolUse", "a", tool: "ExitPlanMode"))
        XCTAssertEqual(store.aggregate, .attention, "a plan awaiting approval blocks too")

        store.apply(try envelope("UserPromptSubmit", "a"))
        XCTAssertEqual(store.aggregate, .working)
    }

    // MARK: - Background agents

    private func task(_ id: String, _ type: String = "subagent") -> [String: String] {
        ["id": id, "type": type, "status": "running", "description": "x"]
    }

    /// The observed failure: the main turn stopped with "Waiting for 3
    /// background agents to finish" on screen, and the light went green.
    func testAStoppedTurnWithBackgroundAgentsIsStillWorking() throws {
        let store = AmpelStore()
        store.apply(try envelope("UserPromptSubmit", "a"))
        store.apply(try envelope("Stop", "a", tasks: [task("x"), task("y"), task("z")]))
        XCTAssertEqual(store.aggregate, .working)
        XCTAssertEqual(store.sessions["a"]?.stateLabel, "Working · 3 background agents")

        // A background agent's own SubagentStop still lists it as running.
        store.apply(try envelope("SubagentStop", "a", agent: "x", tasks: [task("x"), task("y"), task("z")]))
        XCTAssertEqual(store.sessions["a"]?.backgroundAgents, 2)
        store.apply(try envelope("SubagentStop", "a", agent: "y", tasks: [task("y"), task("z")]))
        XCTAssertEqual(store.sessions["a"]?.stateLabel, "Working · 1 background agent")

        store.apply(try envelope("SubagentStop", "a", agent: "z", tasks: [task("z")]))
        XCTAssertEqual(store.aggregate, .idle, "the last one finishing leaves nothing running")
        XCTAssertEqual(store.sessions["a"]?.stateLabel, "Idle")
    }

    /// A dev server or a passive watch outlives the work. Counting them would
    /// hold the session yellow for as long as it stays open.
    func testBackgroundShellsAndMonitorsDoNotHoldASessionBusy() throws {
        let store = AmpelStore()
        store.apply(try envelope("Stop", "a", tasks: [task("s", "shell"), task("m", "monitor")]))
        XCTAssertEqual(store.aggregate, .idle)

        store.apply(try envelope("Stop", "a", tasks: [task("s", "shell"), task("w", "workflow")]))
        XCTAssertEqual(store.sessions["a"]?.backgroundAgents, 1)
    }

    /// The field is new and its shape is not ours. A Stop must still land.
    func testAMalformedTaskListDoesNotLoseTheStop() throws {
        let store = AmpelStore()
        store.apply(try envelope("UserPromptSubmit", "a"))
        store.apply(try JSONDecoder().decode(HookEnvelope.self, from: Data(
            #"{"event":"Stop","received_at":1,"payload":{"session_id":"a","background_tasks":"nope"}}"#.utf8)))
        XCTAssertEqual(store.aggregate, .idle)
    }

    func testStartsOff() {
        XCTAssertEqual(AmpelStore().aggregate, .off)
        XCTAssertEqual(AmpelStore().summary, "No active sessions")
    }

    /// Quitting Ampel while a session is mid-flight must not lose it.
    func testSurvivesRelaunch() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ampel-\(UUID().uuidString)/sessions.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AmpelStore(stateURL: url)
        store.apply(try envelope("UserPromptSubmit", "a", at: Int(Date().timeIntervalSince1970)))
        XCTAssertEqual(store.aggregate, .working)

        let relaunched = AmpelStore(stateURL: url)
        XCTAssertEqual(relaunched.aggregate, .working)
        XCTAssertEqual(relaunched.sessions["a"]?.cwd, "/tmp/proj")

        // ...but a session last seen days ago is not resurrected.
        store.apply(try envelope("SessionStart", "old", at: 1_000))
        XCTAssertEqual(AmpelStore(stateURL: url).sessions.keys.sorted(), ["a"])
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
