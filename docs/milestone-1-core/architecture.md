# PlusOne core: Architecture

## Stack
- Swift + SwiftUI, iOS 16 minimum: individual Screen Time authorization requires iOS 16.
- FamilyControls, ManagedSettings, DeviceActivity: the only sanctioned iOS mechanism for blocking apps and websites.
- AVFoundation + Vision: live front-camera capture and on-device face detection.
- XcodeGen: the four-target project is defined in `project.yml`; the generated `.xcodeproj` is not committed.

## Key decisions
- Individual authorization (`AuthorizationCenter`, `.individual`): the user manages their own device. No family setup, no MDM.
- Four targets: the app plus three extensions (shield UI, shield action, activity monitor). Apple runs each in its own sandboxed process; the split is mandated by the platform.
- Shared state lives in an App Group (`group.com.riverray.plusone`): settings, session state, and the archived `FamilyActivitySelection`. App and extensions read the same store.
- Per-item unlock handoff: the shield action extension receives the blocked item's token, writes it to the App Group as the pending unlock request, and posts a local notification that deep links into the app. Shield buttons cannot launch an app directly; the notification hop is the only route.
- Re-lock is enforced by `DeviceActivityMonitor.intervalDidEnd` on a schedule started at unlock. In-app timers die on suspension and are never used for enforcement.
- Face check: `VNDetectFaceRectanglesRequest` on the live feed. Pass requires at least 2 faces, each bounding box at least 12% of frame height, sustained across ~1.5 s of consecutive samples. Frames never leave the capture pipeline.
- Cooldown and daily cap are enforced in the app before the camera opens, using counters in the App Group store that reset by calendar day.

## Structure
- `Sources/App/`: SwiftUI app. Screens: Onboarding, Home, Capture, Settings. Services: `ShieldController` (wraps `ManagedSettingsStore`), `SessionManager` (unlock windows, cooldown, cap), `FaceCheck` (capture + Vision).
- `Sources/ShieldUI/`: shield configuration extension; block screen text and button.
- `Sources/ShieldAction/`: shield action extension; records the pending token, fires the notification.
- `Sources/Monitor/`: device activity monitor extension; re-applies the shield at interval end.
- `Sources/Shared/`: models, App Group store, constants; compiled into all four targets.
- Root: `project.yml`, `docs/`, `README.md`.

## Breakouts
None.

## Risks / unknowns
- Family Controls entitlement: development-signed builds need only the Xcode capability; TestFlight or App Store distribution requires Apple approval of the distribution entitlement.
- The shield-to-app hop depends on the user tapping a local notification. If iOS defers it or the user dismisses it, the fallback is opening PlusOne manually; the capture screen must be one tap from Home.
- Screen Time behavior is physical-device only; simulator runs prove nothing about enforcement.
- `ApplicationToken` is opaque and only comparable within the current selection. The pending-unlock handoff must never persist tokens beyond the life of the selection that produced them.
