<!-- modforge-doc
authority: canonical
load: always
purpose: current production position and immediate goal
-->

# Knox Survivors — current production state

Updated: 2026-09-28

## Repository baseline

The connected GitHub repository is `exe-create/KnoxSurvivors`.

GitHub `main` and the local checkout are at commit:

`163b789a2564ee626bc9d5acdad46674623c25b8` — 2026-09-26 — `Consolidate production docs, wire ModForge contract, stabilize storage/organize`

This commit is directly based on the prior baseline `7f56dcb846f107a4c226770b3ca72fe21232235b`.

## Current worktree

The implementation baseline is `163b789`, but the current worktree is not
clean. The intentional post-baseline changes are documentation and coordination
work for the optional ModForge/OpenCode workflow:

- modified `.modforge/agents.json`, `context.json`, `project.json` and
  `workflows.json`;
- modified `AGENTS.md` and selected `docs/production/*.md` records;
- added `.modforge/free-models.json`, `opencode.json` and `scripts/`;
- modified `KS_WorldTraces.lua` and `test-world-traces.lua` for the bounded
  `BUG-KS-002` retry fix, which is offline-verified but still needs its live gate.

These changes must remain visible in Git review. They do not prove or claim new
gameplay behavior. Do not describe the worktree as clean until these changes are
deliberately committed or discarded.

Source/test scope represented by this candidate commit:

- 24 Lua source files changed (20 modified, 4 added);
- 21 Lua regression tests changed (17 modified, 4 added);
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
- **2026-09-25:** GitHub `main` was at the prior baseline `7f56dcb`.
- **2026-09-26:** commit `163b789` consolidated production documentation and coordination contracts, and committed the associated base/storage/UI/autonomy/event/off-screen implementation and regression tests.

## Last retained offline evidence

`docs/FEATURE_AUDIT.md` records an integrated stabilization checkpoint dated 2026-09-24 with:

- 107 Lua syntax checks;
- 164 Lua regression scripts;
- Java build/check passing;
- 272 checks total;
- 0 failed.

That evidence predates `163b789`. It remains useful historical evidence, but it is not proof that the current worktree is release-ready.

## Current release state

- Public release line: `0.3.0-rc1`.
- Target: Project Zomboid `42.20.4`.
- Single-player is the supported focus.
- ZombieBuddy and the retained Knox launcher are alternative runtime paths; use one per launch.
- Focused candidate checks and the complete Lua regression suite are current;
  the full build/staging/package gate in `KS-PROD-003` remains open.
- Engine-bound behavior still requires live Build 42.20.4 acceptance.
- No new release-ready claim was produced by this documentation cleanup.

## NPC-system design direction

The owner-approved research direction is now captured in:

`docs/design/NPC_SYSTEM_INSPIRATION.md`

The central rule is that a Knox survivor remains an AI-controlled Project Zomboid survivor, not a colony pawn. Existing autonomy, base jobs, relationships, groups, off-screen simulation and persistence should be connected through clearer shared operating rules rather than replaced by unrelated parallel systems.

Settled 2026-09-28 additions: off-screen life is continuous-real and cheaper, never faked (D-016); population is rare-but-findable with future named modes, hostility is relations-driven, and full politics/creator/MP are deferred future tracks (D-017); danger is Walking-Dead unpredictable with universal living-world first moments, all roadmap systems kept, and join-as-member recorded as future work (D-018). The per-slice completion track for the core loop lives in `WORK_QUEUE.md` `KS-PROD-008`; no implementation state changes were claimed by this docs pass.

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
| Bases and jobs | Base ownership, task claims, supply planning and job scheduling implemented; base-duty changes now interrupt an in-progress organizer through the existing directive path | Offline verified | BUG-KS-013 remains in progress; native timed action, real item transfer, base-duty/UI behavior, task completion, and resource consumption remain unverified | Dynamic organizer duty-change regression (leave base duty, hauling disabled, reassignment; cancels action/route once and releases item/container claims), eight related focused base-life checks, and full offline gate: 112 Lua sources, 176 scripts, 288 checks, 0 failures | None recorded | Codex / OpenCode | Complete one supplied base job and replay base-duty changes during an active organizer round; verify actual world/inventory changes and no visible idle/stuck behavior |
| Companions, orders and UI | Companion directives, order routing, card/notebook and HUD implemented; stale-shell detachment has bounded hibernation/recovery handling; speech overlay is transparent and input-pass-through configured | Offline verified | BUG-KS-008 lifecycle and BUG-KS-010 rendered indicator/right-click behavior remain open for live validation | Focused lifecycle/order/persistence tests plus speech style/input/expiry/stale-coordinate regression pass | Owner observed a black/ugly arrow and apparent right-click loss before the correction; corrected rendering and input behavior have not been replayed live | Codex | Replay the speech indicator in Build 42, visually confirm projection/colour, and open world context menus outside and over the Activity Feed |
| Events, factions, raids and world activity | Persistent event/faction systems; unloaded raids retain stored travel/arrival and pause at the native active/objective boundary | Blocked | BUG-KS-001 remains open until live loaded → unloaded → loaded replay; BUG-KS-002 native trace replay remains required | Six focused event/trace tests passed; full Lua verification: 112 sources, 174 scripts, 286 checks, 0 failed | None recorded | Codex | Run the disposable-save raid replay and inspect loaded combat, history, trace, and roster ownership |
| Launcher/runtime compatibility | Separate launcher repository is the sole launcher source, verification, and packaging owner; embedded project/build path retired | In progress | BUG-KS-003 remains open pending live legacy launch with ZombieBuddy disabled and exactly one runtime PASS | Sibling `scripts/build.ps1` security, updater, runtime-isolation, and Windows-bootstrap checks passed; main repo retirement check and `tools/verify.ps1` passed (112 Lua sources, 174 scripts, Java included, 287 checks, 0 failed); no live startup evidence | None recorded | OpenCode / Human | Run live legacy launch with ZombieBuddy disabled; confirm exactly one `runtime start PASS source=legacy-javaagent` line |
| ZombieBuddy compatibility | Patch API integration and Lua bridge implemented | Offline verified | Runtime-start PASS alone does not prove patch readiness or live hook behavior; must not be stacked with Knox legacy agent | Java/bridge offline checks recorded; KS-PROD-006 lists required readiness markers | None recorded | OpenCode / Human | ZombieBuddy-only live startup: patch readiness, Java bridge exposure, Lua bridge PASS, then real combat |
| Performance, defaults and customization | Conservative defaults and configurable limits/settings exist in implemented systems | Implemented | No end-to-end live performance measurement or unified customization acceptance recorded | Regression suite passes; no dedicated performance acceptance recorded | None recorded | Codex / OpenCode | Measure population/action loop cost and verify meaningful settings in a fresh save |
| Vehicles and driving | Shared admission verdict (driver/engine/driveability/speed/towing/fuel/locks with reason codes) consumed by travel discovery and drive admission; group boarding commits an explicit roster rolled back on any abort/arrival; duty/order changes arbitrate vehicle leases (takeover preserves riders); native part storage routes to Materials; geometry/routing and seat leases unchanged | Offline verified | BUG-KS-030 remains open; native fuel/condition/lock semantics, real boarding, multi-car driving runs, convoy spacing, control release, and part consumption remain unverified | Focused vehicle matrix on both shared and fallback paths, roster/rollback and duty-arbitration coverage, plus full offline gate: 112 Lua sources, 176 scripts, 288 checks, 0 failures | None recorded | Codex / OpenCode | Disposable-save replay over real parked vehicles in every admission state plus one valid fueled vehicle; convoys and native consumption are separate future gates |

## Main active risk

The main risks are **evidence drift** and **system overlap**: implementation is
substantial, but several connected boundaries still need focused/live proof and
must be completed through their existing owners rather than parallel replacements.

The documentation structure has been simplified so ModForge, Codex, OpenCode
and normal human work share one current operational truth instead of competing
old plans and release snapshots. ModForge is optional; its generated state is a
convenience snapshot and never replaces the repository records.
