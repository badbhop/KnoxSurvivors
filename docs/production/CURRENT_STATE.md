<!-- modforge-doc
authority: canonical
load: always
purpose: current production position and immediate goal
-->

# Knox Survivors — current production state

Updated: 2026-09-26

## Repository baseline

The connected GitHub repository is `exe-create/KnoxSurvivors`.

GitHub `main` was verified at commit:

`7f56dcb846f107a4c226770b3ca72fe21232235b` — 2026-09-25 — `Commit`

The uploaded local checkout is based on that same HEAD, so the local changes are **post-main work**, not a stale clone that is missing a newer remote commit.

## Current worktree

The current worktree contains substantial uncommitted implementation and test work beyond GitHub `main`.

Source/test scope present in the uploaded worktree before this documentation cleanup:

- 20 tracked Lua source files modified;
- 4 additional untracked Lua source files;
- 17 tracked Lua regression tests modified;
- 4 additional untracked regression tests;
- additional ModForge/OpenCode/documentation configuration work.

The changed implementation is concentrated in these connected areas:

### Base / settlement / storage

- base setup/context/manager behavior;
- multi-base selection;
- storage routing and organizer behavior;
- supply planning;
- task/duty scheduling;
- associated storage/base regression coverage.

### Companion orders / presentation

- companion service/HUD;
- radial order routing;
- Survivor Card and Notebook;
- inventory/view-model presentation;
- activity/speech indicators;
- associated order/UI/notebook tests.

### Persistence / lifecycle / autonomy

- persistence;
- survivor runtime;
- autonomy and autonomy-controller ownership;
- unloaded survival;
- lifecycle-policy coverage.

### Events / off-screen world continuity

- Knox Events and event runtime;
- world traces;
- unloaded/off-screen behavior;
- related event/world-trace tests.

### Threat awareness

- zombie awareness and focused regression coverage.

These groups define the current candidate reconciliation boundary. They are **not automatically release-verified** merely because earlier checkpoints passed.

## Recent repository history anchors

These are concise anchors only; detailed implementation history remains in `../FEATURE_AUDIT.md` and Git history.

- **2026-09-21:** release-readiness work had reached a 245-check / 0-failure offline snapshot, but live engine acceptance was still required.
- **2026-09-23:** persistent survivor memory/off-screen story stabilization and the ZombieBuddy Patch API runtime path landed around this period; live acceptance remained pending.
- **2026-09-24:** commit `2f3aeec` (`Stabilize survivor state, UI, and release tooling`) and the retained 272-check integrated stabilization checkpoint.
- **2026-09-25:** GitHub `main` advanced to `7f56dcb`.
- **2026-09-26:** the uploaded worktree contains additional uncommitted base/storage/UI/autonomy/event/off-screen work plus its associated regression tests.

## Last retained offline evidence

`docs/FEATURE_AUDIT.md` records an integrated stabilization checkpoint dated 2026-09-24 with:

- 107 Lua syntax checks;
- 164 Lua regression scripts;
- Java build/check passing;
- 272 checks total;
- 0 failed.

That evidence predates the current local source/test changes. It remains useful historical evidence, but it is not proof that the current worktree is release-ready.

## Current release state

- Public release line: `0.3.0-rc1`.
- Target: Project Zomboid `42.20.4`.
- Single-player is the supported focus.
- ZombieBuddy and the retained Knox launcher are alternative runtime paths; use one per launch.
- Current source work still requires fresh focused/offline verification.
- Engine-bound behavior still requires live Build 42.20.4 acceptance.
- No new release-ready claim was produced by this documentation cleanup.

## NPC-system design direction

The owner-approved research direction is now captured in:

`docs/design/NPC_SYSTEM_INSPIRATION.md`

The central rule is that a Knox survivor remains an AI-controlled Project Zomboid survivor, not a colony pawn. Existing autonomy, base jobs, relationships, groups, off-screen simulation and persistence should be connected through clearer shared operating rules rather than replaced by unrelated parallel systems.

## Immediate production goal

1. Preserve and reconcile the current implementation scope.
2. Run focused verification for every changed subsystem.
3. Run the full offline gate on the exact candidate.
4. Complete required live Build 42.20.4 acceptance.
5. Update public release claims only from that exact evidence.

Do not start unrelated feature families merely because an AI worker is idle.

## Main active risk

The main risk remains **evidence drift**: implementation has moved beyond the latest full recorded verification checkpoint.

The documentation structure has now been simplified so ModForge/Codex/OpenCode have one current operational truth instead of competing old plans and release snapshots.
