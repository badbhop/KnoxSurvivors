<!-- modforge-doc
authority: canonical
load: on-demand
purpose: canonical documentation authority registry
-->

# Knox Survivors — documentation authority registry

Updated: 2026-09-26

The repository intentionally keeps **fewer overlapping documents**. Current status belongs in one canonical production layer; deep technical/history sources are loaded only when relevant.

## Authority classes

- **ENTRYPOINT** — repository-wide start point for coding agents.
- **CANONICAL** — current operational/design truth, updated in place.
- **TECHNICAL** — subsystem/procedure authority.
- **GENERATED** — cache/snapshot produced by tooling; never authoritative over repository records.
- **REFERENCE / PUBLIC** — useful player/developer procedure or public text.
- **HISTORICAL** — retained deep evidence that does not own current status.

## Current sources

| Source | Authority | Role |
|---|---|---|
| `AGENTS.md` | ENTRYPOINT | Single coding-agent startup/router |
| `docs/production/*.md` | CANONICAL | Current project, status, work, bugs, decisions, QA, runtime, collaboration and workflow |
| `docs/design/NPC_SYSTEM_INSPIRATION.md` | CANONICAL DESIGN | Current NPC-system direction derived from owner research |
| `docs/design/README.md` | CANONICAL DESIGN | Design intake/provenance rules |
| `.modforge/PROJECT_STATE.md` | GENERATED | Optional generated coordination snapshot |
| `docs/FEATURE_SPEC.md` | TECHNICAL | Gameplay/product scope |
| `docs/ARCHITECTURE.md` | TECHNICAL | Architecture, ownership, persistence, identity/lifecycle |
| `docs/DEVELOPMENT_TESTING.md` | TECHNICAL | Automated/live verification procedures |
| `docs/FEATURE_AUDIT.md` | HISTORICAL / TECHNICAL EVIDENCE | Single deep implementation/evidence ledger; load targeted sections only |
| `docs/LAUNCHER.md` | REFERENCE | Retained launcher details |
| `docs/LAUNCHER_FREE_MIGRATION.md` | REFERENCE / DESIGN | Long-term Workshop-native migration |
| `docs/NORMAL_PLAYER_TEST.md` | REFERENCE | Normal-player acceptance procedure |
| `docs/SANDBOX_SETTINGS.md` | REFERENCE | Sandbox/developer settings |
| `docs/WORKSHOP_RELEASE.md` | REFERENCE | Workshop packaging mechanics |
| `README.md` | PUBLIC / TECHNICAL | Player-facing product/runtime promise boundary |
| `RELEASE_NOTES.md` | PUBLIC | Current player-facing release notes |
| `LICENSE.md` | REFERENCE | Ownership/redistribution terms |
| `mod/Installation Help.txt` | PUBLIC REFERENCE | Shipped short runtime/install help |

## Deliberately removed after consolidation

The following older documents served the same plan/status/release/migration purpose as the canonical layer and were merged before removal:

- `FINISH_PLAN.md`
- `RELEASE_READINESS.md`
- `MIGRATION_README.txt`
- `PLAYER_MIGRATION_NOTE.txt`
- `ZOMBIEBUDDY_AUTHOR_SIGNING.txt`
- `docs/PROJECT_BRIEF.md`
- `docs/AGENTS.md`
- `docs/MILESTONES.md`
- `docs/COMPLETION_REVIEW.md`
- `docs/RELEASE_QUALITY.md`
- `docs/COMPETITIVE_CHECKPOINT_2026-09-19.md`
- `docs/LONG_SESSION_REVIEW_2026-09-06.md`
- `docs/PROGRESS_2026-09-07.md`
- duplicate `mod/STEAM_SETUP.txt`

Their detailed historical content remains recoverable from Git history; current useful rules/evidence were moved into the retained canonical/technical documents.

## Conflict rule

When sources disagree:

1. current CANONICAL operational state wins for status/priorities;
2. TECHNICAL authority wins for the subsystem rule it owns;
3. `FEATURE_AUDIT.md` and Git history are evidence, not current task/status owners;
4. newer evidence does not silently rewrite a settled decision — reconcile it in `DECISIONS.md`;
5. unresolved conflicts go to the owner/Boss instead of being guessed away.
