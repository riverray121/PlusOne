import SwiftUI

// Queued weakenings: each row shows its countdown and a one-tap cancel.
// Cancelling keeps the current, stronger settings.
struct PendingChangesView: View {
    @State private var changes = SharedStore.shared.pendingChanges

    var body: some View {
        List {
            if changes.isEmpty {
                Section {
                    Text("No pending changes.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(sortedChanges) { change in
                        row(change)
                    }
                } footer: {
                    Text("These changes are waiting out your delay. Each one takes effect the next time you open the app after its countdown ends. Cancel keeps things as they are.")
                }
            }
        }
        .navigationTitle("Pending changes")
        .navigationBarTitleDisplayMode(.inline)
        // A countdown may have lapsed while this screen was off; apply before
        // showing so the list never lists an already-due change as pending.
        .onAppear {
            ProtectionGate.shared.applyDue()
            changes = SharedStore.shared.pendingChanges
            Task { await FriendSync.shared.sync() }
        }
        // A friend's verdict can land while this screen is open; the gate
        // posts after every queue mutation.
        .onReceive(
            NotificationCenter.default.publisher(for: .plusOnePendingChangesChanged)
                .receive(on: RunLoop.main)
        ) { _ in
            changes = SharedStore.shared.pendingChanges
        }
    }

    private var sortedChanges: [PendingChange] {
        changes.sorted { ($0.appliesAt ?? .distantFuture) < ($1.appliesAt ?? .distantFuture) }
    }

    private func row(_ change: PendingChange) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.summary)
                    status(change)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    ProtectionGate.shared.cancel(change.id)
                    changes = SharedStore.shared.pendingChanges
                }
                .buttonStyle(.bordered)
            }
            if SharedStore.shared.friendPaired && !change.approvalRequested {
                Button("Ask a friend to approve") {
                    ProtectionGate.shared.requestApproval(change.id)
                    changes = SharedStore.shared.pendingChanges
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func status(_ change: PendingChange) -> some View {
        // One Date sample: the range below must not invert if the deadline
        // passes between a check and the range construction.
        let now = Date()
        if let appliesAt = change.appliesAt {
            if appliesAt <= now {
                Text("Applies on next launch")
            } else if change.approvalRequested {
                Text("Applies in ") + Text(timerInterval: now...appliesAt, countsDown: true) + Text(", or sooner if a friend approves")
            } else {
                Text("Applies in ") + Text(timerInterval: now...appliesAt, countsDown: true)
            }
        } else if change.approvalRequested {
            Text("Waiting for a friend's approval")
        } else {
            Text("Waits until a friend approves")
        }
    }
}

// Feedback that a weakening was queued instead of applied.
struct QueuedNotice {
    let summary: String
    let appliesAt: Date?

    init(_ change: PendingChange) {
        summary = change.summary
        appliesAt = change.appliesAt
    }

    var message: String {
        guard let appliesAt else {
            return "\(summary): waits until a friend approves it. Send or cancel it under Pending changes."
        }
        return "\(summary): applies \(appliesAt.formatted(date: .abbreviated, time: .shortened)) unless cancelled under Pending changes."
    }
}

// Shared shape of every gated control: propose, and on queue surface the
// notice. Returns whether the change applied, so callers can snap a picker
// or toggle back to the stored value.
func proposeOrNotify(_ kind: PendingChange.Kind, into queued: Binding<QueuedNotice?>) -> Bool {
    switch ProtectionGate.shared.propose(kind) {
    case .applied:
        return true
    case .queued(let change):
        queued.wrappedValue = QueuedNotice(change)
        return false
    }
}

extension View {
    func queuedChangeAlert(_ notice: Binding<QueuedNotice?>) -> some View {
        alert(
            "Change scheduled",
            isPresented: Binding(
                get: { notice.wrappedValue != nil },
                set: { if !$0 { notice.wrappedValue = nil } }
            ),
            presenting: notice.wrappedValue
        ) { _ in
            Button("OK") {}
        } message: { presented in
            Text(presented.message)
        }
    }
}
