import SwiftUI
import CloudKit
import UIKit

// Friend approval sections for AntiTamperView: the owner-side pairing state
// and the companion-side inbox.
struct FriendPairingSection: View {
    @ObservedObject private var friendSync = FriendSync.shared
    @Binding var queued: QueuedNotice?
    @State private var sharePresentation: SharePresentation?

    var body: some View {
        Section {
            switch friendSync.ownerState {
            case .none:
                Button {
                    startPairing()
                } label: {
                    Label("Pair with a friend", systemImage: "person.badge.plus")
                }
            case .invited:
                Label("Invitation sent", systemImage: "paperplane")
                Button("Show invitation again") { startPairing() }
                Button("Withdraw invitation", role: .destructive) {
                    friendSync.abandonShare()
                }
            case .paired:
                Label("Friend paired", systemImage: "person.2.fill")
                    .foregroundStyle(.green)
                Button("Unpair friend", role: .destructive) {
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
            Text("Weakening changes go to your friend: approved applies now, denied is discarded, unanswered falls back to the delay. Only requests and responses sync over iCloud.")
        }
        .sheet(item: $sharePresentation) { presentation in
            CloudSharingSheet(share: presentation.share)
                .ignoresSafeArea()
        }
    }

    private func startPairing() {
        Task {
            do {
                let share = try await friendSync.prepareShare()
                sharePresentation = SharePresentation(share: share)
            } catch {
                friendSync.lastError = error.localizedDescription
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
                    Text("No requests.")
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
                Text("Approve for your friend")
            } footer: {
                Text("Approving applies your friend's change immediately; denying discards it.")
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
                FriendSync.shared.lastError = error.localizedDescription
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                FriendSync.shared.abandonShare()
            }
        }
    }
}
