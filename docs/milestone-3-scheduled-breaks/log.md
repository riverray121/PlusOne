# PlusOne scheduled breaks: Dev Log

Development context for resuming work. Keep entries to one line. Not a changelog.

## Completed
- Slice 1: BreakRule/BreakManager, monitor + shield integration, gating, Scheduled breaks UI, Home row and status line; device build green, installed.

## Todo
- [ ] On-device verification per implementation.md (schedule firing, re-shield, notification, hard-block precedence).

## Notes
- Break active state lives in `activeBreaks` (rule id to window end); `BreakManager.activeRules` self-filters lapsed entries so a missed callback cannot hold a shield open past a refresh.
- A window opens from `intervalDidStart`, or from `BreakManager.openDueActive` on the foreground pass when the monitor extension was killed for memory as the window opened; `openedBreakWindows` (rule id to window start) records the window so a spent one never reopens, and re-arming a rule stamps its current window as opened.
- Adding a break is a weakening (inverse of time limits, where adding strengthens); only shrink-in-place edits and deletes are immediate.
