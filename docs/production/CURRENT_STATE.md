<!-- modforge-doc
authority: canonical
load: always
purpose: current production position and immediate goal
-->

# Knox Survivors — current production state

Updated: 2026-09-28

## Repository baseline

The connected GitHub repository is `exe-create/KnoxSurvivors`. The local
checkout is on `main` at `8c78129973afbb227e56adefa2f5ba5d3dd7b1c4`
(`Bounded vehicle boarding interruption safety; record PT-BR collaboration`).
GitHub remote parity was not checked in this cycle.

## Current worktree

At this cycle's start, the worktree already contained uncommitted production
documentation updates from the preceding combat/base-danger evidence review;
those edits were preserved. The worktree includes the prior base-supply
delivery fix and this cycle's base-life watchdog recovery fix in
`KS_SurvivorAutonomyController.lua`; related canonical records are updated.
The regression harnesses under `tools/` are ignored by the repository-wide
`.gitignore`; their local edits were exercised but are not tracked Git changes.
The latest commit bounds vehicle boarding interruption when danger or critical
needs arise and records Portuguese-Brazilian collaboration state. This does not
establish native vehicle or combat behavior.

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
- **2026-09-23:** persistent survivor memory/off-screen story stabilization and the alternate runtime Patch API runtime path landed around this period; live acceptance remained pending.
- **2026-09-24:** commit `2f3aeec` (`Stabilize survivor state, UI, and release tooling`) and the retained 272-check integrated stabilization checkpoint.
- **2026-09-25:** GitHub `main` was at the prior baseline `7f56dcb`.
- **2026-09-26:** commit `163b789` consolidated production documentation and coordination contracts, and committed the associated base/storage/UI/autonomy/event/off-screen implementation and regression tests.
- **2026-09-28:** local `main` advanced through bounded vehicle admission/boarding interruption changes to `8c78129`. The latest saved Build 42 diagnostic run is `dev-runs/20260928-021135`; it shows both successful native zombie damage and a mixed-group horde scenario that remained `PARTIAL`.

## Last retained offline evidence

`docs/FEATURE_AUDIT.md` records an integrated stabilization checkpoint dated 2026-09-24 with:

- 107 Lua syntax checks;
- 164 Lua regression scripts;
- Java build/check passing;
- 272 checks total;
- 0 failed.

That evidence predates `163b789`. It remains useful historical evidence, but it is not proof that the current worktree is release-ready.

The retained full gate ran with Java on `decbda5` plus five uncommitted files:
112 Lua sources, 177 Lua scripts, 290 checks, 0 failed. It is not exact-candidate
evidence for `8c78129`. Fresh offline gate on 2026-09-28 after the base-supply
delivery fix: `tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 177
scripts (289 checks, 0 failed). Focused `test-base-auto-scavenge.lua`,
`test-base-needs.lua`, and `test-inventory-cleanup.lua` passed. `git diff --check`
passed. Java checks were intentionally skipped under the offline-first cycle;
workshop staging/package verification remains outstanding.

Fresh exact-worktree evidence on 2026-09-28 after the base-life recovery and
Survivor Card semantic integration updates: `tools/verify.ps1 -SkipJava`
checked 112 Lua sources and ran 177 regression scripts (289 checks, 0 failed).
Focused view-model, Card UI, Notebook refresh/mission ownership, offscreen-story,
relationship-coherence, and survivor-needs checks passed. The Card now surfaces
persisted life-purpose, relationship meeting count, and up to three bounded
memory details through the existing view-model; the focused script remains local
under ignored `tools/` policy. `git diff --check` passed after documentation
updates. Live Build 42 Card readability/scroll behavior at small
and large UI scales remains pending; native gameplay queues remain unchanged.

The next source-confirmed social defect was that `Offer Gift` and `Give Money`
awarded trust and thank-you responses without transferring an item. The
trust-only acts are removed; `Give Item` now opens the existing exchange UI in
one-way mode and uses its real transfer/capacity/receipt/rollback/capture
owner. Relationship credit comes only after verified receipt. Abstract `Give
Money` remains absent, while real supported currency items are selectable.
Focused social-act and Trade valuation/action/UI regressions and the exact-
worktree full offline gate passed on 2026-09-28: 112 Lua sources, 177 scripts,
289 checks, 0 failures. `BUG-KS-032` and D-020 record the boundary. The four
focused test edits are local under ignored `tools/` policy and are not tracked
Git evidence. Native item gift/barter receipt, capacity, cancellation, and
save/reload remain Build 42 acceptance items.

The current QA improvement extends the existing survivor status command with
up to twelve recent failures from the autonomy controller's shared failure
owner. The session-only records contain bounded scalar context (tick, cause,
state, decision, retry deadline, and position when available); they do not
persist and do not record every tick. Focused autonomy/formation,
developer-menu, debug-log, and combat-scenario-reporting checks passed. The
exact-worktree offline gate passed on 2026-09-28: 112 Lua sources, 177
regression scripts, 289 checks, 0 failures; Java was skipped. This remains
diagnostic evidence only and does not verify Build 42 behavior.

The next gameplay review found the existing needs/food implementation sound
through real-item selection, native eat action, and verified hunger reduction,
but ordinary active base-task states did not revisit that needs owner. The
autonomy controller now gives eligible ordinary task states a bounded urgent-
need yield, using the existing suspension path to retain the base task claim
and release movement/action/transfer state through its current owners. Focused
tests cover work/action/supply-task interruption, no interruption below the
need threshold, verified self-care, and task resumption; connected needs,
cooking, security, task, and arrival regressions pass. Exact-worktree
`tools/verify.ps1 -SkipJava` checked 112 Lua sources, ran 177 regression
scripts, and passed 289 checks with 0 failures. The regression edits remain
local under ignored `tools/` policy. The September 23 public hunger report is
not reproduced or confirmed by this offline evidence. Build 42 must verify
native food access/eating, cancellation and same-task resumption, including
urgent hunger during a supply transfer and unavailable-food recovery.

## Current release state

- Public release line: `0.3.0-rc1`.
- Existing public candidate target: Project Zomboid `42.20.4`.
- Current compatibility-test target: Project Zomboid `42.21.0` Stable. The
  existing mod files now declare support metadata through 42.21, but Knox
  gameplay compatibility is not verified yet; see `KS-PROD-010`.
- The configured local Workshop `Contents` folder was replaced from current
  source and now declares `42.20–42.21`. The prior 125 files are backed up in
  ignored `build/pre-knoxbridge-full-stage-backup`. The staged payload scan
  found no external Java runtime references. This records staging before the owner
  reported uploading/updating both Knox Survivors and KnoxBridge Workshop items.
  Publication/access and Required Item linkage still need owner-side
  confirmation; upload is not gameplay or release-gate evidence.
- Current Knox Workshop staging now mirrors the Knox source mod and includes
  the built KnoxBridge module JAR at the descriptor's exact path
  (`42/media/java/knox-agent.jar`). Its `mod.info` declares
  `require=KnoxBridgeRuntime`. The prior staged copy and safety backup are
  outside the upload `Contents` folder. Current upload staging is limited to
  Knox's mod folder plus the existing Workshop preview/metadata.
- KnoxBridge's Workshop item is a required dependency marker and author
  reference: its staging script includes the compile-time API JAR and setup/
  module-author guides, but not the player runtime installer. Players get setup
  from GitHub Releases. The revised staging change has not yet been uploaded or
  verified on Steam. Windows uses a standalone installer; Linux/macOS use a ZIP
  plus Python setup helper and remain unverified live. The owner previously
  reported both Workshop items public; verify Required Item linkage after the
  next Bridge Workshop upload. This is publication status, not gameplay evidence.
- Single-player is the supported focus.
- KnoxBridge is the active Workshop runtime target. The direct Knox legacy
  agent remains only as a source rollback path during migration.
- Focused candidate checks and the complete Lua regression suite are current;
  the full build/staging/package gate in `KS-PROD-003` remains open.
- Engine-bound behavior still requires live Build 42.20.4 acceptance.
- On 2026-09-28 KnoxBridge was updated in the installed PZ directory and
  launched through normal Steam Play in PZ 42.21.0 / Java 25.0.1. PZ's actual
  enabled list resolved KnoxBridgeIndependentTest and KnoxSurvivors to their
  selected roots. Both unknown JARs were blocked on the first run, then exact
  hashes were allowed for this requested local test. On restart, both modules
  loaded; the independent module initialized and registered its harmless
  probe, and Knox initialized with its required combat/visibility patches
  ready. `KnoxJavaBridge` was exposed. This proves startup, discovery, trust,
  module entrypoints, patch readiness, and bridge exposure, not in-world NPC
  behavior or persistence.
- Knox now has a `knoxbridge.properties` module descriptor and Java entrypoint;
  its source no longer requires the alternate runtime API. Module migration,
  Build 42.21 transformer checks, and the live runtime/module boundary are
  verified. NPC creation, movement, combat, save/reload, changed-hash/deny
  policy, and 42.20 live compatibility remain open beyond the limited probe
  below. See `KS-PROD-010`.
- During the 42.21 KnoxBridge session, the Knox log recorded native probe
  `ks-dev-1` spawned, door/fence movement transitions, live combat start with a
  baseball bat, attack requests, and zombie health reaching zero. A movement
  route also recorded `FailedStuck`; treat this as narrow bridge/patch/runtime
  evidence, not reliable pathing acceptance. Save/reload was not observed.
- The current KnoxBridge uninstaller restored `ProjectZomboid64.json` to the
  exact backed-up SHA-256. Ordinary Steam startup then succeeded with no new
  KnoxBridge log entry. Reinstall/health check and a second normal Steam launch
  rediscovered and loaded both approved modules. No saves or mod list files
  were targeted by the installer or Workshop staging task.
- The loaded base-supply loop now retains its shortage claim and durable return
  intent until typed storage confirms receipt; see `BUG-KS-031` and KS-PROD-008
  Slice E. Native transfer, capacity, save/reload, and shortage reevaluation
  still need Build 42 acceptance.
- Base-danger arbitration is covered offline. Do not repeat its source audit
  absent new evidence; the one-zombie/small-group combat replay remains live
  acceptance. No release-ready claim was produced by this offline change.

## NPC-system design direction

The owner-approved research direction is now captured in:

`docs/design/NPC_SYSTEM_INSPIRATION.md`

The central rule is that a Knox survivor remains an AI-controlled Project Zomboid survivor, not a colony pawn. Existing autonomy, base jobs, relationships, groups, off-screen simulation and persistence should be connected through clearer shared operating rules rather than replaced by unrelated parallel systems.

Settled 2026-09-28 additions: off-screen life is continuous-real and cheaper, never faked (D-016); population is rare-but-findable with future named modes, hostility is relations-driven, and full politics/creator/MP are deferred future tracks (D-017); danger is Walking-Dead unpredictable with universal living-world first moments, all roadmap systems kept, and join-as-member recorded as future work (D-018). The per-slice completion track for the core loop lives in `WORK_QUEUE.md` `KS-PROD-008`; this cycle's base-life watchdog update is recorded under Slice F.

## Immediate production goal

Complete and connect the existing survivor systems into one reliable playable
loop while preserving their current ownership boundaries:

1. Reconcile identity, persistence, lifecycle and off-screen truth.
2. Make survivor brains, goals, needs, claims and autonomy produce believable
   decisions without controller conflicts.
3. Finish movement, pathing, traversal, native actions and interruption recovery.
4. Finish combat, threat awareness, retreat and resource consequences.
5. Finish storage, bases, jobs, supplies and workforce loops using real items and
   native world actions.
6. Finish companion orders, UI, notebook and player-facing feedback.
7. Complete purposeful implemented events, factions, missions and world activity.
8. Keep the launcher/runtime path compatible with the mod when a boundary needs
   both repositories.
9. Validate performance, balanced defaults and player customization.
10. Run focused, full offline and live Build 42 gates before making release claims.

Do not start unrelated feature families merely because an AI worker is idle.

## System status inventory

Status describes repository/offline evidence only unless the live-evidence
column explicitly records a Build 42 acceptance. “Offline verified” does not
mean engine behavior is verified. The recorded candidate gate is
`163b789a2564ee626bc9d5acdad46674623c25b8`; focused tests were 21/21 and the
full Lua regression set was 174/174 on 2026-09-27. The focused trace fix also
passed `test-world-traces.lua`, `test-event-runtime.lua`, and
`test-knox-events.lua`. No live Build 42 evidence is recorded for these systems.

| System | Implementation state | Status | Known issues | Offline evidence | Live evidence | Owner | Next action |
|---|---|---|---|---|---|---|---|
| Survivor identity and lifecycle | Stable identity separated from temporary engine body; lifecycle/materialization implemented | Offline verified | No confirmed defect; real identity continuity through death, hibernation and reconstruction remains unproven | Lifecycle-policy regression; full Lua suite 174/174 | None recorded | Codex | Replay identity through save/load and hibernation/rematerialization in a disposable save |
| Persistence and save/load | Java survivor records and Lua domain persistence/migrations implemented | Offline verified | Native inventory/body restoration and real save compatibility remain unverified | Persistence-related regressions; full Lua suite 174/174; Java checks recorded in KS-PROD-002 | None recorded | Codex | Save/reload one survivor and compare stable ID, body state, inventory, equipment and orders |
| Off-screen continuity | Bounded unloaded survival, stored-group movement and story state implemented; abstract scuffle outcomes removed; hibernation and away-team dispatch commit ledger ownership before native teardown; blocked dispatches retain only confirmed-removed members until canonical restoration registers them | Offline verified | BUG-KS-001 and BUG-KS-024 remain open for native replay; live parity between loaded and unloaded states is unverified | Focused away-dispatch, lifecycle, virtual-base-return, unloaded-survival/group/base-return, persistence recovery and rematerialization tests pass, including blocked-ledger reload/recovery and finalization failure; `tools/verify.ps1 -SkipJava`: 112 Lua files, 176 scripts, 288 checks, 0 failures | None recorded | Codex | Replay unloaded travel and multi-member dispatch through pre-removal failure, partial teardown, save/reload and rematerialization; verify no duplicate or lost survivor |
| Brains and autonomy | Priority controller, needs, duties and interruption ownership implemented; successful leader roam/regroup routes issue bounded follow through existing follower arbitration; explicit bounded hold remains API-only | Offline verified | Leader-order timing, native movement/action behavior, cancellation/retry, interruption/resumption, and save/reload require live observation; no autonomous hold, order UI, or destination command exists | Extended relationship-coherence, autonomy-formation and roaming-autonomy coverage; full offline gate 112 Lua files, 176 scripts, 288 checks, 0 failures; `git diff --check` passed | None recorded | Codex | Disposable leader plus two followers: ordinary travel/regroup; persistence-API hold during fence/door and need/combat; clear, expiry and reload; inspect route spam/duplicates |
| Movement and pathing | Shared movement requests, traversal and retries implemented; formation follow latches native traversal, reevaluates on the first landed update, and reopens group-follow arbitration on the next tick after native route success | Offline verified | BUG-KS-011 and BUG-KS-028 remain open for live fence and multi-follower timing; general doors/windows/path recovery remain unverified | Focused formation, combat/traversal, command, order and conversation regressions pass; full offline gate: 112 Lua files, 176 scripts, 288 checks, 0 failures | Owner observed a several-second post-fence pause and follower stop/think/resume cadence before the corrections; neither is replayed live | Codex | Repeat a leader-plus-two-followers route through ordinary travel, a door/fence, need/combat interruption and recovery; verify no route spam or prolonged post-arrival pause |
| Native actions | Native action adapters and action ownership implemented | Implemented | Native animation, completion, real item transfer and interruption have no live acceptance evidence | Related offline action regressions are included in the 174/174 suite | None recorded | Codex / OpenCode | Verify one native work action and one danger-interrupted action in game |
| Combat and threat awareness | Native combat integration and threat selection implemented; unsafe off-slot lighting-bit assist disabled; bounded retreat admission restored through the existing native movement path | In progress | BUG-KS-009 and BUG-KS-012 need live replay; native damage and route completion remain unverified | Focused zombie-awareness, combat-intelligence, formation, companion/order, and conversation regressions pass; full Lua suite 175/175 (287 checks) | Build 42.20.4 QA observation recorded the LightingJNI error and owner observed risky multi-zombie commitment; neither corrected combat nor retreat behavior is live-verified | Codex | Run one controlled combat replay: healthy one-zombie/small-group hold, then overwhelming-group retreat through a viable lane and recovery without a loop |
| Inventory and storage | Native item snapshots, routing, organizer and transfer logic implemented; Logs & Lumber and General Storage roles are assignable through the persisted container policy | Offline verified | Real item transfer, nested-item persistence, resource consumption, and loose ground-item pickup remain unverified; broader reported misrouting needs a live/current reproducer | Focused base/storage/job/resupply tests, including typed roles, general fallback, logs/firewood matching; full Lua suite 175/175 (287 checks). Native `VehicleMaintenance` parts (tires, batteries, brakes, gas tanks) now route to Materials via the existing building matcher with focused + full offline evidence in Slice E (112/176/288, 0 failed); native transfer, capacity/weight, save/reload, and vehicle acquisition behavior remain live-only. | None recorded | Codex / OpenCode | Live-test real item deposit, General fallback, log/firewood routing, and save/reload identity/count |
| Bases and jobs | Base ownership, task claims, supply planning and job scheduling implemented; organizer and base-life watchdog cleanup use existing interruption/recovery owners | Offline verified | BUG-KS-013 remains in progress; native timed action, transfer, base-duty/UI behavior, visible base-life and task completion remain unverified | Dynamic organizer duty-change regression; seven focused base-life/recovery checks including `test-base-leisure-routing.lua` patrol/return/rest watchdog dispatch; full offline gate: 112 Lua sources, 177 scripts, 289 checks, 0 failures | None recorded | Codex / OpenCode | Observe a full day at a two-resident base; force stalled rest and patrol/return routes, verify fallback/released claims, then complete one real-resource job |
| Companions, orders and UI | Companion directives, order routing, card/notebook and HUD implemented; stale-shell detachment has bounded hibernation/recovery handling; speech overlay is transparent and input-pass-through configured | Offline verified | BUG-KS-008 lifecycle and BUG-KS-010 rendered indicator/right-click behavior remain open for live validation | Focused lifecycle/order/persistence tests plus speech style/input/expiry/stale-coordinate regression pass | Owner observed a black/ugly arrow and apparent right-click loss before the correction; corrected rendering and input behavior have not been replayed live | Codex | Replay the speech indicator in Build 42, visually confirm projection/colour, and open world context menus outside and over the Activity Feed |
| Events, factions, raids and world activity | Persistent event/faction systems; unloaded raids retain stored travel/arrival and pause at the native active/objective boundary | Blocked | BUG-KS-001 remains open until live loaded → unloaded → loaded replay; BUG-KS-002 native trace replay remains required | Six focused event/trace tests passed; full Lua verification: 112 sources, 174 scripts, 286 checks, 0 failed | None recorded | Codex | Run the disposable-save raid replay and inspect loaded combat, history, trace, and roster ownership |
| Launcher/runtime compatibility | KnoxBridge is the sole supported public Knox runtime; separate Knox Survivors Launcher is deprecated/unsupported and its requested privacy change is pending; direct legacy agent is rollback-only | In progress | KS-PROD-010: current approval dialog, Linux/macOS startup, save/reload, and full gameplay acceptance remain open | KnoxBridge runtime and setup checks; existing Windows Steam evidence is for an earlier packaged installer | Current alpha6 approval UI and package need fresh Windows replay; no Linux/macOS live startup or Knox save/reload evidence | Codex / Human | Keep the user path on KnoxBridge; publish the current Bridge Workshop author-reference payload and validate startup/gameplay on disposable saves |
| external runtime interoperability | Not a supported Knox startup path; old notes are historical, and KnoxBridge is the active runtime target | Not started | Existing modules that use other Java runtimes are not compatible unless ported; competing instrumentation must not be stacked | Source-level competing-bootstrap block; no live compatibility/stacking test; published external Java runtime page describes an older B42 range | None recorded | Codex / Human | Keep compatibility claims limited to KnoxBridge modules; do not use external Java runtime as the technical baseline |
| Performance, defaults and customization | Conservative defaults and configurable limits/settings exist in implemented systems | Implemented | No end-to-end live performance measurement or unified customization acceptance recorded | Regression suite passes; no dedicated performance acceptance recorded | None recorded | Codex / OpenCode | Measure population/action loop cost and verify meaningful settings in a fresh save |
| Vehicles and driving | Shared admission verdict (driver/engine/driveability/speed/towing/fuel/locks with reason codes) consumed by travel discovery and drive admission; group boarding commits an explicit roster rolled back on any abort/arrival; duty/order changes arbitrate vehicle leases (takeover preserves riders); boarding yields to danger/critical needs; refused exits retry boundedly once stopped; arrival exits each passenger once with the driver staying and one truthful feed line; unrecoverable exits report once; native part storage routes to Materials; geometry/routing and seat leases unchanged | Offline verified | BUG-KS-030 remains open; native fuel/condition/lock semantics, real boarding, multi-car driving runs, convoy spacing, control release, and part consumption remain unverified | Focused vehicle matrix on both shared and fallback paths, roster/rollback, duty-arbitration, urgency, stranded-recovery, and arrival/give-up coverage, plus full offline gate: 112 Lua sources, 177 scripts, 289 checks, 0 failures | None recorded | Codex / OpenCode | Disposable-save replay over real parked vehicles in every admission state plus one valid fueled vehicle; convoys and native consumption are separate future gates |

## Main active risk

The main risks are **evidence drift** and **system overlap**: implementation is
substantial, but several connected boundaries still need focused/live proof and
must be completed through their existing owners rather than parallel replacements.

The documentation structure has been simplified so ModForge, Codex, OpenCode
and normal human work share one current operational truth instead of competing
old plans and release snapshots. ModForge is optional; its generated state is a
convenience snapshot and never replaces the repository records.

## Assigned-storage traversal recovery — 2026-09-28

The current autonomy controller already recovered entry failures during the
work-site leg, but failed a claimed base job immediately when its assigned
storage pickup route encountered an entry-related native failure. The pickup
uses one real item and a transient item/container reservation. It now feeds the
assigned container's room and exact approach into the existing bounded window
detour; permitted door breaking retains that exact lease and resumes the same
pickup route. If entry is unavailable, the existing task-failure path releases
the task and reservations. Transfer remains owned by the native inventory
action and is not considered complete until the existing receipt check.

Planner and Terra compared this gap with the public locked-door and
corpse/fence reports. Corpse handling already has bounded retries/drop
cooldown and fail-closed task release in offline coverage, so its physical
fence outcome stays a live-only question. The generic locked-entry machinery
was already used by other routes; this cycle closed the assigned base-storage
leg that bypassed it. BUG-KS-033 records the source-confirmed correction.
Focused supply-entry, shared entry, base-action, task-validation, supply
arrival, claim-suspension and inventory-cleanup checks passed. Exact-worktree
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 178 regression
scripts (290 checks, 0 failures). Java was skipped; the new regression script
is local under ignored `tools/` policy. Native Build 42 traversal, actual
container receipt, interruption and save/reload remain unverified.

## Base-job completion authority — 2026-09-28

Current executors verify physical results before task completion, and the
existing persistent task board rejects finishes from stale/revoked claim
owners. The autonomy controller now waits for that authoritative response
before recording job success, advancing automatic-work pacing, or announcing
completion. Rejected completion is recorded as a bounded failure and clears
only the local task's transient state/reservations; it does not undo a real
world change or mutate another survivor's claim. `BUG-KS-034` records this
handoff correction. Focused task-validation and connected base-job regressions,
the broad offline gate, and exact counts are recorded in `WORK_QUEUE.md`. A
native Build 42 job completion with claim reassignment/interruption, feedback,
next-activity arbitration and save/reload remains unverified.

## Durable base-supply ownership — 2026-09-28

The loaded-world shortage claim was time-limited, but an elected resident's
persisted `activeSupplyRun` could continue searching or returning past its
1.5-hour lease. The controller now reconstructs the transient claim from valid
same-base active runs before electing another worker, including unloaded
residents. The durable duty remains the sole run owner; native transfer and
save/reload remain live acceptance. `BUG-KS-035` records the confirmed defect
and offline correction. The full `tools/verify.ps1 -SkipJava` gate checked 112
Lua sources, 178 regression scripts, 290 checks and 0 failures; focused supply
planner, auto-scavenge, inventory-cleanup and base-needs tests passed. Focused
test updates are local under ignored `tools/` policy, not tracked evidence.

## Loaded social memory connection — 2026-09-28

The loaded encounter coordinator now writes finalized greet, decline, hostile,
join, and rejected-join outcomes through the existing `KS_OffscreenStories`
owner into both participants' existing persistent ledgers. Entries use
canonical survivor IDs, are idempotent for the same outcome/time, and retain
the established 12-entry cap. Missing ledgers fail closed. Dialogue recounts
and Survivor Card labels describe joining, parting, and hostility without
implying combat or theft that was not verified. Focused story/history, recount,
human-encounter, view-model, and relationship-coherence checks passed.
`tools/verify.ps1 -SkipJava` checked 112
Lua sources, 178 regression scripts, 290 checks, 0 failures. Focused test
changes are local under ignored `tools/` policy. Build 42 still needs encounter
completion, save/reload persistence, and later dialogue/Card replay; hostility
does not imply native combat/robbery acceptance.
