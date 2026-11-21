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

    // Notification kinds (see Notifier). Posted by the shield action to route
    // the user into the app.
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

// Bounds for typed settings. Only the schedule bounds come from Screen Time;
// the rest keep a value inside what its unit means.
enum SettingLimits {
    // DeviceActivity rejects schedules shorter than this.
    static let minScheduleMinutes = 15
    // A repeating break schedule needs distinct start and end times, so a
    // window stops short of a full day.
    static let maxWindowMinutes = 24 * 60 - 1
    // Usage granted or counted within one day.
    static let maxDayMinutes = 24 * 60
    // Cooldown and change delay.
    static let maxWaitMinutes = 365 * 24 * 60
    static let maxCount = 999
}

// "45 min" / "90 min" / "2 hours" / "3 days", in the largest unit that
// divides evenly.
func hoursOrMinutesLabel(_ minutes: Int) -> String {
    if minutes > 0, minutes % (24 * 60) == 0 {
        let days = minutes / (24 * 60)
        return days == 1 ? "1 day" : "\(days) days"
    }
    guard minutes > 0, minutes % 60 == 0 else { return "\(minutes) min" }
    let hours = minutes / 60
    return hours == 1 ? "1 hour" : "\(hours) hours"
}

// "Off", or the delay as hoursOrMinutesLabel spells it.
func delayHoursLabel(_ minutes: Int) -> String {
    minutes > 0 ? hoursOrMinutesLabel(minutes) : "Off"
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
