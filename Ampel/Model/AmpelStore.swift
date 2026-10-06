import Foundation
import Observation
import os

@MainActor
@Observable
final class AmpelStore {
    private(set) var sessions: [String: Session] = [:]

    /// Tools that put a prompt on screen and wait for the person to answer.
    /// Claude Code sends no Notification for these, so the only way to know a
    /// human is being asked something is the tool name on PreToolUse.
    static let blockingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// Called when a session transitions INTO `.attention` (SPEC §6).
    /// A closure rather than a direct dependency so the store stays testable
    /// outside an app bundle, where UNUserNotificationCenter is unavailable.
    @ObservationIgnored
    var onAttention: ((Session) -> Void)?

    /// Called when a turn that ran for at least `longTurn` ends, with how long
    /// it took. A closure for the same reason as `onAttention`.
    @ObservationIgnored
    var onFinished: ((Session, TimeInterval) -> Void)?

    // ponytail: fixed. Make it a setting if three minutes suits nobody.
    static let longTurn: TimeInterval = 180

    /// How long a session may sit idle after a `SubagentStop` and still be in
    /// the same turn. Claude Code wakes the main turn within seconds.
    // ponytail: a wake-up slower than this splits the turn, and the finished
    // notification is skipped. Read `<task-notification>` off the prompt if so.
    static let wakeGrace: TimeInterval = 60

    @ObservationIgnored
    private let log = Log("store")

    /// Where the live sessions are mirrored, so quitting and relaunching Ampel
    /// does not lose every session that is mid-flight. Nil in tests, which want
    /// an empty store and no side effects on the real spool.
    @ObservationIgnored
    private let stateURL: URL?

    static var defaultStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ampel/sessions.json")
    }

    init(stateURL: URL? = nil) {
        self.stateURL = stateURL
        guard let stateURL,
              let data = try? Data(contentsOf: stateURL),
              let saved = try? JSONDecoder().decode([String: Session].self, from: data)
        else { return }
        sessions = saved
        log.info("restored \(saved.count) session(s) from disk")
        // A session that was already dead when we quit must not come back.
        sweepStale()
    }

    private func save() {
        guard let stateURL else { return }
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: .atomic)
    }

    var aggregate: AggregateState {
        if sessions.isEmpty { return .off }
        if sessions.values.contains(where: { $0.activity == .attention }) { return .attention }
        if sessions.values.contains(where: { $0.activity == .working }) { return .working }
        return .idle
    }

    /// SPEC §6 header line.
    var summary: String {
        let attention = sessions.values.filter { $0.activity == .attention }.count
        let working = sessions.values.filter { $0.activity == .working }.count
        if attention > 0 { return "\(attention) \(attention == 1 ? "session needs" : "sessions need") attention" }
        if working > 0 { return "\(working) \(working == 1 ? "session" : "sessions") working" }
        return sessions.isEmpty ? "No active sessions" : "All quiet"
    }

    var sortedSessions: [Session] {
        // attention first, then by most recent activity
        sessions.values.sorted {
            if ($0.activity == .attention) != ($1.activity == .attention) {
                return $0.activity == .attention
            }
            return $0.lastActivity > $1.lastActivity
        }
    }

    /// SPEC §3 transition table. Unknown events are logged and ignored.
    func apply(_ envelope: HookEnvelope) {
        guard let id = envelope.payload.sessionId else {
            log.debug("event \(envelope.event) without session_id, ignored")
            return
        }

        if envelope.event == "SessionEnd" {
            log.info("\(id) SessionEnd, removing")
            sessions.removeValue(forKey: id)
            save()
            return
        }

        let previous = sessions[id]
        var blockedOn = previous?.blockedOn
        let tool = envelope.payload.toolName

        // A tool that puts a prompt in front of the user blocks until they
        // answer, and Claude Code fires no Notification for it: PreToolUse when
        // the prompt appears and PostToolUse when it is answered are the only
        // signals there are. Verified against the hook stream, and the docs
        // list no notification_type for a pending question.
        if envelope.event == "PreToolUse", let tool, Self.blockingTools.contains(tool) {
            blockedOn = tool
        } else if envelope.event == "UserPromptSubmit"
                    || (envelope.event == "PostToolUse" && tool != nil && tool == blockedOn) {
            // Answered, or the user typed instead of answering. Either way they
            // are back, so nothing is waiting on them any more.
            blockedOn = nil
        }

        var backgroundAgents = previous?.backgroundAgents
        let activity: SessionActivity
        switch envelope.event {
        case "SessionStart":
            backgroundAgents = nil
            activity = .idle
        case "Stop", "SubagentStop":
            // The main turn ending is not the session going quiet: agents it
            // left running in the background are still working, and Claude
            // Code wakes the main turn again when they report back.
            let running = envelope.payload.runningBackgroundAgents
            backgroundAgents = running > 0 ? running : nil
            activity = running > 0 ? .working : .idle
        case "UserPromptSubmit":
            // The count is only known at a stop, so it is stale from here on.
            backgroundAgents = nil
            activity = .working
        case "PreToolUse", "PostToolUse": activity = .working
        case "Notification":
            // Only a decision waiting on the user goes red. Claude Code also
            // fires Notification when a session merely sits at an empty
            // prompt, which would pin the icon red permanently. SPEC §3.
            guard envelope.payload.isBlockingNotification else {
                touch(id, envelope)
                return
            }
            activity = .attention
        default:
            log.info("unknown event \(envelope.event), ignored")
            return
        }

        // A prompt still on screen outranks whatever else the session is doing.
        // Without this a backgrounded agent finishing fires SubagentStop and
        // turns the light green while the question is still waiting.
        let resolved: SessionActivity = blockedOn == nil ? activity : .attention

        let at = Date(timeIntervalSince1970: TimeInterval(envelope.receivedAt))

        // Only a Stop ends a turn. A SubagentStop also lands on idle, but
        // either the main turn is still running (a foreground agent) or Claude
        // Code is about to wake it (the last background agent), so the start
        // time is kept unless that follow-up never came.
        var turnStarted = previous?.turnStarted
        if let last = previous, last.activity == .idle,
           at.timeIntervalSince(last.lastActivity) > Self.wakeGrace {
            turnStarted = nil
        }
        var finishedAfter: TimeInterval?
        if resolved != .idle {
            turnStarted = turnStarted ?? at
        } else if envelope.event != "SubagentStop" {
            if envelope.event == "Stop", let turnStarted {
                finishedAfter = at.timeIntervalSince(turnStarted)
            }
            turnStarted = nil
        }

        var session = previous ?? Session(id: id, cwd: "", activity: resolved, lastActivity: at, lastMessage: nil)
        session.activity = resolved
        session.lastActivity = at
        session.blockedOn = blockedOn
        session.backgroundAgents = backgroundAgents
        session.turnStarted = turnStarted
        if let cwd = envelope.payload.cwd { session.cwd = cwd }
        if let terminal = envelope.terminal, !terminal.isEmpty { session.terminal = terminal }
        // Keep the message only while it is the reason we are red.
        session.lastMessage = resolved == .attention ? envelope.payload.message : nil
        sessions[id] = session

        log.info("\(id) \(envelope.event) -> \(String(describing: resolved)) (\(self.sessions.count) live)")

        save()

        if resolved == .attention && previous?.activity != .attention {
            onAttention?(session)
        }
        if let finishedAfter, finishedAfter >= Self.longTurn {
            onFinished?(session, finishedAfter)
        }
    }

    /// Refreshes liveness and cwd without changing the activity.
    private func touch(_ id: String, _ envelope: HookEnvelope) {
        guard var session = sessions[id] else { return }
        session.lastActivity = Date(timeIntervalSince1970: TimeInterval(envelope.receivedAt))
        if let cwd = envelope.payload.cwd { session.cwd = cwd }
        sessions[id] = session
        save()
    }

    func sweepStale(olderThan interval: TimeInterval = 6 * 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        let dead = sessions.filter { $0.value.lastActivity < cutoff }.keys
        for id in dead {
            log.info("sweeping stale session \(id)")
            sessions.removeValue(forKey: id)
        }
        if !dead.isEmpty { save() }
    }
}
