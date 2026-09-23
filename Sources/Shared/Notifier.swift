import Foundation
import UserNotifications

// Posts local notifications from extensions. The banner icon comes from the
// extensions' CFBundleIcons entries, not from here.
//
// `kind` groups notifications; each post gets its own request identifier
// under it. A request that reuses the identifier of a notification still in
// Notification Center updates that entry in place and presents no banner,
// so an unread earlier alert would swallow the new one. Older delivered
// notifications of the same kind are removed so only the newest remains.
enum Notifier {
    static func post(kind: String, title: String, body: String, completion: (() -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: "\(kind).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.getDeliveredNotifications { delivered in
            let stale = delivered.map(\.request.identifier).filter { matches($0, kind: kind) }
            center.removeDeliveredNotifications(withIdentifiers: stale)
            center.add(request) { _ in completion?() }
        }
    }

    // A bare `kind` matches too, so a delivered notification carrying no
    // suffix is still recognized.
    static func matches(_ identifier: String, kind: String) -> Bool {
        identifier == kind || identifier.hasPrefix(kind + ".")
    }
}
