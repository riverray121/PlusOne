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
                SessionManager.shared.endAllSessions()
                ShieldController.shared.clearShields()
            }
        }
    }
    @Published var pendingUnlock: UnlockTarget?
    @Published var activeSessions: [UnlockSession] = []
    // Lite build only: presents the demo capture sheet.
    @Published var showCapture = false
    // One capture flow per unlock request; sheet identity is tied to it so a
    // new request always gets a fresh view with fresh state.
    @Published var captureRequest: CaptureRequest?

    init() {
        onboarded = UserDefaults.standard.bool(forKey: "onboarded")
        selection = store.selection
        protectionEnabled = store.protectionEnabled
        pendingUnlock = store.pendingUnlock
        activeSessions = store.activeSessions
    }

    // Re-reads extension-written state (pending unlocks, ended sessions) and
    // opens a capture flow for a new unlock request. Never tears down a flow
    // already on screen; dismissal does that.
    func refresh() {
        pendingUnlock = store.pendingUnlock
        activeSessions = store.activeSessions
        if let target = pendingUnlock, captureRequest == nil {
            captureRequest = CaptureRequest(target: target)
        }
    }

    // Sheet dismissed (Done, Cancel, or swipe): consume the pending request
    // unconditionally so nothing re-presents. sheet(item:) nils the binding
    // before onDismiss runs, so the dismissed target cannot be read here.
    func captureDidDismiss() {
        captureRequest = nil
        store.pendingUnlock = nil
        pendingUnlock = nil
        activeSessions = store.activeSessions
    }

    var blockedItemCount: Int {
        selection.applicationTokens.count
            + selection.webDomainTokens.count
            + selection.categoryTokens.count
    }
}

struct CaptureRequest: Identifiable {
    let id = UUID()
    let target: UnlockTarget
}
