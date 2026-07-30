import Foundation

// Identifiers shared by the app and all extensions.
enum AppGroup {
    static let suite = "group.com.riverray.plusone"

    // One named store so every process manipulates the same shield state.
    static let managedSettingsStoreName = "plusone"

    // DeviceActivity identifiers for the unlock session lifecycle.
    static let activityName = "unlockSession"
    static let usageEventName = "usageLimit"

    // Notification posted by the shield action to route the user into the app.
    static let unlockNotificationId = "com.riverray.plusone.unlock"

    // Notification posted by the monitor when a time limit is nearly spent.
    static let limitWarningNotificationId = "com.riverray.plusone.limitWarning"
}

// "1 minute" / "5 minutes"
func pluralMinutes(_ n: Int) -> String {
    n == 1 ? "1 minute" : "\(n) minutes"
}
