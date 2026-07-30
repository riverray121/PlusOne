# Documentation rules

Rules for everything under `docs/`.

## Structure
- `index.md`: milestone table in build order. Every milestone folder has a
  row. Status: `planning` → `active` → `shipped`.
- One folder per milestone, `milestone-<n>-<name>/`, containing as needed:
  - `design.md`: what the feature is and how it behaves. Written first.
  - `architecture.md`: technical shape; components, data flow, APIs.
  - `implementation.md`: build plan as vertical slices.
  - `log.md`: running record of work done and decisions made.
- `media/`: screenshots and images referenced from docs.

## Status discipline
- Only one milestone is `active` at a time; it is the only current one.
- A milestone enters `active` when its doc set is approved, `shipped` when
  built, verified on device, and cleaned up.
- Shipped milestones are history: do not edit them except to fix errors.

## Writing style
- Precise and concise. No personality, no fluff, no filler.
- State facts and fundamental truths only; no opinions unless the doc's
  purpose is a decision record.
- No timelines or effort estimates.
- No em dashes; use a colon, comma, parentheses, or a separate sentence.
- Design docs describe behavior, not implementation. Architecture docs may
  name APIs and components. Implementation docs define slices and their
  done conditions.
- Every design doc ends with an `Open questions` section, kept current;
  "None." when empty.
