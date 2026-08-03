import Foundation
import CloudKit
import UIKit

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
    // Shown as the invitation title and in the system share sheet.
    static let shareTitle = "PlusOne friend approval"
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

    // Returns the zone-wide share for the sharing sheet, creating the zone
    // and share on first use. Fetch-first keeps the re-tap path to a single
    // network call. fetchShare distinguishes "no share" from transient
    // errors; a swallowed error here would attempt a duplicate share save.
    // Owner state is untouched: a share with no participants has invited no
    // one, so only the sheet's save callback advances it.
    func prepareShare() async throws -> CKShare {
        await finishTeardown()
        if let existing = try await fetchShare() {
            #if DEBUG
            await registerSchema()
            #endif
            return existing
        }
        _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        #if DEBUG
        await registerSchema()
        #endif
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = Self.shareTitle as CKRecordValue
        // Without a thumbnail the invitation renders with a generic
        // document icon in Messages and the share sheet.
        if let thumbnail = UIImage(named: "FriendInvite")?.pngData() {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnail as CKRecordValue
        }
        share.publicPermission = .none
        do {
            let (saveResults, _) = try await privateDB.modifyRecords(saving: [share], deleting: [])
            for (_, result) in saveResults {
                _ = try result.get()
            }
        } catch let error as CKError where error.code == .serverRecordChanged {
            // The zone gained a share between the fetch and the save; use it.
            if let existing = try await fetchShare() {
                return existing
            }
            throw error
        }
        return share
    }

    #if DEBUG
    // CloudKit creates record types just-in-time only in the development
    // environment; production gets them solely via a console schema deploy.
    // Saving and deleting a throwaway ApprovalRequest here puts the type into
    // the development schema, so one deploy carries the complete schema and a
    // TestFlight build cannot hit "type not found" on its first request. Runs
    // on every prepareShare path (the zone may predate the bootstrap); the
    // flag keeps it to one round trip per install.
    private func registerSchema() async {
        guard !defaults.bool(forKey: "schemaRegistered") else { return }
        let recordID = CKRecord.ID(recordName: "schema-bootstrap", zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["summary"] = "schema bootstrap"
        record["status"] = Status.pending.rawValue
        do {
            _ = try await privateDB.modifyRecords(saving: [record], deleting: [])
            _ = try await privateDB.modifyRecords(saving: [], deleting: [recordID])
            defaults.set(true, forKey: "schemaRegistered")
        } catch {
            report(error)
        }
    }
    #endif

    // The sharing sheet saved the invitation: the only path that sends
    // anything to anyone.
    func invitationSent() {
        setOwnerState(.invited)
        Task { await ensureOwnerSubscription() }
    }

    // Invitation withdrawn, sharing stopped from the system UI, unpair
    // applied by the gate, or share revoked externally. Local state resets
    // immediately so the UI never waits on the network; the remote zone
    // deletion runs behind a flag and retries on later syncs if it fails.
    func resetPairing() {
        setOwnerState(.none)
        setRequestedIDs([])
        defaults.set(true, forKey: "teardownNeeded")
        Task { await finishTeardown() }
    }

    // Deleting the zone removes the share and every request with it. A
    // failure must never resurrect pairing state; it only lingers as cleanup
    // work for the next sync.
    private func finishTeardown() async {
        guard defaults.bool(forKey: "teardownNeeded") else { return }
        do {
            _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
            defaults.set(false, forKey: "teardownNeeded")
        } catch {
            report(error)
        }
    }

    // MARK: Owner: sync

    private func syncOwner() async {
        await finishTeardown()
        do {
            switch ownerState {
            case .none:
                break
            case .invited:
                guard let share = try await fetchShare() else {
                    resetPairing()
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
                    resetPairing()
                    break
                }
                guard try await fetchShare() != nil else {
                    // Share revoked outside the app: treat as unpaired.
                    // Queued approval-only changes stay queued; the user can
                    // cancel them, which is always allowed.
                    resetPairing()
                    break
                }
                try await reconcileRequests()
            }
            lastError = nil
        } catch {
            report(error)
        }
    }

    // localizedDescription for CKErrors is a record-ID dump; the server's own
    // reason string is the part that identifies the failure.
    func report(_ error: Error) {
        guard let ckError = error as? CKError else {
            lastError = error.localizedDescription
            return
        }
        let detail = ckError.userInfo["ServerErrorDescription"] as? String
            ?? ckError.localizedDescription
        lastError = "\(detail) (CKError \(ckError.code.rawValue))"
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
            let (_, deleteResults) = try await privateDB.modifyRecords(saving: [], deleting: ids)
            try checkDeletes(deleteResults)
        }

        guard !pending.isEmpty else {
            setRequestedIDs([])
            return
        }

        let ids = pending.map { CKRecord.ID(recordName: $0.id.uuidString, zoneID: zoneID) }
        let results = try await privateDB.records(for: ids)
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
            let (saveResults, deleteResults) = try await privateDB.modifyRecords(saving: toSave, deleting: toDelete)
            for (_, result) in saveResults {
                _ = try result.get()
            }
            try checkDeletes(deleteResults)
        }
        // Resolving drops approved and denied changes from the queue, so the
        // mirror tracks the queue as it stands, not `pending`.
        setRequestedIDs(SharedStore.shared.pendingChanges.map { $0.id.uuidString })
    }

    // A record already gone counts as deleted: a crash between a delete and
    // the requestedIDs update must not wedge every later sync. Any other
    // failure throws so the caller surfaces it and the next sync retries.
    private func checkDeletes(_ results: [CKRecord.ID: Result<Void, Error>]) throws {
        for (_, result) in results {
            do {
                try result.get()
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
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
                report(error)
            }
        }
    }

    private func syncCompanion() async {
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
            var records: [CKRecord] = []
            for zone in approvalZones {
                let zoneRecords = try await allRecords(in: zone.zoneID)
                records.append(contentsOf: zoneRecords.filter {
                    $0.recordType == Self.recordType
                        && $0["status"] as? String == Status.pending.rawValue
                })
            }
            incomingRequests = records
                .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
                .map { IncomingRequest(id: $0.recordID, summary: $0["summary"] as? String ?? "A settings change") }
            lastError = nil
        } catch {
            report(error)
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
                report(error)
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
    private func allRecords(in zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
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
            sharedDB.add(operation)
        }
    }
}
