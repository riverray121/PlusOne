import SwiftUI

// Tamper resistance: the settings change delay and the queue it feeds.
// Lengthening the delay is immediate; shortening it is itself a weakening and
// waits out the current delay.
struct AntiTamperView: View {
    @State private var delay = SharedStore.shared.delayMinutes
    @State private var deletePrevention = SharedStore.shared.deletePreventionEnabled
    @State private var queued: QueuedNotice?
    @State private var sharePresentation: SharePresentation?

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
                Text("While this is on, no app on this phone can be deleted, including PlusOne itself. Turning it back off counts as loosening your protection, so it waits out the delay.")
            }

            Section {
                // Proposed only when an edit is finished: every keystroke
                // would otherwise queue its own pending change.
                NumberField(
                    title: "Change delay",
                    value: $delay,
                    range: 0...SettingLimits.maxWaitMinutes,
                    units: [.minutes, .hours, .days]
                ) {
                    guard delay != SharedStore.shared.delayMinutes else { return }
                    if !proposeOrNotify(.setDelay(delay), into: $queued) {
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
                Text("Any change that loosens your protection has to wait this long before it takes effect. While it waits you can cancel it. Changes that tighten protection happen right away. Set it to 0 to turn the delay off.")
            }

            FriendPairingSection(queued: $queued, sharePresentation: $sharePresentation)
            FriendInboxSection()
        }
        .numberPadDoneButton()
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
        // Applied verdicts change the delay, toggle states, and the pending
        // count; re-read so this screen follows without a reappear.
        .onReceive(
            NotificationCenter.default.publisher(for: .plusOnePendingChangesChanged)
                .receive(on: RunLoop.main)
        ) { _ in
            delay = SharedStore.shared.delayMinutes
            deletePrevention = SharedStore.shared.deletePreventionEnabled
        }
        .queuedChangeAlert($queued)
    }
}
