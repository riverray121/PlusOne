import SwiftUI
import FamilyControls

// Selfie-unlock rules: each rule blocks its own selection behind the selfie
// check, with its own duration, cooldown, cap, and warning. The editor is
// pushed, never sheeted: FamilyActivityPicker presented over a sheet pulls
// the whole sheet down when it closes, losing the edit.
struct SelfieBlockView: View {
    @State private var rules = SharedStore.shared.selfieRules
    @State private var saveSelfies = SharedStore.shared.saveSelfiesEnabled
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
                Toggle("Save unlock selfies", isOn: $saveSelfies)
                    .onChange(of: saveSelfies) { on in
                        SharedStore.shared.saveSelfiesEnabled = on
                        guard on else { return }
                        SelfieSaver.requestAccess { granted in
                            if !granted { saveSelfies = false }
                        }
                    }
            } footer: {
                Text("Each passing selfie is saved to your photo library. PlusOne asks only for permission to add photos, never to view them; if that was denied, allow it in Settings.")
            }

            Section {
                Label("All processing happens on this device. Selfie frames are analyzed in memory and never stored unless saving is on.", systemImage: "hand.raised.fill")
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
    @State private var rule: SelfieRule
    @State private var editing: Bool
    private let original: SelfieRule
    let isNew: Bool
    let onSave: (SelfieRule) -> Void

    init(rule: SelfieRule, isNew: Bool, onSave: @escaping (SelfieRule) -> Void) {
        _rule = State(initialValue: rule)
        _editing = State(initialValue: isNew)
        original = rule
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        List {
            // The rule is local until Save, so commit needs no extra work.
            SelectionEditor(
                selection: $rule.selection,
                footer: "Swipe an item left to remove it.",
                editable: editing
            ) { _ in }

            Section {
                if editing {
                    NumberField(
                        title: "Unlock duration",
                        value: $rule.durationMinutes,
                        range: 1...SettingLimits.maxDayMinutes,
                        units: [.minutes, .hours]
                    )
                    NumberField(
                        title: "Cooldown",
                        value: $rule.cooldownMinutes,
                        range: 0...SettingLimits.maxWaitMinutes,
                        units: [.minutes, .hours, .days]
                    )
                    NumberField(
                        title: "Daily cap",
                        value: $rule.dailyCap,
                        range: 0...SettingLimits.maxCount,
                        units: [.init(label: "sessions", factor: 1)]
                    )
                    NumberField(
                        title: "Warn when left",
                        value: $rule.warnMinutes,
                        range: 0...max(0, rule.durationMinutes - 1)
                    )
                } else {
                    ValueRow(title: "Unlock duration", value: hoursOrMinutesLabel(rule.durationMinutes))
                    ValueRow(title: "Cooldown", value: durationOrOffLabel(rule.cooldownMinutes))
                    ValueRow(title: "Daily cap", value: rule.dailyCap == 0 ? "Off" : "\(rule.dailyCap) sessions")
                    ValueRow(title: "Warn when left", value: durationOrOffLabel(rule.warnMinutes))
                }
            } footer: {
                Text("Each selfie pass unlocks the tapped item for the duration. Cooldown is the wait between unlocks, and the daily cap limits how many you get per day. The warning notifies you when that many minutes are left in a session. Set cooldown, cap or warning to 0 to turn it off.")
            }
        }
        .navigationTitle(isNew ? "New block" : "Selfie block")
        .navigationBarTitleDisplayMode(.inline)
        .ruleEditorChrome(
            editing: $editing,
            isNew: isNew,
            canSave: rule.itemCount > 0,
            revert: { rule = original },
            save: { onSave(rule) }
        )
    }
}
