import SwiftUI
import FamilyControls

// Selfie-unlock blocks: the picker selection plus the session settings that
// only govern selfie unlocks (duration, cooldown, daily cap).
struct SelfieBlockView: View {
    @EnvironmentObject private var appState: AppState
    @State private var duration = SharedStore.shared.durationMinutes
    @State private var cooldown = SharedStore.shared.cooldownMinutes
    @State private var cap = SharedStore.shared.dailyCap
    @State private var warn = SharedStore.shared.sessionWarnMinutes

    private let durationOptions = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    private let cooldownOptions = [0, 5, 15, 30, 60, 120]
    private let capOptions = Array(0...10)
    private let warnOptions = [0, 1, 2, 5, 10]

    var body: some View {
        List {
            // appState.selection's observer persists and re-shields on every
            // assignment, so commit needs no extra work here.
            SelectionEditor(
                selection: $appState.selection,
                footer: "Blocked until a selfie shows at least two people, then unlocked for the duration below. Swipe an item left to remove it."
            ) { _ in }

            Section {
                Picker("Unlock duration", selection: $duration) {
                    ForEach(durationOptions, id: \.self) { Text("\($0) min") }
                }
                .onChange(of: duration) { SharedStore.shared.durationMinutes = $0 }

                Picker("Cooldown", selection: $cooldown) {
                    ForEach(cooldownOptions, id: \.self) {
                        Text($0 == 0 ? "Off" : "\($0) min")
                    }
                }
                .onChange(of: cooldown) { SharedStore.shared.cooldownMinutes = $0 }

                Picker("Daily cap", selection: $cap) {
                    ForEach(capOptions, id: \.self) {
                        Text($0 == 0 ? "Off" : "\($0) sessions")
                    }
                }
                .onChange(of: cap) { SharedStore.shared.dailyCap = $0 }

                Picker("Warn when minutes left", selection: $warn) {
                    ForEach(warnOptions, id: \.self) {
                        Text($0 == 0 ? "Off" : "\($0) min")
                    }
                }
                .onChange(of: warn) { SharedStore.shared.sessionWarnMinutes = $0 }
            } footer: {
                Text("Duration is minutes of usage granted per selfie pass and applies to the next session. Cooldown is the wait required between sessions. The cap is the maximum sessions per day. The warning notifies when a session has this many minutes remaining; it is skipped when the duration is at or under the warning value.")
            }

            Section {
                Label("All processing happens on this device. Selfie frames are analyzed in memory and never stored.", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Selfie-unlock blocks")
        .navigationBarTitleDisplayMode(.inline)
    }
}
