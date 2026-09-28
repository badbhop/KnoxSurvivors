<!-- OpenCode adapter: Codex AGENTS.md remains the project source of truth. -->
# OpenCode workflow adapter

OpenCode must follow the repository root `AGENTS.md` as the authoritative project workflow. This file only maps that workflow onto OpenCode's roles and model profiles; it must not contradict or replace the Codex instructions.

## Role mapping

- `boss` is OpenCode's single active workstream owner. It is the OpenCode equivalent of the Codex/Terra boss lane: it owns the task contract, routing, implementation boundary, evidence review, and handoff.
- `planner` is the Luna/Planner lane: plan, scope, acceptance, dependencies, and checklists. It does not edit source.
- `grunt` is the Luna/Grunt lane: narrow lookups, evidence collection, repetitive checks, cleanup, and existing-record maintenance. It does not make architecture decisions.
- `researcher` is the narrow research/scout lane: resolve one technical or compatibility unknown using authoritative evidence.
- `reviewer` is the Terra/QA lane: independently inspect correctness, compatibility, regression risk, and evidence. It does not implement.
- `bugfix` is the bounded OpenCode implementation lane for confirmed isolated defects. Escalate persistence, identity, lifecycle, save migration, architecture, or tightly coupled multi-system work to Codex/Astra.
- `support-triage` and `collaboration` are support lanes and must not silently become implementation owners.

## Boss and worker limits

1. Use one `boss` lane per workstream and one implementation owner per task or bug ID.
2. The Boss may assign at most one support worker at a time unless two tasks are genuinely independent and cannot touch the same records or files.
3. Never launch a premium or architecture-level model as a routine subagent. OpenCode workers use the active profile's role assignment; they do not invent Sol/Astra equivalents or switch providers.
4. The Boss must delegate planning, lookups, evidence collection, cleanup, documentation maintenance, and independent review to the appropriate cheap role when practical. The Boss only integrates the result and makes the final bounded judgment.
5. Do not recursively delegate from a worker. A worker returns a report to the Boss or escalates to Codex; it does not create another worker chain.
6. Codex remains the primary heavy-engineering authority. OpenCode owns only the bounded work explicitly assigned to it.

## Codex escalation boundary

OpenCode must not attempt to imitate or automatically invoke the premium Codex
escalation lanes. If a confirmed issue remains unresolved after two bounded
attempts, record the failed approaches and hand off to Codex. The Codex-side
ladder is Terra → one Sol 5.6 low escalation → one Astra medium final
escalation. Routine tasks, documentation, testing, cleanup, and lookups never
qualify. Do not mark the issue solved merely because escalation is unavailable.

## Model lanes and cost safety

- The default `free` profile is the normal lane. It may use only the allowlisted `opencode/...-free` catalog entries in `opencode.free.json`.
- `-Profile go` is an explicit OpenCode Go subscription lane. It may use only `opencode-go/...` entries in `opencode.go.json` and never silently falls back to free, Zen, or another paid provider.
- OpenCode Go is not ChatGPT Go/Codex usage. Do not claim the two allowances are shared.
- If the selected provider is unavailable or out of allowance, preserve the task and evidence. Do not silently change profiles or claim completion.
- Change model assignments in the profile/catalog files, not in individual task prompts. Keep role names stable so the workflow remains easy to swap.

## Required task loop

1. Read the root `AGENTS.md`, then the small current production records and only the relevant subsystem authority. The shared map is `docs/production/README.md`; it points to technical, testing, design, reference, support, and collaboration records without requiring all of them to be loaded.
2. Identify an existing `KS-PROD-*`, `BUG-KS-*`, or explicit owner request before editing.
3. Have `planner` or `grunt` produce the bounded plan/evidence when the work is not already clear.
4. Have one implementation owner make the smallest correct change.
5. Run focused checks first, then broader checks only when justified.
6. Have `reviewer` inspect the diff and evidence when risk warrants it.
7. Update existing canonical records in place; never create duplicate status, bug, or plan documents.
8. Keep live Build 42 requirements tracked but distinguish implemented, offline-verified, live-verified, and release-ready. Unrun live testing may remain open while independent work continues.

ModForge coordinates and records. Codex/OpenCode implement. The human owner decides product direction, release, public claims, permissions, and paid usage.

## Documentation awareness and maintenance

OpenCode must treat `docs/production/` as the operational source of truth and
must know that `docs/design/`, `docs/FEATURE_SPEC.md`, `docs/ARCHITECTURE.md`,
and `docs/DEVELOPMENT_TESTING.md` are available authorities. Load them only
when the active subsystem, testing question, or next-task decision requires
them. When the queue and bugs are clear but no next item is obvious, consult
`ROADMAP.md`, `MILESTONES.md`, and the relevant vision/reference notes before
proposing work.

Keep existing records synchronized as evidence changes: update the owning task
or bug, current state, decisions, roadmap/milestones, QA evidence, tester
intake, or collaboration record as appropriate. Do not create duplicate
documents or mark a record complete without evidence. ModForge is optional;
OpenCode must leave the same canonical records usable when ModForge is closed.
