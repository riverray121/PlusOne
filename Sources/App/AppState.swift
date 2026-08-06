import SwiftUI
import FamilyControls

// Observable mirror of the SharedStore state the UI binds to. Assigning
// selection persists it and re-shields, so views never write it directly.
@MainActor
final class AppState: ObservableObject {
    private let store = SharedStore.shared

    @Published var onboarded: Bool {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") }
    }
    // Mirror only; every mutation goes through setProtection so the gate can
    // defer weakening. ProtectionGate owns the side effects.
    @Published var protectionEnabled: Bool
    @Published var pendingUnlock: UnlockTarget?
    @Published var activeSessions: [UnlockSession] = []
    // One capture flow per unlock request; sheet identity is tied to it so a
    // new request always gets a fresh view with fresh state.
    @Published var captureRequest: CaptureRequest?

    init() {
        onboarded = UserDefaults.standard.bool(forKey: "onboarded")
        protectionEnabled = store.protectionEnabled
        pendingUnlock = store.pendingUnlock
        activeSessions = store.activeSessions
    }

    // Onboarding's initial pick becomes the first selfie-unlock rule, with
    // default settings.
    func setInitialSelfieSelection(_ selection: FamilyActivitySelection) {
        var rules = store.selfieRules
        if var first = rules.first {
            first.selection = selection
            rules[0] = first
        } else {
            var rule = SelfieRule()
            rule.selection = selection
            rules = [rule]
        }
        store.selfieRules = rules
        if protectionEnabled { ShieldController.shared.applyShields() }
        objectWillChange.send()
    }

    var initialSelfieSelection: FamilyActivitySelection {
        store.selfieRules.first?.selection ?? FamilyActivitySelection()
    }

    // Turning protection on is always immediate; turning it off is a
    // weakening the gate may queue. Returns the queued change, nil if applied.
    @discardableResult
    func setProtection(_ on: Bool) -> PendingChange? {
        switch ProtectionGate.shared.propose(.setProtection(on)) {
        case .applied:
            protectionEnabled = store.protectionEnabled
            return nil
        case .queued(let change):
            return change
        }
    }

    // Re-reads extension-written state (pending unlocks, ended sessions) and
    // state the gate may have changed by applying due pending changes, and
    // opens a capture flow for a new unlock request. Never tears down a flow
    // already on screen; dismissal does that.
    func refresh() {
        pendingUnlock = store.pendingUnlock
        activeSessions = store.activeSessions
        protectionEnabled = store.protectionEnabled
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

    var selfieBlockItemCount: Int {
        store.selfieRules.reduce(0) { $0 + $1.itemCount }
    }
}

struct CaptureRequest: Identifiable {
    let id = UUID()
    let target: UnlockTarget
}
