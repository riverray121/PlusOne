import Foundation
import FamilyControls
import ManagedSettings

// One selfie-unlock rule: its selection blocks behind the selfie check, and
// a pass unlocks the tapped item for `durationMinutes`. Cooldown, daily cap,
// and the warning are scoped to this rule alone.
struct SelfieRule: Codable, Identifiable, Equatable {
    // Identity of the rule synthesized from the single-selection legacy
    // layout, fixed so counters keyed by rule id survive re-reads.
    static let legacyId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id = UUID()
    var selection = FamilyActivitySelection()
    // Minutes of usage granted per selfie pass.
    var durationMinutes = 5
    // Minutes required between this rule's sessions. 0 = off.
    var cooldownMinutes = 0
    // Max sessions per calendar day for this rule. 0 = off.
    var dailyCap = 0
    // Minutes-remaining mark for the session warning notification. 0 = off.
    var warnMinutes = 1

    var itemCount: Int {
        selection.itemCount
    }

    func contains(_ target: UnlockTarget) -> Bool {
        switch target {
        case .application(let token): return contains(token)
        case .webDomain(let token): return contains(token)
        case .category(let token): return contains(token)
        }
    }

    func contains(_ token: ApplicationToken) -> Bool {
        selection.applicationTokens.contains(token)
    }

    func contains(_ token: WebDomainToken) -> Bool {
        selection.webDomainTokens.contains(token)
    }

    func contains(_ token: ActivityCategoryToken) -> Bool {
        selection.categoryTokens.contains(token)
    }
}
