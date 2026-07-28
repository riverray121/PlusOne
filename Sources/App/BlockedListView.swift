import SwiftUI
import FamilyControls

// The blocked list: picker-based apps/categories/websites, plus the blanket
// adult-content filter.
struct BlockedListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var adultFilter = SharedStore.shared.adultFilterEnabled

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Choose apps, categories, and websites", systemImage: "square.grid.2x2")
                    }
                } footer: {
                    Text("\(appState.blockedItemCount) selected. Websites added here get the PlusOne unlock screen in Safari.")
                }

                Section {
                    Toggle("Block adult websites", isOn: $adultFilter)
                        .onChange(of: adultFilter) { on in
                            SharedStore.shared.adultFilterEnabled = on
                            if SharedStore.shared.protectionEnabled {
                                SessionManager.shared.refreshShields()
                            }
                        }
                } footer: {
                    Text("Apple's adult-content filter for Safari. Hard block: no selfie unlock.")
                }
            }
            .navigationTitle("Blocked list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
            .familyActivityPicker(isPresented: $showPicker, selection: $appState.selection)
        }
    }
}
