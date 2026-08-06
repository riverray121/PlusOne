import Foundation

extension Notification.Name {
    // Posted after any pending-queue mutation (queue, cancel, apply, resolve).
    static let plusOnePendingChangesChanged = Notification.Name("plusOnePendingChangesChanged")
}

// The single path for protection-relevant settings changes. Strengthening
// applies immediately; weakening waits out the configured delay. Direction is
// judged against the stored value at proposal time, so a queued change never
// re-evaluates and late application always errs toward more protection.
struct ProtectionGate {
    static let shared = ProtectionGate()

    private let store = SharedStore.shared

    enum Outcome {
        case applied
        case queued(PendingChange)
    }

    // With no delay configured and no friend paired, every change is
    // immediate.
    private var gatingActive: Bool {
        store.delayMinutes > 0 || store.friendPaired
    }

    func propose(_ kind: PendingChange.Kind, now: Date = Date()) -> Outcome {
        guard gatingActive, isWeakening(kind) else {
            apply(kind)
            return .applied
        }
        // No delay set (paired-only gating): no countdown, the change waits
        // on approval alone.
        let appliesAt = store.delayMinutes > 0
            ? now.addingTimeInterval(TimeInterval(store.delayMinutes * 60))
            : nil
        let change = PendingChange(
            id: UUID(),
            createdAt: now,
            appliesAt: appliesAt,
            summary: Self.summary(for: kind),
            kind: kind
        )
        var pending = store.pendingChanges
        if let key = change.replaceKey {
            pending.removeAll { $0.replaceKey == key }
        }
        pending.append(change)
        store.pendingChanges = pending
        notifyPendingChanged()
        return .queued(change)
    }

    // Applies every pending change whose countdown has passed, oldest first.
    // Runs on the foreground pass; there is no background job, so a change
    // can only apply late, never early.
    func applyDue(now: Date = Date()) {
        let pending = store.pendingChanges
        let due = pending
            .filter { ($0.appliesAt ?? .distantFuture) <= now }
            .sorted { $0.createdAt < $1.createdAt }
        guard !due.isEmpty else { return }
        store.pendingChanges = pending.filter { change in
            !due.contains { $0.id == change.id }
        }
        for change in due {
            apply(change.kind)
        }
        notifyPendingChanged()
    }

    // Marks a queued change as sent to the paired friends. Sending is an
    // explicit user action; queuing alone notifies no one.
    func requestApproval(_ id: UUID) {
        store.pendingChanges = store.pendingChanges.map { change in
            guard change.id == id else { return change }
            var sent = change
            sent.approvalRequested = true
            return sent
        }
        notifyPendingChanged()
    }

    // Cancelling keeps the stronger settings; always immediate.
    func cancel(_ id: UUID) {
        store.pendingChanges = store.pendingChanges.filter { $0.id != id }
        notifyPendingChanged()
    }

    // Friend verdict on a pending change. Approved applies immediately,
    // whatever its countdown says; denied discards it. Either way the change
    // leaves the queue.
    func resolve(_ id: UUID, approved: Bool) {
        guard let change = store.pendingChanges.first(where: { $0.id == id }) else { return }
        store.pendingChanges = store.pendingChanges.filter { $0.id != id }
        if approved {
            apply(change.kind)
        }
        notifyPendingChanged()
    }

    // Lets the app's CloudKit layer mirror the queue to the paired friend.
    // Extensions include this code but never mutate the queue.
    private func notifyPendingChanged() {
        NotificationCenter.default.post(name: .plusOnePendingChangesChanged, object: nil)
    }

    private func isWeakening(_ kind: PendingChange.Kind) -> Bool {
        switch kind {
        case .setProtection(let on):
            return !on && store.protectionEnabled
        case .removeSelfieItems(let removed), .removeHardItems(let removed):
            return removed.itemCount > 0
        case .setDuration(let minutes):
            return minutes > store.durationMinutes
        case .setCooldown(let minutes):
            return minutes < store.cooldownMinutes
        case .setDailyCap(let cap):
            let current = store.dailyCap
            return current > 0 && (cap == 0 || cap > current)
        case .setAdultFilter(let on):
            return !on && store.adultFilterEnabled
        case .upsertSelfieRule(let rule):
            // A new rule adds blocking and is immediate. On an existing rule,
            // any change that grants more or easier unlocks queues.
            guard let existing = store.selfieRules.first(where: { $0.id == rule.id }) else {
                return false
            }
            let capWeakened = existing.dailyCap > 0
                && (rule.dailyCap == 0 || rule.dailyCap > existing.dailyCap)
            return rule.durationMinutes > existing.durationMinutes
                || rule.cooldownMinutes < existing.cooldownMinutes
                || capWeakened
                || existing.selection.subtracting(rule.selection).itemCount > 0
        case .deleteSelfieRule(let id):
            return store.selfieRules.contains { $0.id == id }
        case .upsertTimeLimitRule(let rule):
            guard let existing = store.timeLimitRules.first(where: { $0.id == rule.id }) else {
                return false
            }
            return rule.minutes > existing.minutes
                || (existing.period == .day && rule.period == .hour)
                || existing.selection.subtracting(rule.selection).itemCount > 0
        case .deleteTimeLimitRule(let id):
            return store.timeLimitRules.contains { $0.id == id }
        case .upsertBreakRule(let rule):
            // Inverse of time limits: a break grants free time, so creating
            // one, adding minutes, window, or items, or moving the start
            // weakens. A start-time move must queue because an instant move
            // re-arms the schedule and would grant a second window the same
            // day.
            guard let existing = store.breakRules.first(where: { $0.id == rule.id }) else {
                return true
            }
            return rule.minutes > existing.minutes
                || rule.windowMinutes > existing.windowMinutes
                || rule.startMinuteOfDay != existing.startMinuteOfDay
                || rule.selection.subtracting(existing.selection).itemCount > 0
        case .deleteBreakRule:
            return false
        case .setDelay(let minutes):
            return minutes < store.delayMinutes
        case .setDeletePrevention(let on):
            return !on && store.deletePreventionEnabled
        case .unpairFriend:
            return true
        }
    }

    private func apply(_ kind: PendingChange.Kind) {
        switch kind {
        case .setProtection(let on):
            // Flag first and synchronously: refreshShields callers observe it
            // immediately. Screen Time XPC calls block; keep them off the
            // calling thread.
            store.protectionEnabled = on
            Task.detached {
                if on {
                    ShieldController.shared.applyShields()
                    TimeLimitManager.shared.syncMonitoring()
                    BreakManager.shared.syncMonitoring()
                } else {
                    SessionManager.shared.endAllSessions()
                    TimeLimitManager.shared.stopAll()
                    BreakManager.shared.stopAll()
                    ShieldController.shared.clearShields()
                }
            }
        case .removeSelfieItems(let removed):
            store.selfieRules = store.selfieRules.map { rule in
                var updated = rule
                updated.selection = rule.selection.subtracting(removed)
                return updated
            }
            SessionManager.shared.refreshShields()
        case .removeHardItems(let removed):
            store.hardSelection = store.hardSelection.subtracting(removed)
            SessionManager.shared.refreshShields()
        case .setDuration(let minutes):
            store.selfieRules = store.selfieRules.map { rule in
                var updated = rule
                updated.durationMinutes = minutes
                return updated
            }
        case .setCooldown(let minutes):
            store.selfieRules = store.selfieRules.map { rule in
                var updated = rule
                updated.cooldownMinutes = minutes
                return updated
            }
        case .setDailyCap(let cap):
            store.selfieRules = store.selfieRules.map { rule in
                var updated = rule
                updated.dailyCap = cap
                return updated
            }
        case .upsertSelfieRule(let rule):
            var rules = store.selfieRules
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[index] = rule
            } else {
                rules.append(rule)
            }
            store.selfieRules = rules
            SessionManager.shared.refreshShields()
        case .deleteSelfieRule(let id):
            store.selfieRules = store.selfieRules.filter { $0.id != id }
            SessionManager.shared.refreshShields()
        case .setAdultFilter(let on):
            store.adultFilterEnabled = on
            SessionManager.shared.refreshShields()
        case .upsertTimeLimitRule(let rule):
            var rules = store.timeLimitRules
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[index] = rule
            } else {
                rules.append(rule)
            }
            store.timeLimitRules = rules
            resyncLimits()
        case .deleteTimeLimitRule(let id):
            store.timeLimitRules = store.timeLimitRules.filter { $0.id != id }
            resyncLimits()
        case .upsertBreakRule(let rule):
            var rules = store.breakRules
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[index] = rule
            } else {
                rules.append(rule)
            }
            store.breakRules = rules
            resyncBreaks()
        case .deleteBreakRule(let id):
            store.breakRules = store.breakRules.filter { $0.id != id }
            resyncBreaks()
        case .setDelay(let minutes):
            store.delayMinutes = minutes
        case .setDeletePrevention(let on):
            store.deletePreventionEnabled = on
            ShieldController.shared.setDenyAppRemoval(on)
        case .unpairFriend:
            store.friendPaired = false
        }
    }

    // Screen Time XPC calls block; keep them off the calling thread.
    private func resyncLimits() {
        guard store.protectionEnabled else { return }
        Task.detached {
            TimeLimitManager.shared.syncMonitoring()
            SessionManager.shared.refreshShields()
        }
    }

    // Screen Time XPC calls block; keep them off the calling thread.
    private func resyncBreaks() {
        guard store.protectionEnabled else { return }
        Task.detached {
            BreakManager.shared.syncMonitoring()
            SessionManager.shared.refreshShields()
        }
    }

    private static func summary(for kind: PendingChange.Kind) -> String {
        switch kind {
        case .setProtection:
            return "Turn protection off"
        case .removeSelfieItems(let removed):
            return "Remove \(pluralItems(removed.itemCount)) from selfie-unlock blocks"
        case .removeHardItems(let removed):
            return "Remove \(pluralItems(removed.itemCount)) from hard blocks"
        case .setDuration(let minutes):
            return "Unlock duration to \(minutes) min"
        case .setCooldown(let minutes):
            return minutes == 0 ? "Turn cooldown off" : "Cooldown to \(minutes) min"
        case .setDailyCap(let cap):
            return cap == 0 ? "Turn daily cap off" : "Daily cap to \(cap) sessions"
        case .setAdultFilter:
            return "Turn adult website filter off"
        case .upsertSelfieRule(let rule):
            return "Selfie-unlock block: \(pluralItems(rule.itemCount)), \(rule.durationMinutes) min per pass"
        case .deleteSelfieRule:
            return "Delete a selfie-unlock block"
        case .upsertTimeLimitRule(let rule):
            return "Time limit to \(rule.minutes) min / \(rule.period.label)"
        case .deleteTimeLimitRule:
            return "Delete a time limit"
        case .upsertBreakRule(let rule):
            return "Scheduled break: \(pluralMinutes(rule.minutes)) at \(rule.timeLabel)"
        case .deleteBreakRule:
            return "Delete a scheduled break"
        case .setDelay(let minutes):
            return minutes == 0
                ? "Turn settings change delay off"
                : "Settings change delay to \(delayHoursLabel(minutes))"
        case .setDeletePrevention:
            return "Turn delete prevention off"
        case .unpairFriend:
            return "Unpair friend"
        }
    }
}
