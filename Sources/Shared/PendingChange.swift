import Foundation
import FamilyControls

// A weakening change waiting out the settings change delay. The live
// configuration is untouched until ProtectionGate applies it.
struct PendingChange: Codable, Identifiable {
    // Target values are captured at proposal time. Selection kinds carry the
    // removed tokens as a diff so applying late cannot clobber items added in
    // the meantime.
    enum Kind: Codable {
        case setProtection(Bool)
        case removeSelfieItems(FamilyActivitySelection)
        case removeHardItems(FamilyActivitySelection)
        case setDuration(Int)
        case setCooldown(Int)
        case setDailyCap(Int)
        case setAdultFilter(Bool)
        case upsertTimeLimitRule(TimeLimitRule)
        case deleteTimeLimitRule(UUID)
        case setDelay(Int)
        case setDeletePrevention(Bool)
        case unpairFriend
    }

    let id: UUID
    let createdAt: Date
    // nil = no countdown; the change waits on friend approval alone.
    let appliesAt: Date?
    // Plain-language description, fixed at proposal time; also the text a
    // paired friend sees.
    let summary: String
    let kind: Kind

    // One pending change per setting: a proposal with the same key replaces
    // the previous one and restarts its countdown. Selection removals
    // accumulate (nil key).
    var replaceKey: String? {
        switch kind {
        case .setProtection: return "protection"
        case .removeSelfieItems, .removeHardItems: return nil
        case .setDuration: return "duration"
        case .setCooldown: return "cooldown"
        case .setDailyCap: return "dailyCap"
        case .setAdultFilter: return "adultFilter"
        case .upsertTimeLimitRule(let rule): return "rule-\(rule.id)"
        case .deleteTimeLimitRule(let id): return "rule-\(id)"
        case .setDelay: return "delay"
        case .setDeletePrevention: return "deletePrevention"
        case .unpairFriend: return "unpair"
        }
    }
}
