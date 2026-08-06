# PlusOne scheduled breaks: Design

## Summary
A scheduled break opens a chosen set of apps and websites at a set time every
day for a set number of minutes, with no selfie. Outside breaks, normal
blocking applies. Multiple breaks can exist, each with its own items, start
time, and duration.

## How it works
- A break has four parts: the apps and websites it opens, a daily start
  time, a window length (15 minutes to 4 hours), and a budget of minutes
  usable within that window.
- At the start time the break's items unshield and a notification announces
  the break. The budget counts actual use and can be spent any time within
  the window. When the budget is spent or the window closes, blocking
  returns automatically.
- Breaks never open hard-blocked items and never refill a spent time limit.
  Usage during a break counts against time-limit budgets as usual.
- Anti-tamper: creating a break, adding items or minutes, lengthening the
  window, or moving the start time is a weakening and goes through the
  settings change delay and friend approval. Deleting a break or shrinking
  it in place applies immediately.

## Usage
- Settings gains one row, Scheduled breaks, beside Time limits. The list and
  editor mirror the Time limits screens: item picker, start time, minutes.

## Scope
- In: multiple daily breaks, per-break selection, time, window, and use
  budget, automatic unshield and re-shield, break-start notification,
  anti-tamper gating.
- Out: per-day-of-week schedules, overlap merging beyond union, Home screen
  break countdowns.

## Open questions
None.
