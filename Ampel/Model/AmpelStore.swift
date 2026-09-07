import Foundation
import Observation

@MainActor
@Observable
final class AmpelStore {
    private(set) var sessions: [String: Session] = [:]

    var aggregate: AggregateState {
        if sessions.isEmpty { return .off }
        if sessions.values.contains(where: { $0.activity == .attention }) { return .attention }
        if sessions.values.contains(where: { $0.activity == .working }) { return .working }
        return .idle
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

    func apply(_ envelope: HookEnvelope) {
        // TODO(M2): implement the transition table from SPEC §3.
        // Every event updates lastActivity and cwd. SessionEnd removes the session.
        // Ignore and log unknown events; never crash.
    }

    func sweepStale(olderThan interval: TimeInterval = 6 * 3600) {
        // TODO(M2): remove sessions whose lastActivity is older than `interval`.
        // Called by a 60s timer (killed terminals never send SessionEnd).
    }
}
