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
- FamilyActivityPicker must be presented from a pushed view or the root, never from inside a sheet: dismissing the picker also dismisses the presenting sheet, discarding unsaved edits.
- FamilyActivityPicker deselection can fail to update the selection binding (known Apple bug), so the picker is add-only where it matters; removal happens in our own token lists (Label(token) renders name and icon) with swipe-to-delete.
- Time limits: one repeating DeviceActivity per rule (hourly window minute 0-59, daily 00:00-23:59) with a "limit" threshold event and an optional "warn" event at limit minus warnMinutesLeft. Threshold usage counts from startMonitoring, so TimeLimitManager.syncMonitoring diffs against an armed snapshot and restarts only changed rules.
- Spent rules live in SharedStore.exhaustedLimits (rule id -> wall-clock reset) written by the monitor extension; they shield like hard blocks (after session exclusions). intervalDidStart clears them; foreground clearLapsedExhausted is the backstop.
- iOS pairs apps with their websites: shielding a WebDomainToken also restricts the associated native app (observed with instagram.com and youtube.com; Apple's own Screen Time website limits behave the same). The pairing lives in the OS and there is no API to opt out; tokens are opaque so the app cannot even detect the pairing. Blocking an ApplicationToken does NOT restrict the website, so the asymmetric setup (app blocked, site open) works but not the reverse.
- iOS web filter has NO pure blocklist mode: any blockedByFilter policy (.specific included) implies the adult filter, and it disables Safari private browsing. So webContent serves only the adult toggle (.auto on, explicit FilterPolicy.none off; bare .none resolves to Optional nil = remove, which can leave the filter stuck).
- Hard blocks are a second FamilyActivitySelection (hardSelection), always shielded, excluded from session exceptions; shield extensions render a no-unlock variant by token membership.
- Website blocklist: string domains (presets + custom) enforced via webContent.blockedByFilter. Tokens are opaque so app->domain pairing cannot be automatic. Safari shows its own restricted page; unlocks start from Home. String-domain sessions have no usage threshold: wall-clock re-lock at >= 15 min plus foreground backstop.
- Depth metrics use median statistics (MAD residual, median bump) plus a +-15cm cluster around median depth: robust to specular IR noise from glossy screens and to background leakage past screen edges.
- Depth liveness: on TrueDepth devices each counted face must deviate >= 4mm RMS from its best-fit plane (FaceCheck.minDepthResidual). Plane fit, not std dev: a tilted screen has depth spread but stays planar. Threshold needs on-device tuning; DEBUG builds show per-face residual in Capture.
- Depth-path faces come from AVCaptureMetadataOutput (synchronized with video+depth); rects convert via outputRectConverted into the buffer space the depth map shares. Vision is 2D-fallback only: its mirrored-space rects were sampling the wrong depth region.
- Capture flow is driven by sheet(item:) with a per-request CaptureRequest id; view phases are an explicit enum. Grant no longer collides with pendingUnlock clearing.
- Sessions are concurrent (one per item, DeviceActivity name "unlockSession-<uuid>"); gateCheck only refuses a target that is already unlocked.
- Free Personal Teams do not support Family Controls at all; paid membership renewal in progress. Device registration list is also full until membership is active.
- PlusOneLite target (temporary): entitlement-free, runs on free team and on Mac; remove after device testing.
- DeviceActivity rejects schedules under 15 minutes, so the session limit is a usage threshold event (true "minutes of use"); interval end at max(15, duration+1) min and a foreground expiry check are backstops.
- Extension targets are named *Extension to avoid colliding with ManagedSettings type names (ShieldAction).
- Extension bundle IDs must be prefixed by the app's bundle ID; set explicitly in project.yml.
- Simulator: Screen Time auth is stubbed via targetEnvironment(simulator); Capture shows a sim-only "Simulate two-face pass" button.
- Development-signed builds need only the Xcode Family Controls capability; the distribution entitlement (TestFlight/App Store) must be requested from Apple and is not yet requested.
