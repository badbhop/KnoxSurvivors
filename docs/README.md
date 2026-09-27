# Knox Survivors development documentation

Start coding/agent work from the repository root `AGENTS.md`.

## Current production truth

`production/` owns current project state, work queue, bugs, decisions, QA/release rules, runtime migration, collaboration and AI workflow.

Start with:

1. `production/PROJECT.md`
2. `production/CURRENT_STATE.md`
3. `production/WORK_QUEUE.md`
4. `production/BUGS.md`
5. `production/DECISIONS.md`

## Technical authorities

- `FEATURE_SPEC.md` — gameplay/product scope.
- `ARCHITECTURE.md` — deep architecture, persistence, identity and ownership rules.
- `DEVELOPMENT_TESTING.md` — automated/live testing procedures.
- `FEATURE_AUDIT.md` — single deep historical implementation/evidence ledger; load only the section needed.
- `LAUNCHER.md` — retained launcher details.
- `LAUNCHER_FREE_MIGRATION.md` — long-term Workshop-native migration design.
- `NORMAL_PLAYER_TEST.md` — normal-player acceptance flow.
- `SANDBOX_SETTINGS.md` — settings reference.
- `WORKSHOP_RELEASE.md` — packaging/release mechanics.

## NPC design / research

- `design/NPC_SYSTEM_INSPIRATION.md` — current NPC-system direction and game-reference lessons.
- `design/README.md` — design-intake rules.

## Documentation rule

Do not create another broad plan/status/release document when an existing canonical document owns the topic. Update the current owner and use Git history plus `FEATURE_AUDIT.md` for old evidence.
