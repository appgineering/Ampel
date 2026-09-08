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

    var displayName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// One file in ~/.ampel/events, written by ampel-hook. See SPEC §2.3.
struct HookEnvelope: Decodable {
    let event: String
    let receivedAt: Int
    let payload: Payload

    struct Payload: Decodable {
        let sessionId: String?
        let cwd: String?
        let message: String?
        let notificationType: String?
        let toolName: String?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case cwd
            case message
            case notificationType = "notification_type"
            case toolName = "tool_name"
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
        case payload
    }
}
