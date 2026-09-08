import AppKit
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

    /// The icon to the left of a notification belongs to LaunchServices and
    /// cannot be set from here, so the app icon rides along as an attachment.
    /// A fresh file each time, because the notification centre takes ownership
    /// of the one it is handed.
    private func iconAttachment() -> UNNotificationAttachment? {
        guard let icon = NSApp.applicationIconImage,
              let tiff = icon.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ampel-icon-\(UUID().uuidString).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "icon", url: url, options: nil)
    }

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
        if let icon = iconAttachment() { content.attachments = [icon] }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { self.log.error("notification failed: \(error.localizedDescription)") }
        }
    }
}
