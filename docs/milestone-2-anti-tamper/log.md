# PlusOne anti-tamper: Dev Log

Development context for resuming work. Keep entries to one line. Not a changelog.

## Completed
- Slice 1: PendingChange + ProtectionGate, delay setting, pending list with countdown/cancel, all weakening surfaces gated; sim build green.
- Slice 2: delete prevention via denyAppRemoval on the shared store, Anti-tamper toggle, onboarding passcode note; sim build green.
- Slice 3: CloudKit friend approval (zone-wide share, ApprovalRequest records, database subscriptions, companion inbox, gate integration); sim build green.

## Todo
- [ ] On-device verification per implementation.md (delay, delete prevention; friend approval needs two devices with iCloud).

## Notes
- Every weakening flows through ProtectionGate.propose; UI never writes a weakening to SharedStore directly. Direction is judged against the stored value at proposal time.
- SelectionEditor's picker merge is additive-only (union of prior tokens back into the buffer); removal happens only in the token rows, where the removal closure can queue it. A gated surface returns false from the closure and the selection stays untouched.
- Gated pickers/toggles snap back by re-reading SharedStore inside onChange when propose returns .queued; the snap-back re-fires onChange with the stored value, which classifies as non-weakening and is a harmless same-value write.
- AppState.protectionEnabled is a side-effect-free mirror; setProtection routes through the gate and gate.apply owns shields/monitoring teardown. refresh() re-reads it plus selection after applyDue.
- Pending changes apply only in the foreground pass (PlusOneApp scenePhase .active) and PendingChangesView.onAppear; no background job, late application errs stronger.
- FriendSync is reconciliation-based: any nudge (push, foreground, queue mutation via .plusOnePendingChangesChanged) re-syncs full state, so missed pushes heal. ApprovalRequest recordName == pending change UUID; answered and cancelled records are deleted.
- Shared DBs only support CKDatabaseSubscription; the companion's carries a generic alertBody since database subscriptions cannot be record-specific.
- Share acceptance only reaches a scene delegate; AppDelegate injects SceneDelegate via configurationForConnecting while SwiftUI keeps the window. Needs device verification.
- A share revoked outside the app (either side) is detected on sync and treated as unpaired; approval-only pending changes (nil appliesAt) then wait until the user cancels them, which is always allowed. Owner-side revocation outside the app bypasses the unpair gate; same class of limitation as Screen Time permission revocation.
- denyAppRemoval rides the same named ManagedSettingsStore as shields but clearShields leaves it alone; protection off and delete prevention are independent.
- Delay bounds decided: Off, 1, 6, 12, 24, 48, 72 hours, default Off. Denied requests may be re-requested immediately.
- CloudKit entitlements (container iCloud.com.riverray.PlusOne, aps-environment, remote-notification background mode, CKSharingSupported) are app-target only; Shared stays CloudKit-free so extensions do not link it.
- Multiple friends are participants on the one zone-wide share; any accepted participant can flip a request's status. Unpair deletes the zone and removes everyone.
- Approval requests are explicit: PendingChange.approvalRequested gates mirroring to CloudKit; queuing alone notifies no one. Requests are sent per change from Pending changes.
- CKUserIdentity can return present-but-empty nameComponents; displayName maps blank to nil so copy falls back to "your friend".
- Screens listen for plusOnePendingChangesChanged so a friend's verdict updates open UI without a relaunch; the silent push still triggers the fetch.
