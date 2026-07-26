import DeviceActivity
import ManagedSettings

// Ends unlock sessions from outside the app. The usage threshold is the real
// limit; interval end is the backstop if usage tracking never fires.
class SessionMonitor: DeviceActivityMonitor {

    // Activity names are "<base>-<sessionId>"; sessions end independently.
    private func sessionId(from activity: DeviceActivityName) -> String? {
        let prefix = "\(AppGroup.activityName)-"
        guard activity.rawValue.hasPrefix(prefix) else { return nil }
        return String(activity.rawValue.dropFirst(prefix.count))
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        guard let id = sessionId(from: activity) else { return }
        SessionManager.shared.endSession(id: id)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        guard let id = sessionId(from: activity) else { return }
        SessionManager.shared.endSession(id: id)
    }
}
