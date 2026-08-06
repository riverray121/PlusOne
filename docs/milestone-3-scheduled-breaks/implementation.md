# PlusOne scheduled breaks: Implementation

Single slice: model, manager, monitor handling, shield integration, gating,
UI, and the Home row land together; the feature has no useful smaller
vertical.

Done when:
- Breaks can be created, edited, and deleted from Settings; weakening edits
  queue, strengthening edits apply instantly.
- On device: at the start time the break's items open without a selfie, a
  notification announces the break, and blocking returns after the minutes
  are used or the window closes.
- A break never opens a hard-blocked item or a spent time limit.
