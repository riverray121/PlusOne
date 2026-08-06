# PlusOne scheduled breaks: Architecture

## Key decisions
- Enforcement mirrors unlock sessions: each break arms a repeating daily
  schedule spanning its window (user-set, 15 minutes minimum because
  DeviceActivity rejects shorter intervals), and a usage-threshold event at
  the break's minutes is the real limit. The interval end is the backstop.
- `BreakManager` (Shared) mirrors `TimeLimitManager`: diff-based arming
  against an `armedBreaks` snapshot, active state as an id-to-window-end
  dictionary in the App Group store, flipped by the monitor extension.
- Shield math: active breaks subtract from the shielded sets after session
  exclusions and before hard blocks and exhausted limits union in, so a
  break can never open a hard block or a spent limit.
- Gating: `upsertBreakRule` is a weakening unless it shrinks the same rule
  in place (same start time, no more minutes or window, no added items);
  `deleteBreakRule` always strengthens and applies instantly. A start-time
  change is a weakening because an instant move re-arms the schedule and
  would grant a second window the same day.

## Structure
- `Sources/Shared/BreakRule.swift`: model (selection, start minute of day,
  minutes).
- `Sources/Shared/BreakManager.swift`: arming, active state, shield inputs.
- `Sources/App/ScheduledBreaksView.swift`: list and editor, mirroring the
  Time limits screens.
- Touched: `SharedStore`, `ShieldController`, `PendingChange`,
  `ProtectionGate`, `SessionMonitor`, `HomeView`, `PlusOneApp`, `AppGroup`.

## Risks / unknowns
- A missed interval-end callback leaves an open break unshielded until the
  next shield refresh; the foreground pass clears lapsed break state, and
  the usage threshold still caps total use.
- Editing a break mid-window restarts its monitoring; the new interval may
  not fire until the next day.
- A window that crosses midnight (start near the end of the day) relies on
  DeviceActivity treating an interval end earlier than its start as
  next-day; unverified on device.
