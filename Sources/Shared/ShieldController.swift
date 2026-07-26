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

        var apps = selection.applicationTokens
        var domains = selection.webDomainTokens
        var categories = selection.categoryTokens
        var exceptApps: Set<ApplicationToken> = []
        var exceptDomains: Set<WebDomainToken> = []

        var filterDomains = Set(SharedStore.shared.blockedDomains.map { WebDomain(domain: $0) })

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
            case .domain(let string):
                filterDomains.remove(WebDomain(domain: string))
            }
        }

        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.webDomains = domains.isEmpty ? nil : domains
        store.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: exceptApps)
        store.shield.webDomainCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: exceptDomains)
        // The string blocklist rides the content filter; Safari shows its own
        // restricted page for these, and unlocks start from inside PlusOne.
        store.webContent.blockedByFilter = filterDomains.isEmpty
            ? nil
            : .specific(filterDomains)
    }

    // Removes all shields (protection toggled off).
    func clearShields() {
        store.shield.applications = nil
        store.shield.webDomains = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        store.webContent.blockedByFilter = nil
    }
}
