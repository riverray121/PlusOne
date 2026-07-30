import SwiftUI
import FamilyControls

// Usage budgets: each rule gives its selection a shared pool of minutes per
// hour or day. Changes apply immediately while protection is on. The editor
// is pushed, never sheeted: FamilyActivityPicker presented over a sheet pulls
// the whole sheet down when it closes, losing the edit.
struct TimeLimitsView: View {
    @State private var rules = SharedStore.shared.timeLimitRules

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
                Text("Each limit is a pool of minutes shared by its apps and websites. When it runs out they block with no unlock until the hour or day rolls over. Editing a limit restarts its count for the current period.")
            }
        }
        .navigationTitle("Time limits")
    }

    private func pluralItems(_ n: Int) -> String {
        n == 1 ? "1 item" : "\(n) items"
    }

    private func save(_ saved: TimeLimitRule) {
        if let index = rules.firstIndex(where: { $0.id == saved.id }) {
            rules[index] = saved
        } else {
            rules.append(saved)
        }
        persist()
    }

    private func delete(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        SharedStore.shared.timeLimitRules = rules
        guard SharedStore.shared.protectionEnabled else { return }
        // Screen Time XPC calls block; keep them off the main thread.
        Task.detached {
            TimeLimitManager.shared.syncMonitoring()
            SessionManager.shared.refreshShields()
        }
    }
}

struct TimeLimitEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: TimeLimitRule
    let isNew: Bool
    let onSave: (TimeLimitRule) -> Void

    private var minuteOptions: [Int] {
        let all = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
        return rule.period == .hour ? all.filter { $0 < 60 } : all
    }
    private let warnOptions = [0, 1, 2, 5, 10]

    var body: some View {
        Form {
            // The rule is local until Save, so commit needs no extra work.
            SelectionEditor(
                selection: $rule.selection,
                footer: "Everything in this limit shares its pool of minutes. Swipe an item left to remove it."
            ) { _ in }

            Section {
                Picker("Minutes", selection: $rule.minutes) {
                    ForEach(minuteOptions, id: \.self) { Text("\($0) min") }
                }
                Picker("Per", selection: $rule.period) {
                    Text("Hour").tag(TimeLimitRule.Period.hour)
                    Text("Day").tag(TimeLimitRule.Period.day)
                }
                .onChange(of: rule.period) { period in
                    if period == .hour && rule.minutes >= 60 { rule.minutes = 30 }
                }
                Picker("Warn when minutes left", selection: $rule.warnMinutes) {
                    ForEach(warnOptions, id: \.self) {
                        Text($0 == 0 ? "Off" : "\($0) min")
                    }
                }
            } footer: {
                Text("Budgets reset on the clock: hourly limits at the top of each hour, daily limits at midnight. The warning notifies when this limit has that many minutes remaining; it is skipped when the limit is at or under the warning value.")
            }
        }
        .navigationTitle(isNew ? "New limit" : "Edit limit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
