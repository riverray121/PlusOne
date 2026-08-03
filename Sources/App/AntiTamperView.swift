import SwiftUI

// Tamper resistance: the settings change delay and the queue it feeds.
// Lengthening the delay is immediate; shortening it is itself a weakening and
// waits out the current delay.
struct AntiTamperView: View {
    @State private var delay = SharedStore.shared.delayMinutes
    @State private var deletePrevention = SharedStore.shared.deletePreventionEnabled
    @State private var queued: QueuedNotice?
    @State private var sharePresentation: SharePresentation?

    private let delayOptions = [0, 60, 360, 720, 1440, 2880, 4320]

    var body: some View {
        List {
            Section {
                Toggle("Prevent app deletion", isOn: $deletePrevention)
                    .onChange(of: deletePrevention) { on in
                        if !proposeOrNotify(.setDeletePrevention(on), into: $queued) {
                            deletePrevention = SharedStore.shared.deletePreventionEnabled
                        }
                    }
            } footer: {
                Text("While this is on, no app on this phone can be deleted, including PlusOne itself. Turning it back off is treated as a weakening change. Heads up: removing PlusOne's Screen Time permission in Settings also turns this off.")
            }

            Section {
                Picker("Settings change delay", selection: $delay) {
                    ForEach(delayOptions, id: \.self) { Text(delayHoursLabel($0)) }
                }
                .onChange(of: delay) { minutes in
                    if !proposeOrNotify(.setDelay(minutes), into: $queued) {
                        delay = SharedStore.shared.delayMinutes
                    }
                }

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
            } footer: {
                Text("Any change that weakens your protection has to wait this long before it takes effect. While it waits you can cancel it. Changes that make protection stronger happen right away.")
            }

            FriendPairingSection(queued: $queued, sharePresentation: $sharePresentation)
            FriendInboxSection()
        }
        .navigationTitle("Anti-tamper")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePresentation) { presentation in
            CloudSharingSheet(share: presentation.share)
                .ignoresSafeArea()
        }
        .onAppear {
            delay = SharedStore.shared.delayMinutes
            deletePrevention = SharedStore.shared.deletePreventionEnabled
            Task { await FriendSync.shared.sync() }
        }
        .queuedChangeAlert($queued)
    }
}
