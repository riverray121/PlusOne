import SwiftUI
import FamilyControls

// Usage budgets: each rule gives its selection a shared pool of minutes per
// hour or day. Changes apply immediately while protection is on.
struct TimeLimitsView: View {
    @State private var rules = SharedStore.shared.timeLimitRules
    @State private var warn = SharedStore.shared.warnMinutesLeft
    @State private var editing: TimeLimitRule?

    private let warnOptions = [0, 1, 2, 5, 10]

    var body: some View {
        List {
            Section {
                ForEach(rules) { rule in
                    Button {
                        editing = rule
                    } label: {
                        HStack {
                            Label(pluralItems(rule.itemCount), systemImage: "hourglass")
                            Spacer()
                            Text("\(rule.minutes) min / \(rule.period.label)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete(perform: delete)

                Button {
                    editing = TimeLimitRule()
                } label: {
                    Label("Add limit", systemImage: "plus")
                }
            } footer: {
                Text("Each limit is a pool of minutes shared by its apps and websites. When it runs out they block with no unlock until the hour or day rolls over. Editing a limit restarts its count for the current period.")
            }

            Section {
                Picker("Warn when minutes left", selection: $warn) {
                    ForEach(warnOptions, id: \.self) {
                        Text($0 == 0 ? "Off" : "\($0) min")
                    }
                }
                .onChange(of: warn) { newValue in
                    SharedStore.shared.warnMinutesLeft = newValue
                    applyNow()
                }
            } footer: {
                Text("Notifies when a limit has this many minutes remaining. Skipped for limits at or under the warning value.")
            }
        }
        .navigationTitle("Time limits")
        .sheet(item: $editing) { rule in
            TimeLimitEditView(
                rule: rule,
                isNew: !rules.contains { $0.id == rule.id }
            ) { saved in
                if let index = rules.firstIndex(where: { $0.id == saved.id }) {
                    rules[index] = saved
                } else {
                    rules.append(saved)
                }
                persist()
            }
        }
    }

    private func pluralItems(_ n: Int) -> String {
        n == 1 ? "1 item" : "\(n) items"
    }

    private func delete(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        SharedStore.shared.timeLimitRules = rules
        applyNow()
    }

    private func applyNow() {
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

    @State private var showPicker = false

    private var minuteOptions: [Int] {
        let all = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
        return rule.period == .hour ? all.filter { $0 < 60 } : all
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Label("Choose apps and websites", systemImage: "square.grid.2x2")
                            Spacer()
                            Text("\(rule.itemCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

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
                } footer: {
                    Text("Budgets reset on the clock: hourly limits at the top of each hour, daily limits at midnight.")
                }
            }
            .navigationTitle(isNew ? "New limit" : "Edit limit")
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $showPicker, selection: $rule.selection)
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
                    .disabled(rule.itemCount == 0)
                }
            }
        }
    }
}
