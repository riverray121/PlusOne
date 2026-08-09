# PlusOne selfie rules: Dev Log

Development context for resuming work. Keep entries to one line. Not a changelog.

## Completed
- Slice 1: SelfieRule model with legacy synthesis, per-rule gates and counters, rules UI, gating, shield and extension lookups; device build green.
- On-device: an existing selection migrated to two persisted rules, each rule's duration resolved on its own shield and session (3 min and 5 min), and a pass released its whole rule.

## Todo
- [ ] On-device verification: per-rule cooldown and daily cap, both 0 on the test device, so neither gate has been exercised.

## Notes
- SharedStore.selfieRules synthesizes one rule (fixed SelfieRule.legacyId) from the legacy selection + global settings whenever the selfieRules key is absent; first write persists real rules.
- Legacy PendingChange kinds (removeSelfieItems, setDuration, setCooldown, setDailyCap) are proposed by no surface but may arrive from a persisted queue; applying one affects every rule.
- Rule lookup is first-match in stored order, so an item in two rules is governed by the older rule; a new laxer rule cannot loosen an existing block.
- Per-rule cooldown state lives in sessionEnds and daily counts in sessionsTodayById; UnlockSession carries ruleId and warnMinutes, decoded leniently.
- A pass frees the whole governing rule, not just the tapped item: iOS restricts an app whenever a web domain it claims is shielded, so releasing an app token while its site stays in `shield.webDomains` leaves the app blocked behind iOS's own restriction screen, which consults no shield extension; opaque tokens make app-to-site pairing impossible, so the rule is the smallest releasable unit.
