<!-- modforge-doc
authority: canonical
load: on-demand
purpose: durable owner design/reference intake and settled design direction
-->

# Knox Survivors — design and research

This folder stores design/reference material that should survive individual AI sessions without becoming an implementation order by accident.

## Current settled direction

- `NPC_SYSTEM_INSPIRATION.md` — owner-approved NPC design direction derived from the 2026-09-26 research pass.

## Design Inbox flow

`raw idea/reference → ModForge Design Inbox → triage/research/questions → owner approves planning → docs/design/INTAKE-*.md → design review task → approved implementation task → Codex/OpenCode`

Rules:

- Preserve source/provenance and the owner's likes/dislikes/constraints.
- Reference another game's high-level mechanic or behavior; never copy proprietary assets/text/code.
- Do not silently turn raw inspiration into Knox canon.
- A design note is not automatically an implementation task.
- Implementation requires a bounded work item with scope, acceptance, validation and one implementation owner.
- When a design becomes settled project direction, reconcile it into `docs/production/DECISIONS.md`, `PROJECT.md`, roadmap/work queue or the relevant technical authority.
