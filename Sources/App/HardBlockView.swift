import SwiftUI
import FamilyControls

// Permanent blocks: a second picker selection that is always shielded with no
// selfie unlock, plus Apple's adult-content filter. Changes apply immediately
// while protection is on.
struct HardBlockView: View {
    @State private var hardSelection = SharedStore.shared.hardSelection
    @State private var adultFilter = SharedStore.shared.adultFilterEnabled

    var body: some View {
        List {
            SelectionEditor(
                selection: $hardSelection,
                footer: "Hard-blocked items show a block screen with no unlock button. Swipe an item left to remove it."
            ) { newValue in
                SharedStore.shared.hardSelection = newValue
                applyNow()
            }

            Section {
                Toggle("Block adult websites", isOn: $adultFilter)
                    .onChange(of: adultFilter) { on in
                        SharedStore.shared.adultFilterEnabled = on
                        applyNow()
                    }
            } footer: {
                Text("Apple's adult-content filter for Safari. Note: while on, Safari private browsing is disabled by iOS.")
            }
        }
        .navigationTitle("Hard blocks")
    }

    private func applyNow() {
        if SharedStore.shared.protectionEnabled {
            SessionManager.shared.refreshShields()
        }
    }
}
