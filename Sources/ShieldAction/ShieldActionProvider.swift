import ManagedSettings

// Handles the shield's unlock button. Extensions cannot launch the app, so
// this records the request and posts a notification whose tap opens PlusOne.
// Hard-blocked and out-of-time items have no unlock: every tap just closes.
class ShieldActionProvider: ShieldActionDelegate {

    private func requestUnlock(_ target: UnlockTarget, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        SharedStore.shared.pendingUnlock = target
        Notifier.post(
            id: AppGroup.unlockNotificationId,
            title: "Unlock with a selfie",
            body: "Tap to take a selfie with someone and unlock this \(target.displayNoun)."
        ) {
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let locked = SharedStore.shared.hardSelection.applicationTokens.contains(application)
            || TimeLimitManager.shared.exhaustedRule(containing: application) != nil
        switch action {
        case .primaryButtonPressed where !locked:
            requestUnlock(.application(application), completionHandler: completionHandler)
        default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let locked = SharedStore.shared.hardSelection.webDomainTokens.contains(webDomain)
            || TimeLimitManager.shared.exhaustedRule(containing: webDomain) != nil
        switch action {
        case .primaryButtonPressed where !locked:
            requestUnlock(.webDomain(webDomain), completionHandler: completionHandler)
        default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let locked = SharedStore.shared.hardSelection.categoryTokens.contains(category)
            || TimeLimitManager.shared.exhaustedRule(containing: category) != nil
        switch action {
        case .primaryButtonPressed where !locked:
            requestUnlock(.category(category), completionHandler: completionHandler)
        default:
            completionHandler(.close)
        }
    }
}
