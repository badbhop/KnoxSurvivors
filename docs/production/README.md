<!-- modforge-doc
authority: canonical
load: always
purpose: production documentation map
-->

# Knox Survivors — production documentation map

Updated: 2026-09-27

`docs/production/` is the **canonical repository operational layer** for Codex,
OpenCode, humans, and optionally ModForge. ModForge indexes this layer when it
is available; it is not required for normal development.

Do not create parallel "final plan", "current status", "release readiness" or "migration note" documents.

## Canonical production documents

- `PROJECT.md` — stable product vision and NPC rules.
- `CURRENT_STATE.md` — exact current position and repository baseline.
- `WORK_QUEUE.md` — active work items.
- `BUGS.md` — confirmed failures/blockers.
- `DECISIONS.md` — settled project decisions.
- `ROADMAP.md` — ordered next phases.
- `MILESTONES.md` — release gates/milestone state.
- `QA_RELEASE.md` — verification/release contract.
- `RELEASE_OPERATIONS.md` — candidate/package/publication procedure.
- `RUNTIME_AND_MIGRATION.md` — Java bootstrap, migration and signing.
- `RESEARCH_AND_COMPATIBILITY.md` — research/compatibility index.
- `AI_WORKFLOW.md` — ModForge/Codex/OpenCode operating model.
- `SUPPORT_AND_TRIAGE.md` — player report flow.
- `COLLABORATION.md` — external authors/translators/permissions.
- `CREDITS.md` — confirmed credit source.
- `SOURCE_REGISTRY.md` — document authority map.

## Technical authorities outside this folder

- `../FEATURE_SPEC.md`
- `../ARCHITECTURE.md`
- `../DEVELOPMENT_TESTING.md`
- `../FEATURE_AUDIT.md` — deep historical evidence only when needed
- `../design/NPC_SYSTEM_INSPIRATION.md`

## Shared context and lazy loading

All three workflows—Codex, OpenCode, and ModForge—must know that these
production records, technical authorities, design references, and testing
documents exist. They do not need to load every document on every task.

Always establish operational truth from the small production set: `PROJECT.md`,
`CURRENT_STATE.md`, `WORK_QUEUE.md`, `BUGS.md`, `DECISIONS.md`, and the active
workflow/QA rules. Then load only what the current question needs:

| Need | Read next |
|---|---|
| gameplay/system behavior | `../FEATURE_SPEC.md` and the relevant subsystem source |
| ownership, identity, persistence, lifecycle | `../ARCHITECTURE.md` |
| offline/live testing or release confidence | `../DEVELOPMENT_TESTING.md`, `QA_RELEASE.md`, `NORMAL_PLAYER_TEST.md` |
| launcher/runtime/save compatibility | `RUNTIME_AND_MIGRATION.md`, `RELEASE_OPERATIONS.md`, `LAUNCHER.md` |
| vision, references, inspiration, or deciding what to start next | `PROJECT.md`, `ROADMAP.md`, `MILESTONES.md`, `../design/README.md`, the relevant `INTAKE-*` or inspiration note |
| player/tester reports | `SUPPORT_AND_TRIAGE.md`, then `BUGS.md` only when evidence supports a bug |
| translator/external author work | `COLLABORATION.md`, `CREDITS.md`, and linked task/bug records |
| deep history or reverse-engineering background | `FEATURE_AUDIT.md` or the specific research record only when needed |

Do not treat a design reference as implementation authority, or an offline test
as proof of live engine behavior. Do not load logs or historical audits merely
because they exist.

## Update rules

- Current state changes → update `CURRENT_STATE.md`.
- Task state changes → update `WORK_QUEUE.md`.
- Confirmed bug → update `BUGS.md`.
- Settled owner/project decision → update `DECISIONS.md`.
- Verification/release gate change → update `QA_RELEASE.md`.
- Runtime/migration/signing change → update `RUNTIME_AND_MIGRATION.md`.
- NPC/game-reference design direction → update the relevant `docs/design/` note and reconcile settled decisions here.
- Public claim → update `README.md`/`RELEASE_NOTES.md` only after evidence supports it.
- Roadmap/phase change → update `ROADMAP.md` and reconcile affected `MILESTONES.md` or `WORK_QUEUE.md` entries.
- New or changed acceptance/evidence requirement → update `QA_RELEASE.md` and the owning task/bug.
- Collaboration/tester/support evidence → update the existing person/report record and link the owning task/bug; do not create a duplicate ledger.

Git history and `FEATURE_AUDIT.md` preserve old engineering evidence. They do not need duplicate dated checkpoint files.

## Minimal coding-tool startup

1. root `AGENTS.md`;
2. `PROJECT.md`;
3. `CURRENT_STATE.md`;
4. `WORK_QUEUE.md`;
5. `BUGS.md`;
6. `DECISIONS.md`;
7. `AI_WORKFLOW.md` and `QA_RELEASE.md` when routing or evidence level is unclear;
8. only the technical, testing, design, or reference authority needed for the active task.

When choosing the next task, if the active queue and bugs are clear and no
blocking issue remains, consult `ROADMAP.md`, `MILESTONES.md`, and the relevant
vision/design/reference notes before inventing new work.
