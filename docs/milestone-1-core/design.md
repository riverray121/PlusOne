# PlusOne core: Design

## Summary
PlusOne blocks user-chosen apps and websites behind a selfie check. Opening a
blocked item shows a block screen; passing a live selfie check that finds at
least two people present unlocks that item for a set duration (default 5
minutes), after which the block returns automatically.

## How it works
- The user selects any apps and websites on the device to control. Controlled
  items are blocked by default: opening one shows a block screen instead of the
  app or page.
- The block screen offers one action, unlock via selfie, which routes into
  PlusOne's camera.
- The check runs on the live front-camera feed: at least two faces, each large
  enough to indicate a person physically present, held continuously for ~1.5
  seconds. Photo import is not possible. Frames are analyzed in memory and
  never stored.
- Pass: the item that prompted the check unlocks for the configured duration.
  PlusOne shows a countdown; when it ends, the block re-applies automatically.
- Fail: no state changes; the block stays and the check can be retried.
- Cooldown (off by default): after a session ends, no new unlock can start
  until the cooldown elapses.
- Daily cap (off by default): a maximum number of unlock sessions per day;
  once reached, checks are refused until the next day.

## Usage
- First run: grant device-control and camera permissions, pick apps/websites
  to control. Done; blocking is active.
- Daily: tapping a controlled app hits the block screen. Alone, there is no way
  in. With someone, the selfie takes seconds and grants a timed session.
- Settings is one screen: the controlled list, unlock duration, cooldown,
  daily cap. Nothing else.

## Scope
- In: app/website selection, blocking, block screen, live two-face selfie
  check, per-item timed unlock with automatic re-block, duration/cooldown/cap
  settings.
- Out (planned for future milestones): anti-tamper, meaning a device-wide
  deletion lock while protection is on, a visible record when device-control
  permission is revoked, and time-delayed settings weakening.
- Out (no current plan): usage history, streaks, stats; accounts, server,
  analytics, any off-device data.

## Open questions
None.
