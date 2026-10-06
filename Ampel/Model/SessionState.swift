import AppKit
import Foundation

enum SessionActivity: String, Codable {
    case idle, working, attention

    var label: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .attention: "Needs attention"
        }
    }

    var color: NSColor {
        switch self {
        case .idle: .systemGreen
        case .working: .systemYellow
        case .attention: .systemRed
        }
    }
}

enum AggregateState {
    case off, idle, working, attention

    var color: NSColor {
        switch self {
        case .off: .systemGray
        case .idle: .systemGreen
        case .working: .systemYellow
        case .attention: .systemRed
        }
    }
}

struct Session: Identifiable, Codable {
    let id: String            // payload.session_id
    var cwd: String
    var activity: SessionActivity
    var lastActivity: Date
    var lastMessage: String?  // Notification payload "message", if present
    /// The tool whose prompt is currently on screen, if one is. Decodes as nil
    /// from a sessions.json written before this existed.
    var blockedOn: String?
    /// Background agents still running after the main turn stopped. Nil when
    /// there are none, and from a sessions.json written before this existed.
    var backgroundAgents: Int?
    /// Bundle id of the app the session runs in, which is what a click on the
    /// row brings to the front. Nil until the first event from a hook script
    /// new enough to report it.
    var terminal: String?
    /// When the turn in progress began. Outlives a `SubagentStop`, which can
    /// leave the session idle for a moment in the middle of a turn.
    var turnStarted: Date?

    /// The row's state line. A session that stopped but is waiting on its
    /// background agents says so, since "Working" alone hides why.
    var stateLabel: String {
        guard activity == .working, let count = backgroundAgents else { return activity.label }
        return "\(activity.label) · \(count) background \(count == 1 ? "agent" : "agents")"
    }

    var displayName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// One file in ~/.ampel/events, written by ampel-hook. See SPEC §2.3.
struct HookEnvelope: Decodable {
    let event: String
    let receivedAt: Int
    /// `__CFBundleIdentifier` as the hook saw it. Empty outside a GUI app.
    let terminal: String?
    let payload: Payload

    struct Payload: Decodable {
        let sessionId: String?
        let cwd: String?
        let message: String?
        let notificationType: String?
        let toolName: String?
        let agentId: String?
        let backgroundTasks: [BackgroundTask]?

        /// One entry of `background_tasks` on Stop and SubagentStop.
        struct BackgroundTask: Decodable {
            let id: String?
            let type: String?
            let status: String?
        }

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case cwd
            case message
            case notificationType = "notification_type"
            case toolName = "tool_name"
            case agentId = "agent_id"
            case backgroundTasks = "background_tasks"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
            cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
            toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
            agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
            // A changed shape here must not cost us the Stop it rides on.
            backgroundTasks = try? container.decodeIfPresent([BackgroundTask].self, forKey: .backgroundTasks)
        }

        /// Task types that are agents. A `shell` is usually a dev server and a
        /// `monitor` a passive watch: both outlive the work and would pin the
        /// session yellow for as long as it is open.
        static let agentTaskTypes: Set<String> = ["subagent", "workflow"]

        /// Agents still running in the background. A background agent's own
        /// SubagentStop lists that agent as running, so it is excluded.
        var runningBackgroundAgents: Int {
            (backgroundTasks ?? []).filter { task in
                task.status == "running" && task.id != agentId
                    && Self.agentTaskTypes.contains(task.type ?? "")
            }.count
        }

        /// Notification types that do not represent a decision waiting on the
        /// user. Anything else, including an absent or unrecognised type, does:
        /// a new blocking notification type should show up, not be swallowed.
        static let nonBlockingNotifications: Set<String> = [
            "idle_prompt", "auth_success", "elicitation_complete", "elicitation_response",
            "quota_auto_resume_fired", "quota_auto_resume_stale", "quota_auto_resume_disabled",
        ]

        var isBlockingNotification: Bool {
            guard let notificationType else { return true }
            return !Self.nonBlockingNotifications.contains(notificationType)
        }
    }

    enum CodingKeys: String, CodingKey {
        case event
        case receivedAt = "received_at"
        case terminal
        case payload
    }
}
