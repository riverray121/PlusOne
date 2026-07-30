import Foundation
import UserNotifications

// Posts local notifications from extensions. Extension-posted banners don't
// reliably show the app icon, so the logo ships as an attachment; attachments
// consume their file, so a temp copy is handed over.
enum Notifier {
    static func post(id: String, title: String, body: String, completion: (() -> Void)? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .timeSensitive
        if let icon = Bundle.main.url(forResource: "NotificationIcon", withExtension: "png") {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".png")
            try? FileManager.default.copyItem(at: icon, to: tmp)
            if let attachment = try? UNNotificationAttachment(identifier: "icon", url: tmp) {
                content.attachments = [attachment]
            }
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in completion?() }
    }
}
