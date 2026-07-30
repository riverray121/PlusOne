# PlusOne anti-tamper: Implementation

Vertical slices in build order. Each slice ends with a green simulator build;
Screen Time and CloudKit behavior additionally require the on-device checks
listed per slice.

## Slice 1: settings change delay
- `PendingChange` model: id, createdAt, appliesAt, summary, kind. Kinds:
  setProtection, removeSelfieItems, removeHardItems, setDuration,
  setCooldown, setDailyCap, setAdultFilter, upsertTimeLimitRule,
  deleteTimeLimitRule, setDelay, setDeletePrevention, unpairFriend.
- `ProtectionGate`: `propose(_:)` classifies direction and either applies or
  queues; `applyDue()` applies past-due changes; `cancel(_:)` removes one.
  Same-key proposals replace the existing pending change.
- `SharedStore` keys: `delayMinutes` (0 = off), `pendingChanges`.
- All weakening surfaces route through the gate: Home protection toggle,
  selfie selection removal, duration, cooldown, cap, hard selection removal,
  adult filter, time limit rule save and delete.
- `SelectionEditor`: picker merge becomes additive-only; row removal asks the
  owner whether to apply now (gated surfaces queue and keep the item).
- `AntiTamperView` with the delay picker; Home link. `PendingChangesView`
  with live countdowns and cancel; Home shows a pending section when
  non-empty.
- `applyDue()` runs in the foreground pass before shields refresh.
- Done when: sim build green; a weakening with delay on creates a visible
  pending change and leaves settings unchanged; cancel removes it;
  strengthening applies instantly; with delay off behavior matches
  milestone 1.

## Slice 2: delete prevention
- Toggle in `AntiTamperView` writing `application.denyAppRemoval` on the
  shared store. On applies instantly; off routes through the gate.
- UI states the restriction is device-wide and that revoking Screen Time
  permission clears it.
- Onboarding note: have a friend set the device's Screen Time passcode.
- Done when: sim build green; toggle state survives relaunch; on-device
  check: "Remove App" is absent while on.

## Slice 3: friend approval via CloudKit
- project.yml: iCloud (CloudKit, container `iCloud.com.riverray.PlusOne`),
  push entitlement, remote-notification background mode, `CKSharingSupported`
  in Info.plist. App target only.
- `FriendSync`: create `approvals` zone and zone-wide `CKShare`; present the
  share via `UICloudSharingController`; accept flow via scene delegate;
  mirror pairing state and request outcomes into `SharedStore`.
- Gate integration: queuing a weakening while paired also writes an
  `ApprovalRequest`; approved applies on resolution, denied discards the
  pending change, cancel marks the record cancelled. Delay countdown still
  applies when set.
- `FriendApprovalView`: companion inbox listing pending requests with
  approve and deny.
- Unpair routes through the gate.
- Done when: sim build green; two-device check: pair, request a weakening,
  approve on the friend device, change applies; deny discards; unpair
  requires approval or delay.

## On-device verification (both phones, after all slices)
1. Delay on, remove a blocked app: pending change with countdown, app stays
   blocked, cancel restores.
2. Countdown elapsed, relaunch: change applied.
3. Delete prevention on: "Remove App" gone everywhere; off goes through the
   delay.
4. Pairing, approval, denial, unpair per slice 3 done conditions.
