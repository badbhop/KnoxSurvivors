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
- multi-day real food/water behavior without duplicate or fabricated consumption;
- factions/groups/events enabled for the candidate, including loaded ↔ unloaded transitions;
- vehicle entry/travel only where the candidate advertises/supports it;
- Survivor Card / Notebook / inventory / health / medical UI at multiple UI scales;
- ZombieBuddy startup path when shipped;
- Knox launcher/legacy startup path when shipped;
- any direct Steam bootstrap route only after a real Steam startup acceptance.

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
