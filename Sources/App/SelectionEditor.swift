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
    // Asked before a row removal is applied, with the removed tokens as a
    // token-only selection. Return false to keep the selection unchanged
    // (the removal was queued elsewhere). nil = removals always apply.
    var removal: ((FamilyActivitySelection) -> Bool)? = nil
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
                // The picker only adds. Deselections made inside it are
                // discarded by unioning the prior tokens back in: removal is
                // the token rows' job, where it can be gated as a weakening.
                var merged = pickerBuffer
                merged.applicationTokens.formUnion(selection.applicationTokens)
                merged.webDomainTokens.formUnion(selection.webDomainTokens)
                merged.categoryTokens.formUnion(selection.categoryTokens)
                apply(merged)
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

    // Removal rides swipeActions rather than ForEach.onDelete: the per-row
    // action passes the token directly (no offset mapping), and its swipe
    // chrome animates the section's rounded corners more cleanly.
    private var appsSection: some View {
        Section("Apps") {
            ForEach(Array(selection.applicationTokens), id: \.self) { token in
                Label(token)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove", role: .destructive) {
                            removeTokens(apps: [token])
                        }
                    }
            }
        }
    }

    private var websitesSection: some View {
        Section("Websites") {
            ForEach(Array(selection.webDomainTokens), id: \.self) { token in
                Label(token)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove", role: .destructive) {
                            removeTokens(domains: [token])
                        }
                    }
            }
        }
    }

    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(Array(selection.categoryTokens), id: \.self) { token in
                Label(token)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove", role: .destructive) {
                            removeTokens(categories: [token])
                        }
                    }
            }
        }
    }

    private func removeTokens(
        apps: [ApplicationToken] = [],
        domains: [WebDomainToken] = [],
        categories: [ActivityCategoryToken] = []
    ) {
        var removed = FamilyActivitySelection()
        removed.applicationTokens = Set(apps)
        removed.webDomainTokens = Set(domains)
        removed.categoryTokens = Set(categories)
        if let removal, !removal(removed) { return }
        apply(selection.subtracting(removed))
    }

    private func apply(_ newValue: FamilyActivitySelection) {
        selection = newValue
        commit(newValue)
    }
}
