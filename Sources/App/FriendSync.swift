import Foundation
import CloudKit

// CloudKit friend approval. Two roles, both possible on one device: owner
// (this device's weakenings need the friend's approval) and companion (this
// device approves a friend's weakenings).
//
// Storage: a custom zone "approvals" in the owner's private database, shared
// zone-wide with one friend. Each queued weakening mirrors to an
// ApprovalRequest record whose recordName is the pending change's UUID; the
// friend flips its status field and the owner resolves on fetch. Only these
// requests and responses ever leave the device.
//
// The gate reads pairing state from SharedStore; this class is the only
// CloudKit code and the only writer of that mirror. All sync is
// reconciliation against current state, so a missed push or failed call is
// healed by the next sync().
@MainActor
final class FriendSync: ObservableObject {
    static let shared = FriendSync()

    static let containerID = "iCloud.com.riverray.PlusOne"
    private static let zoneName = "approvals"
    private static let recordType = "ApprovalRequest"

    enum Status: String {
        case pending, approved, denied
    }

    enum OwnerState: String {
        case none, invited, paired
    }

    struct IncomingRequest: Identifiable {
        let id: CKRecord.ID
        let summary: String
    }

    private let container = CKContainer(identifier: FriendSync.containerID)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    @Published private(set) var ownerState: OwnerState
    @Published private(set) var isCompanion: Bool
    @Published private(set) var incomingRequests: [IncomingRequest] = []
    @Published var lastError: String?

    private let defaults = UserDefaults.standard

    private init() {
        ownerState = OwnerState(rawValue: defaults.string(forKey: "ownerPairingState") ?? "") ?? .none
        isCompanion = defaults.bool(forKey: "companionPaired")
        NotificationCenter.default.addObserver(
            forName: .plusOnePendingChangesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.syncOwner() }
        }
    }

    private func setOwnerState(_ state: OwnerState) {
        ownerState = state
        defaults.set(state.rawValue, forKey: "ownerPairingState")
        SharedStore.shared.friendPaired = state == .paired
    }

    private func setCompanion(_ on: Bool) {
        isCompanion = on
        defaults.set(on, forKey: "companionPaired")
    }

    func sync() async {
        await syncOwner()
        await syncCompanion()
    }

    // MARK: Owner: pairing

    // Creates (or reuses) the zone and its zone-wide share for the sharing
    // sheet. Pairing completes when the friend accepts.
    func prepareShare() async throws -> CKShare {
        _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        await ensureOwnerSubscription()
        // fetchShare distinguishes "no share" from transient errors; a
        // swallowed error here would attempt a duplicate share save.
        if let existing = try await fetchShare() {
            if ownerState == .none { setOwnerState(.invited) }
            return existing
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "PlusOne friend approval" as CKRecordValue
        share.publicPermission = .none
        let (saveResults, _) = try await privateDB.modifyRecords(saving: [share], deleting: [])
        for (_, result) in saveResults {
            _ = try result.get()
        }
        setOwnerState(.invited)
        return share
    }

    // Invitation withdrawn before acceptance, or sharing stopped from the
    // system share UI. Pre-pairing this is not a weakening; the gate is not
    // involved.
    func abandonShare() {
        Task {
            do {
                try await teardownShare()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: Owner: sync

    func syncOwner() async {
        do {
            switch ownerState {
            case .none:
                break
            case .invited:
                guard let share = try await fetchShare() else {
                    setOwnerState(.none)
                    break
                }
                if share.participants.contains(where: { $0.role != .owner && $0.acceptanceStatus == .accepted }) {
                    setOwnerState(.paired)
                    await syncOwner()
                    return
                }
            case .paired:
                // Unpair applied by the gate: finish it in CloudKit.
                if !SharedStore.shared.friendPaired {
                    try await teardownShare()
                    break
                }
                guard try await fetchShare() != nil else {
                    // Share revoked outside the app: treat as unpaired.
                    // Queued approval-only changes stay queued; the user can
                    // cancel them, which is always allowed.
                    setOwnerState(.none)
                    setRequestedIDs([])
                    break
                }
                try await reconcileRequests()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchShare() async throws -> CKShare? {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await privateDB.record(for: shareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    // Record names already created remotely, kept so a locally cancelled
    // change can be deleted from the friend's inbox.
    private func requestedIDs() -> [String] {
        defaults.stringArray(forKey: "approvalRequestIDs") ?? []
    }

    private func setRequestedIDs(_ ids: [String]) {
        defaults.set(ids, forKey: "approvalRequestIDs")
    }

    private func reconcileRequests() async throws {
        let pending = SharedStore.shared.pendingChanges
        let pendingIDs = Set(pending.map { $0.id.uuidString })

        // Cancelled locally: remove the remote record so the friend's inbox
        // clears.
        let cancelled = requestedIDs().filter { !pendingIDs.contains($0) }
        if !cancelled.isEmpty {
            let ids = cancelled.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
            _ = try await privateDB.modifyRecords(saving: [], deleting: ids)
        }

        guard !pending.isEmpty else {
            setRequestedIDs([])
            return
        }

        let ids = pending.map { CKRecord.ID(recordName: $0.id.uuidString, zoneID: zoneID) }
        let results = try await privateDB.records(for: ids, desiredKeys: nil)
        var toSave: [CKRecord] = []
        var toDelete: [CKRecord.ID] = []
        for change in pending {
            let recordID = CKRecord.ID(recordName: change.id.uuidString, zoneID: zoneID)
            switch results[recordID] {
            case .success(let record):
                switch Status(rawValue: record["status"] as? String ?? "") {
                case .approved:
                    ProtectionGate.shared.resolve(change.id, approved: true)
                    toDelete.append(recordID)
                case .denied:
                    ProtectionGate.shared.resolve(change.id, approved: false)
                    toDelete.append(recordID)
                case .pending, .none:
                    break
                }
            case .failure, .none:
                let record = CKRecord(recordType: Self.recordType, recordID: recordID)
                record["summary"] = change.summary
                record["status"] = Status.pending.rawValue
                toSave.append(record)
            }
        }
        if !toSave.isEmpty || !toDelete.isEmpty {
            _ = try await privateDB.modifyRecords(saving: toSave, deleting: toDelete)
        }
        setRequestedIDs(SharedStore.shared.pendingChanges.map { $0.id.uuidString })
    }

    private func teardownShare() async throws {
        _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
        setOwnerState(.none)
        setRequestedIDs([])
    }

    // MARK: Companion

    func acceptShare(metadata: CKShare.Metadata) {
        Task {
            do {
                _ = try await container.accept(metadata)
                setCompanion(true)
                await ensureCompanionSubscription()
                await syncCompanion()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func syncCompanion() async {
        guard isCompanion else { return }
        do {
            let zones = try await sharedDB.allRecordZones()
            let approvalZones = zones.filter { $0.zoneID.zoneName == Self.zoneName }
            guard !approvalZones.isEmpty else {
                // The owner unpaired (zone deleted) or revoked the share.
                setCompanion(false)
                incomingRequests = []
                return
            }
            var requests: [(Date, IncomingRequest)] = []
            for zone in approvalZones {
                for record in try await allRecords(in: zone.zoneID, database: sharedDB)
                where record.recordType == Self.recordType
                    && record["status"] as? String == Status.pending.rawValue {
                    requests.append((
                        record.creationDate ?? .distantPast,
                        IncomingRequest(id: record.recordID, summary: record["summary"] as? String ?? "A settings change")
                    ))
                }
            }
            incomingRequests = requests.sorted { $0.0 < $1.0 }.map { $0.1 }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func respond(_ request: IncomingRequest, approve: Bool) {
        Task {
            do {
                let record = try await sharedDB.record(for: request.id)
                record["status"] = (approve ? Status.approved : Status.denied).rawValue
                let (saveResults, _) = try await sharedDB.modifyRecords(saving: [record], deleting: [])
                for (_, result) in saveResults {
                    _ = try result.get()
                }
                incomingRequests.removeAll { $0.id == request.id }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: Push

    // Both subscriptions are database subscriptions: the only kind CloudKit
    // supports for shared databases, and enough here since sync() reconciles
    // everything on any nudge.
    private func ensureOwnerSubscription() async {
        let subscription = CKDatabaseSubscription(subscriptionID: "owner-approvals")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await privateDB.save(subscription)
    }

    private func ensureCompanionSubscription() async {
        let subscription = CKDatabaseSubscription(subscriptionID: "shared-approvals")
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "Your friend asked to weaken their protection. Open PlusOne to review."
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await sharedDB.save(subscription)
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            return false
        }
        await sync()
        return true
    }

    // MARK: Fetch

    // Zone-change fetch with a nil token returns every record in the zone.
    // The zone holds at most a handful of requests, so no token bookkeeping.
    private func allRecords(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: .init()]
            )
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: records)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }
}
