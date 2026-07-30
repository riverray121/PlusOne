import Foundation
import UserNotifications

// Posts local notifications from extensions. The banner icon comes from the
// extensions' CFBundleIcons entries, not from here.
enum Notifier {
    static func post(id: String, title: String, body: String, completion: (() -> Void)? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in completion?() }
    }
}
