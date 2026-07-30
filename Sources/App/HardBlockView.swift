import SwiftUI
import FamilyControls

// Permanent blocks: a second picker selection that is always shielded with no
// selfie unlock, plus Apple's adult-content filter. Changes apply immediately
// while protection is on.
struct HardBlockView: View {
    @State private var hardSelection = SharedStore.shared.hardSelection
    @State private var adultFilter = SharedStore.shared.adultFilterEnabled
    @State private var queued: QueuedNotice?

    var body: some View {
        List {
            // Additions commit directly; removals are weakenings and go
            // through the gate.
            SelectionEditor(
                selection: $hardSelection,
                footer: "Hard-blocked items show a block screen with no unlock button. Swipe an item left to remove it.",
                removal: { removed in
                    switch ProtectionGate.shared.propose(.removeHardItems(removed)) {
                    case .applied:
                        return true
                    case .queued(let change):
                        queued = QueuedNotice(change)
                        return false
                    }
                }
            ) { newValue in
                SharedStore.shared.hardSelection = newValue
                applyNow()
            }

            Section {
                Toggle("Block adult websites", isOn: $adultFilter)
                    .onChange(of: adultFilter) { on in
                        if case .queued(let change) = ProtectionGate.shared.propose(.setAdultFilter(on)) {
                            queued = QueuedNotice(change)
                            adultFilter = SharedStore.shared.adultFilterEnabled
                        }
                    }
            } footer: {
                Text("Apple's adult-content filter for Safari. Note: while on, Safari private browsing is disabled by iOS.")
            }
        }
        .navigationTitle("Hard blocks")
        .onAppear {
            hardSelection = SharedStore.shared.hardSelection
            adultFilter = SharedStore.shared.adultFilterEnabled
        }
        .queuedChangeAlert($queued)
    }

    private func applyNow() {
        if SharedStore.shared.protectionEnabled {
            SessionManager.shared.refreshShields()
        }
    }
}
