import Foundation
import FamilyControls
import ManagedSettings

// Applies and clears shields on the one named store all processes share.
// Idempotent: callers re-apply freely; the store settles to the same state.
struct ShieldController {
    static let shared = ShieldController()

    private let store = ManagedSettingsStore(named: .init(AppGroup.managedSettingsStoreName))

    // Shields the full selection, minus excluded (unlocked) items.
    // Category-shielded items are excluded via the policy's `except` sets.
    func applyShields(excluding excluded: [UnlockTarget] = []) {
        let selection = SharedStore.shared.selection
        let hard = SharedStore.shared.hardSelection

        var apps = selection.applicationTokens
        var domains = selection.webDomainTokens
        var categories = selection.categoryTokens
        var exceptApps: Set<ApplicationToken> = []
        var exceptDomains: Set<WebDomainToken> = []

        for target in excluded {
            switch target {
            case .application(let token):
                apps.remove(token)
                exceptApps.insert(token)
            case .webDomain(let token):
                domains.remove(token)
                exceptDomains.insert(token)
            case .category(let token):
                categories.remove(token)
            }
        }

        // Hard-blocked items join after session exclusions so a session can
        // never unshield them.
        apps.formUnion(hard.applicationTokens)
        domains.formUnion(hard.webDomainTokens)
        categories.formUnion(hard.categoryTokens)
        exceptApps.subtract(hard.applicationTokens)
        exceptDomains.subtract(hard.webDomainTokens)

        // Spent time-limit rules shield the same way until their period
        // resets: no session can unshield them either.
        for rule in TimeLimitManager.shared.exhaustedRules {
            apps.formUnion(rule.selection.applicationTokens)
            domains.formUnion(rule.selection.webDomainTokens)
            categories.formUnion(rule.selection.categoryTokens)
            exceptApps.subtract(rule.selection.applicationTokens)
            exceptDomains.subtract(rule.selection.webDomainTokens)
        }

        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.webDomains = domains.isEmpty ? nil : domains
        store.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: exceptApps)
        store.shield.webDomainCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: exceptDomains)
        // The web filter serves ONLY the adult toggle. Any filter policy on
        // iOS implies adult filtering (there is no pure blocklist mode), so
        // custom hard blocks go through shields above, never through here.
        store.webContent.blockedByFilter = SharedStore.shared.adultFilterEnabled
            ? .auto([], except: [])
            : WebContentSettings.FilterPolicy.none
    }

    // The OS app-removal restriction, device-wide by design. Independent of
    // shields: clearShields leaves it alone. Releasing it clears the value to
    // nil so the store stops asserting a removal policy at all.
    func setDenyAppRemoval(_ deny: Bool) {
        store.application.denyAppRemoval = deny ? true : nil
    }

    // Removes all shields (protection toggled off).
    func clearShields() {
        store.shield.applications = nil
        store.shield.webDomains = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        store.webContent.blockedByFilter = WebContentSettings.FilterPolicy.none
    }
}
