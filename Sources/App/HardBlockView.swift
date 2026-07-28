import SwiftUI
import FamilyControls

// Permanent blocks: a second picker selection that is always shielded with no
// selfie unlock, plus Apple's adult-content filter. Changes apply immediately
// while protection is on.
struct HardBlockView: View {
    @State private var showPicker = false
    @State private var hardSelection = SharedStore.shared.hardSelection
    @State private var adultFilter = SharedStore.shared.adultFilterEnabled

    var body: some View {
        List {
            Section {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Label("Choose apps and websites", systemImage: "square.grid.2x2")
                        Spacer()
                        Text("\(hardItemCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            } footer: {
                Text("Hard-blocked items show a block screen with no unlock button. Remove them from this list to open them again.")
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
        .familyActivityPicker(isPresented: $showPicker, selection: $hardSelection)
        .onChange(of: hardSelection) { newValue in
            SharedStore.shared.hardSelection = newValue
            applyNow()
        }
    }

    private var hardItemCount: Int {
        hardSelection.applicationTokens.count
            + hardSelection.webDomainTokens.count
            + hardSelection.categoryTokens.count
    }

    private func applyNow() {
        if SharedStore.shared.protectionEnabled {
            SessionManager.shared.refreshShields()
        }
    }
}
