# Knox Survivors finishing plan

Audit: 2026-09-20. Authority: current working files, including uncommitted/new files.
Source-traced production audit; no gameplay fixes or live test performed in this pass.
P0 = core simulation blocked; P1 = major inconsistency; P2 = reliability/polish; P3 = optional cleanup.
No unconditional P0 established. Existing offline passes do not establish live completion.

## Survivor status, HUD and loaded/unloaded accuracy repair — 2026-09-21

**Completed in this focused pass (code and offline regression verified).** The
existing native-needs and unloaded-survival boundary remains the sole source of
condition data. This pass repairs its player-facing projection rather than
adding a parallel HUD or need simulator.

1. **Authoritative condition projection:** loaded survivors read hunger, thirst,
   fatigue, endurance, health and bleeding from native Build 42 stats/body
   damage. Pain is projected only when the live native API supplies it. A
   survivor with no real materialized/offscreen snapshot now reports condition
   unavailable rather than a fabricated full-health, full-needs display.
2. **Safe materialization handoff:** capture continues to overwrite the ledger
   from the live native body before hibernation. Materialization restores that
   ledger once, preserves a monotonic `lastHours`, and cannot reopen elapsed
   offscreen time if a stale clock is observed. Existing active-ID exclusion
   keeps loaded bodies out of the offscreen advance loop.
3. **Meaningful activity ownership:** runtime state now keeps flee/combat and
   vehicle ownership above stale action decisions; direct decisions only label
   their own timed recovery/self-care state. Exact active base tasks (including
   barricading, corpse hauling, farming and woodwork) and the existing native
   reload lease project as their real activity instead of generic base work.
4. **HUD/card honesty:** the companion HUD renders unknown condition bars as
   unknown instead of empty/full values, handles absent need tables safely, and
   calls unloaded equipment unavailable rather than unarmed. The Survivor Card
   already consumes this shared snapshot, so its health/needs/activity/order,
   faction/base and relationship fields now receive the same corrected values.
   Existing per-player companion lookup, death filtering and card teardown
   retain split-screen/local ownership behavior.
5. **Critical visibility:** starving, dehydrated and critical-exhaustion states
   are distinguished from ordinary food, water and catch-breath advisories;
   live pain is included when supported without inventing offscreen injury data.

### Changed files in this pass

- `mod/42/media/lua/client/KS_SurvivorNeeds.lua`
- `mod/42/media/lua/client/KS_UnloadedSurvival.lua`
- `mod/42/media/lua/client/KS_Persistence.lua`
- `mod/42/media/lua/client/KS_SurvivorRuntime.lua`
- `mod/42/media/lua/client/KS_SurvivorViewModel.lua`
- `mod/42/media/lua/client/KS_CompanionHUD.lua`
- `tools/test-survivor-view-model.lua`
- `tools/test-world-presence.lua`

### Automated coverage added or extended

- Unknown unloaded state cannot display fabricated healthy bars or unarmed gear.
- Loaded native hunger/thirst/health values, critical exhaustion and live pain
  project through the shared view model.
- A barricade task and native reload lease report their exact current activity;
  a stale self-care decision cannot hide a flee state.
- Materializing a survivor restores exact ledger stats into the native body and
  preserves the ledger clock, preventing a double offscreen advance.
- Existing companion death removal, unloaded activity, base-task projection,
  no-double-advance, starvation/dehydration and card structural coverage remain
  part of the complete verifier suite.

### Live-only Build 42 acceptance

- Confirm native `BodyDamage:getPain()` is present on the target Build 42 build
  and that its displayed scale is useful during actual injuries.
- Confirm the HUD changes from live to stored condition without a one-refresh
  stale row when a companion streams out/in, dies, leaves or changes local
  player ownership.
- Confirm native reload activity clears immediately after reload, target loss,
  firearm fallback and combat disengagement.
- Confirm the Survivor Card's vanilla tabs continue to bind the newly
  materialized survivor body after a long offscreen interval.

### Next highest-value release-readiness pass

1. Run one focused live Build 42 acceptance scenario for base jobs, barricading,
   needs/HUD, firearms, corpse hauling, hostile encounters, a faction raid and
   save/reload; triage only confirmed engine-boundary evidence.
2. Complete the remaining base-job native-action acceptance pass, especially
   interruption/resume behavior for non-barricade physical tasks.
3. Validate companion and NPC vehicle entry, seat changes and long-distance
   faction travel with real Build 42 vehicles.
4. Audit Java-agent/Workshop/launcher release packaging only after the gameplay
   acceptance run confirms the current mod build is stable.

## Runtime map and lifecycle coverage

Paths below are relative to the repository; Lua files are under `mod/42/media/lua/client/`.

- `KS_Bootstrap.lua` logs startup and loads QA. The simulation actually starts through
  `KS_SurvivorAutonomy.lua`'s game/player/death events and OnTick owner.
- That owner reconciles population/settlements/events, coordinates relationships and
  group scavenging, synchronizes companion duties, then ticks each autonomy controller.
- `KS_SurvivorAutonomyController.lua` selects needs, combat, orders, base tasks, group
  movement, shelter and scavenging. `KS_SurvivorRuntime.lua` maps stable IDs to bodies.
  Java bridge/runtime own body creation, movement, traversal and combat execution.
- `KS_Persistence.lua` owns survivor records, duties, groups, factions, bases and
  relationship normalization. `KS_WorldPopulation.lua`, `KS_UnloadedSurvival.lua`
  and `KS_GroupCohesion.lua` advance stored survivors and group cohesion.

| Lifecycle/system | Current connection and limit |
| --- | --- |
| Spawn → survive → scavenge/travel | Population → autonomy → needs/looting/native actions → Java movement. Connected; unloaded base residents now receive a bounded handoff of real assigned supplies before storage. |
| Meet → cooperate/ignore/threaten/rob/fight → group | Relationships observe/coordinate meetings and group membership; dialogue and recruitment use persistent relationship state. Not just player-driven. |
| Group → faction | Relationships periodically evaluates readiness; GroupCohesion also credits verified unloaded together-time and evaluates promotion. Do not rewrite this as missing. |
| Temporary shelter → permanent base | Night shelter serves eligible lone wanderers; faction camps require an existing faction; faction scouting selects a home and safehouse/base setup follows. Temporary travel-group shelter is missing. |
| Base → jobs/resources | BaseManager/BaseJobs/TaskBoard → storage supply plan → controller → native task action. Farming, woodwork, cooking, repairs, guarding/patrol and corpses have execution paths. Animals/construction retired; metal barricading absent. |
| Hostility/player/NPC interactions | ThreatClassifier, Relationships, HumanCombatRelations and Java combat gates connect relationship policy to targets. FactionProperty records player theft. Automatic raid candidates include other faction bases, not only player bases. |
| Melee/firearms/zombie reactions | Controller → Java combat; FirearmSupport uses native canShoot/rack/reload/attackHook. Agent adapters handle off-slot collision/visibility. Connected, but actual damage/reload/reaction acceptance still requires engine evidence. |
| Orders vs autonomy | CompanionService sync → controller priorities; jobs suspend for temporary combat/needs. Event, group sortie and vehicle ownership also participate. Error cleanup and recovery priority gaps below. |
| Death/loss/replacement/save | Population retirement, persisted membership and relationship normalization exist. Do not label faction lifecycle wholly absent; verify leader loss/last-member/base ownership together. Capture failure boundary below needs hardening. |

## Prioritized root causes

### F1 — P1: exception recovery does not unwind the current owner

**Completed in focused repair pass (code and offline regression verified).**

**Confirmed source path:** `KS_SurvivorAutonomy.lua:1060-1080` catches a controller
exception, calls only `abandonBaseTask`, then forces IDLE. In the controller,
`abandonBaseTask` (~4558) returns early when there is no base task. It does not
reset combat or release unrelated supply/meeting/rest reservations. The broader
`abandonCurrentDecision` (~5463) already does much of the required teardown.

**Effect/risk:** an interrupted combat, loot, medical or rest action may remain
active while the newly idle Lua controller starts another decision. Repeated
exceptions can present as freezing, oscillation or cancelled work.

**Small repair:** one bounded, exception-safe recovery boundary that releases the
actual transient owner, retains durable orders and records the original failure.
Test failures during combat, reload, transfer, hauling and rest; no stale route,
queue, claim or reservation may remain after recovery.

### F2 — P1: retired fleeing still owns a corpse-danger branch

**Completed in focused repair pass (code and offline regression verified).**

**Confirmed:** controller `fleeAssessment` (~1560) always returns false;
`beginFlee` (~7373) always returns false. The close-threat corpse carrier branch
(~8450-8477) calls `beginFlee` and unconditionally returns before combat/haul updates.

**Effect:** on threat-scan ticks the carrier neither releases the corpse nor
enters defense; the intended safe interruption is disconnected. This is not proof
of the earlier infinite walking symptom, but is a real remaining handoff defect.

**Small repair:** explicitly release/suspend hauling and hand off to permitted
defense when fleeing is disabled. Do not re-enable fleeing contrary to policy.
Test occupied hands, failed release, repeated scans and resumption after danger.

### F3 — P1: direct orders suppress recovery without an exhaustion exception

**Completed in focused repair pass (code and offline regression verified).**

**Confirmed:** controller `think` (~7794) converts both rest and sleep to roam for
any companion order/directive. Hunger/thirst retain interrupts; normal exhaustion
does not. This includes durable guard/patrol/follow orders.

**Effect/risk:** ordered survivors can repeatedly resume strenuous work/following
without entering the recovery path used by autonomous survivors.

**Small repair:** distinguish optional rest from critical endurance/fatigue; allow
bounded nearby recovery while retaining the exact order/guard post/patrol waypoint.
Test tired follow, guard, patrol and combat → recovery → original duty.

### F4 — P1: offscreen survival consumes resources without a base resupply loop

**Completed as a bounded authoritative handoff in the second focused repair pass
(code and offline regression verified). Long absences beyond serialized reserves
remain an explicit limitation below.**

**Confirmed:** `KS_UnloadedSurvival.lua:68` consumes only encoded personal inventory;
`advanceOne` (~431) advances hunger/thirst and lethal shortage damage.
`KS_BaseDutySimulation.lua:14` advances only guard/patrol. Physical production and
container withdrawals do not occur there. Loaded deposits/storage/jobs live in
`KS_BaseStorage.lua`, `KS_BaseSupplyPlanner.lua`, `KS_BaseJobs.lua` and the controller.

**Effect:** stocked settlements can lose unloaded residents once carried supplies
run out, even though their base has food/water. The world is partially autonomous,
not yet a closed sustainable resource simulation outside loaded cells.

**Small repair direction:** define a conservative unloaded resource policy before
adding production. Never fabricate loot or deduct the same stock twice. Reconcile
real withdrawals, pending materialization and time advancement atomically; if
stock cannot be authoritatively accessed, expose that limit instead of implying
normal base support. Test long absences, empty/stocked bases and repeated reloads.

### F5 — P1: save capture isolation is incomplete

**Completed in focused repair pass (code and offline regression verified).**

**Confirmed risk:** `KS_Persistence.lua:5388-5478` protects native record capture,
but subsequent capability capture and some character lookups can throw.
`captureAllActiveSurvivors` calls each capture directly without an outer per-ID
pcall, despite its comment promising one failed survivor cannot block the rest.

**Effect:** an exception after one record is written can prevent later active
survivors being captured; their persisted bodies/inventories may remain stale.

**Small repair:** per-survivor exception isolation and explicit partial-capture
reporting; preserve last valid records and death/departure tombstones. Inject a
capability/snapshot failure and verify all other survivors still save correctly.

### F6 — P2: temporary travel groups have no shared night-shelter transition

**Confirmed:** controller `beginNightShelter` (~7285) excludes followers and leaders
with more than one group member. `KS_FactionCamps.lua:136` creates camps only for
existing NPC factions. `KS_NightShelter.lua:59` chooses room tiles without ownership
or threat eligibility checks.

**Effect:** loners can shelter, while pre-faction groups lack that stage; a loner's
shelter destination may also be an occupied hostile home.

**Small repair:** reuse group objective/formation ownership for a bounded shared
refuge, with existing territory/hostility filters. Preserve the temporary group;
do not force faction promotion or invent a second camp architecture.

### F7 — Completed: wood-window barricade execution boundary

**Confirmed:** `KS_BaseJobs.lua:9-12` explicitly retires animal care/construction;
their modules are deleted in this workspace. TaskBoard/OrderCatalog omit those
jobs. `KS_BaseBarricades.lua:398-434` equips hammer/plank, calls
`ISBarricadeAction(..., false, false)` and verifies plank count; no metal path exists.

**Action:** document the actual release scope. Keep animals/construction excluded
unless deliberately restored later. Treat metal barricading as incomplete, not a
working variant of wood barricading. Do not diagnose every blocked wood task as a
missing material feature: inspect discovery → approach → carried supplies → native
action result using the current barricade code and QA evidence.

## Focused repair pass completed — 2026-09-20

1. **Controller cleanup/error recovery:** the tick boundary now calls one
   idempotent recovery method. It independently cancels movement/combat/actions,
   releases corpse grip, task ownership, supply/rest/aid/social/ambient leases and
   every reservation owned by that controller, then returns to IDLE without
   clearing durable orders, membership or life intent. A failing cleanup step no
   longer prevents later steps. If normal base-task teardown itself throws, a
   final fallback releases the persisted claim and applies the normal bounded
   blocked-task retry fields.
2. **Corpse hauling/defense:** the obsolete flee handoff was removed. A nearby
   valid threat suspends the haul claim, cancels movement and requests native
   corpse release. Combat starts only after the hands are free. The retained task
   is reconsidered after combat; a release that never completes times out, drops
   the stale claim safely and still hands control to defense.
3. **Orders/exhaustion:** ordinary tiredness remains below Follow/Hold/Guard/Patrol,
   while endurance at or below `0.12` or fatigue at or above `0.90` may enter the
   existing recovery path. Recovery completion thresholds provide hysteresis;
   the exact companion order/directive remains stored for reevaluation afterward.
4. **Save capture isolation:** active-ID lookup and every survivor capture now have
   exception boundaries. Later survivors continue after one exception. Capability,
   needs and unloaded-state hook failures are reported as partial failures while a
   successfully serialized native record remains preserved.
5. **Regression coverage:** focused tests now exercise cleanup with an injected
   teardown failure and repeated invocation, reservation ownership, fallback task
   release, asynchronous corpse release and timeout, critical ordered recovery,
   partial save capture and a middle-survivor exception.

### Changed files in this pass

- `mod/42/media/lua/client/KS_SurvivorAutonomyController.lua`
- `mod/42/media/lua/client/KS_SurvivorAutonomy.lua`
- `mod/42/media/lua/client/KS_Persistence.lua`
- `tools/test-ai-priority-stability.lua`
- `tools/test-combat-intelligence.lua`
- `tools/test-persistence-first-capture.lua`
- `tools/test-base-mechanics.lua`
- `FINISH_PLAN.md`

### Verification

- `powershell -ExecutionPolicy Bypass -File tools\verify.ps1`: **243 checks,
  0 failed**, including 102 Lua syntax checks, 140 Lua regression scripts and the
  Java check/build verifiers.
- `.\gradlew.bat build deployDev --console=plain`: **BUILD SUCCESSFUL**; development
  payload staged and deployed.
- No new source-confirmed blocker was found inside this focused batch.

### Live-runtime acceptance still required

- Confirm Build 42 finishes `setDoGrappleLetGo()` within the bounded corpse-defense
  handoff and visibly resumes/reconsiders the interrupted haul after combat.
- Confirm native rest/sleep posture and stat recovery under Follow, Hold, Guard and
  Patrol do not visually flap before returning to the retained order.
- Force a real controller exception during native movement/combat/timed action and
  confirm the engine body has no stale animation or native owner after recovery.
- Save with a deliberately problematic loaded survivor and confirm Project Zomboid
  completes the save while later survivor records restore correctly.

## Unloaded base-resource repair completed — 2026-09-20

The root cause was the ownership boundary between loaded world containers and
serialized survivors. `KS_BaseStorage` could inspect and transfer real container
items only while their squares were loaded. `KS_UnloadedSurvival` deliberately
consumed only encoded personal inventory, but no handoff moved assigned base stock
into that inventory before the body disappeared.

This pass fixed four connected P1 inconsistencies:

1. **Real base provisioning:** immediately before distance hibernation, a resident
   physically inside its functioning base receives a bounded reserve of up to four
   safe food items and three valid water items. Existing carried supplies count
   toward the limit. Every provision is the actual world item moved from an assigned
   typed container into the survivor inventory before native record capture.
2. **Transactional ownership and mission parity:** provisioning is idempotent and
   rolls a moved item back to its source if transfer verification fails. Successful
   body removal explicitly marks the survival ledger hibernated. Player base scouts
   and NPC faction away teams use the same provisioning boundary before capture.
3. **Base sharing while unloaded:** hibernated residents assigned to the same base
   may consume a real provision serialized in another hibernated resident record.
   Loaded bodies, foreign bases and live world containers are excluded. The donor
   record is committed before relief reaches the recipient, preventing duplication.
4. **Fair shortage consequences:** starvation/dehydration damage now applies only
   to the part of an unloaded simulation step spent beyond the lethal threshold,
   instead of charging the full step after a late threshold crossing.

The loaded job/resource loop remains authoritative. Provisioning reduces the real
container inventory, so the existing storage summary, shortage planner and loaded
scavenging/job logic see the reduced stock when the base is loaded again. No food,
water, loot, farming output or construction material is generated offscreen.

### Changed files in this pass

- `mod/42/media/lua/client/KS_BaseStorage.lua`
- `mod/42/media/lua/client/KS_UnloadedSurvival.lua`
- `mod/42/media/lua/client/KS_SurvivorAutonomy.lua`
- `tools/test-base-storage.lua`
- `tools/test-unloaded-survival.lua`
- `tools/test-away-teams.lua`
- `FINISH_PLAN.md`

### Automated verification

- Focused storage tests verify real-instance transfer, bounded reserves,
  idempotence, unavailable-storage shortages and rollback after failed transfer.
- Focused unloaded tests verify canonical-base eligibility, persisted shortage
  evidence, explicit loaded→stored ownership, same-base record sharing, atomic
  donor depletion and proportional lethal damage.
- Away-team tests verify both player and NPC base departures use the provisioning
  and stored-ledger handoff.
- `powershell -ExecutionPolicy Bypass -File tools\verify.ps1`: **243 checks,
  0 failed**, including 102 Lua syntax checks, 140 Lua regression scripts and Java
  verification/build checks.

### Newly confirmed limits and live-only acceptance

- Only assigned containers whose real squares are loaded at handoff can provide
  supplies. Unavailable storage is recorded as a shortage and never guessed.
- The carried reserve is intentionally bounded. A base left unloaded longer than
  its residents' combined serialized provisions can still suffer shortages even
  if inaccessible world containers retain additional stock. Solving that fully
  requires exact item serialization/escrow and reconciliation, not an abstract
  numeric stockpile.
- Farming, cooking, harvesting and physical production remain loaded-world jobs.
  Simulating their output without world objects would fabricate resources.
- Live Build 42 must confirm `AddItem(instance)` detaches nested/container items as
  expected, record capture preserves food/fluid state, restored residents deposit
  surplus normally, and multi-day faction bases consume each item exactly once.

### Recommended next connected items

1. Design the exact-item long-duration base escrow/reconciliation boundary, or
   explicitly accept the bounded-reserve policy after multi-day live evidence.
2. F6: connect temporary travel groups to one shared, hostility-filtered night
   shelter transition through existing group objectives.
3. F7: run the targeted wood-barricade discovery → supply → approach → native
   action acceptance pass; keep retired animal care/construction and absent metal
   barricading out of scope.
4. Verify faction/base leader loss, last-member collapse and base ownership cleanup
   together so sustainable settlements cannot leave orphaned resource ownership.
5. Run one engine acceptance pass covering resource handoff, firearms, wood
   barricading, corpse drop-off and multi-day save/reload.

## Temporary-group shelter and faction lifecycle repair — 2026-09-20

This focused pass completed F6 and the related faction/base cleanup boundary.

1. **Shared temporary shelter:** a pre-faction travel-group leader now publishes
   a normal `night_shelter` group objective after the existing regroup path has
   completed. The leader selects an indoor square outside established base
   territory; followers retain normal formation until indoors, then use the
   existing sleep/recovery path. The objective clears at dawn or when the leader
   enters genuine combat. It creates no camp, faction, base, storage or claim.
2. **Off-screen continuity:** stored travel groups honor the same temporary
   shelter objective. They travel to the recorded refuge, rest overnight through
   their existing serialized need ledger, and clear the objective at dawn before
   ordinary itinerary travel resumes. No off-screen building, supplies or base
   state is fabricated.
3. **Faction succession and collapse:** membership removal now immediately runs
   canonical relationship normalization. A living faction retains a deterministic
   successor leader even below its formation threshold. An ordinary empty faction
   releases its camp, faction-owned base record, base jobs/zones/storage, generated
   safehouse (when available), diplomacy records, faction group link and stale
   resident duty. Event factions in their explicit departed lifecycle remain
   preserved for event history.

### Changed files in this pass

- `mod/42/media/lua/client/KS_NightShelter.lua`
- `mod/42/media/lua/client/KS_SurvivorAutonomyController.lua`
- `mod/42/media/lua/client/KS_UnloadedSurvival.lua`
- `mod/42/media/lua/client/KS_Persistence.lua`
- `tools/test-night-shelter.lua`
- `tools/test-night-shelter-hook.lua`
- `tools/test-relationship-coherence.lua`

### Focused automated coverage

- Shelter selection rejects established base territory for a temporary group.
- A group leader publishes one temporary objective and an indoor follower enters
  recovery rather than selecting a second destination.
- Leader death elects a deterministic successor; final-member death collapses the
  faction and removes its base, diplomacy and generated safehouse ownership.

### Live-only acceptance

- Verify a loaded group regroups before the leader enters a refuge, followers do
  not crowd the doorway, and all members resume travel after dawn.
- Verify combat near a refuge clears the overnight objective without breaking
  formation or leaving a sleeping pose behind.
- Verify a real Build 42 safehouse is released after a faction's final member dies.

### Recommended next connected items

1. Run the targeted wood-barricade discovery → supply → approach → native-action
   acceptance pass; keep retired animal care/construction and absent metal
   barricading out of scope.
2. Complete the engine acceptance pass for firearms, corpse drop-off, temporary
   group shelter, faction collapse and multi-day save/reload.
3. Use live evidence to decide whether the bounded unloaded base reserve needs
   exact-item long-duration escrow/reconciliation.
4. Address remaining P2 controller/UI polish only when a confirmed runtime trace
   identifies a shared root cause.

## Live-test bug repair batch — 2026-09-20

The latest live-test log exposed one definite runtime exception and several
connected player-facing failures. This batch addressed the shared action,
traversal and recovery boundaries without changing the save schema.

1. **Barricading:** native barricade validation now runs after the worker equips
   the hammer and plank and confirms carried nails before queueing. If a window
   object index becomes stale after streaming or another worker secures it, the
   claimed task retargets another valid opening instead of walking to a window
   and abandoning the job.
2. **Post-sleep error:** Build 42 `ISHandcraftAction` rejects a nil manual-input
   table during construction. Saw-log jobs now pass an empty table, preventing
   the repeated `convertToPZNetTable` null-pointer error seen after the worker
   resumed base work.
3. **Companion visibility and movement:** party shells now remain rendered for
   their owner even when ordinary LOS briefly occludes them. This keeps a
   companion readable while turning the camera without changing zombie
   perception or traversal. Formation routes commit longer, refresh less often,
   ignore small one-tile target shifts and still update pace without replacing
   the route.
4. **Door/window permission:** a new `AllowSurvivorDoorWindowOpening` sandbox
   setting gates native opening of closed doors and windows. Already-open or
   smashed openings remain usable. When disabled, a survivor reports the blocked
   permission and the route is recorded as blocked rather than repeatedly
   toggling the same entrance.
5. **Needs and sleep:** food, water and endurance recovery begin below the
   halfway point, while existing completion checks remain responsible for
   stopping recovery. Floor sleep remains available when no bed exists, and a
   partial native sleep-event failure unwinds cleanly for a later retry.

### Changed files in this batch

- `java/src/main/java/com/knoxsurvivors/bridge/KnoxBridge.java`
- `java/src/main/java/com/knoxsurvivors/engine/KnoxShellVisibility.java`
- `java/src/main/java/com/knoxsurvivors/npc/KnoxNpc.java`
- `java/src/main/java/com/knoxsurvivors/npc/KnoxNpcFactory.java`
- `java/src/main/java/com/knoxsurvivors/npc/KnoxNpcRegistry.java`
- `mod/42/media/lua/client/KS_BaseBarricades.lua`
- `mod/42/media/lua/client/KS_BaseWoodcutting.lua`
- `mod/42/media/lua/client/KS_CompanionService.lua`
- `mod/42/media/lua/client/KS_Settings.lua`
- `mod/42/media/lua/client/KS_SurvivorAutonomyController.lua`
- `mod/42/media/lua/client/KS_SurvivorNeeds.lua`
- `mod/42/media/lua/shared/Translate/EN/Sandbox.json`
- `mod/42/media/sandbox-options.txt`
- `tools/test-autonomy-formation.lua`
- `tools/test-base-barricades.lua`
- `tools/test-survivor-needs.lua`

### Verification

- `powershell -ExecutionPolicy Bypass -File tools\verify.ps1`: **243 checks,
  0 failed**.
- Focused barricade, woodcutting, needs and formation tests passed.
- `.\gradlew.bat build deployDev --console=plain`: **BUILD SUCCESSFUL**.
- `git diff --check`: passed.

### Live-only confirmation still required

- Confirm the survivor visibly completes a real wood barricade and consumes one
  plank plus nails after arriving at the correct side of the window.
- Confirm the new door/window setting blocks closed openings and that companions
  remain visible on the world and minimap in the actual Build 42 client.
- Confirm native combat and work actions award XP to the shell's native perks,
  then confirm the updated levels survive save/reload.
- Confirm a survivor with fatigue or endurance below the new thresholds eats,
  rests or sleeps on furniture/ground and returns to the prior order without
  oscillation.
- Recheck the newest DebugLog after a sleep-to-work transition for the prior
  `ISHandcraftAction` exception.

Keep the current architecture, Java backend and save schema. Launcher removal and
release publishing remain outside this plan. Offline checks do not prove native
Build 42 item transfer, timing, animation or save-file behavior.

## Wood-window barricade reliability repair — 2026-09-20

This focused pass completed the remaining shared task-ownership and supply-lease
repairs for wooden **window** barricades. Metal barricades, construction, gates
and animal care remain intentionally out of scope.

1. **Window-only target safety:** door detection now fails closed even during a
   partial/modded class-load path. A task never accepts an object exposing the
   native `isDoor()` contract as a barricade target.
2. **Durable retarget ownership:** when streaming invalidates a claimed window,
   the worker skips every opening already queued or claimed for barricading. The
   accepted replacement is atomically written back to the persistent task,
   including its duplicate-prevention signature. A non-claimant cannot retarget
   another worker's task.
3. **Short-lived supply leases:** a worker reserves the exact pending item and
   source container before walking to collect a real hammer, plank or nails.
   A competing worker receives a bounded supply wait rather than racing the
   transfer. Completion, failure, movement cleanup, combat/need interruption and
   controller recovery release that lease safely and repeatedly without leaks.

### Changed files in this pass

- `mod/42/media/lua/client/KS_BaseBarricades.lua`
- `mod/42/media/lua/client/KS_Persistence.lua`
- `mod/42/media/lua/client/KS_SurvivorAutonomyController.lua`
- `tools/test-base-barricades.lua`
- `tools/test-base-task-validation.lua`
- `tools/test-barricade-task-ownership.lua`

### Automated verification

- Focused Lua syntax checks and barricade target, task-validation, claim-suspend
  and action-lifecycle regressions passed.
- New persistence coverage confirms a retarget cannot collide with queued work,
  updates the durable signature, and rejects a non-owner.
- New controller coverage confirms an item/container supply lease excludes a
  second worker and is reusable after release.

### Live-only Build 42 confirmation

- Confirm a survivor reaches the valid side of a real closed window, equips the
  carried hammer/plank, completes `ISBarricadeAction`, consumes its vanilla
  materials and returns to normal duty.
- Confirm combat or a critical need during the walk/action either resumes a
  still-valid task or cleanly blocks/releases it with no duplicate worker.
- Confirm a missing or inaccessible real item produces one bounded shortage path
  rather than a repeated walk/animation loop.

### Remaining high-value connected work

1. Run the single engine acceptance pass for real wood barricade action,
   firearms, corpse drop-off, temporary shelter and save/reload.
2. Use multi-day live evidence to decide whether unloaded base reserves need
   exact-item escrow/reconciliation beyond the existing bounded policy.
3. Triage any Build 42 action failure from that pass at the shared controller,
   reservation or native-action boundary before adding retries.
4. Address remaining P2 HUD/controller polish only from confirmed runtime traces.

## Firearm reliability and acceptance-readiness repair — 2026-09-20

This focused pass hardened the existing native Build 42 firearm path. It does
not add weapons, bullets, damage simulation, ammunition grants, or a separate
gun-combat system.

1. **Exact real-weapon selection:** the firearm planner now searches a
   survivor's carried containers, moves a selected bagged gun to root inventory
   as the same native item, and asks the bridge to equip its exact item ID.
   Two weapons sharing a full type can no longer cause the bridge to equip a
   different dry/broken weapon than the ready one Knox selected.
2. **Target-first combat recovery:** combat now clears a dead, unloaded or no
   longer-hostile target before checking firearm reload/aim state. Native reload
   actions are cancelled only on that real interruption, not on normal combat
   refreshes, preventing stale target preparation from delaying recovery.
3. **Emergency retargeting:** a valid higher-priority human or zombie threat is
   evaluated before firearm preparation. A real emergency target switch clears
   the prior native action once, releases its claim, and re-enters the existing
   combat path with the new target. Ordinary valid reloads remain uninterrupted.
4. **Existing native boundaries retained:** Project Zomboid still owns magazine,
   chamber, reload, ammo consumption, projectile, hit, damage, tracer and
   sound behavior. Knox only selects, equips, schedules/relinquishes the native
   action, and uses the existing timed fallback when it cannot proceed.

### Changed files in this pass

- `mod/42/media/lua/client/KS_FirearmSupport.lua`
- `mod/42/media/lua/client/KS_SurvivorAutonomyController.lua`
- `java/src/main/java/com/knoxsurvivors/bridge/KnoxBridge.java`
- `java/src/main/java/com/knoxsurvivors/npc/KnoxNpcRegistry.java`
- `java/src/main/java/com/knoxsurvivors/npc/KnoxEquipmentController.java`
- `tools/test-firearm-support.lua`
- `tools/test-combat-intelligence.lua`

### Automated verification

- Valid loaded firearm, native reload/rack queue, no compatible ammo, safe mode,
  ranged preference fallback, native firing-hook ownership and reload
  cancellation remain covered.
- New coverage verifies a ready firearm stored in a bag is selected and equipped
  as the exact real item even when another gun has the same full type.
- Combat coverage verifies target death clears before firearm-state inspection,
  reload handoff returns control, and a more urgent threat retargets normally.
- Complete verification: **102 Lua files** checked, **142 regression scripts**
  run, **245 checks passed, 0 failed**. `build deployDev` and the automated QA
  coordinator passed.

### Live-only Build 42 acceptance

- Confirm an NPC with a gun/magazines/loose rounds fires real rounds, damages a
  zombie and hostile survivor, emits native muzzle/tracer/noise effects, and
  consumes ammunition through the game.
- Confirm empty magazine, loaded spare magazine, loose compatible rounds,
  chamber/rack state, jam, reload interruption and weapon transfer recover
  without a reload loop or permanent aiming pose.
- Confirm a human-to-zombie and zombie-to-human emergency switch stops the old
  action, retains normal faction/raid hostility rules, and resumes the survivor's
  prior order/job/travel after combat ends.
- Confirm companion, base defender, independent survivor, faction member and
  raid participant all share this same combat path in a real loaded world.

### Recommended next high-value reliability pass

1. Run the single comprehensive Build 42 acceptance scenario and repair only
   confirmed engine-boundary failures from its newest logs.
2. Focus the next code pass on remaining native base-job action reliability,
   especially interruption/resume around combat, needs and pathing.
3. Reconcile player-facing needs/HUD values and chatter against real hunger,
   thirst, rest and endurance transitions.
4. Use multi-day live evidence to decide whether unloaded base reserves need
   exact-item escrow/reconciliation beyond the existing bounded policy.

## Faction raid defender response and combat-at-target repair — 2026-09-20

This focused pass completed the event/runtime boundary that previously could
leave a real raid waiting on its original exterior approach points after normal
combat had correctly moved survivors around the target base. It preserves the
existing diplomacy, normal human-combat, base-alarm, real-loot and withdrawal
systems; no raid-only combat controller or fabricated result was added.

1. **Target-area handoff:** a raider that has reached the target base perimeter
   now advances from `active` to its real objective even if a defender or zombie
   moved it away from the exact approach square. Human target selection,
   faction hostility, weapons, injuries and zombie reactions remain owned by
   the normal autonomy/combat controller.
2. **Objective while combat moves:** once a raid objective begins, its bounded
   review continues while combat repositions participants around the target.
   The existing `FLEEING` handoff still changes the raid to `withdrawing`, so
   zombie pressure or a genuine survival retreat ends the event cleanly rather
   than freezing objective progress.
3. **Loaded/unloaded continuity:** approach arrival now uses the existing
   persisted virtual coordinates for unloaded members. A save/load or distance
   boundary can no longer leave an otherwise-arrived party permanently in
   `approaching` solely because it has no loaded character.
4. **Terminal behavior preserved:** invalid/collapsed target state, member duty
   changes, casualties, failed approach, withdrawal, returned survivors and a
   removed source home continue to use the existing single-transition event
   cleanup path. Raid objectives still record only actual native inventory
   transfers from the target base.

### Changed files in this pass

- `mod/42/media/lua/client/KS_EventRuntime.lua`
- `tools/test-event-runtime.lua`

### Automated verification added

- A mixed loaded/unloaded party reaches `active` from real persisted virtual
  coordinates.
- Raiders moved into the target perimeter during normal `COMBAT` proceed to the
  bounded real-loot objective instead of waiting for their former approach
  tiles.
- A `FLEEING` survivor changes the active raid to `withdrawing` with
  `party_retreating`; normal return/duty-release coverage confirms the event
  resolves once without reviving or teleporting survivors.
- Existing objective coverage continues to prove that receipts are real native
  transfers, invalid target/duty/death state cancels looting, and outcomes do
  not fabricate supplies.
- Complete verification after this pass: **102 Lua files** syntax-checked,
  **142 regression scripts** run, **245 checks passed, 0 failed**;
  `build deployDev` and the automated QA coordinator also passed.

### Remaining raid limitations / live-only Build 42 acceptance

- Confirm a loaded target-base resident perceives an approaching hostile
  raider, enters normal human combat and raises the existing base alarm for
  nearby off-duty residents.
- Confirm gunfire attracts real zombies, a survivor `FLEEING` state withdraws
  the raid, defenders stop pursuing after the threat clears, and no controller
  remains in `COMBAT`, `EVENT_WAIT` or event duty after resolution.
- Confirm a raid can complete a real container transfer and return with its
  actual inventory; broader raid looting design remains intentionally bounded
  to the current real-transfer objective and is not expanded here.

### Recommended next high-value work across the mod

1. Run one focused live Build 42 acceptance scenario spanning base jobs,
   barricading, firearms, corpse hauling, hostile encounters, faction raid
   response and save/reload; use the resulting logs to fix only confirmed
   engine-boundary failures.
2. Audit firearm live behavior end-to-end: weapon selection, aim/reload,
   native projectile damage, fallback and human/zombie target transitions.
3. Complete a focused base-job action pass for the remaining native actions
   that are not yet accepted in live play, especially task interruption and
   resume after combat/needs recovery.
4. Reconcile player-facing need/HUD displays against the actual hunger, thirst,
   rest and endurance lifecycle using live traces, then remove any remaining
   false chatter loops.
5. Use multi-day live evidence to decide whether unloaded base reserves need
   exact-item escrow/reconciliation beyond the existing bounded policy.

## Natural survivor-conflict repair — 2026-09-20

This focused pass completed the loaded encounter-to-conflict boundary without
adding scripted raids, fabricated loot, or a second combat/relationship manager.

1. **Durable conflict escalation:** an encounter now records direct hostility
   between the two actual survivors. It escalates to faction diplomacy only
   when both belong to separate established NPC factions. Temporary groups keep
   individual hostility, preventing one dispute from permanently flagging every
   traveller on both sides as hostile.
2. **Nearby ally defense:** when a threat or robbery begins, nearby loaded allies
   receive a bounded combat-defense permission for the opposing survivor. This
   lets a group defend a member while preserving normal ally safety and avoids
   a group-wide permanent hostility rewrite. Direct/faction hostility remains
   persisted through save/load; the short defense permission correctly expires
   on separation, death or unload.
3. **Robbery interruption and aftermath:** robbery still queues only native
   transfers from the victim's real inventory. The victim has a short bounded
   compliance hold while transfers resolve. A zombie, another human threat,
   action failure, controller recovery, detachment or expiry releases that hold
   and cancels the paired transfer safely. Once the hold ends, the durable
   hostile relationship allows ordinary combat, disengagement and later memory.

### Changed files in this pass

- `mod/42/media/lua/client/KS_Persistence.lua`
- `mod/42/media/lua/client/KS_SurvivorRelationships.lua`
- `mod/42/media/lua/client/KS_SurvivorAutonomyController.lua`
- `tools/test-relationship-coherence.lua`
- `tools/test-natural-conflict.lua`

### Automated verification

- Neutral, allied, personal-hostile and faction-hostile relationship outcomes
  are covered through persistence and reload checks.
- New conflict regression verifies real robbery source/destination transfers,
  bounded victim release, zombie/combat interruption cleanup and local ally
  defense registration.
- Existing combat regression verifies stale/dead targets disengage and group
  membership/death persistence remains coherent.
- Complete suite: **102 Lua files**, **142 regression scripts**, **245 checks,
  0 failed**. `build deployDev` completed successfully.

### Newly discovered boundary

- Off-screen simulation preserves the direct/faction relationship result but
  does not simulate a fresh detailed robbery or loaded group-defense scene.
  That is intentional to avoid fabricating items or running expensive remote
  combat; only live encounters own real inventory transfer and native damage.

### Live-only Build 42 confirmation

- Confirm two independent survivors can greet, keep distance, threaten or rob
  based on their persisted relationship/personality without every meeting
  becoming combat.
- Confirm a nearby groupmate defends a threatened ally, while same-group allies
  never become valid human-combat targets.
- Confirm a zombie interrupt cancels a robbery and both survivors resume normal
  combat/retreat decisions with no stranded `GROUP_WAIT` or `ROBBING` state.
- Confirm a survivor death removes the active target and surviving members
  continue their normal group/base/travel lifecycle after combat.

### Remaining high-value connected work

1. Run one engine acceptance pass for independent conflict, firearm damage,
   robbery interruption, corpse drop-off, temporary shelter and save/reload.
2. Use multi-day live evidence to decide whether unloaded base reserves need
   exact-item escrow/reconciliation beyond the existing bounded policy.
3. Triage any Build 42 combat failure at the shared relationship, controller or
   native-action boundary before adding retries or scripted outcomes.
4. Address remaining P2 HUD/controller polish only from confirmed runtime traces.

## Faction diplomacy and conflict-foundation repair — 2026-09-20

This focused pass completed the shared diplomacy boundary used by human combat,
territory responses and experimental raid eligibility. It does not expand the
raid objective or create an always-on faction war system.

1. **Canonical faction disposition:** member combat and raid validation now use
   one persistent faction-disposition lookup. It consistently resolves same
   faction as allied, ordinary unrelated factions as neutral, stored diplomacy
   as allied/neutral/hostile, and a hostile-patrol policy as hostile to a
   different faction policy even when that faction formed later.
2. **Scoped escalation remains intact:** direct personal hostility still affects
   only the two survivors unless the existing explicit escalation path records
   an established NPC-faction conflict. A personal grudge cannot silently turn
   neutral factions into a war.
3. **Raid foundation alignment:** raid proposal and event validation now share
   the same hostile rule used by member targeting. They continue to require a
   valid source faction/base, valid target owner/base, living real members,
   available home defenders, and revalidate all of that through travel,
   withdrawal and persistence transitions.

### Changed files in this pass

- `mod/42/media/lua/client/KS_Persistence.lua`
- `mod/42/media/lua/client/KS_KnoxEvents.lua`
- `tools/test-relationship-coherence.lua`
- `tools/test-faction-diplomacy.lua`

### Automated verification

- Neutral and allied factions remain non-hostile; established hostile factions
  classify members consistently without friendly fire.
- Personal hostility between two members does not create faction hostility.
- Hostile-patrol policy works for a faction formed after the patrol and makes
  the otherwise valid real-member raid proposal eligible.
- Faction hostility survives reload; existing faction-collapse tests confirm
  stale diplomacy/base ownership is removed after the final member dies.
- Complete suite: **102 Lua files**, **142 regression scripts**, **245 checks,
  0 failed**. `build deployDev` completed successfully.

### Raid readiness assessment

The raid system is ready for its own focused pass on defender response and
combat-at-target behavior: its shared ownership, diplomacy, roster, real-item,
travel, return, death and persistence foundations are now aligned. It is not
yet accepted as a complete raid feature without a dedicated Build 42 test of
target-base defenders, native human combat and withdrawal under zombie pressure.

### Live-only Build 42 confirmation

- Confirm neutral/allied factions pass each other without targeting, while
  hostile factions only fight after entering normal perception/combat range.
- Confirm a faction resident raises the existing base alarm for a hostile member
  inside its territory, then returns to normal base work after the threat clears.
- Confirm leadership succession and member death leave the surviving faction's
  diplomacy intact, while final collapse removes its relationships and base.
- Confirm a valid hostile raid dispatches real equipped members, responds to
  target-base defenders/zombies, and releases every survivor duty on retreat.

### Remaining high-value connected work

1. Run one engine acceptance pass for faction conflict, firearms, robbery
   interruption, territory alarms, corpse drop-off, shelter and save/reload.
2. Take the experimental raid system through a separate defender-response and
   combat-at-target pass after the shared foundations receive live confirmation.
3. Use multi-day live evidence to decide whether unloaded base reserves need
   exact-item escrow/reconciliation beyond the existing bounded policy.
4. Address remaining P2 HUD/controller polish only from confirmed runtime traces.

## Final release-readiness audit — 2026-09-21

This audit traced the current workspace as a complete product lifecycle and
reviewed only release-blocking risks. No new high-confidence blocker was found,
so no gameplay code was changed in this pass.

The supported base-job chain remains connected through task discovery, atomic
claim, eligibility/material checks, native action entry, interruption handling,
completion/failure cleanup and normal duty recovery. Farming, cooking,
woodcutting/log processing, repairs, corpse work, guarding, patrol and wooden
window barricading remain the supported scope. Retired construction, animal
care and metal barricades remain intentionally excluded.

Save/load ownership is also internally consistent at the source level:
per-survivor capture isolation allows later survivors to save after an
individual failure; interrupted base claims are requeued at game start; live
hibernation captures before removal and marks the ledger stored only after
removal; materialization restores the stored needs state once; and lifecycle
normalization cleans invalid group, faction, leadership, base and event links.

The remaining items are engine acceptance requirements rather than source
confirmed blockers. They cover real native action completion, firearm damage and
reload behavior, vehicle behavior, safehouse release, multi-day storage use,
raid defender response, and save/reload during active gameplay. They are listed
with strict classifications in `RELEASE_READINESS.md`.

### Final audit result

- Release blockers found: **none confirmed**.
- Code changes in this audit: **none justified**.
- Full offline verification: **102 Lua files, 142 regression scripts, 245
  checks passed, 0 failed**.
- Development build/deployment: **passed**.
- Automated QA coordinator: **passed**.
- Commit, push, Workshop update and launcher release: **not performed**.

The next action is one comprehensive live Build 42 release-candidate test. Any
new blocker must be tied to a current DebugLog/runtime reproduction before code
is changed.

## QA wording and isolation finishing pass — 2026-09-21

Safe, high-confidence player-facing cleanup only. No gameplay, architecture,
save-schema, or numeric-balance changes.

1. **Sandbox tooltip:** `SurvivorAimingAssist` no longer says "help testing";
   it now describes Basic/Strong Assistance as a more forgiving experience.
2. **Driving orders:** `Take Driver Seat & Drive (Experimental)` and
   `Drive Here (Experimental)` are now plain `Take Driver Seat & Drive` and
   `Drive Here`, matching the already-shipped `Allow NPC Driving` sandbox name
   and `docs/SANDBOX_SETTINGS.md`. Internal setting/function names such as
   `EnableExperimentalNpcDriving` are unchanged for save compatibility.
3. **Sandbox wording regression:** `tools/test-sandbox-settings.lua` now asserts
   the absence of player-facing `(Experimental)` / `(Work in Progress)` display
   suffixes instead of bare `Experimental`, so internal option keys no longer
   trip the check. Prior strict form failed on the retained internal key even
   though no player-facing label contained it.

Prior Codex work preserved in this workspace: isolated hostile-survivor firearm
duel with unloaded guns/magazines, controlled QA retries, nearby-zombie plus
developer-fixture-only cleanup, sandbox catalogue defaults/naming audit, and
the hostile firearm QA fixture.

### Verification

- `powershell -ExecutionPolicy Bypass -File tools\verify.ps1`: **102 Lua
  files, 142 regression scripts, 245 checks, 0 failed**.
- `.\gradlew.bat build deployDev --console=plain`: **BUILD SUCCESSFUL**.
- Commit, push, Workshop update and launcher release: **not performed**.

### Intentionally left for Sol

- One disposable-save live QA run (`KnoxQA`, Developer Tools + Run Automated
  Knox QA, scenario None), then `tools/parse-live-qa.ps1`; live raid
  travel/combat, native driving, long faction lifecycle, and player-death
  succession remain separate acceptance gates.
- Exact-item long-duration base escrow/reconciliation beyond the bounded
  unloaded reserve policy.
- Any rename of the internal `EnableExperimentalNpcDriving` sandbox key (save
  compatibility risk; not attempted here).

## Foolproof QA pass — 2026-09-21

Superseded on 2026-09-23: automated QA no longer enables god, ghost, or
invisibility on the player. It only clears those flags at suite start/end and
menu exit to clean up state left by an older interrupted run.

Test-harness changes only. No gameplay, architecture, save-schema, or
numeric-balance changes.

1. **Historical observer protection:** this checkpoint applied god, ghost and
   invisible mode to the player. The current suite no longer enables those
   modes and only clears flags left by an older interrupted run.
2. **Global run timeout:** a stuck suite fails its active scenario instead of
   hanging; per-step retries (3 attempts) are unchanged.
3. **Five new boundary checks** (all synchronous, honest `BLOCKED` when the
   world fixture is absent): `hostile_encounter` (durable hostile relationship
   between two disposable survivors), `raid_eligibility` (real duty-safe raid
   proposal), `vehicle_boarding` (real free passenger-seat discovery),
   `night_shelter` (real indoor search with the territory filter), and
   `persistence_roundtrip` (real save-capture pass with living-roster
   comparison).
4. **Historical docs/tooltip:** the checkpoint documented the protected
   observer and new stages. Current instructions are maintained in
   `docs/DEVELOPMENT_TESTING.md`; `docs/FEATURE_AUDIT.md` retains dated history.

### Verification

- `powershell -ExecutionPolicy Bypass -File tools\verify.ps1`: **102 Lua
  files, 142 regression scripts, 245 checks, 0 failed**.
- Focused `test-automated-qa` and `test-sandbox-settings` regressions pass,
  including new observer-protection and boundary-API assertions.
- Commit, push, Workshop update and launcher release: **not performed**.
