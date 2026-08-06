# PlusOne scheduled breaks: Design

## Summary
A scheduled break opens a chosen set of apps and websites at a set time every
day for a set number of minutes, with no selfie. Outside breaks, normal
blocking applies. Multiple breaks can exist, each with its own items, start
time, and duration.

## How it works
- A break has three parts: the apps and websites it opens, a daily start
  time, and a duration in minutes.
- At the start time the break's items unshield and a notification announces
  the break. The duration is a budget of actual use, spendable within a
  window starting at the set time; the window is at least 15 minutes long (a
  system minimum). When the budget is spent or the window closes, blocking
  returns automatically.
- Breaks never open hard-blocked items and never refill a spent time limit.
  Usage during a break counts against time-limit budgets as usual.
- Anti-tamper: creating a break, adding items, adding minutes, or moving the
  start time is a weakening and goes through the settings change delay and
  friend approval. Deleting a break or shrinking it in place applies
  immediately.

## Usage
- Settings gains one row, Scheduled breaks, beside Time limits. The list and
  editor mirror the Time limits screens: item picker, start time, minutes.

## Scope
- In: multiple daily breaks, per-break selection, time, and duration,
  automatic unshield and re-shield, break-start notification, anti-tamper
  gating.
- Out: per-day-of-week schedules, overlap merging beyond union, Home screen
  break countdowns.

## Open questions
None.
