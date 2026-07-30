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
        static let pendingUnlock = "pendingUnlock"
        static let activeSessions = "activeSessions"
        static let sessionsToday = "sessionsToday"
        static let sessionsDay = "sessionsDay"
        static let lastSessionEnd = "lastSessionEnd"
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

    // MARK: Selection

    var selection: FamilyActivitySelection {
        get { decoded(Key.selection) ?? FamilyActivitySelection() }
        nonmutating set { encode(newValue, forKey: Key.selection) }
    }

    var protectionEnabled: Bool {
        get { defaults.bool(forKey: Key.protectionEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.protectionEnabled) }
    }

    // MARK: Settings

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
    // Applies to sessions started after a change.
    var sessionWarnMinutes: Int {
        get { defaults.object(forKey: Key.sessionWarnMinutes) as? Int ?? 1 }
        nonmutating set { defaults.set(newValue, forKey: Key.sessionWarnMinutes) }
    }

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

    var lastSessionEnd: Date? {
        get { defaults.object(forKey: Key.lastSessionEnd) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastSessionEnd) }
    }

    // MARK: Daily counter

    // Session count is scoped to a day string so it resets at midnight without
    // needing a scheduled job.
    func sessionsToday(now: Date = Date()) -> Int {
        guard defaults.string(forKey: Key.sessionsDay) == Self.dayString(now) else { return 0 }
        return defaults.integer(forKey: Key.sessionsToday)
    }

    func incrementSessionsToday(now: Date = Date()) {
        let day = Self.dayString(now)
        let count = defaults.string(forKey: Key.sessionsDay) == day ? defaults.integer(forKey: Key.sessionsToday) : 0
        defaults.set(day, forKey: Key.sessionsDay)
        defaults.set(count + 1, forKey: Key.sessionsToday)
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
}
