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
