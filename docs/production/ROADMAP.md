<!-- modforge-doc
authority: canonical
load: on-demand
purpose: ordered production sequence
-->

# Knox Survivors — production roadmap

Updated: 2026-09-26

This roadmap describes the next production sequence, not every historical feature.

## Phase 1 — Current worktree reconciliation

Status: substantially documented; validation still follows the active queue.

- GitHub `main` baseline identified.
- Current post-main source/test work grouped by subsystem in `CURRENT_STATE.md`.
- Overlapping old planning/release documents consolidated.
- NPC-system research promoted into a durable design direction.

Exit gate: every release-bound changed subsystem has a named focused verification path.

## Phase 2 — Focused stabilization

- Run focused Lua/Java/verifier coverage for each changed subsystem.
- Fix confirmed regressions at the first failing boundary.
- Re-run focused checks after each fix.
- Keep architecture/persistence/identity ownership intact.

Exit gate: focused verification is green or every failure is represented as an explicit bug/blocker.

## Phase 3 — Full offline release gate

- Run complete syntax/regression/Java/build/package verification on the exact candidate.
- Stage/verify the Workshop payload and supported runtime packaging.
- Record exact counts and revision.

Exit gate: full offline gate is green with no source-confirmed blocker.

## Phase 4 — Live Build 42.20.4 acceptance

Exercise `QA_RELEASE.md`, including UI, orders, native jobs, storage/organizer behavior, combat/firearms, save/reload, hibernation/rematerialization, faction/event lifecycle where enabled and supported runtime/vehicle paths.

Exit gate: required live scenarios pass or failures become reproducible tracked bugs.

## Phase 5 — Release decision and publication

- Reconcile `CURRENT_STATE.md`, `WORK_QUEUE.md`, `BUGS.md` and `RELEASE_NOTES.md` against the exact candidate.
- Verify subscribed/published-style Workshop payload and runtime startup.
- Publish only after owner approval.

## Post-release / design growth

After candidate stability, approved NPC-system work should favor **connecting existing systems**:

- clearer survivor decision arbitration;
- broader shared reservation semantics;
- group/base needs creating missions;
- richer role preference/specialist consequences;
- event-driven memories/relationships;
- safe off-screen equivalents and reconciliation;
- presentation/dialogue polish;
- broader faction/world interactions only when the core lifecycle remains stable.

See `../design/NPC_SYSTEM_INSPIRATION.md`.
