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

        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.webDomains = domains.isEmpty ? nil : domains
        store.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: exceptApps)
        store.shield.webDomainCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: exceptDomains)
        // Hard blocks: custom domains plus Apple's adult-content filter.
        // Never excluded by sessions; there is no selfie unlock for these.
        // Off writes an explicit allow-all policy: removing the setting (nil)
        // can leave the previous filter engaged, and a bare `.none` assignment
        // resolves to Optional.none, which is exactly that nil removal.
        let hard = Set(SharedStore.shared.blockedDomains.map { WebDomain(domain: $0) })
        if SharedStore.shared.adultFilterEnabled {
            store.webContent.blockedByFilter = .auto(hard, except: [])
        } else if !hard.isEmpty {
            store.webContent.blockedByFilter = .specific(hard)
        } else {
            store.webContent.blockedByFilter = WebContentSettings.FilterPolicy.none
        }
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
