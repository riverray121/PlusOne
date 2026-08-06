import Foundation
import DeviceActivity
import ManagedSettings

// Owns the unlock session lifecycle: gate checks, granting, and ending.
// Sessions are concurrent, one per unlocked item, each backed by its own
// DeviceActivity. Ending is also called from the monitor extension, so this
// lives in Shared.
struct SessionManager {
    static let shared = SessionManager()

    private let store = SharedStore.shared
    private let center = DeviceActivityCenter()

    private static let usageEvent = DeviceActivityEvent.Name(AppGroup.usageEventName)
    private static let warnEvent = DeviceActivityEvent.Name(AppGroup.sessionWarnEventName)

    private func activity(for id: String) -> DeviceActivityName {
        .init("\(AppGroup.activityName)-\(id)")
    }

    // DeviceActivity rejects schedules shorter than 15 minutes, so the wall
    // clock interval is a backstop; the real limit is the usage threshold.
    private static let minIntervalMinutes = 15

    enum GateResult: Equatable {
        case allowed
        case coolingDown(remaining: TimeInterval)
        case capReached(cap: Int)
        case sessionActive
    }

    // MARK: Gates

    // First rule whose selection contains the target; stored order breaks
    // ties so an older rule keeps governing an item that appears in two.
    func rule(containing target: UnlockTarget) -> SelfieRule? {
        store.selfieRules.first { $0.contains(target) }
    }

    func gateCheck(for target: UnlockTarget, now: Date = Date()) -> GateResult {
        let sessions = store.activeSessions.filter { $0.wallClockEnd > now }
        if sessions.contains(where: { $0.target == target }) {
            return .sessionActive
        }
        guard let rule = rule(containing: target) else { return .allowed }
        if rule.cooldownMinutes > 0, let lastEnd = store.sessionEnds[rule.id.uuidString] {
            let readyAt = lastEnd.addingTimeInterval(TimeInterval(rule.cooldownMinutes * 60))
            if readyAt > now { return .coolingDown(remaining: readyAt.timeIntervalSince(now)) }
        }
        if rule.dailyCap > 0, store.sessionsToday(ruleId: rule.id, now: now) >= rule.dailyCap {
            return .capReached(cap: rule.dailyCap)
        }
        return .allowed
    }

    // MARK: Grant

    // Unshields the target and arms DeviceActivity: a usage threshold at the
    // rule's duration, plus an interval end as the re-lock backstop.
    func startSession(for target: UnlockTarget, now: Date = Date()) throws {
        let rule = rule(containing: target)
        let minutes = rule?.durationMinutes ?? 5
        let intervalMinutes = max(Self.minIntervalMinutes, minutes + 1)
        let end = now.addingTimeInterval(TimeInterval(intervalMinutes * 60))
        let id = UUID().uuidString

        var apps: Set<ApplicationToken> = []
        var domains: Set<WebDomainToken> = []
        var categories: Set<ActivityCategoryToken> = []
        switch target {
        case .application(let token): apps.insert(token)
        case .webDomain(let token): domains.insert(token)
        case .category(let token): categories.insert(token)
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now),
            intervalEnd: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end),
            repeats: false
        )
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
            Self.usageEvent: DeviceActivityEvent(
                applications: apps,
                categories: categories,
                webDomains: domains,
                threshold: DateComponents(minute: minutes)
            )
        ]
        let warn = rule?.warnMinutes ?? 1
        if warn > 0, minutes - warn >= 1 {
            events[Self.warnEvent] = DeviceActivityEvent(
                applications: apps,
                categories: categories,
                webDomains: domains,
                threshold: DateComponents(minute: minutes - warn)
            )
        }
        try center.startMonitoring(activity(for: id), during: schedule, events: events)

        var sessions = store.activeSessions
        sessions.append(UnlockSession(
            id: id,
            target: target,
            startedAt: now,
            usageMinutes: minutes,
            wallClockEnd: end,
            ruleId: rule?.id,
            warnMinutes: warn
        ))
        store.activeSessions = sessions
        store.pendingUnlock = nil
        if let rule {
            store.incrementSessionsToday(ruleId: rule.id, now: now)
        }
        refreshShields(now: now)
    }

    // MARK: End

    // Ends one session by id. Called by the monitor extension on threshold or
    // interval end.
    func endSession(id: String, now: Date = Date()) {
        var sessions = store.activeSessions
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        center.stopMonitoring([activity(for: id)])
        sessions.removeAll { $0.id == id }
        store.activeSessions = sessions
        markSessionEnd(session, now: now)
        refreshShields(now: now)
    }

    // Foreground backstop: re-lock any session whose wall clock window lapsed
    // while DeviceActivity failed to fire.
    func endExpiredSessions(now: Date = Date()) {
        for session in store.activeSessions where session.wallClockEnd <= now {
            endSession(id: session.id, now: now)
        }
    }

    // Protection toggled off: tear everything down.
    func endAllSessions(now: Date = Date()) {
        let sessions = store.activeSessions
        guard !sessions.isEmpty else { return }
        center.stopMonitoring(sessions.map { activity(for: $0.id) })
        store.activeSessions = []
        for session in sessions { markSessionEnd(session, now: now) }
        refreshShields(now: now)
    }

    // Stamps the rule's cooldown clock.
    private func markSessionEnd(_ session: UnlockSession, now: Date) {
        guard let ruleId = session.ruleId else { return }
        var ends = store.sessionEnds
        ends[ruleId.uuidString] = now
        store.sessionEnds = ends
    }

    // Shields everything except items with a live session. Callers re-apply
    // after any edit that changes what should be shielded.
    func refreshShields(now: Date = Date()) {
        guard store.protectionEnabled else { return }
        let unlocked = store.activeSessions
            .filter { $0.wallClockEnd > now }
            .map(\.target)
        ShieldController.shared.applyShields(excluding: unlocked)
    }
}
