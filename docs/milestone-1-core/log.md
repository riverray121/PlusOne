# PlusOne core: Dev Log

Development context for resuming work. Keep entries to one line. Not a changelog.

## Completed
- Slice 1: four-target XcodeGen project; all targets build for simulator.
- Slice 2: authorization flow, FamilyActivityPicker, protection toggle, ShieldController.
- Slice 3: Capture screen with FaceCheck (Vision, 2 faces at min height, 1.5 s hold).
- Slice 4: shield extensions, notification hop, per-item unlock, DeviceActivity re-lock.
- Slice 5: Settings with duration/cooldown/daily cap; gates enforced in SessionManager.
- Slice 6: onboarding, README with sim screenshots.

## Todo
- [ ] On-device verification of all Screen Time paths (shield, unlock hop, re-lock).

## Notes
- Depth liveness: on TrueDepth devices each counted face must deviate >= 4mm RMS from its best-fit plane (FaceCheck.minDepthResidual). Plane fit, not std dev: a tilted screen has depth spread but stays planar. Threshold needs on-device tuning; DEBUG builds show per-face residual in Capture.
- Sessions are concurrent (one per item, DeviceActivity name "unlockSession-<uuid>"); gateCheck only refuses a target that is already unlocked.
- Free Personal Teams do not support Family Controls at all; paid membership renewal in progress. Device registration list is also full until membership is active.
- PlusOneLite target (temporary): entitlement-free, runs on free team and on Mac; remove after device testing.
- DeviceActivity rejects schedules under 15 minutes, so the session limit is a usage threshold event (true "minutes of use"); interval end at max(15, duration+1) min and a foreground expiry check are backstops.
- Extension targets are named *Extension to avoid colliding with ManagedSettings type names (ShieldAction).
- Extension bundle IDs must be prefixed by the app's bundle ID; set explicitly in project.yml.
- Simulator: Screen Time auth is stubbed via targetEnvironment(simulator); Capture shows a sim-only "Simulate two-face pass" button.
- Development-signed builds need only the Xcode Family Controls capability; the distribution entitlement (TestFlight/App Store) must be requested from Apple and is not yet requested.
