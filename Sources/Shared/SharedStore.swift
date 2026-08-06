import Foundation
import FamilyControls

// App Group backed state shared by the app and extensions. Every process
// reads and writes through this type; nothing else touches the suite.
struct SharedStore {
    static let shared = SharedStore()

    private let defaults = UserDefaults(suiteName: AppGroup.suite)!
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key {
        static let selection = "selection"
        static let protectionEnabled = "protectionEnabled"
        static let durationMinutes = "durationMinutes"
        static let cooldownMinutes = "cooldownMinutes"
        static let dailyCap = "dailyCap"
        static let adultFilter = "adultFilter"
        static let hardSelection = "hardSelection"
        static let timeLimitRules = "timeLimitRules"
        static let exhaustedLimits = "exhaustedLimits"
        static let sessionWarnMinutes = "sessionWarnMinutes"
        static let armedLimits = "armedLimits"
        static let breakRules = "breakRules"
        static let activeBreaks = "activeBreaks"
        static let armedBreaks = "armedBreaks"
        static let delayMinutes = "delayMinutes"
        static let pendingChanges = "pendingChanges"
        static let deletePrevention = "deletePrevention"
        static let friendPaired = "friendPaired"
        static let pendingUnlock = "pendingUnlock"
        static let activeSessions = "activeSessions"
        static let selfieRules = "selfieRules"
        static let sessionsTodayById = "sessionsTodayById"
        static let sessionsDay = "sessionsDay"
        static let sessionEnds = "sessionEnds"
    }

    // Codable values are stored as JSON. A missing or unreadable value reads
    // as nil, and writing nil clears the key.
    private func decoded<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(try? encoder.encode(value), forKey: key)
    }

    // MARK: Selfie-unlock rules

    // Missing key means the suite still holds the single-selection legacy
    // layout; it reads as one rule carrying the legacy global settings, under
    // a fixed id so per-rule counters stay stable. The first write persists
    // real rules and ends the synthesis.
    var selfieRules: [SelfieRule] {
        get {
            if let rules: [SelfieRule] = decoded(Key.selfieRules) { return rules }
            let legacy = selection
            guard legacy.itemCount > 0 else { return [] }
            var rule = SelfieRule()
            rule.id = SelfieRule.legacyId
            rule.selection = legacy
            rule.durationMinutes = durationMinutes
            rule.cooldownMinutes = cooldownMinutes
            rule.dailyCap = dailyCap
            rule.warnMinutes = sessionWarnMinutes
            return [rule]
        }
        nonmutating set { encode(newValue, forKey: Key.selfieRules) }
    }

    var protectionEnabled: Bool {
        get { defaults.bool(forKey: Key.protectionEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.protectionEnabled) }
    }

    // MARK: Legacy single-selection layout

    // Read only to synthesize selfieRules and to apply queued changes
    // recorded against the global settings.

    var selection: FamilyActivitySelection {
        get { decoded(Key.selection) ?? FamilyActivitySelection() }
        nonmutating set { encode(newValue, forKey: Key.selection) }
    }

    // Minutes of usage granted per pass.
    var durationMinutes: Int {
        get { defaults.object(forKey: Key.durationMinutes) as? Int ?? 5 }
        nonmutating set { defaults.set(newValue, forKey: Key.durationMinutes) }
    }

    // Minutes required between sessions. 0 = off.
    var cooldownMinutes: Int {
        get { defaults.integer(forKey: Key.cooldownMinutes) }
        nonmutating set { defaults.set(newValue, forKey: Key.cooldownMinutes) }
    }

    // Max sessions per calendar day. 0 = off.
    var dailyCap: Int {
        get { defaults.integer(forKey: Key.dailyCap) }
        nonmutating set { defaults.set(newValue, forKey: Key.dailyCap) }
    }

    // Minutes-remaining mark for the session warning notification. 0 = off.
    var sessionWarnMinutes: Int {
        get { defaults.object(forKey: Key.sessionWarnMinutes) as? Int ?? 1 }
        nonmutating set { defaults.set(newValue, forKey: Key.sessionWarnMinutes) }
    }

    // MARK: Settings

    // Apple's machine-learned adult-content web filter. Hard block, no
    // selfie unlock.
    var adultFilterEnabled: Bool {
        get { defaults.bool(forKey: Key.adultFilter) }
        nonmutating set { defaults.set(newValue, forKey: Key.adultFilter) }
    }

    // Second picker selection: hard-blocked items. Always shielded, and the
    // shield offers no unlock.
    var hardSelection: FamilyActivitySelection {
        get { decoded(Key.hardSelection) ?? FamilyActivitySelection() }
        nonmutating set { encode(newValue, forKey: Key.hardSelection) }
    }

    // MARK: Anti-tamper

    // Minutes a weakening change waits before applying. 0 = off.
    var delayMinutes: Int {
        get { defaults.integer(forKey: Key.delayMinutes) }
        nonmutating set { defaults.set(newValue, forKey: Key.delayMinutes) }
    }

    // Weakening changes waiting out the delay. Written only by ProtectionGate.
    var pendingChanges: [PendingChange] {
        get { decoded(Key.pendingChanges) ?? [] }
        nonmutating set { encode(newValue, forKey: Key.pendingChanges) }
    }

    // Mirrors the OS app-removal restriction held on the managed settings
    // store. The restriction is device-wide.
    var deletePreventionEnabled: Bool {
        get { defaults.bool(forKey: Key.deletePrevention) }
        nonmutating set { defaults.set(newValue, forKey: Key.deletePrevention) }
    }

    // Whether a friend is paired for approvals. Mirrored from CloudKit by the
    // app target; ProtectionGate only reads it.
    var friendPaired: Bool {
        get { defaults.bool(forKey: Key.friendPaired) }
        nonmutating set { defaults.set(newValue, forKey: Key.friendPaired) }
    }

    // MARK: Time limits

    var timeLimitRules: [TimeLimitRule] {
        get { decoded(Key.timeLimitRules) ?? [] }
        nonmutating set { encode(newValue, forKey: Key.timeLimitRules) }
    }

    // Rules whose budget is spent this period, keyed by rule id, with the
    // wall-clock reset time as a backstop for a missed period-start callback.
    var exhaustedLimits: [String: Date] {
        get { decoded(Key.exhaustedLimits) ?? [:] }
        nonmutating set { encode(newValue, forKey: Key.exhaustedLimits) }
    }

    var armedLimits: ArmedLimits? {
        get { decoded(Key.armedLimits) }
        nonmutating set { encode(newValue, forKey: Key.armedLimits) }
    }

    // MARK: Scheduled breaks

    var breakRules: [BreakRule] {
        get { decoded(Key.breakRules) ?? [] }
        nonmutating set { encode(newValue, forKey: Key.breakRules) }
    }

    // Breaks whose window is open, keyed by rule id, with the wall-clock
    // window end as a backstop for a missed window-end callback.
    var activeBreaks: [String: Date] {
        get { decoded(Key.activeBreaks) ?? [:] }
        nonmutating set { encode(newValue, forKey: Key.activeBreaks) }
    }

    var armedBreaks: ArmedBreaks? {
        get { decoded(Key.armedBreaks) }
        nonmutating set { encode(newValue, forKey: Key.armedBreaks) }
    }

    // MARK: Unlock flow state

    // Written by the shield action extension; consumed by the app's capture flow.
    var pendingUnlock: UnlockTarget? {
        get { decoded(Key.pendingUnlock) }
        nonmutating set { encode(newValue, forKey: Key.pendingUnlock) }
    }

    // Concurrent sessions: one per unlocked item, each with its own timer.
    var activeSessions: [UnlockSession] {
        get { decoded(Key.activeSessions) ?? [] }
        nonmutating set { encode(newValue, forKey: Key.activeSessions) }
    }

    // When each rule's last session ended, keyed by rule id; drives per-rule
    // cooldowns.
    var sessionEnds: [String: Date] {
        get { decoded(Key.sessionEnds) ?? [:] }
        nonmutating set { encode(newValue, forKey: Key.sessionEnds) }
    }

    // MARK: Daily counters

    // Per-rule session counts, scoped to a day string so they reset at
    // midnight without needing a scheduled job.
    func sessionsToday(ruleId: UUID, now: Date = Date()) -> Int {
        guard defaults.string(forKey: Key.sessionsDay) == Self.dayString(now) else { return 0 }
        let counts: [String: Int] = decoded(Key.sessionsTodayById) ?? [:]
        return counts[ruleId.uuidString] ?? 0
    }

    func incrementSessionsToday(ruleId: UUID, now: Date = Date()) {
        let day = Self.dayString(now)
        var counts: [String: Int] = defaults.string(forKey: Key.sessionsDay) == day
            ? (decoded(Key.sessionsTodayById) ?? [:])
            : [:]
        counts[ruleId.uuidString, default: 0] += 1
        defaults.set(day, forKey: Key.sessionsDay)
        encode(counts, forKey: Key.sessionsTodayById)
    }

    private static func dayString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year!)-\(components.month!)-\(components.day!)"
    }
}

// A granted unlock window. wallClockEnd is a backstop; the primary limit is
// usage-based and enforced by DeviceActivity. `id` names this session's
// DeviceActivity so concurrent sessions end independently.
struct UnlockSession: Codable {
    let id: String
    let target: UnlockTarget
    let startedAt: Date
    let usageMinutes: Int
    let wallClockEnd: Date
    // Rule that granted the session; nil when no rule contained the target.
    let ruleId: UUID?
    // Warning mark captured at grant so mid-session edits don't shift it.
    let warnMinutes: Int

    init(
        id: String,
        target: UnlockTarget,
        startedAt: Date,
        usageMinutes: Int,
        wallClockEnd: Date,
        ruleId: UUID?,
        warnMinutes: Int
    ) {
        self.id = id
        self.target = target
        self.startedAt = startedAt
        self.usageMinutes = usageMinutes
        self.wallClockEnd = wallClockEnd
        self.ruleId = ruleId
        self.warnMinutes = warnMinutes
    }

    // ruleId and warnMinutes decode leniently so sessions persisted without
    // the keys still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        target = try container.decode(UnlockTarget.self, forKey: .target)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        usageMinutes = try container.decode(Int.self, forKey: .usageMinutes)
        wallClockEnd = try container.decode(Date.self, forKey: .wallClockEnd)
        ruleId = try container.decodeIfPresent(UUID.self, forKey: .ruleId)
        warnMinutes = try container.decodeIfPresent(Int.self, forKey: .warnMinutes) ?? 1
    }

    private enum CodingKeys: String, CodingKey {
        case id, target, startedAt, usageMinutes, wallClockEnd, ruleId, warnMinutes
    }
}
