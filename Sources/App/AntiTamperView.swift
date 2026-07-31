import SwiftUI

// Tamper resistance: the settings change delay and the queue it feeds.
// Lengthening the delay is immediate; shortening it is itself a weakening and
// waits out the current delay.
struct AntiTamperView: View {
    @State private var delay = SharedStore.shared.delayMinutes
    @State private var deletePrevention = SharedStore.shared.deletePreventionEnabled
    @State private var queued: QueuedNotice?

    private let delayOptions = [0, 60, 360, 720, 1440, 2880, 4320]

    var body: some View {
        List {
            Section {
                Picker("Settings change delay", selection: $delay) {
                    ForEach(delayOptions, id: \.self) { Text(delayHoursLabel($0)) }
                }
                .onChange(of: delay) { minutes in
                    if !proposeOrNotify(.setDelay(minutes), into: $queued) {
                        delay = SharedStore.shared.delayMinutes
                    }
                }
            } footer: {
                Text("Any change that weakens protection (removing a blocked item, lengthening the unlock duration, turning protection off) waits this long before taking effect, with a visible countdown and one-tap cancel. Strengthening changes are always immediate.")
            }

            Section {
                Toggle("Prevent app deletion", isOn: $deletePrevention)
                    .onChange(of: deletePrevention) { on in
                        if !proposeOrNotify(.setDeletePrevention(on), into: $queued) {
                            deletePrevention = SharedStore.shared.deletePreventionEnabled
                        }
                    }
            } footer: {
                Text("Uses the OS app-removal restriction: no app on this device can be deleted, PlusOne included. The restriction is device-wide by iOS design. Turning it on is immediate; turning it off waits out the delay. Limitation: revoking PlusOne's Screen Time permission in the Settings app clears it, so have a friend set the device's Screen Time passcode.")
            }

            Section {
                NavigationLink {
                    PendingChangesView()
                } label: {
                    HStack {
                        Label("Pending changes", systemImage: "clock")
                        Spacer()
                        // Read per render: queueing from this screen must
                        // reflect immediately, before any onAppear.
                        Text("\(SharedStore.shared.pendingChanges.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            FriendPairingSection(queued: $queued)
            FriendInboxSection()
        }
        .navigationTitle("Anti-tamper")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            delay = SharedStore.shared.delayMinutes
            deletePrevention = SharedStore.shared.deletePreventionEnabled
            Task { await FriendSync.shared.sync() }
        }
        .queuedChangeAlert($queued)
    }
}
