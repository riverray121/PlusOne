# PlusOne

iOS app that blocks selected apps and websites until a live selfie shows at
least two faces, granting a timed unlock window (default 5 minutes).

Design and process live in `docs/`. Read them before starting work.

## Session start
Read `docs/index.md`, then the ACTIVE milestone's `log.md` and
`implementation.md`, then `design.md` / `architecture.md` as the task needs.
Only the ACTIVE milestone is current; ignore shipped ones unless asked.

## Stack
- Swift / SwiftUI: app and extension UI
- Screen Time APIs (FamilyControls, ManagedSettings, DeviceActivity): app blocking
- AVFoundation + Vision: live selfie capture and face detection
- XcodeGen: project generated from `project.yml`; the `.xcodeproj` is not committed

## Commands
- Generate project: `xcodegen generate`
- Build: `xcodebuild -project PlusOne.xcodeproj -scheme PlusOne -destination 'generic/platform=iOS' build`
- Test: `xcodebuild -project PlusOne.xcodeproj -scheme PlusOne -destination 'platform=iOS Simulator,name=iPhone 17' test`
- Run: from Xcode, on a physical iPhone (Screen Time APIs do not work in the simulator)

## Git
- Remote: `riverray121/PlusOne` (GitHub, public)
- Push: as work completes; no per-slice user-testing gate

## Standing rules
- Public portfolio repo: clean history, presentable README, no secrets, no
  scratch files or dead code committed.
- Screen Time behavior (shields, DeviceActivity) can only be verified on a
  physical device; simulator results are not proof.
- All processing is on-device. No server, no analytics, no image persistence;
  camera frames are analyzed in memory and discarded.
