# PlusOne core: Implementation

Thin vertical slices in build order. Each is independently testable end-to-end.

## Slice 1: Project scaffold
- Goal: four-target project that builds and runs on a physical iPhone.
- Touches: `project.yml`, entitlement files, App Group config, placeholder sources for all targets, `.gitignore`.
- Acceptance:
  - `xcodegen generate` produces a project in which all four targets build.
  - App launches on device showing a placeholder Home screen.
  - All targets carry the App Group and Family Controls capabilities.
- Out of scope: real UI, any blocking logic.

## Slice 2: Block and unblock
- Goal: chosen apps and websites actually shield.
- Touches: App target (authorization flow, `FamilyActivityPicker`, protection toggle on Home), `Sources/Shared` store, `ShieldController`.
- Acceptance:
  - Screen Time permission prompt appears once; granted state survives relaunch.
  - Enabling protection shields the picked apps and websites, verified on device including a Safari domain.
  - Disabling protection unshields everything.
- Out of scope: selfie check, timed sessions, custom shield appearance.

## Slice 3: Live two-face check
- Goal: standalone camera screen that passes only with two live faces.
- Touches: App target (Capture screen, `FaceCheck` service).
- Acceptance:
  - Face count indicator updates live; one face never passes.
  - Two faces held ~1.5 s passes; a photo waved past the camera does not.
  - No image data is written anywhere; frames stay in the capture pipeline.
- Out of scope: any connection to shielding.

## Slice 4: Unlock loop
- Goal: the core loop, block screen to selfie to timed unlock to automatic re-lock.
- Touches: ShieldUI, ShieldAction, and Monitor extensions; App deep link handling; `SessionManager`.
- Acceptance:
  - A blocked app's shield shows the custom message and unlock button.
  - The button leads, via notification tap, to the Capture screen.
  - A pass unshields only the prompting item, which then opens normally.
  - After the configured duration the shield returns without PlusOne being opened.
- Out of scope: cooldown, daily cap, settings UI.

## Slice 5: Session rules
- Goal: duration, cooldown, and daily cap are configurable and enforced.
- Touches: Settings screen, `SessionManager`, `Sources/Shared` store.
- Acceptance:
  - A duration change applies to the next session.
  - With a cooldown set, a new check is refused until it elapses, and the remaining wait is shown.
  - With a cap set, the session after the Nth is refused; the counter resets the next calendar day.
- Out of scope: onboarding polish.

## Slice 6: Presentation
- Goal: portfolio-ready first impression.
- Touches: Onboarding flow, visual pass on Home and Settings, shield styling, README with screenshots and a demo GIF.
- Acceptance:
  - A fresh install reaches active protection through onboarding alone.
  - README explains the app, the unlock loop, and the platform constraints, with media.
- Out of scope: App Store assets, anti-tamper features.
