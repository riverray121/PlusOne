import ManagedSettings
import UserNotifications

// Handles the shield's unlock button. Extensions cannot launch the app, so
// this records the request and posts a notification whose tap opens PlusOne.
class ShieldActionProvider: ShieldActionDelegate {

    private func requestUnlock(_ target: UnlockTarget, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        SharedStore.shared.pendingUnlock = target

        let content = UNMutableNotificationContent()
        content.title = "Unlock with a selfie"
        content.body = "Tap to take a selfie with someone and unlock this \(target.displayNoun)."
        content.interruptionLevel = .timeSensitive
        // Extension-posted banners don't reliably show an app icon; attach
        // the logo as a thumbnail instead. Attachments consume their file, so
        // hand over a temp copy.
        if let icon = Bundle.main.url(forResource: "NotificationIcon", withExtension: "png") {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".png")
            try? FileManager.default.copyItem(at: icon, to: tmp)
            if let attachment = try? UNNotificationAttachment(identifier: "icon", url: tmp) {
                content.attachments = [attachment]
            }
        }
        let request = UNNotificationRequest(
            identifier: AppGroup.unlockNotificationId,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            requestUnlock(.application(application), completionHandler: completionHandler)
        default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            requestUnlock(.webDomain(webDomain), completionHandler: completionHandler)
        default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            requestUnlock(.category(category), completionHandler: completionHandler)
        default:
            completionHandler(.close)
        }
    }
}
