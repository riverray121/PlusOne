import DeviceActivity
import ManagedSettings

// Ends unlock sessions and enforces time-limit rules from outside the app.
// For sessions, the usage threshold is the real limit and interval end is the
// backstop. For time limits, the threshold marks the rule spent and the next
// period start clears it.
class SessionMonitor: DeviceActivityMonitor {

    // Activity names are "<base>-<sessionId>"; sessions end independently.
    private func sessionId(from activity: DeviceActivityName) -> String? {
        let prefix = "\(AppGroup.activityName)-"
        guard activity.rawValue.hasPrefix(prefix) else { return nil }
        return String(activity.rawValue.dropFirst(prefix.count))
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        if let ruleId = TimeLimitManager.ruleId(from: activity) {
            TimeLimitManager.shared.clearExhausted(ruleId)
            SessionManager.shared.refreshShields()
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        if let ruleId = TimeLimitManager.ruleId(from: activity) {
            switch event {
            case TimeLimitManager.limitEvent:
                TimeLimitManager.shared.markExhausted(ruleId)
                SessionManager.shared.refreshShields()
            case TimeLimitManager.warnEvent:
                if let rule = TimeLimitManager.shared.rule(withId: ruleId) {
                    let left = SharedStore.shared.warnMinutesLeft
                    Notifier.post(
                        id: AppGroup.limitWarningNotificationId,
                        title: "Time limit almost up",
                        body: "You have \(pluralMinutes(left)) left of \(pluralMinutes(rule.minutes)) per \(rule.period.label)."
                    )
                }
            default:
                break
            }
            return
        }
        guard let id = sessionId(from: activity) else { return }
        SessionManager.shared.endSession(id: id)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        if let ruleId = TimeLimitManager.ruleId(from: activity) {
            TimeLimitManager.shared.clearExhausted(ruleId)
            SessionManager.shared.refreshShields()
            return
        }
        guard let id = sessionId(from: activity) else { return }
        SessionManager.shared.endSession(id: id)
    }
}
