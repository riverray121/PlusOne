import SwiftUI
import FamilyControls

// Always-on blocks: a second picker selection that is shielded around the
// clock with no selfie unlock, plus Apple's adult-content filter. Changes
// apply immediately while protection is on.
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
                footer: "Anything on this list is blocked 24/7 for as long as it stays here, and its block screen has no unlock button. Swipe an item left to remove it.",
                removal: { removed in
                    proposeOrNotify(.removeHardItems(removed), into: $queued)
                }
            ) { newValue in
                SharedStore.shared.hardSelection = newValue
                SessionManager.shared.refreshShields()
            }

            Section {
                Toggle("Block adult websites", isOn: $adultFilter)
                    .onChange(of: adultFilter) { on in
                        if !proposeOrNotify(.setAdultFilter(on), into: $queued) {
                            adultFilter = SharedStore.shared.adultFilterEnabled
                        }
                    }
            } footer: {
                Text("Apple's adult-content filter for Safari. Note: while on, Safari private browsing is disabled by iOS.")
            }
        }
        .navigationTitle("Hard blocks")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hardSelection = SharedStore.shared.hardSelection
            adultFilter = SharedStore.shared.adultFilterEnabled
        }
        .queuedChangeAlert($queued)
    }
}
