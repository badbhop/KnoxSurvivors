<!-- modforge-doc
authority: canonical
load: always
purpose: canonical verification and release contract
-->

# Knox Survivors — QA and release contract

Updated: 2026-09-26

## Evidence levels

Use these states consistently:

1. **Planned** — described but not implemented.
2. **Implemented** — code exists; behavior not yet proven.
3. **Offline verified** — focused/unit/regression/build evidence passes.
4. **Live verified** — required behavior passed in real Project Zomboid on the target build.
5. **Release ready** — candidate-wide offline/live gates pass and no release blocker remains.

Never skip from “implemented” to “release ready.”

## Automated in-game QA vertical slice

The opt-in Build 42 QA entry point currently runs only `QA-START-001` through
`QA-CLEANUP-001`: readiness, one QA-owned native survivor fixture, recruitment
eligibility observation, checkpoints, and owned-fixture cleanup. It records a
unique run ID, save/build/mod/runtime metadata, evidence type, and one of
`PASS`, `FAIL`, `BLOCKED`, `SKIPPED`, or `HARNESS_ERROR` for every scenario.

`HARNESS_ERROR` identifies a coordinator, checkpoint, timeout, or cleanup
failure and must not be converted into a gameplay failure without separate
evidence. `BLOCKED` identifies an unavailable native fixture or prerequisite.
The fixture does not prove natural population frequency, social progression,
visual correctness, combat, movement, persistence, or player experience. Those
remain human-observed live acceptance checks. Run only in a disposable save;
the slice removes only its own `ks-dev-*` fixture and never clears ordinary
world entities.

## Current release gate

The current worktree needs fresh evidence because source/test work continued after the last retained full offline checkpoint.

### Focused/offline gate

- focused tests for every release-bound changed subsystem;
- Lua syntax/regression coverage appropriate to the exact current source;
- Java build/verifiers;
- payload/staging validation;
- no unexplained regression or source-confirmed blocker.

### Required live Build 42.20.4 coverage

At minimum cover:

- companion Follow/Hold/Return/Guard/Patrol/order interruption and recovery;
- representative base jobs using real tools/materials, including claim/release cleanup;
- storage/organizer behavior with real items and reservations;
- firearms, native damage/reload and melee fallback;
- save/reload during representative active work/combat/travel;
- hibernation/rematerialization preserving identity, needs, equipment, inventory, orders, relationships and activity;
- detached-companion lifecycle across recognized vault/climb/window/fence/sheet-rope traversal, cell-edge/streaming gaps and vehicle occupancy; prolonged unexplained detachment must hibernate safely, reject detached order writes without losing the prior order, and recover through save/reload/rematerialization without duplication;
- multi-day real food/water behavior without duplicate or fabricated consumption;
- factions/groups/events enabled for the candidate, including loaded ↔ unloaded transitions;
- vehicle entry/travel only where the candidate advertises/supports it;
- Survivor Card / Notebook / inventory / health / medical UI at multiple UI scales;
- ZombieBuddy startup path when shipped;
- Knox launcher/legacy startup path when shipped;
- any direct Steam bootstrap route only after a real Steam startup acceptance.

## Quick owner playthrough

Use this short checklist after a risky change or before advancing a live gate. Use a disposable save, record the Git revision, and test one startup path at a time. Mark a step **PASS** only when the expected result is observed in the real game; otherwise record **FAIL**, preserve the save/log, and create or update the relevant bug/task.

1. **Startup path** — launch with exactly one route: normal Project Zomboid, Knox launcher, or ZombieBuddy. Example: start the game, confirm the mod loads, enter a disposable save, and record the route.
2. **Survivor identity** — create or recruit one survivor. Example: note the name/identity, location, equipment, and relationship, then confirm they remain the same after a save/reload.
3. **Orders and movement** — issue Follow, Hold, or Return. Example: send the survivor through a doorway or around an obstacle, interrupt with a nearby threat, and confirm the order recovers or fails visibly rather than silently hanging.
4. **Combat** — test one threat, then several. Example: confirm real damage/health changes, weapon or melee behavior, retreat/recovery, and no fabricated combat result.
5. **Items and work** — transfer a real item and assign one representative job. Example: move an item between inventory/storage, confirm reservations and consumption, then verify the job completes or reports its failure.
6. **Persistence** — save during active work, travel, or combat and reload. Example: verify identity, location, needs, equipment, inventory, order, relationship, and activity are preserved once.
7. **Time and off-screen behavior** — travel roughly 300+ tiles away and return, or advance a controlled period. Example: confirm unloaded survivors/events do not invent native outcomes and can retry failed materialization.
8. **UI and runtime boundary** — inspect the relevant Survivor Card, Notebook, inventory, health, or order UI, then repeat the smallest launcher/ZombieBuddy conflict check when that path changed.

For each step record only: **PASS/FAIL**, expected result, actual result, save name, runtime path, revision, and the smallest useful log excerpt. A PASS advances evidence; a FAIL becomes a reproducible bug/task; an unrun step remains **unverified**.

### Fast 20-minute pass

Use this when checking a small change or deciding whether a build is worth deeper testing:

1. Start a disposable save with one supported runtime path.
2. Create or recruit one survivor and note their identity, equipment, location, and current order.
3. Give one movement/order command, interrupt it with a safe nearby threat, and observe recovery.
4. Transfer one real item, assign one simple job, and confirm the item/job state changes correctly.
5. Save during the activity, reload, and confirm identity, location, equipment, inventory, order, and job state.
6. Travel far enough to unload the area, return, and check that no outcome was invented without the required loaded/native behavior.
7. Record PASS, FAIL, or unverified for each step before moving on.

### Specific failure signals

Look for these concrete symptoms rather than trying to diagnose their cause:

- a survivor changes identity, duplicates, disappears, or returns as a different survivor;
- an order says it is active but the survivor is motionless, loops, walks to the wrong place, or never recovers after interruption;
- a survivor walks through an obstacle, cannot reach an obvious destination, or becomes permanently detached;
- combat changes no real health/body state, resolves without contact, duplicates damage, or leaves a survivor stuck in combat;
- an item appears, disappears, duplicates, transfers to the wrong container, or is consumed without a real action;
- a reservation, job, storage claim, or base assignment remains locked after cancellation, death, reload, or failure;
- save/reload loses needs, equipment, inventory, relationship, order, location, health, or job state;
- unloaded activity creates blood, smashed windows, combat history, loot, death, or terminal outcomes without valid simulation evidence;
- returning to an unloaded area creates duplicate survivors, stale shells, duplicate events, or failed materialization that cannot retry;
- the UI shows a different state from the survivor, inventory, health, or order actually observed in the world;
- launcher and ZombieBuddy both appear active, the wrong runtime loads, or startup reports PASS before the required bridge/patch/combat checks are real;
- performance degrades sharply, survivors spam the same action, or the game becomes unstable during ordinary population/activity levels.

### Useful report format

Send or record a failed result in this compact form:

```text
Result: FAIL
Build/revision:
Runtime path: normal / Knox launcher / ZombieBuddy
Save:
Steps: 1) ... 2) ... 3) ...
Expected:
Actual:
Repeatable: yes / no / unknown
Evidence: screenshot, timestamp, or smallest relevant log excerpt
```

Do not spend time reproducing a failure indefinitely. One clear reproduction is enough to record it; a second reproduction is useful confirmation. If it does not reproduce after two focused attempts, mark it intermittent or unverified and move to the next scenario.

## Bug conversion rule

Any failed acceptance scenario becomes a bug/task with:

- exact build/revision;
- save/setup;
- reproduction steps;
- logs/evidence;
- expected behavior;
- first confirmed failing boundary when known;
- focused regression requirement.

## Candidate evidence record

When the exact candidate passes a gate, record:

- Git commit plus whether the worktree is clean;
- exact Lua source/test counts;
- exact failed-check count;
- Java/build/package result;
- target Project Zomboid build;
- live scenarios actually completed;
- runtime path used;
- remaining experimental/not-promised systems.

Do not keep creating dated release-readiness files. Update `CURRENT_STATE.md`, this QA contract, the active work queue and public `RELEASE_NOTES.md` as evidence changes.

## Release decision

Only the project owner decides publication. AI agents may summarize evidence and blockers, but they do not publish, upload or change public promises without explicit approval.
