import SwiftUI
import FamilyControls
import ManagedSettings

// Permanent blocks: a second picker selection that is always shielded with no
// selfie unlock, plus Apple's adult-content filter. Changes apply immediately
// while protection is on.
//
// Removal happens in our own list, not the picker: FamilyActivityPicker has a
// known bug where unchecking items does not update the selection binding.
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
                    Label("Add apps and websites", systemImage: "plus")
                }
                .foregroundStyle(.primary)
            } footer: {
                Text("Hard-blocked items show a block screen with no unlock button. Swipe an item left to remove it.")
            }

            if !hardSelection.applicationTokens.isEmpty {
                appsSection
            }
            if !hardSelection.webDomainTokens.isEmpty {
                websitesSection
            }
            if !hardSelection.categoryTokens.isEmpty {
                categoriesSection
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

    // The token array is captured per render so delete offsets always match
    // the rendered order.
    private var appsSection: some View {
        let tokens = Array(hardSelection.applicationTokens)
        return Section("Apps") {
            ForEach(tokens, id: \.self) { Label($0) }
                .onDelete { offsets in
                    for index in offsets { hardSelection.applicationTokens.remove(tokens[index]) }
                }
        }
    }

    private var websitesSection: some View {
        let tokens = Array(hardSelection.webDomainTokens)
        return Section("Websites") {
            ForEach(tokens, id: \.self) { Label($0) }
                .onDelete { offsets in
                    for index in offsets { hardSelection.webDomainTokens.remove(tokens[index]) }
                }
        }
    }

    private var categoriesSection: some View {
        let tokens = Array(hardSelection.categoryTokens)
        return Section("Categories") {
            ForEach(tokens, id: \.self) { Label($0) }
                .onDelete { offsets in
                    for index in offsets { hardSelection.categoryTokens.remove(tokens[index]) }
                }
        }
    }

    private func applyNow() {
        if SharedStore.shared.protectionEnabled {
            SessionManager.shared.refreshShields()
        }
    }
}
