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

    // Notification posted by the monitor when a scheduled break opens.
    static let breakStartNotificationId = "com.riverray.plusone.breakStart"
}

func pluralMinutes(_ n: Int) -> String {
    n == 1 ? "1 minute" : "\(n) minutes"
}

func pluralItems(_ n: Int) -> String {
    n == 1 ? "1 item" : "\(n) items"
}

// Minutes-remaining choices for the session and time-limit warning pickers,
// shared so the two warnings always offer the same marks. 0 = off.
let warnMinuteOptions = [0, 1, 2, 5, 10]

// "45 min" / "1 hour" / "2 hours"
func hoursOrMinutesLabel(_ minutes: Int) -> String {
    guard minutes % 60 == 0 else { return "\(minutes) min" }
    let hours = minutes / 60
    return hours == 1 ? "1 hour" : "\(hours) hours"
}

// "Off" / "1 hour" / "12 hours"
func delayHoursLabel(_ minutes: Int) -> String {
    guard minutes > 0 else { return "Off" }
    let hours = minutes / 60
    return hours == 1 ? "1 hour" : "\(hours) hours"
}

extension FamilyActivitySelection {
    var itemCount: Int {
        applicationTokens.count + webDomainTokens.count + categoryTokens.count
    }

    // Token-only rebuild: carrying the member views over lets a removed token
    // resurrect through an encode/decode round trip.
    func subtracting(_ other: FamilyActivitySelection) -> FamilyActivitySelection {
        var fresh = FamilyActivitySelection()
        fresh.applicationTokens = applicationTokens.subtracting(other.applicationTokens)
        fresh.webDomainTokens = webDomainTokens.subtracting(other.webDomainTokens)
        fresh.categoryTokens = categoryTokens.subtracting(other.categoryTokens)
        return fresh
    }
}
