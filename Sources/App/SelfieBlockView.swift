import SwiftUI
import FamilyControls

// Selfie-unlock rules: each rule blocks its own selection behind the selfie
// check, with its own duration, cooldown, cap, and warning. The editor is
// pushed, never sheeted: FamilyActivityPicker presented over a sheet pulls
// the whole sheet down when it closes, losing the edit.
struct SelfieBlockView: View {
    @State private var rules = SharedStore.shared.selfieRules
    @State private var queued: QueuedNotice?

    var body: some View {
        List {
            Section {
                ForEach(rules) { rule in
                    NavigationLink {
                        SelfieRuleEditView(rule: rule, isNew: false, onSave: save)
                    } label: {
                        HStack {
                            Label(pluralItems(rule.itemCount), systemImage: "person.2.fill")
                            Spacer()
                            Text("\(rule.durationMinutes) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)

                NavigationLink {
                    SelfieRuleEditView(rule: SelfieRule(), isNew: true, onSave: save)
                } label: {
                    Label("Add block", systemImage: "plus")
                }
            } footer: {
                Text("A selfie with two people unlocks the item you tapped. Each block has its own unlock duration, cooldown, and daily cap.")
            }

            Section {
                Label("All processing happens on this device. Selfie frames are analyzed in memory and never stored.", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Selfie-unlock blocks")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { rules = SharedStore.shared.selfieRules }
        .queuedChangeAlert($queued)
    }

    // New rules add blocking and apply immediately; edits that grant more or
    // easier unlocks are weakenings the gate may queue.
    private func save(_ saved: SelfieRule) {
        if proposeOrNotify(.upsertSelfieRule(saved), into: $queued) {
            rules = SharedStore.shared.selfieRules
        }
    }

    private func delete(at offsets: IndexSet) {
        for rule in offsets.map({ rules[$0] }) {
            _ = proposeOrNotify(.deleteSelfieRule(rule.id), into: $queued)
        }
        rules = SharedStore.shared.selfieRules
    }
}

struct SelfieRuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: SelfieRule
    let isNew: Bool
    let onSave: (SelfieRule) -> Void

    private let durationOptions = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    private let cooldownOptions = [0, 5, 15, 30, 60, 120]
    private let capOptions = Array(0...10)

    var body: some View {
        List {
            // The rule is local until Save, so commit needs no extra work.
            SelectionEditor(
                selection: $rule.selection,
                footer: "Swipe an item left to remove it."
            ) { _ in }

            Section {
                Picker("Unlock duration", selection: $rule.durationMinutes) {
                    ForEach(durationOptions, id: \.self) { Text("\($0) min") }
                }
                Picker("Cooldown", selection: $rule.cooldownMinutes) {
                    ForEach(cooldownOptions, id: \.self) {
                        Text($0 == 0 ? "Off" : "\($0) min")
                    }
                }
                Picker("Daily cap", selection: $rule.dailyCap) {
                    ForEach(capOptions, id: \.self) {
                        Text($0 == 0 ? "Off" : "\($0) sessions")
                    }
                }
                Picker("Warn when minutes left", selection: $rule.warnMinutes) {
                    ForEach(warnMinuteOptions, id: \.self) {
                        Text($0 == 0 ? "Off" : "\($0) min")
                    }
                }
            } footer: {
                Text("Each selfie pass unlocks the tapped item for the duration. Cooldown is the wait between unlocks, and the daily cap limits how many you get per day. The warning notifies you when that many minutes are left in a session.")
            }
        }
        .navigationTitle(isNew ? "New block" : "Edit block")
        .navigationBarTitleDisplayMode(.inline)
        // Leaving is an explicit choice: Save or Cancel, no back button, so
        // edits can't be silently dropped.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .bold()
                .tint(.blue)
                .disabled(rule.itemCount == 0)
            }
        }
    }
}
