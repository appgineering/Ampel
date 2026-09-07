import AppKit
import Foundation

enum SessionActivity {
    case idle, working, attention
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

struct Session: Identifiable {
    let id: String            // payload.session_id
    var cwd: String
    var activity: SessionActivity
    var lastActivity: Date
    var lastMessage: String?  // Notification payload "message", if present

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

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case cwd
            case message
        }
    }

    enum CodingKeys: String, CodingKey {
        case event
        case receivedAt = "received_at"
        case payload
    }
}
