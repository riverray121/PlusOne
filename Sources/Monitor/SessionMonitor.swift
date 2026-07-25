import DeviceActivity
import ManagedSettings

// Ends unlock sessions from outside the app. The usage threshold is the real
// limit; interval end is the backstop if usage tracking never fires.
class SessionMonitor: DeviceActivityMonitor {

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        guard activity.rawValue == AppGroup.activityName else { return }
        SessionManager.shared.endSession()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        guard activity.rawValue == AppGroup.activityName else { return }
        SessionManager.shared.endSession()
    }
}
