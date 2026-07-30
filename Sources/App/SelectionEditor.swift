import SwiftUI
import FamilyControls
import ManagedSettings

// Add-and-remove editor for a FamilyActivitySelection, shared by every
// blocking surface so selection behavior is identical across the app.
//
// Three platform traps shape this design:
// 1. FamilyActivityPicker deselection can fail to update its binding, and a
//    mounted picker can write its own stale selection back into a live
//    binding. The picker therefore works on a private buffer, merged back
//    exactly once when it closes; removal happens in the token lists below.
// 2. A selection carries member views (applications, webDomains, categories)
//    parallel to its token sets. Removing only a token lets the member view
//    resurrect it through an encode/decode round trip, so removal rebuilds a
//    fresh token-only selection.
// 3. Persistence never rides on Equatable-based onChange of the selection:
//    every mutation calls commit explicitly with the new value.
struct SelectionEditor: View {
    @Binding var selection: FamilyActivitySelection
    let footer: String
    let commit: (FamilyActivitySelection) -> Void

    @State private var showPicker = false
    @State private var pickerBuffer = FamilyActivitySelection()

    var body: some View {
        Section {
            Button {
                pickerBuffer = selection
                showPicker = true
            } label: {
                Label("Add apps and websites", systemImage: "plus")
            }
            .foregroundStyle(.primary)
            .familyActivityPicker(isPresented: $showPicker, selection: $pickerBuffer)
            .onChange(of: showPicker) { presented in
                guard !presented else { return }
                apply(pickerBuffer)
            }
        } footer: {
            Text(footer)
        }

        if !selection.applicationTokens.isEmpty {
            appsSection
        }
        if !selection.webDomainTokens.isEmpty {
            websitesSection
        }
        if !selection.categoryTokens.isEmpty {
            categoriesSection
        }
    }

    // Token arrays are captured per render so delete offsets always match the
    // rendered order.
    private var appsSection: some View {
        let tokens = Array(selection.applicationTokens)
        return Section("Apps") {
            ForEach(tokens, id: \.self) { Label($0) }
                .onDelete { offsets in
                    removeTokens(apps: offsets.map { tokens[$0] })
                }
        }
    }

    private var websitesSection: some View {
        let tokens = Array(selection.webDomainTokens)
        return Section("Websites") {
            ForEach(tokens, id: \.self) { Label($0) }
                .onDelete { offsets in
                    removeTokens(domains: offsets.map { tokens[$0] })
                }
        }
    }

    private var categoriesSection: some View {
        let tokens = Array(selection.categoryTokens)
        return Section("Categories") {
            ForEach(tokens, id: \.self) { Label($0) }
                .onDelete { offsets in
                    removeTokens(categories: offsets.map { tokens[$0] })
                }
        }
    }

    private func removeTokens(
        apps: [ApplicationToken] = [],
        domains: [WebDomainToken] = [],
        categories: [ActivityCategoryToken] = []
    ) {
        var fresh = FamilyActivitySelection()
        fresh.applicationTokens = selection.applicationTokens.subtracting(apps)
        fresh.webDomainTokens = selection.webDomainTokens.subtracting(domains)
        fresh.categoryTokens = selection.categoryTokens.subtracting(categories)
        apply(fresh)
    }

    private func apply(_ newValue: FamilyActivitySelection) {
        selection = newValue
        commit(newValue)
    }
}
