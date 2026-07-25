import Foundation
import DeviceActivity
import ManagedSettings

// Owns the unlock session lifecycle: gate checks, granting, and ending.
// Ending is also called from the monitor extension, so it lives in Shared.
struct SessionManager {
    static let shared = SessionManager()

    private let store = SharedStore.shared
    private let center = DeviceActivityCenter()

    private var activity: DeviceActivityName { .init(AppGroup.activityName) }
    private var usageEvent: DeviceActivityEvent.Name { .init(AppGroup.usageEventName) }

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

    func gateCheck(now: Date = Date()) -> GateResult {
        if let session = store.activeSession, session.wallClockEnd > now {
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
        let event = DeviceActivityEvent(
            applications: apps,
            categories: categories,
            webDomains: domains,
            threshold: DateComponents(minute: minutes)
        )

        center.stopMonitoring([activity])
        try center.startMonitoring(activity, during: schedule, events: [usageEvent: event])

        store.activeSession = UnlockSession(
            target: target,
            startedAt: now,
            usageMinutes: minutes,
            wallClockEnd: end
        )
        store.pendingUnlock = nil
        store.incrementSessionsToday(now: now)
        ShieldController.shared.applyShields(excluding: target)
    }

    // MARK: End

    // Re-locks everything. Called by the monitor extension on threshold or
    // interval end, and by the app as a foreground backstop.
    func endSession(now: Date = Date()) {
        center.stopMonitoring([activity])
        if store.activeSession != nil {
            store.activeSession = nil
            store.lastSessionEnd = now
        }
        if store.protectionEnabled {
            ShieldController.shared.applyShields()
        }
    }

    // Foreground backstop: if the wall clock window lapsed while DeviceActivity
    // failed to fire, re-lock on next app open.
    func endSessionIfExpired(now: Date = Date()) {
        guard let session = store.activeSession, session.wallClockEnd <= now else { return }
        endSession(now: now)
    }
}
