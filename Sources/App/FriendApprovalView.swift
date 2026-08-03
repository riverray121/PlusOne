import SwiftUI
import CloudKit
import UIKit

// Friend approval sections for AntiTamperView: the owner-side pairing state
// and the companion-side inbox.
// The share sheet item lives in the parent screen: presentation modifiers
// attached to a Section inside a List present and then immediately dismiss.
struct FriendPairingSection: View {
    @ObservedObject private var friendSync = FriendSync.shared
    @Binding var queued: QueuedNotice?
    @Binding var sharePresentation: SharePresentation?
    @State private var isPreparing = false

    var body: some View {
        Section {
            switch friendSync.ownerState {
            case .none:
                Button {
                    startPairing()
                } label: {
                    if isPreparing {
                        Label {
                            Text("Preparing invitation")
                        } icon: {
                            ProgressView()
                        }
                    } else {
                        Label("Pair with a friend", systemImage: "person.badge.plus")
                    }
                }
                .disabled(isPreparing)
            case .invited:
                Label("Invitation sent", systemImage: "person.2.wave.2")
                Button("Show invitation again") { startPairing() }
                    .disabled(isPreparing)
                Button("Withdraw invitation", role: .destructive) {
                    friendSync.resetPairing()
                }
            case .paired:
                Label(pairedLabel, systemImage: "person.2.fill")
                    .foregroundStyle(.green)
                Button("Invite another friend") { startPairing() }
                    .disabled(isPreparing)
                Button(friendSync.ownerFriendNames.count > 1 ? "Unpair friends" : "Unpair friend", role: .destructive) {
                    _ = proposeOrNotify(.unpairFriend, into: $queued)
                }
            }
            if let error = friendSync.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Friend approval")
        } footer: {
            Text("Paired friends can approve your changes. While a change sits in Pending changes, you can send it to them: an approval makes it happen right away, a no throws it away, and no answer means the delay timer decides.")
        }
    }

    private var pairedLabel: String {
        let names = friendSync.ownerFriendNames
        guard !names.isEmpty else { return "Paired with your friend" }
        return "Paired with \(ListFormatter.localizedString(byJoining: names))"
    }

    // The guard and flag stop double-taps from racing two share creations;
    // the spinner is the immediate feedback while CloudKit round-trips.
    private func startPairing() {
        guard !isPreparing else { return }
        isPreparing = true
        Task {
            defer { isPreparing = false }
            do {
                let share = try await friendSync.prepareShare()
                sharePresentation = SharePresentation(share: share)
            } catch {
                friendSync.report(error)
            }
        }
    }
}

struct FriendInboxSection: View {
    @ObservedObject private var friendSync = FriendSync.shared

    var body: some View {
        if friendSync.isCompanion {
            Section {
                if friendSync.incomingRequests.isEmpty {
                    Text("No requests right now.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(friendSync.incomingRequests) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.summary)
                            HStack {
                                Button("Approve") {
                                    friendSync.respond(request, approve: true)
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Deny", role: .destructive) {
                                    friendSync.respond(request, approve: false)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Approve for \(friendSync.companionFriendName ?? "your friend")")
            } footer: {
                Text("When \(friendSync.companionFriendName ?? "your friend") asks you to approve a change to their protection, it shows up here. Approve and it happens right away. Deny and nothing changes.")
            }
        }
    }
}

struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
}

// UICloudSharingController drives invitation, acceptance status, and stop
// sharing; CloudKit has no SwiftUI equivalent with participant management.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: share,
            container: CKContainer(identifier: FriendSync.containerID)
        )
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? {
            FriendSync.shareTitle
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in
                FriendSync.shared.report(error)
            }
        }

        // The save callback is the only signal an invitation actually went
        // out; cancelling the sheet fires neither delegate method.
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            Task { @MainActor in
                FriendSync.shared.invitationSent()
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                FriendSync.shared.resetPairing()
            }
        }
    }
}
