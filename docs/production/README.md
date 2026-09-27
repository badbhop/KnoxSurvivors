<!-- modforge-doc
authority: canonical
load: always
purpose: production documentation map
-->

# Knox Survivors — production documentation map

Updated: 2026-09-26

`docs/production/` is the **single current operational layer** for ModForge, Codex and OpenCode.

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

## Update rules

- Current state changes → update `CURRENT_STATE.md`.
- Task state changes → update `WORK_QUEUE.md`.
- Confirmed bug → update `BUGS.md`.
- Settled owner/project decision → update `DECISIONS.md`.
- Verification/release gate change → update `QA_RELEASE.md`.
- Runtime/migration/signing change → update `RUNTIME_AND_MIGRATION.md`.
- NPC/game-reference design direction → update the relevant `docs/design/` note and reconcile settled decisions here.
- Public claim → update `README.md`/`RELEASE_NOTES.md` only after evidence supports it.

Git history and `FEATURE_AUDIT.md` preserve old engineering evidence. They do not need duplicate dated checkpoint files.

## Minimal coding-tool startup

1. root `AGENTS.md`;
2. `PROJECT.md`;
3. `CURRENT_STATE.md`;
4. `WORK_QUEUE.md`;
5. `BUGS.md`;
6. `DECISIONS.md`;
7. only the technical/design authority needed for the active task.
