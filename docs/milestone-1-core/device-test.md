# PlusOne: On-device test script

Run in order on a physical iPhone (iOS 16+). Each step states what proves it
passed. Prerequisite: a second person (or a co-conspirator photo, to prove the
liveness check rejects it).

## Setup (one time)
1. Open Xcode, sign in: Xcode > Settings > Accounts > add your Apple ID.
2. In `PlusOne.xcodeproj`, select each of the 4 targets > Signing &
   Capabilities > check "Automatically manage signing" and pick your personal
   team. (If the Family Controls capability shows a signing error, add your
   Apple ID's team first, then retry.)
3. Plug in the iPhone, enable Developer Mode if prompted
   (Settings > Privacy & Security > Developer Mode, requires restart).
4. Select the iPhone as the run destination, press Run.
5. First launch: trust the developer cert if prompted
   (Settings > General > VPN & Device Management).

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
1. Point the camera at yourself only. Hold 3+ seconds.
- Pass: counter stays at "1 of 2," progress never completes.
2. Hold up a photo of a face next to yours, wave it.
- Pass: brief flickers at most; sustained hold does not complete.
3. With a second person in frame, hold still ~2 seconds.
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
