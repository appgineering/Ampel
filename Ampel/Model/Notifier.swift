import Foundation
import UserNotifications
import os

/// One macOS notification per session transition into `attention`, at most one
/// per session per 30 seconds. See SPEC §6. Nothing else notifies.
@MainActor
final class Notifier {
    private let log = Log("ui")
    private let debounce: TimeInterval = 30
    private var lastSent: [String: Date] = [:]

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { self.log.error("notification authorization failed: \(error.localizedDescription)") }
            else if !granted { self.log.info("notification authorization denied") }
        }
    }

    func notify(_ session: Session) {
        if let last = lastSent[session.id], Date().timeIntervalSince(last) < debounce { return }
        lastSent[session.id] = Date()

        let content = UNMutableNotificationContent()
        content.title = session.displayName
        content.body = session.lastMessage ?? "Claude needs your attention"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { self.log.error("notification failed: \(error.localizedDescription)") }
        }
    }
}
