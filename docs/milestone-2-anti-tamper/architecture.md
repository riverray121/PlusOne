# PlusOne anti-tamper: Architecture

## Key decisions
- One gate for every weakening: `ProtectionGate` in `Sources/Shared/`. UI
  surfaces never write a weakening directly to `SharedStore`; they submit a
  typed change and the gate either applies it immediately (strengthening, or
  gating inactive) or persists it as a `PendingChange`.
- Gating is active when the change delay is nonzero or a friend is paired.
  With no delay and no friend, every change applies instantly (milestone 1
  behavior). With a friend and no delay, weakenings wait for approval with no
  countdown.
- Turning protection off is a weakening and goes through the gate. The design
  lists specific weakenings; without this one the whole system unlocks with a
  single toggle.
- Change direction is decided against the currently stored value at proposal
  time. Scalar weakenings store the target value and apply it as stored.
  Selection weakenings store the removed tokens as a diff and apply by
  subtraction, so late application cannot clobber items added in the
  meantime. Removal rebuilds a token-only selection (member-view resurrection
  trap, see milestone 1 log).
- A time limit rule edit is weakening if any component weakens (minutes
  increased, period day to hour, items removed, rule deleted). A mixed edit
  queues in full; a purely strengthening edit applies instantly. The pending
  payload is the full new rule.
- Proposing a change to a setting that already has a pending change replaces
  that pending change and restarts its countdown. Selection-removal changes
  accumulate as separate entries.
- Pending changes apply on the app's foreground pass (`scenePhase == .active`)
  before shields refresh. No scheduled job; late application errs stronger.
- Cancel is instant and always allowed; it deletes the pending change and,
  when paired, the next sync deletes the CloudKit request so the friend's
  inbox clears.
- Delete prevention sets `application.denyAppRemoval = true` on the shared
  named `ManagedSettingsStore`. `clearShields()` (protection off) does not
  touch it; the two toggles are independent.
- The picker in `SelectionEditor` merges additively on close; removal happens
  only in the token list rows, where it can be gated. Picker deselection was
  already unreliable (milestone 1 log) and is not a supported removal path.

## Friend approval (CloudKit)
- Container `iCloud.com.riverray.PlusOne`. A custom zone `approvals` in the
  owner's private database, shared zone-wide via `CKShare`; the friend
  accepts and sees it in their shared database.
- One record type `ApprovalRequest`: recordName is the pending change UUID;
  fields `summary` (plain language) and `status` (`pending`, `approved`,
  `denied`). The friend flips `status`; the share grants read-write. Answered
  and cancelled requests are deleted after processing.
- Both sides register a `CKDatabaseSubscription` (owner: private DB, friend:
  shared DB). The friend's subscription carries alert text; the owner's is
  silent (`content-available`) and triggers a fetch that resolves pending
  changes.
- Approved: the change applies on next resolution pass. Denied: the pending
  change and its countdown are discarded. Denial does not block re-requesting
  the same change (design open question resolved: immediate retry is allowed;
  each retry is a fresh visible request).
- CloudKit code lives in the app target only. The gate reads pairing state
  and request outcomes mirrored into `SharedStore`, so `Sources/Shared/`
  stays free of CloudKit.
- Unpairing is a weakening routed through the gate like any other.

## Resolved open questions
- Delay options: Off, 1, 6, 12, 24, 48, 72 hours. Default Off; the feature is
  opt-in. Lengthening applies instantly, shortening (including to Off) goes
  through the gate.
- Denied requests can be re-requested immediately.

## Structure
- `Sources/Shared/PendingChange.swift`: change model, kinds, direction rules.
- `Sources/Shared/ProtectionGate.swift`: propose, apply-due, cancel; the only
  writer of gated settings.
- `Sources/App/AntiTamperView.swift`: delay picker, delete prevention toggle,
  friend pairing entry, pending changes list.
- `Sources/App/PendingChangesView.swift`: countdown list with cancel.
- `Sources/App/FriendSync.swift`: CloudKit pairing, request sync, push
  handling (app target only).
- `Sources/App/FriendApprovalView.swift`: companion-role inbox (approve /
  deny).

## Risks / unknowns
- Countdowns compare against the device clock. Advancing the clock applies
  pending changes early; friend approval and a Screen Time passcode (which
  can restrict date changes) are the mitigations, not the app.
- CloudKit requires signed-in iCloud accounts on both devices and push, which
  need a physical device and active membership; the simulator proves
  compilation only.
- Revoking PlusOne's Screen Time permission clears `denyAppRemoval` and all
  shields. Not preventable from the app; the UI states it and onboarding
  suggests a friend-held Screen Time passcode.
- A `CKShare` can be revoked by either side outside the app's control; the
  sync layer must treat a missing zone or share as unpaired and surface it,
  never crash.
- Zone-wide sharing and database subscriptions behave differently across iOS
  versions; the flow needs verification on iOS 16 hardware.
