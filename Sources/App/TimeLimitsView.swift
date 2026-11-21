import SwiftUI
import FamilyControls

// Usage budgets: each rule gives its selection a shared pool of minutes per
// hour or day. Changes apply immediately while protection is on. The editor
// is pushed, never sheeted: FamilyActivityPicker presented over a sheet pulls
// the whole sheet down when it closes, losing the edit.
struct TimeLimitsView: View {
    @State private var rules = SharedStore.shared.timeLimitRules
    @State private var queued: QueuedNotice?

    var body: some View {
        List {
            Section {
                ForEach(rules) { rule in
                    NavigationLink {
                        TimeLimitEditView(rule: rule, isNew: false, onSave: save)
                    } label: {
                        HStack {
                            Label(pluralItems(rule.itemCount), systemImage: "hourglass")
                            Spacer()
                            Text("\(rule.minutes) min / \(rule.period.label)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)

                NavigationLink {
                    TimeLimitEditView(rule: TimeLimitRule(), isNew: true, onSave: save)
                } label: {
                    Label("Add limit", systemImage: "plus")
                }
            } footer: {
                Text("Each limit is a shared pool of minutes for its apps and websites. When the pool runs out, they block until the hour or day rolls over. Editing a limit restarts the current period's count.")
            }
        }
        .navigationTitle("Time limits")
        .toolbar {
            if !rules.isEmpty { EditButton() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { rules = SharedStore.shared.timeLimitRules }
        .queuedChangeAlert($queued)
    }

    // The gate persists and resyncs monitoring. A save that weakens the rule
    // (more minutes, day to hour, items removed) queues; anything else, and
    // all new rules, apply immediately.
    private func save(_ saved: TimeLimitRule) {
        if proposeOrNotify(.upsertTimeLimitRule(saved), into: $queued) {
            rules = SharedStore.shared.timeLimitRules
        }
    }

    private func delete(at offsets: IndexSet) {
        for rule in offsets.map({ rules[$0] }) {
            _ = proposeOrNotify(.deleteTimeLimitRule(rule.id), into: $queued)
        }
        rules = SharedStore.shared.timeLimitRules
    }
}

struct TimeLimitEditView: View {
    @State private var rule: TimeLimitRule
    @State private var editing: Bool
    private let original: TimeLimitRule
    let isNew: Bool
    let onSave: (TimeLimitRule) -> Void

    init(rule: TimeLimitRule, isNew: Bool, onSave: @escaping (TimeLimitRule) -> Void) {
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
                    Picker("Per", selection: $rule.period) {
                        Text("Hour").tag(TimeLimitRule.Period.hour)
                        Text("Day").tag(TimeLimitRule.Period.day)
                    }
                    NumberField(
                        title: "Allowed",
                        value: $rule.minutes,
                        range: 1...rule.period.maxMinutes,
                        units: rule.period == .hour ? [.minutes] : [.minutes, .hours]
                    )
                    NumberField(
                        title: "Warn when left",
                        value: $rule.warnMinutes,
                        range: 0...max(0, rule.minutes - 1)
                    )
                } else {
                    ValueRow(title: "Per", value: rule.period == .hour ? "Hour" : "Day")
                    ValueRow(title: "Allowed", value: hoursOrMinutesLabel(rule.minutes))
                    ValueRow(title: "Warn when left", value: durationOrOffLabel(rule.warnMinutes))
                }
            } footer: {
                Text("Budgets reset on the clock, at the top of each hour or at midnight. The warning notifies you when that many minutes are left; set it to 0 to turn it off.")
            }
        }
        .navigationTitle(isNew ? "New limit" : "Time limit")
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
