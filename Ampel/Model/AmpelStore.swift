import Foundation
import Observation
import os

@MainActor
@Observable
final class AmpelStore {
    private(set) var sessions: [String: Session] = [:]

    /// Called when a session transitions INTO `.attention` (SPEC §6).
    /// A closure rather than a direct dependency so the store stays testable
    /// outside an app bundle, where UNUserNotificationCenter is unavailable.
    @ObservationIgnored
    var onAttention: ((Session) -> Void)?

    @ObservationIgnored
    private let log = Logger(subsystem: "com.appgineering.ampel", category: "store")

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
            log.debug("event \(envelope.event, privacy: .public) without session_id, ignored")
            return
        }

        if envelope.event == "SessionEnd" {
            sessions.removeValue(forKey: id)
            return
        }

        let activity: SessionActivity
        switch envelope.event {
        case "SessionStart", "Stop", "SubagentStop": activity = .idle
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": activity = .working
        case "Notification": activity = .attention
        default:
            log.info("unknown event \(envelope.event, privacy: .public), ignored")
            return
        }

        let at = Date(timeIntervalSince1970: TimeInterval(envelope.receivedAt))
        let previous = sessions[id]
        var session = previous ?? Session(id: id, cwd: "", activity: activity, lastActivity: at, lastMessage: nil)
        session.activity = activity
        session.lastActivity = at
        if let cwd = envelope.payload.cwd { session.cwd = cwd }
        // Keep the message only while it is the reason we are red.
        session.lastMessage = activity == .attention ? envelope.payload.message : nil
        sessions[id] = session

        if activity == .attention && previous?.activity != .attention {
            onAttention?(session)
        }
    }

    func sweepStale(olderThan interval: TimeInterval = 6 * 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        let dead = sessions.filter { $0.value.lastActivity < cutoff }.keys
        for id in dead {
            log.info("sweeping stale session \(id, privacy: .public)")
            sessions.removeValue(forKey: id)
        }
    }
}
