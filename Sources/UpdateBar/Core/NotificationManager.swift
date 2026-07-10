import Foundation
import UserNotifications

/// Posts a local notification when new updates appear since the last check.
@MainActor
enum NotificationManager {

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Notify about newly-appeared updates. `newItems` are items not seen previously.
    static func notifyNewUpdates(count: Int, sample: [String]) {
        guard count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Updates available"
        let names = sample.prefix(3).joined(separator: ", ")
        content.body = count == 1
            ? "1 new update: \(names)"
            : "\(count) new updates" + (names.isEmpty ? "" : ": \(names)…")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
