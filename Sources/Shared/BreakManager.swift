import Foundation
import DeviceActivity
import FamilyControls

// Arms DeviceActivity monitoring for scheduled breaks and tracks which are
// currently open. The monitor extension flips break state from outside the
// app: interval start opens a break, the usage threshold or interval end
// closes it.
struct BreakManager {
    static let shared = BreakManager()

    private let store = SharedStore.shared
    // stopMonitoring with an empty array stops every activity, so call sites
    // check their list for emptiness first.
    private let center = DeviceActivityCenter()

    static let spentEvent = DeviceActivityEvent.Name("breakSpent")

    private static let activityPrefix = "break-"

    static func ruleId(from activity: DeviceActivityName) -> UUID? {
        guard activity.rawValue.hasPrefix(activityPrefix) else { return nil }
        return UUID(uuidString: String(activity.rawValue.dropFirst(activityPrefix.count)))
    }

    private func activity(for rule: BreakRule) -> DeviceActivityName {
        .init(Self.activityPrefix + rule.id.uuidString)
    }

    // MARK: Arming

    // Rearms monitoring to match the stored rules. Diffs against the last
    // armed state and restarts only rules whose definition changed: a restart
    // mid-window drops the window until the schedule next fires.
    func syncMonitoring(now: Date = Date()) {
        let rules = store.breakRules
        let armed = store.armedBreaks?.rules ?? []
        let armedById = Dictionary(uniqueKeysWithValues: armed.map { ($0.id, $0) })

        let currentIds = Set(rules.map(\.id))
        let removed = armed.filter { !currentIds.contains($0.id) }
        if !removed.isEmpty {
            center.stopMonitoring(removed.map { activity(for: $0) })
            for rule in removed {
                clearActive(rule.id)
                forgetWindow(rule.id)
            }
        }

        for rule in rules {
            if armedById[rule.id] == rule { continue }
            center.stopMonitoring([activity(for: rule)])
            clearActive(rule.id)
            suppressCurrentWindow(rule, now: now)
            try? center.startMonitoring(
                activity(for: rule),
                during: schedule(for: rule),
                events: events(for: rule)
            )
        }

        store.armedBreaks = ArmedBreaks(rules: rules)
    }

    // Protection toggled off: stop the schedules and forget open windows.
    func stopAll() {
        let rules = store.breakRules
        if !rules.isEmpty {
            center.stopMonitoring(rules.map { activity(for: $0) })
        }
        store.activeBreaks = [:]
        store.openedBreakWindows = [:]
        store.armedBreaks = nil
    }

    private func schedule(for rule: BreakRule) -> DeviceActivitySchedule {
        let end = (rule.startMinuteOfDay + rule.windowMinutes) % (24 * 60)
        return DeviceActivitySchedule(
            intervalStart: DateComponents(hour: rule.startHour, minute: rule.startMinute),
            intervalEnd: DateComponents(hour: end / 60, minute: end % 60),
            repeats: true
        )
    }

    private func events(for rule: BreakRule) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        [
            Self.spentEvent: DeviceActivityEvent(
                applications: rule.selection.applicationTokens,
                categories: rule.selection.categoryTokens,
                webDomains: rule.selection.webDomainTokens,
                threshold: DateComponents(minute: rule.minutes)
            )
        ]
    }

    // MARK: Window state

    func rule(withId id: UUID) -> BreakRule? {
        store.breakRules.first { $0.id == id }
    }

    // Start of the rule's window containing `now`, nil when outside it. A
    // window that runs past midnight starts on the previous day, so both days
    // are tried.
    private func windowStart(for rule: BreakRule, now: Date) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for dayOffset in [0, -1] {
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                let start = calendar.date(byAdding: .minute, value: rule.startMinuteOfDay, to: day)
            else { continue }
            let end = start.addingTimeInterval(TimeInterval(rule.windowMinutes * 60))
            if start <= now, now < end { return start }
        }
        return nil
    }

    // The window end is wall-clock, not `now` plus the length: a callback that
    // arrives late must not push the end past the scheduled window.
    func markActive(_ id: UUID, now: Date = Date()) {
        guard let rule = rule(withId: id) else { return }
        let start = windowStart(for: rule, now: now)
        var active = store.activeBreaks
        active[id.uuidString] = (start ?? now)
            .addingTimeInterval(TimeInterval(rule.windowMinutes * 60))
        store.activeBreaks = active
        var opened = store.openedBreakWindows
        opened[id.uuidString] = start ?? now
        store.openedBreakWindows = opened
    }

    func clearActive(_ id: UUID) {
        var active = store.activeBreaks
        guard active.removeValue(forKey: id.uuidString) != nil else { return }
        store.activeBreaks = active
    }

    // Foreground backstop for a window end the monitor extension missed.
    func clearLapsedActive(now: Date = Date()) {
        let active = store.activeBreaks
        let live = active.filter { $0.value > now }
        if live.count != active.count {
            store.activeBreaks = live
        }
    }

    // Foreground backstop for a window start the monitor extension missed: the
    // extension can be killed for memory exactly when a window opens, which
    // would otherwise cost the whole day's break with no way to recover. The
    // opened-window record keeps a window that already spent its minutes from
    // reopening here.
    func openDueActive(now: Date = Date()) {
        for rule in store.breakRules {
            guard store.activeBreaks[rule.id.uuidString] == nil else { continue }
            guard let start = windowStart(for: rule, now: now) else { continue }
            guard store.openedBreakWindows[rule.id.uuidString] != start else { continue }
            markActive(rule.id, now: now)
        }
    }

    // A re-armed rule drops the window it is in until the schedule next fires,
    // so that window counts as opened and the backstop leaves it alone.
    private func suppressCurrentWindow(_ rule: BreakRule, now: Date) {
        var opened = store.openedBreakWindows
        if let start = windowStart(for: rule, now: now) {
            opened[rule.id.uuidString] = start
        } else {
            opened.removeValue(forKey: rule.id.uuidString)
        }
        store.openedBreakWindows = opened
    }

    private func forgetWindow(_ id: UUID) {
        var opened = store.openedBreakWindows
        guard opened.removeValue(forKey: id.uuidString) != nil else { return }
        store.openedBreakWindows = opened
    }

    // MARK: Shield inputs

    // Lapsed entries are filtered here as well, so a missed end callback
    // cannot hold a shield open past the next refresh.
    var activeRules: [BreakRule] {
        let now = Date()
        let ids = Set(
            store.activeBreaks
                .filter { $0.value > now }
                .keys
                .compactMap { UUID(uuidString: $0) }
        )
        guard !ids.isEmpty else { return [] }
        return store.breakRules.filter { ids.contains($0.id) }
    }
}

// Snapshot of what monitoring was last armed with; syncMonitoring diffs
// against it so unchanged rules keep their schedules.
struct ArmedBreaks: Codable, Equatable {
    var rules: [BreakRule]
}
