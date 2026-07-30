import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

// Arms DeviceActivity monitoring for time-limit rules and tracks which rules
// have spent their budget. Exhausted rules shield like hard blocks until the
// period resets; the monitor extension flips them from outside the app.
struct TimeLimitManager {
    static let shared = TimeLimitManager()

    private let store = SharedStore.shared
    // stopMonitoring with an empty array stops every activity, so call sites
    // check their list for emptiness first.
    private let center = DeviceActivityCenter()

    static let limitEvent = DeviceActivityEvent.Name("limit")
    static let warnEvent = DeviceActivityEvent.Name("warn")

    private static let activityPrefix = "timeLimit-"

    static func ruleId(from activity: DeviceActivityName) -> UUID? {
        guard activity.rawValue.hasPrefix(activityPrefix) else { return nil }
        return UUID(uuidString: String(activity.rawValue.dropFirst(activityPrefix.count)))
    }

    private func activity(for rule: TimeLimitRule) -> DeviceActivityName {
        .init(Self.activityPrefix + rule.id.uuidString)
    }

    // MARK: Arming

    // Rearms monitoring to match the stored rules. Diffs against the last
    // armed state and restarts only rules whose definition changed: usage
    // thresholds count from when monitoring starts, so a restart wipes the
    // minutes already counted this period.
    func syncMonitoring() {
        let rules = store.timeLimitRules
        let armed = store.armedLimits?.rules ?? []
        let armedById = Dictionary(uniqueKeysWithValues: armed.map { ($0.id, $0) })

        let currentIds = Set(rules.map(\.id))
        let removed = armed.filter { !currentIds.contains($0.id) }
        if !removed.isEmpty {
            center.stopMonitoring(removed.map { activity(for: $0) })
            for rule in removed { clearExhausted(rule.id) }
        }

        for rule in rules {
            if armedById[rule.id] == rule { continue }
            center.stopMonitoring([activity(for: rule)])
            clearExhausted(rule.id)
            try? center.startMonitoring(
                activity(for: rule),
                during: schedule(for: rule.period),
                events: events(for: rule)
            )
        }

        store.armedLimits = ArmedLimits(rules: rules)
    }

    // Protection toggled off: stop counting and forget spent state.
    func stopAll() {
        let rules = store.timeLimitRules
        if !rules.isEmpty {
            center.stopMonitoring(rules.map { activity(for: $0) })
        }
        store.exhaustedLimits = [:]
        store.armedLimits = nil
    }

    private func schedule(for period: TimeLimitRule.Period) -> DeviceActivitySchedule {
        switch period {
        case .hour:
            return DeviceActivitySchedule(
                intervalStart: DateComponents(minute: 0),
                intervalEnd: DateComponents(minute: 59),
                repeats: true
            )
        case .day:
            return DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )
        }
    }

    // Both thresholds ride on one activity, so a warning costs no extra slot
    // against the system's monitored-activity cap.
    private func events(for rule: TimeLimitRule) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
            Self.limitEvent: DeviceActivityEvent(
                applications: rule.selection.applicationTokens,
                categories: rule.selection.categoryTokens,
                webDomains: rule.selection.webDomainTokens,
                threshold: DateComponents(minute: rule.minutes)
            )
        ]
        if rule.warnMinutes > 0, rule.minutes - rule.warnMinutes >= 1 {
            events[Self.warnEvent] = DeviceActivityEvent(
                applications: rule.selection.applicationTokens,
                categories: rule.selection.categoryTokens,
                webDomains: rule.selection.webDomainTokens,
                threshold: DateComponents(minute: rule.minutes - rule.warnMinutes)
            )
        }
        return events
    }

    // MARK: Spent state

    func rule(withId id: UUID) -> TimeLimitRule? {
        store.timeLimitRules.first { $0.id == id }
    }

    func markExhausted(_ id: UUID, now: Date = Date()) {
        guard let rule = rule(withId: id) else { return }
        var exhausted = store.exhaustedLimits
        exhausted[id.uuidString] = rule.nextReset(after: now)
        store.exhaustedLimits = exhausted
    }

    func clearExhausted(_ id: UUID) {
        var exhausted = store.exhaustedLimits
        guard exhausted.removeValue(forKey: id.uuidString) != nil else { return }
        store.exhaustedLimits = exhausted
    }

    // Foreground backstop for a period reset the monitor extension missed.
    func clearLapsedExhausted(now: Date = Date()) {
        let exhausted = store.exhaustedLimits
        let live = exhausted.filter { $0.value > now }
        if live.count != exhausted.count {
            store.exhaustedLimits = live
        }
    }

    // MARK: Shield inputs

    var exhaustedRules: [TimeLimitRule] {
        let ids = Set(store.exhaustedLimits.keys.compactMap { UUID(uuidString: $0) })
        guard !ids.isEmpty else { return [] }
        return store.timeLimitRules.filter { ids.contains($0.id) }
    }

    func exhaustedRule(containing token: ApplicationToken) -> TimeLimitRule? {
        exhaustedRules.first { $0.selection.applicationTokens.contains(token) }
    }

    func exhaustedRule(containing token: WebDomainToken) -> TimeLimitRule? {
        exhaustedRules.first { $0.selection.webDomainTokens.contains(token) }
    }

    func exhaustedRule(containing token: ActivityCategoryToken) -> TimeLimitRule? {
        exhaustedRules.first { $0.selection.categoryTokens.contains(token) }
    }
}

// Snapshot of what monitoring was last armed with; syncMonitoring diffs
// against it so unchanged rules keep their counted usage.
struct ArmedLimits: Codable, Equatable {
    var rules: [TimeLimitRule]
}
