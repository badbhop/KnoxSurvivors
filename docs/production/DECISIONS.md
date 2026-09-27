<!-- modforge-doc
authority: canonical
load: always
purpose: canonical settled decision ledger
-->

# Knox Survivors — active project decisions

Updated: 2026-09-26

These are settled operating/product decisions extracted from the current repository documentation. Agents should not reopen them without new evidence or owner direction.

## D-001 — Single-player is the current supported focus

Multiplayer NPC support is not a current release promise.

Source: `README.md`, `RELEASE_NOTES.md`.

## D-002 — Prefer native Project Zomboid systems where practical

Survivors use real items, actions, containers, combat, clothing, farming, and other vanilla systems instead of simulated success where practical.

Source: `README.md`, `docs/ARCHITECTURE.md`, `docs/production/PROJECT.md`.

## D-003 — Live engine behavior requires live evidence

Offline doubles/tests do not prove native animation, projectile damage, item transfer, pathing, UI behavior, or other engine-bound behavior.

Source: `docs/production/QA_RELEASE.md`, `docs/DEVELOPMENT_TESTING.md`.

## D-004 — Experimental systems remain experimental until accepted

Vehicle autonomy, automatic raids/large faction events, away-team dispatch, developer QA modes, and other explicitly experimental systems must not become release promises without their acceptance gate.

Source: `README.md`, `docs/production/QA_RELEASE.md`, `RELEASE_NOTES.md`.

## D-005 — Use exactly one Java runtime path per launch

ZombieBuddy and the retained Knox launcher/legacy Java-agent route are alternatives. Do not intentionally stack both in one launch.

Source: `README.md`, `docs/production/RUNTIME_AND_MIGRATION.md`, `docs/WORKSHOP_RELEASE.md`.

## D-006 — Historical engineering evidence does not own current status

`docs/FEATURE_AUDIT.md` and Git history preserve deep implementation evidence. Current production truth is routed through `docs/production/` and must be reconciled against the current worktree.

Source: `docs/README.md`, `docs/production/SOURCE_REGISTRY.md`.

## D-007 — ModForge coordinates; Codex/OpenCode implement

ModForge owns organization, roadmap, documentation, low-cost planning/review, bug/decision tracking, and handoffs. Codex/OpenCode remain the normal coding path.

Source: `docs/production/PROJECT.md`, `docs/production/AI_WORKFLOW.md` and owner direction.

## D-008 — Canonical repository records are the durable production truth

`docs/production/WORK_QUEUE.md` and `docs/production/BUGS.md` own repository-backed work state. ModForge may edit those records through guarded write-through, but its local database and generated `.modforge/PROJECT_STATE.md` are coordination/cache layers rather than competing truth. External repository edits win on sync conflicts.

Source: owner direction and the production hardening workflow.

## D-009 — One implementation owner per work item

A single coding lane owns dependent implementation for a task. Planner, Grunt, Researcher, and QA agents may support or independently review it, but they must not make competing edits to the same dependent work. Adjacent discoveries are triaged separately unless the active task demonstrably requires them.

Source: owner direction and the production hardening workflow.

## D-010 — Codex/Astra and OpenCode own technical execution for assigned implementation

For an approved work item, Codex/Astra is the primary technical authority for heavy engineering and OpenCode is the technical authority for bounded budget/scoped engineering. ModForge, Boss, Planner, and cheap support agents own coordination, scope, priority, constraints, evidence, and routing; they do not compete with or repeatedly re-plan the active implementation unless project vision, architecture ownership, scope, evidence, or release safety is violated. The human owner remains final for product/reputation/release/public decisions.

Source: owner direction and the production hardening workflow.

## D-011 — Usage exhaustion and logs must fail safe

Running out of model allowance, rate limit, or credits must not silently enable paid usage, mark work complete, or alter release status. Preserve completed evidence/diffs, use only a deliberately configured safe free fallback when capable, otherwise pause the item for later resumption. Debug/console logs are on-demand diagnostic evidence only and must not be preloaded into routine project context; inspect the smallest relevant recent slice when the active runtime/test boundary requires it.

Source: owner direction and the ModForge 1.9 failover/diagnostics policy.


## D-012 — Knox NPCs remain Project Zomboid survivors, not colony pawns

Other games are mechanic references only. The NPC architecture should connect current Knox systems around one primary intention/job, bounded emergency reactions, real PZ resources, group/base needs, persistent relationships/history and loaded ↔ unloaded continuity.

Do not replace working Knox systems simply to imitate another game's architecture.

Source: owner 2026-09-26 research direction and `docs/design/NPC_SYSTEM_INSPIRATION.md`.
