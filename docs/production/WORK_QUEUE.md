<!-- modforge-doc
authority: canonical
load: always
purpose: canonical active work queue
-->

# Knox Survivors — active production work queue

Updated: 2026-09-28

The sections below are deliberately machine-friendly so ModForge can populate its task board automatically. Keep confirmed bugs in `BUGS.md` instead of hiding them here.

## KS-PROD-001 — Reconcile the current worktree with repository baseline
Status: done
Priority: critical
Owner: Codex
Type: release

### Goal
Identify the GitHub baseline and make the post-main worktree understandable to downstream verification.

### Result
- Commit `163b789a2564ee626bc9d5acdad46674623c25b8` verified as the current GitHub `main` and local checkout HEAD, directly based on prior baseline `7f56dcb846f107a4c226770b3ca72fe21232235b`.
- The implementation baseline was verified at the current HEAD; later coordination/documentation changes remain visible as a separate uncommitted layer and do not change the implementation claim.
- Current source/test changes grouped by subsystem in `CURRENT_STATE.md`.
- Old overlapping plan/release documents consolidated so they no longer compete with current production truth.

### Validation
Repository status/diff, connected GitHub baseline, current source/test inventory and retained historical evidence.

### Definition of Done
Downstream QA can verify the exact current implementation without relying on a stale release snapshot.

## KS-PROD-002 — Run focused verification for all release-bound changed subsystems
Status: done
Priority: critical
Owner: Codex / OpenCode
Type: qa

### Goal
Prove each changed subsystem passes its cheapest meaningful focused checks before the full gate.

### Scope
Use the tests/verifiers already associated with the changed files. OpenCode may handle narrow failures; Codex owns cross-system or architecture-sensitive failures.

### Acceptance
- Focused checks pass for every release-bound subsystem, or a confirmed failure is converted to a tracked bug.
- No failure is hidden by retries, fake fixtures, or wording changes.

### Validation
Candidate: `163b789a2564ee626bc9d5acdad46674623c25b8`; focused evidence applies to that candidate implementation baseline. Current documentation/configuration edits are separate and remain subject to Git review.

Focused command for each listed Lua test:

```powershell
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tools/<test>.lua (Get-Location).Path
```

| Changed subsystem | Focused tests | Result | Remaining live-only boundary |
|---|---|---:|---|
| Base/storage/organize | `test-base-storage.lua`, `test-base-organize-wiring.lua`, `test-base-storage-menu.lua`, `test-base-setup-ui.lua`, `test-base-ambient-life.lua`, `test-base-supply-planner.lua`, `test-duty-schedule.lua`, `test-multi-base.lua` | 8/8 passed | Native jobs, real storage/item transfer, pathing and resource consumption |
| Companion orders/UI | `test-order-routing.lua`, `test-radial-orders.lua`, `test-notebook-away-ownership.lua`, `test-notebook-refresh.lua`, `test-speech-indicators.lua`, `test-survivor-card-ui.lua`, `test-survivor-view-model.lua` | 7/7 passed | Native order execution, interruption recovery and rendered UI at target scales |
| Persistence/autonomy | `test-survivor-lifecycle-policy.lua`, `test-unloaded-survival.lua` | 2/2 passed | Real save/reload, hibernation/rematerialization and engine lifecycle |
| Events/world continuity | `test-event-runtime.lua`, `test-knox-events.lua`, `test-world-traces.lua` | 3/3 passed | Live loaded/unloaded event behavior and native world effects |
| Threat awareness | `test-zombie-awareness.lua` | 1/1 passed | Native detection, combat and damage behavior |

Total changed-test batch: **21/21 passed, 0 failed**. The same 2026-09-27
read-only audit also passed **112/112** Lua 5.1 syntax checks, **174/174**
repository Lua regression scripts, and `gradlew.bat :java:check` (16 successful
tasks). These are offline checks using test fixtures/doubles; they do not prove
the live-only boundaries above. Static review separately established
`BUG-KS-001`, `BUG-KS-002`, and `BUG-KS-003`; green fixtures do not override
those source/architecture failures.

### Definition of Done
The complete changed-test set for the exact candidate is confirmed and the
source-confirmed audit failures are represented by explicit bug records. The
full offline/package gate and live Build 42 acceptance remain separate queue
items and are not implied by this completion.

## KS-PROD-003 — Run the full offline candidate gate
Status: in_progress
Priority: high
Owner: Codex
Type: release

### Goal
Run the complete syntax/regression/Java/build/package verification on the same candidate revision.

### Acceptance
- Full offline suite completes without unexplained failure.
- Exact check counts, revision/worktree state, and packaging result are recorded.

### Validation
On 2026-09-28, `tools/verify.ps1` (full, Java included) checked 112 Lua sources and ran 177
Lua scripts (290 checks, 0 failed, including `java-check-build`) on worktree `decbda5`
plus 5 uncommitted files (`KS_CompanionVehicles.lua`, `KS_SurvivorAutonomyController.lua`,
`BUGS.md`, `CURRENT_STATE.md`, `WORK_QUEUE.md`). Test scripts are intentionally local-only
(`.gitignore`, owner commit `1d10f42`), so the harness itself is not part of the published
candidate. `verify.ps1` covers syntax, regression, and Java check/build only — Workshop
staging/package verification is not part of that tool and remains outstanding, as does a
clean-tree rerun. Prior partial record below is superseded by this run for Lua/Java scope.

On 2026-09-27, `tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 174
Lua scripts (286 checks, 0 failed) against the current working tree. This is
partial offline evidence only; Java, staging/package verification, and the full
candidate gate remain outstanding. BUG-KS-001's six focused event/trace tests
also passed, but native raid behavior remains live-unverified. Follow
`docs/DEVELOPMENT_TESTING.md` and the supported build/release tooling.

### Definition of Done
A fresh offline evidence record exists for the exact candidate.

## KS-PROD-008 — Complete and connect the implemented survivor systems
Status: in progress
Priority: high
Owner: Codex / OpenCode
Type: development

### Goal
Turn the substantial existing implementation into one coherent, reliable,
believable and playable survivor loop without creating overlapping owners or
parallel replacement systems.

### Scope
Work in dependency order: identity/persistence/lifecycle and off-screen truth;
survivor brains/autonomy/claims; movement/pathing/native action interruption;
combat/threat awareness; storage/base/jobs/supplies; companions/orders/UI;
purposeful implemented events/factions/world life; vehicle readiness/driving per
D-019 and Slice J; launcher/runtime compatibility
where required; then performance, balanced defaults and player customization.

### Acceptance
- Existing systems connect through their documented authoritative owners.
- Confirmed failures are fixed at the first failing boundary or tracked in
  `BUGS.md` with evidence.
- No fabricated items, world effects, bodies, completion or test evidence.
- Off-screen continuity is real-time and cheaper, never faked: same needs/travel/rest progression, real supply consumption, deterministic history, and idempotent loaded reconcile per D-016.
- Implemented experimental systems with a real purpose are completed safely;
  unstarted feature families remain deferred.
- Focused and required live evidence is recorded separately and honestly.

### Validation
Use the focused tests listed in KS-PROD-002, the subsystem authorities in
`docs/ARCHITECTURE.md` and `docs/DEVELOPMENT_TESTING.md`, fresh-save Build 42
acceptance, and launcher/runtime checks when the boundary crosses repositories.

The confirmed detached-companion stale-shell defect is tracked as
`BUG-KS-008`. Its bounded lifecycle correction has focused and full offline Lua
evidence recorded in `BUGS.md`; the broader KS-PROD-008 loop remains open. Live
Build 42 replay must cover recognized vault/climb states, cell-edge/streaming
gaps, vehicle occupancy, prolonged unexplained detachment, dismissal,
save/reload, and rematerialization before this boundary is considered live
verified.

### Completion slices (one owner, one acceptance each — no parallel systems)

Work slices in dependency order. A slice is done only when its offline tests
pass on the exact candidate AND its live replay passes (or its failure becomes
a tracked bug). Slices map to `ROADMAP.md` Phase 2 and the dossiers in
`docs/design/NPC_SYSTEM_INSPIRATION.md`; they create no new task IDs.

2026-09-28 traversal integration: claimed base jobs now route entry-related
failure on assigned-storage pickup through the existing window/door recovery
owner. Quiet entry and permitted forced entry retain the exact task supply
lease and resume the same approach; unavailable entry fails through existing
task cleanup. Focused `test-base-task-supply-entry.lua` plus entry, action
lifecycle, task validation, arrival, claim and inventory cleanup checks pass.
The full offline gate passed 112 Lua sources, 178 regression scripts, 290
checks and 0 failures. The focused script is local under ignored `tools/`
policy. BUG-KS-033 records the offline boundary. Build 42 still needs native
door/window traversal, actual container receipt, interruption and save/reload.
Public corpse/fence and general locked-door reports remain unconfirmed live
cases.

- **Slice A — Identity/lifecycle/off-screen truth.** Owners: `KS_Persistence.lua`, lifecycle policy, runtime, unloaded ledger, storylets, traces. Offline: lifecycle-policy, persistence-recovery, unloaded-survival/group/base-return, event-runtime, world-trace tests. Live: save/reload identity/inventory/orders, hibernation/rematerialization with no duplicates, loaded→unloaded→loaded travel with real consumption and retryable traces. Bugs: `BUG-KS-001`, `BUG-KS-002`, `BUG-KS-008`, `BUG-KS-024`. Rule: D-016 continuous-real, never faked.
- **Slice B — Brains/autonomy/claims.** Owners: autonomy controller, needs/loot/medical probes, task board, duty simulation. Offline: autonomy, needs, work-priority, anti-flap, group support/scavenge, behavior-integration tests; the dynamic organizer-duty regression confirms leaving base duty, disabling hauling, or reassignment cancels its action/route once and releases item/container claims. The focused base-life set passed 8/8 and the full offline gate passed 112 Lua sources, 176 scripts, 288 checks, 0 failures. Live: full-day base observation — needs, interruption, resumption, no controller fights, idle residents choose base-life. Bugs: `BUG-KS-013`, `BUG-KS-025`.
- **Slice C — Movement/pathing/native actions.** Owners: Java traversal runtime, cohesion, formation follow, companion service, action adapters. Offline: formation, traversal, command, order, door-discipline tests. Live: leader-plus-two-followers through travel, door/fence, interruption, recovery; one native work action and one danger-interrupted action with real world change. Bugs: `BUG-KS-011`, `BUG-KS-019`, `BUG-KS-028`.
- **Slice D — Combat/threat/retreat/firearms.** Owners: awareness, threat classifier, combat/firearm support. Offline: zombie-awareness, combat-intelligence, formation, threat-classifier tests. Live: one-zombie hold, small-group hold, overwhelming-group retreat through a viable lane and recovery; hostile duel plus bystander check with real ammo/health evidence. Bugs: `BUG-KS-009`, `BUG-KS-012`, `BUG-KS-029`. Diagnostic update 2026-09-28 (`dev-runs/20260928-021135`): no `LightingJNI` visibility-write failure appears in the console extract; other encounter logs show native zombie damage, but `combat_group_horde` remained `PARTIAL` (15 survivor hits, zero zombie damage/kills). Do not repeat the base-danger source audit absent new evidence; offline arbitration is covered. Keep the one-zombie/small-group native combat replay in live acceptance.
- `test-combat-intelligence.lua` drives a base resident through the scheduled danger scan with an active organizer action: the combat bridge starts once, the action is cleared, and the claimed task is retained with `combat_interrupt`. Offline arbitration is covered; native damage, retreat and recovery remain live-only.
- **Slice E — Storage/organizer/supplies.** Owners: base storage, organize, supply planner, context menu, manager categories. Offline: base-storage/menu/organize/supply-routing/planner/cleanup/inventory tests. Live: typed deposit, General fallback,
logs/firewood routing, loot→storage→need loop with identity/counts across save/reload. Native vehicle parts
(`VehicleMaintenance`: tires, batteries, brakes, gas tanks per installed Build 42 item scripts) now resolve to the
Materials role through the existing building matcher — no new role, registry, or stockpile owner; mechanic hand tools
were already Tools. A confirmed supply-claim gap is tracked as `BUG-KS-031`: collection used to terminate the
durable run before storage receipt. The existing autonomy owner now holds the run and return intent through
the typed native transfer, and releases it only when destination receipt is confirmed. Focused
`test-base-auto-scavenge.lua`, `test-base-needs.lua`, and `test-inventory-cleanup.lua` plus the full offline gate
passed (112 Lua sources, 177 scripts, 289 checks, 0 failed). Native transfer, container capacity/weight, and
save/reload identity remain live-only. Bugs: `BUG-KS-015`, `BUG-KS-016`, `BUG-KS-031`.
- **Slice F — Bases/jobs/duties.** Owners: base manager/jobs/task board/needs, zone executors, duty scheduling. Offline: existing base-job/ambient/needs/duty/task-board tests plus dynamic watchdog coverage. `test-base-leisure-routing.lua` now drives `tick` through stalled `BASE_PATROL`, `BASE_RETURN`, and `MOVING_TO_REST`: the first two cancel through `handleBaseMovementFailure` and release their ambient claim with backoff; rest uses the existing ground-rest action and releases its furniture claim. The ordinary base-task loop now also yields to actionable urgent self-care on a 90-tick check while preserving the task claim and routing cancellation/transfer release through existing owners. `test-claim-suspend.lua` covers active work, task action, supply movement/transfer, below-threshold continuation, specialized guard/cook ownership, verified eating, and resumption. The focused connected suite passed; `tools/verify.ps1 -SkipJava` passed 112 Lua files, 177 scripts, 289 checks, 0 failures. Test changes are local under ignored `tools/` policy and are not tracked Git changes. Live: full-day two-resident base observation; stalled chair/patrol/return recovery; hungry residents during ordinary work and supply transfer with real assigned food, native eating, same-task resumption and honest unavailable-food behavior; one supplied job end-to-end; active-organizer duty removal/hauling disable/base reassignment; two-window barricade sequence; territory-corner save/reload. Bugs: `BUG-KS-013`, `BUG-KS-017`, `BUG-KS-018`, `BUG-KS-020`.

2026-09-28 completion-authority correction (`BUG-KS-034`): native base-job
executors already verify the world result, but a stale/revoked claim could make
the task board reject the final finish after the controller had emitted success
and completion speech. The existing board response now gates task success
diagnostics, automatic-work pacing, and completion speech. Rejection records a
distinct bounded failure and releases the stale controller's transient task
and supply leases; it does not mutate another owner's claim or undo a real
world result. Focused `test-base-task-validation.lua`,
`test-base-action-lifecycle.lua`, `test-base-task-board.lua`,
`test-companion-base-domain.lua`, `test-base-repairs.lua`,
`test-base-farming.lua`, `test-base-woodcutting.lua`, and
`test-base-corpse-handling.lua` all passed. The full
`tools/verify.ps1 -SkipJava` run checked **112 Lua sources**, **178 regression
scripts**, **290 checks**, **0 failures**; the updated test remains local under
ignored `tools/` policy. `git diff --check` passed. Build 42 must still replay
ordinary native job completion and a claim revoked during/after the action,
including feedback, next activity and save/reload. No native action or
save/reload result is claimed from these offline fixtures.
- **Slice G — Companions/orders/UI.** Owners: companion service, party commands, order catalog/signals, radial, HUD, card, notebook, map overlay, speech indicators. Offline: order-routing, radial, notebook, speech, card, view-model, map tests. The existing survivor snapshot already supplied persisted life-purpose, relationship meeting count, and bounded newest-first memory to the Card, but those fields were dropped from the player-facing detail. The Card now shows purpose, meeting count, and up to three sanitized history summaries/details without reading raw persistence; list views remain compact and the shared view-model stays authoritative. Focused view-model, Card UI, Notebook refresh/mission ownership, offscreen-story, relationship-coherence, and survivor-needs checks passed; full offline gate on 2026-09-28: 112 Lua sources, 177 regression scripts, 289 checks, 0 failures. The new/updated focused script remains local under ignored `tools/` per repository policy. This cycle corrected trust-only gifts by connecting `Give Item` to explicit one-way mode in the existing trade UI/action: real item eligibility, recipient reserve checks, capacity, transfer receipt, rollback, capture, then the existing gift contribution reward. `Give Money` stays absent as an abstract account action; tangible supported currency objects use the real-item path. `BUG-KS-032` and D-020 record the consequence rule. Focused social-act, valuation, action, and UI regressions plus the full gate passed at 112 Lua sources, 177 scripts, 289 checks, 0 failures. Focused test edits remain local under ignored `tools/` policy. Live: order/interruption/recovery, speech readability plus right-click menus, UI at small/large scales; inspect Card history text clipping/scrolling at both scales and replay real gift/barter receipt, capacity, cancellation, and save/reload. Bugs: `BUG-KS-008`, `BUG-KS-010`, `BUG-KS-021`, `BUG-KS-032`.
- **Slice H — Events/factions/world life.** Owners: event runtime, Knox events, factions/camps/scouting, group scavenge, away-team executor, storylets. Offline: population, origin, faction-development, event-entry, group tests. Live: solo→group→faction→settlement observable; shortage→mission→return→deposit→memory closes; raids only with loaded outcomes. Bugs: `BUG-KS-001`, `BUG-KS-024`, `BUG-KS-026`. Deferred per D-017: full politics, creator, broad raids.
- **Slice I — Performance/defaults/customization.** Owners: settings, schedulers,
population budgets. Offline: full gate counts on exact candidate. Live: frame-time at configured population plus
crowded job/combat; rarity modes direction (Lonely/Balanced/Lively) scoped as future work item. Rule: D-015/D-017 —
conservative defaults, no ownership bypasses.
- **Slice J — Vehicle readiness/driving (D-019).** Owners: `KS_NpcVehicleTravel.lua` (shared admission verdict),
`KS_CompanionVehicles.lua` (drive admission), `KS_VehicleNavigation.lua` (geometry/routing, unchanged),
`KS_BaseStorage.lua` Materials routing for parts. Offline: shared ready/low-fuel/locked/unknown matrix on both the
travel path and the module-absent fallback; no boarding or `driveTo` on rejection; no movement, routing, formation,
leader-order, away-team, lifecycle, or persistence owner changes. Boarding yields to retreat-worthy danger and
critical needs through the existing lease owner (rearming next-tick arbitration); refused abort-time exits retry
boundedly once stopped; arrival exits each passenger exactly once with the driver explicitly staying seated and one
truthful feed line; unrecoverable exits report once. Full gate 112/177/289, 0 failed. Group boarding
commits an explicit per-member roster attached to the driver run; every abort/arrival rolls it back at once (pending
leases release immediately, seated passengers get native exit, overflow stays unclaimed); `stopDriver` only clears a
present run key. Duty/order changes arbitrate vehicle leases through the existing interruption owner (lease-free
survivors untouched); every `cancel` settles the attached roster except player takeover, which preserves riders.
Live: real parked
vehicles across engine/fuel/damage/lock/seat/occupancy/towing states plus one valid fueled vehicle; multi-car driving
runs, convoy spacing, control release, and native part consumption are separate future gates. Deferred: hotwiring/keys, forced entry,
player-assigned vehicle work orders with HP thresholds, specialist workstations, vehicle-work UI. Bugs: `BUG-KS-030`.

Routing per slice: narrow selector/matcher/schedule/retry fixes → OpenCode; persistence/identity/lifecycle/cross-system → Codex; vision/scope/release → Boss/owner.

### Current QA slice

`QA-START-001` through `QA-CLEANUP-001` are the first manifest-driven
in-game QA vertical slice. They cover readiness metadata, one QA-owned native
survivor fixture, read-only recruitment eligibility, checkpoints, and verified
fixture cleanup. The slice uses a unique run ID and separates `BLOCKED` native
prerequisites from `HARNESS_ERROR` coordinator/cleanup failures. A disposable
Build 42.20.4 run exposed BUG-KS-009: the fixture's combat path repeatedly
attempted an unsafe off-slot lighting visibility write. Its narrow source
correction has passed offline regression but still needs a live one-zombie
replay. The slice does not establish natural encounter frequency, recruitment
progression, persistence, combat, movement, storage, jobs, factions, raids,
vehicles, or whole-world safety.

The same existing Diagnostics > **Write Survivor Status to Log** command now
adds a bounded session history from the autonomy controller's centralized
failure path. Up to twelve scalar-only `recent_failure` rows preserve tick,
reason, controller state, decision, retry deadline, and position when
available; this is transient evidence, not persisted state or a second QA
owner. It gives future acceptance scenarios and reports a concise recent
failure trail without per-tick logging. Exact-worktree offline verification on
2026-09-28 passed: 112 Lua sources, 177 regression scripts, 289 checks, 0
failures. Focused autonomy/formation, developer-menu, debug-log, and combat
scenario-reporting regressions passed. Focused scripts remain local under the
ignored `tools/` policy. Live diagnostic acceptance: produce a recoverable
native movement failure, invoke the status command, match its row to the
controller state/retry, then unload/reload and verify only the transient ring
clears. This does not verify the underlying movement outcome. Other Build 42
scenarios remain required for native behavior.

The same live observation established BUG-KS-010 (dark speech overlay),
BUG-KS-011 (post-fence formation cadence), and BUG-KS-012 (retreat policy
retired despite overwhelming-fight inputs). BUG-KS-010 and BUG-KS-011 now have
bounded offline corrections and focused regression evidence; both still need
Build 42 visual/native replay. BUG-KS-012 now has a bounded offline retreat-
admission correction using existing native movement and route-safety ownership;
it still needs the one-zombie/small-group versus overwhelming-group Build 42
comparison before combat acceptance. The former run-stop-return loop was not
restored.

### Definition of Done
The core survivor loop is fun and playable in a fresh save, the known connected
systems have no unexplained ownership gaps, performance/default settings are
documented, and remaining live-only or experimental work is explicitly tracked.

## KS-PROD-004 — Complete live UI acceptance on Build 42.20.4
Status: todo
Priority: high
Owner: Human + QA Reviewer
Type: live-test

### Goal
Verify the current Survivor Card and related character UI in the real engine.

### Acceptance
Inspect Skills, health, inventory, and medical views at small and large UI scales without repeated errors, unusable clipping, or stale unloaded-survivor assumptions.

### Validation
Disposable save, target Build 42.20.4, fresh logs.

### Definition of Done
Live UI evidence is recorded with any failure converted into `BUGS.md`.

## KS-PROD-005 — Complete core live gameplay acceptance
Status: todo
Priority: critical
Owner: Human + QA Reviewer
Type: live-test

### Goal
Validate engine-bound behavior that offline doubles cannot prove.

### Acceptance
Cover companion orders/interruption recovery, representative native base jobs, firearms/native damage/reload, save/reload, hibernation/rematerialization, real resource consumption, faction lifecycle/event behavior where enabled, and vehicle behavior where enabled.

### Validation
Use `docs/production/QA_RELEASE.md` and `docs/DEVELOPMENT_TESTING.md`.

### Definition of Done
Required live scenarios pass or produce reproducible tracked bugs.

## KS-PROD-006 — Verify supported Steam/runtime startup paths
Status: todo
Priority: high
Owner: OpenCode + Human
Type: compatibility

### Goal
Confirm the release candidate starts through the supported runtime path(s) from a real subscribed/published-style install.

### Acceptance
- ZombieBuddy path produces fresh `runtime start PASS` and the later
  `ZombieBuddy patch readiness PASS` evidence when used; the earlier line alone
  is only bridge startup and does not prove that hooks applied.
- The selected path also produces `Lua bridge exposed global=KnoxJavaBridge`
  and Lua-side `[KnoxSurvivors][Bridge] PASS` evidence.
- The deprecated Knox Survivors Launcher is not an acceptance path. Do not
  launch it or compose it with KnoxBridge or ZombieBuddy. Its separate repository
  has been requested to become private; that visibility change remains pending
  owner-side settings confirmation.
- Do not advertise or test the retired standalone launcher or direct legacy Knox agent as supported setup paths. Test KnoxBridge via normal Steam startup only.
- No test intentionally loads duplicate runtime paths.
- One representative live zombie detection/attack/damage sequence succeeds on
  the selected path so startup text is not treated as gameplay proof.

### Validation
Follow `README.md`, `docs/production/RUNTIME_AND_MIGRATION.md`, and
`docs/production/QA_RELEASE.md`. The old standalone launcher is deprecated and
not part of the supported runtime matrix. On 2026-09-27, its source passed
offline launch-option security/native-argument, updater metadata/version/
checksum, runtime-isolation, and Windows-bootstrap checks; this historical
evidence does not make it a supported path. The main repository retirement
check and verifier also passed at that time. Before live acceptance, isolate
the local `<Zomboid-mods>\KnoxSurvivors` shadow copy and use KnoxBridge as the
only Knox Java runtime. ZombieBuddy may be tested separately as an alternative,
never stacked with KnoxBridge.

### Definition of Done
Runtime support claims match live evidence.

## KS-PROD-009 — Triage and stabilize the community-reported gameplay backlog
Status: todo
Priority: high
Owner: Codex / OpenCode
Type: stabilization

### Goal
Reproduce, deduplicate, and resolve the reported gameplay issues recorded as
BUG-KS-013 through BUG-KS-027 after the active confirmed defects and core
integration boundaries are addressed.

### Scope
Start with the highest-impact existing-system failures: storage/resupply,
base-boundary correctness, idle/autonomy behavior, independent survivor/group
decision quality, doors/traversal, and bounded off-screen continuity. Treat map
markers, work-priority expansion, faction markers, and the custom creator as
later feature candidates unless a current implementation defect is proven.

### Rules
- Every report remains `reported` until reproduced against the current Build 42
  and Knox revision or confirmed from a source-owned failure.
- Check whether it is already fixed before changing code.
- Fix one shared failing boundary at a time and update the linked bug evidence.
- Preserve real Project Zomboid state, identity, persistence, and performance
  limits; do not add population/faction systems to hide a measurement gap.
- Use the design references for principles only: Project Zomboid remains the
  foundation, while RimWorld, Rebuild, Dead State, Crusader Kings, and Dwarf
  Fortress inform bounded design comparisons.

### Acceptance
Each promoted bug has a reproduction or source boundary, focused regression
coverage where practical, live verification requirements, and an updated
canonical record. No reported item is silently closed because it is old or
because a different setup produced no failure.

### Next selection
After BUG-KS-012 and current live gates are scheduled, choose the highest-value
reported item whose existing-system boundary is clear. Prefer one that improves
the normal survivor/base/storage loop and can be fixed without introducing a
new parallel system.

The first source-confirmed KS-PROD-009 storage boundary is tracked in
BUG-KS-016: the exposed Logs & Lumber assignment was rejected by the manager's
category registry, and the existing General Storage matcher/fallback could not
be assigned through the menu/persistence allowlist. Both bounded wiring gaps
are corrected with focused coverage; native transfers and the broader resupply
reports remain separate live/current-reproducer work. The 2026-09-27 storage regression pass
also confirms offline coverage for typed categories, same-role containers,
overflow/fallback, real-instance supply/deposit behavior, organizer transfers,
claims and job requirements. No second storage defect was confirmed. The
optional ground-item pickup/placement candidate and its bounds are recorded in
the existing roadmap; implementation remains deferred pending a concrete
cleanup need and verified native action path.

The 2026-09-27 follow-up audit of BUG-KS-015 found no additional offline
transfer/resupply defect after BUG-KS-016's category wiring correction. Focused
storage/organizer/supply/needs/cleanup/job/inventory/persistence tests passed;
native movement, reachability, container mutation, and save/reload remain live
acceptance. BUG-KS-025's current individual/group decision chain likewise has
no deterministic offline priority failure in the reviewed boundary and focused
tests; live decision quality remains unverified. BUG-KS-014 is a distinct
missing general loose-ground-item hauling feature, not a failure in carried
cleanup or corpse hauling, and remains deferred to the existing roadmap
candidate.

BUG-KS-023 was audited on 2026-09-27 and is now classified in `BUGS.md` as a
feature request rather than a confirmed scheduler defect: explicit role,
profession-derived Auto hint, persisted work-group priorities, schedules, and
guarded concrete task assignment already affect selection. Broader multi-role
profiles and additional task groups remain future design choices, not a reason
to replace the current one-job-at-a-time selector.

The follow-up fallback review found no new offline regression in BUG-KS-019's
door helper or BUG-KS-012's bounded retreat admission; their focused tests pass,
but native door/combat behavior remains live-only. BUG-KS-026's source/test
review found one canonical persistence-owned population allocator for survivor
identity/origin, with group/faction/event records referring to those identities;
the report stays open for real Build 42 allocation, materialization, streaming,
and performance evidence.

The 2026-09-27 backlog pass also found a narrow offline door-close fallback
defect in BUG-KS-019: wrappers exposing `setOpen` without a toggle method were
always sent the open state during cleanup. The requested state is now passed
explicitly and covered offline; native Build 42 door traversal remains
unverified. BUG-KS-020 remains reported after focused barricade/task lifecycle
tests: target discovery and claim coverage pass, but the native action-to-next-
window sequence is not proven offline. BUG-KS-013 remains reported after its
existing decision-flow coverage; visible native base-life behavior still needs
the recorded live replay.

The 2026-09-27 BUG-KS-021/022 map audit found that owned-survivor locations
already render through the Knox map overlay, including loaded, logical,
last-known, and durable deceased coordinates. The focused map test passed; no
stale-marker failure was reproduced. Nearby grouping remains a feature
candidate, and native projection/streaming/save-reload behavior remains live-
unverified. Faction-base records already relocate and remove through the
canonical base/faction lifecycle, but no map-marker consumer exists; BUG-KS-022
is therefore a missing feature candidate, not a current stale-marker defect.
Focused map-owned-location, faction-persistence, and multi-base tests passed.
Do not add an independent marker ledger; continue with the next
offline-confirmable existing-system boundary.

The 2026-09-27 BUG-KS-024 stabilization pass removed a source-confirmed
unloaded-combat boundary violation: daily abstract traveler scuffles could
persist damage/death and create fight traces before a native body existed.
Unloaded continuity now remains limited to persisted needs, real carried
supplies, rest, and logical travel. Focused unloaded-survival/group,
world-trace, and event-runtime tests passed, followed by `tools/verify.ps1
-SkipJava` (112 Lua files, 175 scripts, 287 checks, 0 failures). Retain native
materialization/save-reload and loaded/unloaded replay as live acceptance.

The following BUG-KS-024 transition fix commits the hibernated ledger before
native body removal. If the commit fails, the runtime/controller remains active;
if removal does not actually clear the bridge shell, the loaded snapshot is
re-captured before retry. Focused lifecycle, virtual-base-return,
unloaded-survival/base-return, and away-team tests passed, followed by the
offline gate (112 Lua files, 175 scripts, 287 checks, 0 failures). The required
live replay now includes a deliberate hibernation store failure/retry where
diagnostics permit, plus normal restoration with identity, inventory, orders,
affiliation, and duplicate-body checks.

The multi-member away-team handoff now uses the same ownership rule. Its full
roster is validated and stored before removal; pre-removal aborts roll live
members back to loaded ledger ownership, while already-removed members remain
recoverable hibernated identities beneath a blocked, non-outbound dispatch
record. The focused transaction fixture covers valid/invalid roster, duplicate
and dead members, store/team failure, first/middle/final teardown failure and
retry. Focused lifecycle, away-team/executor, unloaded, group, base-return,
world-presence and persistence recovery checks passed before the full offline
gate (112 Lua files, 176 scripts, 288 checks, 0 failures). Live acceptance must still prove native body acknowledgement,
save/reload, restoration and no duplicates.

Blocked dispatch recovery now preserves this distinction through persistence:
only a member whose removal was acknowledged stays `away` beneath the blocked
ledger, while a still-live member restores its prior duty. After canonical
record restoration registers the removed member's body, the lifecycle path
releases that member's saved duty without creating a new identity or body.
Focused coverage includes persistence reload, finalization failure, recovery,
and retry; the same 112-source/176-script/288-check offline gate passed. Native
removal acknowledgement, reconstruction, inventory/equipment/order and
affiliation continuity, and duplicate-body prevention remain for the later
Build 42 disposable-save replay.

## KS-PROD-007 — Refresh candidate evidence and public-facing documentation
Status: todo
Priority: high
Owner: ModForge + Codex
Type: documentation

### Goal
Bring release documentation forward to the exact candidate after verification.

### Acceptance
- `CURRENT_STATE.md`, `QA_RELEASE.md`, `WORK_QUEUE.md` and `BUGS.md` reflect the exact candidate evidence.
- `RELEASE_NOTES.md` contains only supported player-facing claims.
- Generated ModForge state agrees with the canonical repository docs.

### Validation
Cross-check the exact candidate revision, test results, live acceptance, and open bugs.

### Definition of Done
One coherent release story exists across ModForge, production docs, and player-facing docs.

### Newly recorded priorities

- `BUG-KS-028` — group/faction follower cohesion and leader-order arbitration;
  prioritize after the current live combat/UI checks because it affects the
  basic NPC group experience.
- `BUG-KS-029` — firearm stabilization; schedule as a dedicated combat pass,
  not incidental work during group movement.
- `BUG-KS-030` — vehicle/driving stabilization; schedule after lifecycle, group
  cohesion, and core combat boundaries are reliable.

BUG-KS-028 now has one bounded offline correction: native group-follow route
success no longer forces a full formation refresh wait before the follower can
reconsider a moving leader. The success handler issues no new route; normal
next-tick arbitration retains existing route commits, cadence, traversal,
threat/need/combat interruption, and retry ownership. Focused formation,
relationship, unloaded-group, order, and behavior checks passed, followed by
`tools/verify.ps1 -SkipJava` (112 Lua files, 176 scripts, 288 checks, 0
failures). The bounded leader-order slice below is now implemented; require the
specified Build 42 leader-plus-multiple-followers replay before treating either
cohesion or leader-order timing as live verified.

The first inspiration-driven group-order slice is now implemented within
KS-PROD-008: canonical NPC group/faction leaders can issue one persisted
`follow` or bounded `hold` directive to their current travel group. The record
is leader-authorized, stored-issuer/group/faction validated, default-bounded to
15 game minutes, and delivered by existing relationship/formation arbitration;
it never creates a second movement or combat scheduler. Successful ordinary
roam/regroup routes issue follow; explicit hold has no autonomous policy, UI,
destination command, or mission behavior. Pending delivery preserves native
traversal/actions and existing need/job/combat ownership; cancellation requires
native `MOVE_CANCELLED` and a failed cancellation waits 60 ticks. Extended
relationship-coherence, autonomy-formation, and roaming-autonomy tests plus the
112-source/176-script/288-check offline gate passed. Defer the disposable Build
42 replay, destination orders, group missions, order UI, firearms live
acceptance, and vehicle work until their dedicated evidence-backed passes.

2026-09-28 supply-ownership correction (`BUG-KS-035`): the 1.5-hour shared
loaded-world shortage lease could expire while the persisted `activeSupplyRun`
still owned an unfinished search/return, allowing another resident to be
elected for the same shortage. The existing autonomy owner now rebuilds the
transient claim from valid same-base active runs before shortage election,
including unloaded residents; only existing terminal run cleanup releases
that durable ownership. Focused `test-base-auto-scavenge.lua`,
`test-base-supply-planner.lua`, `test-inventory-cleanup.lua`, and
`test-base-needs.lua` passed. `tools/verify.ps1 -SkipJava` checked **112 Lua
sources**, **178 regression scripts**, **290 checks**, **0 failures**; `git
diff --check` passed. The focused fixture is local under ignored `tools/`
policy. Build 42 still needs a trip lasting beyond the lease window, including
unload/reload, real pickup, native storage receipt and reassessment. This is
offline ownership evidence only, not proof of native transfer or persistence.

2026-09-28 social-memory connection (`BUG-KS-036`): finalized loaded survivor
encounters previously changed relationship/group state without entering the
persistent history consumed by later recount dialogue and Survivor Cards. The
relationship owner now submits only resolved outcomes to `KS_OffscreenStories`,
which appends to each existing canonical ledger with per-participant
deduplication and the existing 12-entry cap; no ledger is synthesized. Greet,
decline, persisted hostility, successful join, and rejected join have truthful
separate outcomes. Incomplete/interrupted encounters and unverified robbery or
combat success are not recorded. Dialogue and Survivor Card history labels now
reflect friendly, joined, parted, and hostile outcomes. Focused story/history,
recount, encounter, view-model, and relationship-coherence tests passed.
`tools/verify.ps1 -SkipJava` checked 112
Lua sources and ran 178 regression scripts (290 checks, 0 failures). Focused
test edits remain local under ignored `tools/` policy. Build 42 still needs
native loaded encounter outcome, save/reload, and later dialogue/Card replay;
this offline path does not prove engine encounter or native robbery behavior.

## KS-PROD-010 — Test Knox Survivors on Build 42.21
Status: in progress
Priority: high
Owner: Codex + Human
Type: compatibility / live-test

### Goal
Use the existing Knox Survivors mod ID and files, with one metadata range
covering Build 42.20 through 42.21. Test the same mod on both builds and do not
claim verified 42.21 gameplay support until its live gates pass. The owner
retargeted compatibility testing after Project Zomboid 42.21.0 Stable was
announced on 2026-09-28.

### Acceptance
- Verify the independent KnoxBridge test module in a real 42.21 game context,
  including enabled-mod discovery, trust, entrypoint, and its harmless patch.
- Keep the existing mod ID (`KnoxSurvivors`) and current mod files; do not make
  a duplicate package or Workshop item for 42.21.
- Set the metadata range to 42.20–42.21 and label 42.21 as under test until
  live acceptance passes. The owner reports the candidate Workshop items have
  been uploaded/updated; this does not close the live acceptance or release
  gate.
- Knox module metadata and entrypoint must use KnoxBridge; remove ZombieBuddy
  metadata and compile dependencies from the Workshop payload while retaining
  the direct Knox legacy agent only as a source rollback path.
- Audit every required Knox Java hook against the installed 42.21 JAR and test
  the migrated bridge/transformers without changing survivor Lua simulation or
  save schema.
- On a disposable 42.21 world, verify Knox module approval/load, bridge exposure,
  one survivor creation, movement/order, zombie awareness/combat, and save/reload.
- Verify uninstall/restore removes only KnoxBridge startup ownership, ordinary
  Steam starts without it, then reinstall and verify again.
- Keep the package marked experimental until its test evidence is reviewed;
  public upload/release remains subject to owner approval.

### Current evidence and dependency
Normal Steam Play on 2026-09-28 reported PZ `42.21.0`, Java `25.0.1`, and
successful `ZomboidFileSystem.loadMods(List)` transformation. PZ supplied the
enabled roots `KnoxBridgeIndependentTest` and `KnoxSurvivors`; their unknown
hashes were blocked on the first run. After exact-hash approval and restart,
both modules loaded, the independent entrypoint initialized/registered its
probe, and Knox reported required combat/visibility patches ready plus
`KnoxJavaBridge` exposure. This closes the generic bootstrap/discovery/trust/
module-entrypoint gate and the Knox module bootstrap gate. In the same live
session Knox logged native probe `ks-dev-1` spawned, door/fence movement
transitions, baseball-bat attacks, and zombie health reaching zero. One route
reported `FailedStuck`; this is narrow runtime/combat evidence, not pathing
acceptance. Save/reload, deny or changed-hash policy, and 42.20 live
compatibility remain open. The actual uninstall restored the exact original JSON hash;
normal Steam launched without a new KnoxBridge log entry, then reinstall and a
second Steam launch rediscovered and loaded both approved modules. No saves or
mod-list files were targeted.

The local Workshop `Contents` payload was replaced from source after a verified
backup of its previous 125 files. It declares `42.20–42.21`; its KnoxBridge
module JAR now stages at the descriptor path and has a verified SHA-256 match
to the built JAR. Both Knox metadata trees declare `require=KnoxBridgeRuntime`.
KnoxBridge Workshop staging contains the dependency marker, compile-time API
JAR, and player/mod-author guides; it excludes the runtime agent, native
bootstrap, installer, and setup scripts. The player package is separate:
Windows standalone installer; Linux/macOS ZIP plus Python helper (implemented,
not live verified). The owner reports uploading/updating both Workshop items
after this staging. The current public Knox listing still needs owner review for
Bridge access, Required Item linkage, and setup instructions matching the actual
downloadable package. The old installed Steam Workshop subscription and source
trees were preserved. Publication does not prove module startup, gameplay,
save/reload, or cross-platform acceptance.
