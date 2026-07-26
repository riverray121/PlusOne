# PlusOne: On-device test script

Run in order on a physical iPhone (iOS 16+). Each step states what proves it
passed. Prerequisite: a second person (or a co-conspirator photo, to prove the
liveness check rejects it).

## Setup (one time)
Blocked until the Apple Developer Program renewal (ordered 2026-07-26, order
W1691124427) is active. Family Controls does not work on free Personal Teams.

1. Confirm activation: the "Welcome to the Apple Developer Program" email
   arrived and https://developer.apple.com/account shows the membership as
   active. If it still shows expired, stop; nothing below will work yet.
2. Prune devices: https://developer.apple.com/account/resources/devices/list
   is over its limit from the previous membership year. Remove stale devices
   (or take the one-time reset offered at renewal) so the current iPhone can
   register.
3. In Xcode > Settings > Accounts, select the Apple ID and refresh (or remove
   and re-add it) so the paid team appears alongside the Personal Team.
4. In `PlusOne.xcodeproj`, select each of the 4 main targets (PlusOne,
   ShieldUIExtension, ShieldActionExtension, MonitorExtension) > Signing &
   Capabilities > pick the paid team (the one NOT labeled "Personal Team").
   The Family Controls warning should clear. PlusOneLite can stay on the
   Personal Team; it is temporary and gets deleted after device testing.
5. Select the PlusOne scheme (not PlusOneLite), destination = the iPhone,
   press Run. Trust the developer cert on the phone if prompted
   (Settings > General > VPN & Device Management). Developer Mode is already
   enabled from the lite-build session.

## Test 1: Onboarding
1. Complete all three permission rows. Screen Time shows a system consent
   sheet; approve it.
2. Choose 1 test app you don't mind blocking (pick something harmless like
   Notes, not just social media) and 1 website domain if offered.
3. Tap "Start protecting."
- Pass: Home shows "Protection on" with your item count.

## Test 2: Shield appears
1. Go to the home screen, open the blocked app.
- Pass: a dark block screen appears with "Blocked by PlusOne" and an
  "Unlock with a selfie" button instead of the app.

## Test 3: Unlock hop
1. On the block screen, tap "Unlock with a selfie."
- Pass: a notification appears ("Unlock with a selfie"); tapping it opens
  PlusOne directly into the camera screen.
- Fallback also counts as pass: if no notification, open PlusOne manually;
  the camera screen should appear on its own.

## Test 4: Selfie check
The capture screen should show "Depth check on" (TrueDepth active) and, in
debug builds, a live "depth spread" readout per face. Real faces read roughly
15mm and up; screens/photos read near 0 to 5mm. Threshold is 8mm
(`FaceCheck.minDepthStdDev`); note readings that land on the wrong side.

1. Point the camera at yourself only. Hold 3+ seconds.
- Pass: counter stays at "1 of 2," progress never completes.
2. Hold a face photo on a phone screen next to yours, steady and close.
- Pass: counter stays at "1 of 2"; the flat screen face is rejected by the
  depth check even when held perfectly still.
3. Same with a printed photo or a photo waved around.
- Pass: no sustained "2 of 2."
4. With a second person in frame, hold still ~2 seconds.
- Pass: "Unlocked for 5 minutes" confirmation appears.

## Test 5: Session and re-lock
1. Reopen the blocked app.
- Pass: it opens normally, no shield.
2. Use it (screen on, app foregrounded) for ~5 to 6 minutes.
- Pass: the shield returns over the app. Usage tracking can lag a minute or
  two; up to 16 minutes of wall clock is the backstop worst case.

## Test 6: Session rules
1. In PlusOne Settings, set duration to 1 min, cooldown to 5 min, daily cap
   to 2.
2. Unlock again with a selfie, use the app ~1 to 2 min until re-lock.
3. Immediately tap unlock on the shield again.
- Pass: PlusOne shows "Cooling down" with minutes remaining, no camera.
4. After cooldown, do 1 more full unlock (that is session 2), then attempt a
   third.
- Pass: "Daily cap reached."

## Test 7: Website blocking
1. Ensure a domain (e.g. instagram.com) is in the blocked list. Open it in
   Safari.
- Pass: the block screen appears over the page; the unlock flow works as in
  Tests 3 to 5.

## Known rough edges to note, not fail
- Threshold-based re-lock counts usage minutes, not wall clock; leaving the
  app idle stretches the session up to the backstop.
- The unlock notification can take a second or two to arrive.

Record any failure with: which test, what happened instead, and a screenshot.
