import Foundation
import FamilyControls

// Identifiers shared by the app and all extensions.
enum AppGroup {
    static let suite = "group.com.riverray.plusone"

    // One named store so every process manipulates the same shield state.
    static let managedSettingsStoreName = "plusone"

    // DeviceActivity identifiers for the unlock session lifecycle.
    static let activityName = "unlockSession"
    static let usageEventName = "usageLimit"
    static let sessionWarnEventName = "sessionWarn"

    // Notification posted by the shield action to route the user into the app.
    static let unlockNotificationId = "com.riverray.plusone.unlock"

    // Notification posted by the monitor when a time limit is nearly spent.
    static let limitWarningNotificationId = "com.riverray.plusone.limitWarning"

    // Notification posted by the monitor when an unlock session is nearly over.
    static let sessionWarningNotificationId = "com.riverray.plusone.sessionWarning"
}

// "1 minute" / "5 minutes"
func pluralMinutes(_ n: Int) -> String {
    n == 1 ? "1 minute" : "\(n) minutes"
}

// "1 item" / "5 items"
func pluralItems(_ n: Int) -> String {
    n == 1 ? "1 item" : "\(n) items"
}

extension FamilyActivitySelection {
    var itemCount: Int {
        applicationTokens.count + webDomainTokens.count + categoryTokens.count
    }
}
