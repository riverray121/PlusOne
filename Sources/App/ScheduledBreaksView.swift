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
                            Text("\(rule.minutes) min / \(hoursOrMinutesLabel(rule.windowMinutes))")
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
                Text("During a break, the apps and websites in it can be opened without a selfie. Breaks repeat every day at the time you set. Apps that are hard-blocked or have used up their time limit stay blocked even during a break.")
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

    private let windowOptions = [15, 30, 45, 60, 90, 120, 180, 240]

    private var minuteOptions: [Int] {
        [5, 10, 15, 20, 30, 45, 60, 90, 120].filter { $0 <= rule.windowMinutes }
    }

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
                footer: "Swipe an item left to remove it."
            ) { _ in }

            Section {
                // The compact date picker's capsule makes its row taller than
                // the menu pickers below; capping its height lets the row
                // settle to the same standard height.
                DatePicker("Starts at", selection: startTime, displayedComponents: .hourAndMinute)
                    .frame(maxHeight: 36)
                Picker("Window", selection: $rule.windowMinutes) {
                    ForEach(windowOptions, id: \.self) { Text(hoursOrMinutesLabel($0)) }
                }
                .onChange(of: rule.windowMinutes) { window in
                    if rule.minutes > window { rule.minutes = window }
                }
                Picker("Minutes of use", selection: $rule.minutes) {
                    ForEach(minuteOptions, id: \.self) { Text("\($0) min") }
                }
            } footer: {
                Text("The minutes are a budget you can spend at any point during the window. Blocking comes back once the minutes are used up or the window ends.")
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
