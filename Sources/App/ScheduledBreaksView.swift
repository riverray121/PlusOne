import SwiftUI
import FamilyControls

// Scheduled breaks: each rule opens its selection at a set time every day
// for a set number of minutes, no selfie needed. The editor is pushed, never
// sheeted: FamilyActivityPicker presented over a sheet pulls the whole sheet
// down when it closes, losing the edit.
struct ScheduledBreaksView: View {
    @State private var rules = SharedStore.shared.breakRules
    @State private var queued: QueuedNotice?

    var body: some View {
        List {
            Section {
                ForEach(rules) { rule in
                    NavigationLink {
                        BreakEditView(rule: rule, isNew: false, onSave: save)
                    } label: {
                        HStack {
                            Label(rule.timeLabel, systemImage: "cup.and.saucer.fill")
                            Spacer()
                            Text("\(rule.minutes) min · \(pluralItems(rule.itemCount))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)

                NavigationLink {
                    BreakEditView(rule: BreakRule(), isNew: true, onSave: save)
                } label: {
                    Label("Add break", systemImage: "plus")
                }
            } footer: {
                Text("A break opens its apps and websites at the set time every day for its minutes of use, no selfie needed. Outside breaks, normal blocking applies. Hard blocks and spent time limits stay blocked during breaks.")
            }
        }
        .navigationTitle("Scheduled breaks")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { rules = SharedStore.shared.breakRules }
        .queuedChangeAlert($queued)
    }

    // New breaks, and edits granting different free time (more minutes,
    // another start time, added items), are weakenings the gate may queue.
    private func save(_ saved: BreakRule) {
        if proposeOrNotify(.upsertBreakRule(saved), into: $queued) {
            rules = SharedStore.shared.breakRules
        }
    }

    private func delete(at offsets: IndexSet) {
        for rule in offsets.map({ rules[$0] }) {
            _ = proposeOrNotify(.deleteBreakRule(rule.id), into: $queued)
        }
        rules = SharedStore.shared.breakRules
    }
}

struct BreakEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: BreakRule
    let isNew: Bool
    let onSave: (BreakRule) -> Void

    private let minuteOptions = [5, 10, 15, 20, 30, 45, 60]

    // The rule stores a minute-of-day; the picker wants a Date. Only the
    // hour and minute survive the round trip.
    private var startTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: rule.startHour,
                    minute: rule.startMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                rule.startMinuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        List {
            // The rule is local until Save, so commit needs no extra work.
            SelectionEditor(
                selection: $rule.selection,
                footer: "Everything in this break opens together. Swipe an item left to remove it."
            ) { _ in }

            Section {
                DatePicker("Starts at", selection: startTime, displayedComponents: .hourAndMinute)
                Picker("Minutes", selection: $rule.minutes) {
                    ForEach(minuteOptions, id: \.self) { Text("\($0) min") }
                }
            } footer: {
                Text("The minutes are a budget of actual use, spendable from the start time until the window closes \(rule.windowMinutes) minutes later (the system requires a window of at least 15 minutes). Blocking returns when the minutes are used up or the window closes.")
            }
        }
        .navigationTitle(isNew ? "New break" : "Edit break")
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
