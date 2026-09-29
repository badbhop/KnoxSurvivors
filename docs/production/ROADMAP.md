<!-- modforge-doc
authority: canonical
load: on-demand
purpose: ordered production sequence
-->

# Knox Survivors — production roadmap

Updated: 2026-09-28

This roadmap describes the next production sequence, not every historical feature.

## Phase 1 — Current worktree reconciliation

Status: substantially documented; validation still follows the active queue.

- GitHub `main` baseline identified.
- Current post-main source/test work grouped by subsystem in `CURRENT_STATE.md`.
- Overlapping old planning/release documents consolidated.
- NPC-system research promoted into a durable design direction.

Exit gate: every release-bound changed subsystem has a named focused verification path.

## Phase 2 — Core completion and focused stabilization

This is the next playable milestone. The goal is to make the systems already
present work together as one believable survivor ecosystem, not to start a second
parallel architecture.

Work in dependency order:

1. **Identity, persistence and lifecycle** — stable survivor records, save/load,
   materialization, hibernation, continuous-real off-screen continuity (same rates/intent, real consumption, idempotent reconcile) and migration safety.
2. **Survivor brains and autonomy** — goals, needs, claims, reservations,
   priorities, duty selection, interruption recovery and one authoritative
   controller per action boundary.
3. **Movement and pathing** — route selection, doors/windows, traversal,
   stuck/retry behavior, leader-relative movement and safe handoff to native
   timed actions.
4. **Combat and threat awareness** — perception, target selection, melee/firearm
   behavior, retreat, injury/resource consequences and native damage evidence.
5. **Storage, bases and work loops** — real item transfer, storage policy,
   supplies, claims, recurring jobs, fairness, failure/backoff and base needs.
6. **Companions, orders and UI** — order vocabulary, party behavior, orders that
   survive interruption/unload, Survivor Card, Notebook and honest feedback.
7. **Events, factions and world life** — complete only implemented systems with a
   clear purpose, reusing the existing event/lifecycle boundaries and avoiding
   fabricated supplies, bodies or world effects.
8. **Runtime compatibility** — keep KnoxBridge as the only supported Knox
   startup path; verify its installer, module approval, and game integration.
   The separate Knox Survivors Launcher is deprecated and out of scope.
9. **Performance, defaults and customization** — measure expensive loops, keep
   safe balanced defaults, expose meaningful player settings, and document the
   cost/behavior tradeoffs.

For every step: identify the existing owner, inspect current tests/history, fix
the first confirmed failing boundary, add only the smallest missing connection,
run focused checks, and record unresolved live-only work. Do not create a second
task manager, movement owner, persistence model, combat controller or off-screen
simulation just to fill a gap.

- Run focused Lua/Java/verifier coverage for each changed subsystem.
- Fix confirmed regressions at the first failing boundary.
- Re-run focused checks after each fix.
- Keep architecture/persistence/identity ownership intact.

Exit gate: the core loop is playable in a fresh test save, focused verification
is green or every failure is represented as an explicit bug/blocker, and no
implemented subsystem remains knowingly disconnected without a tracked reason.

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

### Future design candidate — bounded ground-item storage and cleanup

The existing container-first system remains the storage authority. A future
optional ground-storage area may use real Project Zomboid world items and
loaded squares when no suitable assigned container can accept a real item. This
is a design candidate, not an implementation or release commitment. Loose-item
pickup/cleanup and ground placement are separate actions; neither should be
added as a second inventory or abstract stockpile owner.

Before implementation, scope one existing base/work-zone owner for an explicitly
designated, bounded area and route decisions through `KS_BaseStorage`, work
claims through the existing task/claim owner, and item changes through native
world/inventory actions. Container deposit stays preferred: a valid typed
container, then existing typed overflow/fallback behavior; a ground area is
eligible only when explicitly enabled and a real native placement can complete.
If the destination is full, blocked, unloaded, outside the owned base, or the
native action fails, keep the item with its current real owner and report/retry
through existing failure/backoff behavior. Do not delete, recreate, or count an
item as transferred without source removal and destination receipt.

Future acceptance should require: one real loose world item collected and moved
to a matching assigned container; one real deposit placed on a designated
ground square only after container options are unavailable; rejection of
reserved, favorite, equipped, job-required, foreign-base, out-of-zone, blocked,
or stale items/locations; full/invalid destinations leave ownership unchanged;
and save/reload preserves zone geometry while Project Zomboid remains the sole
owner of actual world-item persistence. The UI should reuse the existing base
area editor and clearly show enabled/category/priority state, capacity limits,
and why a destination was skipped. No persisted live square, container, item,
or character references.

Proposed starting performance caps for a future implementation are at most 256
designated squares, 32 world-item candidates inspected in one scan, one scan per
zone every 10 in-game minutes, and one item moved per work cycle. These are
design limits to profile and verify before enablement, not measured performance
claims. Never scan an entire cell or base on every autonomy tick. This work
stays deferred until a reproduced cleanup need and compatible native
pickup/placement path are established.

## Future feasibility research — universal Java-mod launcher

This is a platform feasibility/research track for consideration only after the
core stabilization and live acceptance work above. It carries no implementation,
release, or compatibility promise. Do not begin a universal launcher build or
retire the supported Knox runtime paths based on this roadmap entry.

Before any implementation or release commitment, research and prove:

- reliable JVM discovery and startup across the supported Project Zomboid
  installs;
- Workshop and local mod path discovery, including subscribed and shadow-copy
  cases;
- detection and safe handling of Java-agent conflicts, with exactly one
  compatible instrumentation owner per launch;
- rollback to the existing supported startup paths after a failed launch or
  update;
- permission and trust handling for loading third-party Java code;
- platform behavior, including Steam launch integration and differences across
  supported operating systems.

Exit gate: a separate, reviewed feasibility result records tested platform
coverage and unresolved security, startup, path, conflict and rollback limits.
Passing that research gate would authorize a new planning decision only; it
would not establish a release promise.
