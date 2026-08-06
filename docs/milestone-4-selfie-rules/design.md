# PlusOne selfie rules: Design

## Summary
Selfie-unlock blocks become independent rules. Each rule has its own apps
and websites plus its own unlock duration, cooldown, daily cap, and warning,
instead of one selection sharing global settings.

## How it works
- The Selfie-unlock screen lists rules; each row opens an editor with the
  item picker and that rule's four settings, mirroring the time limit and
  scheduled break editors.
- A selfie pass unlocks the tapped item for its rule's duration. Cooldown
  and daily cap count per rule, not across all rules.
- An item in more than one rule is governed by the oldest rule containing
  it, so adding a second, laxer rule cannot loosen an existing block.
- Anti-tamper: deleting a rule, removing its items, raising its duration,
  lowering its cooldown, or weakening its cap queues through the delay and
  friend approval. Creating a rule and shrinking edits apply immediately.
- The single-selection layout with global settings reads as one rule
  carrying those settings until the first rule edit persists the new layout.

## Open questions
None.
