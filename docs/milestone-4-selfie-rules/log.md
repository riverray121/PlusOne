# PlusOne selfie rules: Dev Log

Development context for resuming work. Keep entries to one line. Not a changelog.

## Completed
- Slice 1: SelfieRule model with legacy synthesis, per-rule gates and counters, rules UI, gating, shield and extension lookups; device build green.

## Todo
- [ ] On-device verification: migration of an existing selection, per-rule cooldown/cap, shield subtitle showing the rule's duration.

## Notes
- SharedStore.selfieRules synthesizes one rule (fixed SelfieRule.legacyId) from the legacy selection + global settings whenever the selfieRules key is absent; first write persists real rules.
- Legacy PendingChange kinds (removeSelfieItems, setDuration, setCooldown, setDailyCap) are proposed by no surface but may arrive from a persisted queue; applying one affects every rule.
- Rule lookup is first-match in stored order, so an item in two rules is governed by the older rule; a new laxer rule cannot loosen an existing block.
- Per-rule cooldown state lives in sessionEnds and daily counts in sessionsTodayById; UnlockSession carries ruleId and warnMinutes, decoded leniently.
