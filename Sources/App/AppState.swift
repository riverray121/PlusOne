import SwiftUI
import FamilyControls

// Observable mirror of SharedStore for the UI. All mutations flow through
// here so shields stay consistent with persisted state.
@MainActor
final class AppState: ObservableObject {
    private let store = SharedStore.shared

    @Published var onboarded: Bool {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") }
    }
    @Published var selection: FamilyActivitySelection {
        didSet {
            store.selection = selection
            if protectionEnabled { ShieldController.shared.applyShields() }
        }
    }
    @Published var protectionEnabled: Bool {
        didSet {
            store.protectionEnabled = protectionEnabled
            if protectionEnabled {
                ShieldController.shared.applyShields()
            } else {
                SessionManager.shared.endSession()
                ShieldController.shared.clearShields()
            }
        }
    }
    @Published var pendingUnlock: UnlockTarget?
    @Published var activeSession: UnlockSession?
    @Published var showCapture = false

    init() {
        onboarded = UserDefaults.standard.bool(forKey: "onboarded")
        selection = store.selection
        protectionEnabled = store.protectionEnabled
        pendingUnlock = store.pendingUnlock
        activeSession = store.activeSession
    }

    // Re-reads extension-written state (pending unlocks, ended sessions).
    func refresh() {
        pendingUnlock = store.pendingUnlock
        activeSession = store.activeSession
    }

    func clearPendingUnlock() {
        store.pendingUnlock = nil
        pendingUnlock = nil
    }

    var blockedItemCount: Int {
        selection.applicationTokens.count
            + selection.webDomainTokens.count
            + selection.categoryTokens.count
    }
}
