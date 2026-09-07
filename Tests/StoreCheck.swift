// Self-check for the SPEC §3 transition table. Run: ./Tests/run.sh
import Foundation

func env(_ event: String, _ sid: String, _ cwd: String = "/tmp/proj", _ msg: String? = nil, at: Int = 1_000) -> HookEnvelope {
    let payload = msg.map { "\"message\":\"\($0)\"," } ?? ""
    let json = "{\"event\":\"\(event)\",\"received_at\":\(at),\"payload\":{\(payload)\"session_id\":\"\(sid)\",\"cwd\":\"\(cwd)\"}}"
    return try! JSONDecoder().decode(HookEnvelope.self, from: Data(json.utf8))
}

@main enum StoreCheck {
@MainActor static func main() {
    let s = AmpelStore()
    assert(s.aggregate == .off, "no sessions is off")

    var attentionFired: [String] = []
    s.onAttention = { attentionFired.append($0.id) }

    s.apply(env("SessionStart", "a"));      assert(s.aggregate == .idle)
    assert(s.summary == "1 session working" || s.summary == "All quiet")
    s.apply(env("UserPromptSubmit", "a"));  assert(s.aggregate == .working)
    s.apply(env("PreToolUse", "a"));        assert(s.aggregate == .working)
    s.apply(env("PostToolUse", "a"));       assert(s.aggregate == .working)
    s.apply(env("Notification", "a", "/tmp/proj", "needs you"))
    assert(s.aggregate == .attention)
    assert(s.summary == "1 session needs attention", s.summary)
    assert(attentionFired == ["a"], "fires once on entering attention")
    s.apply(env("Notification", "a", "/tmp/proj", "still needs you"))
    assert(attentionFired == ["a"], "already red, no second fire")
    assert(s.sessions["a"]?.lastMessage == "still needs you", "latest message wins")
    s.apply(env("Stop", "a"));              assert(s.aggregate == .idle)
    assert(s.sessions["a"]?.lastMessage == nil, "message cleared once no longer red")
    s.apply(env("SubagentStop", "a"));      assert(s.aggregate == .idle)

    // aggregate is worst-case across sessions
    s.apply(env("UserPromptSubmit", "b", "/tmp/other"))
    assert(s.aggregate == .working, "idle + working is working")
    s.apply(env("Notification", "b", "/tmp/other"))
    assert(s.aggregate == .attention, "idle + attention is attention")
    assert(s.sortedSessions.first?.id == "b", "attention sorts first")
    assert(s.sortedSessions.first?.displayName == "other")

    s.apply(env("SessionEnd", "b"));        assert(s.aggregate == .idle)
    assert(s.sessions["b"] == nil, "SessionEnd removes the session")

    // unknown events and missing session_id are ignored, not fatal
    s.apply(env("PreCompact", "a"))
    let noSid = try! JSONDecoder().decode(HookEnvelope.self, from: Data(
        "{\"event\":\"Stop\",\"received_at\":1,\"payload\":{}}".utf8))
    s.apply(noSid)
    assert(s.sessions.count == 1)

    // stale sweep
    s.sweepStale(olderThan: 0);             assert(s.aggregate == .off, "stale sessions swept")

    print("StoreCheck: all assertions passed")
}
}
