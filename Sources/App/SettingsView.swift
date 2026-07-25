import SwiftUI

// The whole settings surface: duration, cooldown, daily cap.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var duration = SharedStore.shared.durationMinutes
    @State private var cooldown = SharedStore.shared.cooldownMinutes
    @State private var cap = SharedStore.shared.dailyCap

    private let durationOptions = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    private let cooldownOptions = [0, 5, 15, 30, 60, 120]
    private let capOptions = Array(0...10)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Unlock duration", selection: $duration) {
                        ForEach(durationOptions, id: \.self) { Text("\($0) min") }
                    }
                    .onChange(of: duration) { SharedStore.shared.durationMinutes = $0 }
                } footer: {
                    Text("Minutes of usage granted per selfie pass. Applies to the next session.")
                }

                Section {
                    Picker("Cooldown", selection: $cooldown) {
                        ForEach(cooldownOptions, id: \.self) {
                            Text($0 == 0 ? "Off" : "\($0) min")
                        }
                    }
                    .onChange(of: cooldown) { SharedStore.shared.cooldownMinutes = $0 }
                } footer: {
                    Text("Wait required between unlock sessions.")
                }

                Section {
                    Picker("Daily cap", selection: $cap) {
                        ForEach(capOptions, id: \.self) {
                            Text($0 == 0 ? "Off" : "\($0) sessions")
                        }
                    }
                    .onChange(of: cap) { SharedStore.shared.dailyCap = $0 }
                } footer: {
                    Text("Maximum unlock sessions per day.")
                }

                Section {
                    Label("All processing happens on this device. Selfie frames are analyzed in memory and never stored.", systemImage: "hand.raised.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
