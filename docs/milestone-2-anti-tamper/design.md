# PlusOne anti-tamper: Design

## Summary
Three features that make weakening or escaping PlusOne's protection slow,
deliberate, and visible: a device-wide delete prevention toggle, a
user-configured delay on all protection-weakening settings changes, and
friend approval of weakening changes via CloudKit.

## Feature 1: Delete prevention

### How it works
- A single toggle in settings: "Prevent app deletion."
- When on, PlusOne sets the OS app-removal restriction (the same one Screen
  Time parental controls use). "Remove App" disappears everywhere; no app on
  the device can be deleted. The restriction is device-wide by OS design, and
  the UI states this plainly.
- The OS holds the restriction, so it persists while PlusOne is closed.
- Turning it on applies instantly. Turning it off is a weakening and goes
  through the settings change delay (feature 2).
- Honest limitation, shown in the UI: revoking PlusOne's Screen Time
  permission in the Settings app clears the restriction. Onboarding suggests
  having a friend set the device's Screen Time passcode to close that gap.

### Scope
- In: the toggle, instant-on, delayed-off, device-wide disclosure, onboarding
  note about the Screen Time passcode.
- Out: preventing permission revocation (not possible from an app), per-app
  deletion rules (the OS has none).

## Feature 2: Settings change delay

### How it works
- One delay duration, chosen in settings, options roughly 1 hour to 72 hours.
- Weakenings covered: removing an app or website from the blocked list,
  lengthening unlock duration, disabling cooldown or daily cap, turning off
  delete prevention, unpairing a friend (feature 3), and shortening the delay
  itself. The last rule is load-bearing: without it, the system unlocks by
  first dropping the delay to its minimum.
- A weakening change creates a pending change with a visible countdown and a
  one-tap cancel. Nothing takes effect until the countdown ends.
- Pending changes apply on the next app launch after their time passes. If
  the app stays closed, the stronger settings simply remain in force longer;
  late application always errs toward more protection.
- Strengthening (adding blocked items, shortening unlock duration, enabling
  cooldown or cap, lengthening the delay, enabling delete prevention) applies
  immediately and never queues.

### Scope
- In: single configurable delay, pending-change list with countdown and
  cancel, asymmetric instant-strengthen rule.
- Out: per-setting delays, escalating delays.

## Feature 3: Friend approval via CloudKit

### Why this is not a server
The project rule "no server" means: no backend that we build, rent, run, or
maintain, and no account system of our own. CloudKit is Apple's hosted sync
service, the same infrastructure iCloud uses for Photos and Notes. Apple
operates it, users are identified by the iCloud account already on their
phone, and the app ships no credentials and runs no infrastructure. Approval
requests do leave the device (they travel through iCloud to the friend's
phone), so the on-device rule is amended for this feature: the only data
synced is approval requests and responses. Selfies, camera frames, and usage
data never leave the device.

### How it works
- Pairing: both people install PlusOne; the friend's install runs in a
  companion role. One phone shows an iCloud share invite (or QR code), the
  other accepts, creating a shared CloudKit record zone between the two
  iCloud accounts.
- Requesting: the user sends a queued weakening change to their friends as an
  approval request record in the shared zone, in plain language ("Remove
  Instagram from blocking"). Sending is explicit; queuing alone notifies no
  one. The friend's phone gets a push notification via a CloudKit
  subscription; Apple delivers the push.
- Approving: the friend opens PlusOne, sees the request, taps approve or
  deny. The response syncs back; approved changes apply, denied ones are
  discarded.
- Interaction with the delay: delay or approval, whichever comes first.
  Approved: applies immediately. Denied: never applies and cancels the
  pending countdown. Ignored: the delay countdown still governs.
- Unpairing is itself a weakening: it requires the friend's approval or the
  full delay; otherwise the feature could remove itself instantly.
- Unreachable friend: requests wait; the user can cancel a pending request
  anytime (cancel strengthens, so it is always allowed).

### Scope
- In: pairing, multiple friends as participants on one share (any single
  approval suffices), user-initiated approval requests for queued weakenings,
  push notifications, unpair protection (unpairing removes all friends).
- Out: split approval, per-friend requests, messaging, any visibility into
  the user's activity beyond the requests themselves.

## Build order
1. Settings change delay: the foundation the other two lean on.
2. Delete prevention: small once the delay exists.
3. Friend approval: largest and riskiest piece (no iCloud account signed in,
   friend deletes the app, share revoked).

## Open questions
- Whether denial of a request should block re-requesting the same change for
  some period, or allow immediate retry.
- Minimum and maximum bounds for the delay setting.
