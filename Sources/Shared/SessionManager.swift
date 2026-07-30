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

    private var usageEvent: DeviceActivityEvent.Name { .init(AppGroup.usageEventName) }
    private var warnEvent: DeviceActivityEvent.Name { .init(AppGroup.sessionWarnEventName) }

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

    func gateCheck(for target: UnlockTarget?, now: Date = Date()) -> GateResult {
        let sessions = store.activeSessions.filter { $0.wallClockEnd > now }
        if let target, sessions.contains(where: { $0.target == target }) {
            return .sessionActive
        }
        let cooldown = store.cooldownMinutes
        if cooldown > 0, let lastEnd = store.lastSessionEnd {
            let readyAt = lastEnd.addingTimeInterval(TimeInterval(cooldown * 60))
            if readyAt > now { return .coolingDown(remaining: readyAt.timeIntervalSince(now)) }
        }
        let cap = store.dailyCap
        if cap > 0, store.sessionsToday(now: now) >= cap {
            return .capReached(cap: cap)
        }
        return .allowed
    }

    // MARK: Grant

    // Unshields the target and arms DeviceActivity: a usage threshold at the
    // configured duration, plus an interval end as the re-lock backstop.
    func startSession(for target: UnlockTarget, now: Date = Date()) throws {
        let minutes = store.durationMinutes
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
            usageEvent: DeviceActivityEvent(
                applications: apps,
                categories: categories,
                webDomains: domains,
                threshold: DateComponents(minute: minutes)
            )
        ]
        let warn = store.sessionWarnMinutes
        if warn > 0, minutes - warn >= 1 {
            events[warnEvent] = DeviceActivityEvent(
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
            wallClockEnd: end
        ))
        store.activeSessions = sessions
        store.pendingUnlock = nil
        store.incrementSessionsToday(now: now)
        reapplyShields(now: now)
    }

    // MARK: End

    // Ends one session by id. Called by the monitor extension on threshold or
    // interval end.
    func endSession(id: String, now: Date = Date()) {
        var sessions = store.activeSessions
        guard sessions.contains(where: { $0.id == id }) else { return }
        center.stopMonitoring([activity(for: id)])
        sessions.removeAll { $0.id == id }
        store.activeSessions = sessions
        store.lastSessionEnd = now
        reapplyShields(now: now)
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
        store.lastSessionEnd = now
        reapplyShields(now: now)
    }

    // Re-applies shields after a blocklist edit, respecting live sessions.
    func refreshShields(now: Date = Date()) {
        reapplyShields(now: now)
    }

    // Shields everything except items with a live session.
    private func reapplyShields(now: Date) {
        guard store.protectionEnabled else { return }
        let unlocked = store.activeSessions
            .filter { $0.wallClockEnd > now }
            .map(\.target)
        ShieldController.shared.applyShields(excluding: unlocked)
    }
}
