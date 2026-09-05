# Milestones

## M0 — Foundation

Success means:

- the repository builds from the Gradle wrapper;
- Lua files compile with Lua 5.1;
- the mod deploys repeatably to the configured Workshop directory;
- the Java agent starts under the game-bundled Java runtime;
- the Lua bootstrap loads in a new single-player game.

## M1 — One human in the world

Success means one `IsoPlayer` NPC:

- is constructed from confirmed 42.20 APIs;
- spawns at a loaded, valid square selected from game spawn-region data;
- maintains a safe distance from the active player;
- does not replace or enter a local player slot;
- renders with a human visual and outfit;
- walks to a reachable destination using engine pathfinding;
- survives cell unload/reload and save/quit/reload;
- is removed cleanly on world teardown;
- produces no repeating exceptions or nil-call errors.

Population remains capped at one until every condition passes.

## M2 — Basic survival loop

M2 is split into narrow gates so failures can be attributed to one engine subsystem:

1. **Inventory/equipment** — give the survivor one real carried weapon, equip it through
   the normal hand-item path, automatically prefer the strongest suitable carried melee
   weapon, retain the other carried tools/items, and preserve the result across reload.
2. **Combat** — perceive, approach, attack, and kill one zombie with that weapon while
   normal attack timing, durability, noise, and animation run.
3. **Looting** — select one useful item from one reachable container and move it through
   the normal transfer action into the survivor's inventory.
4. **Health** — receive ordinary zombie/combat damage and preserve the resulting body-part
   state across reload.
5. **Medical** — consume a real bandage to treat the survivor's most urgent wound, then
   verify the active player can use the normal medical flow on the NPC as patient.

M2 is complete when the survivor can independently:

- perceive nearby zombies and useful containers;
- choose between threat response and resource needs;
- equip a suitable weapon;
- attack and kill a zombie through player-valid combat mechanics;
- path to, open, and loot a reachable container;
- preserve resulting health, equipment, and inventory state across reload.

The current integration gate runs this planner for three persistent identities at once.
Each owns its own action state, movement request, combat target, timers, and counters;
world-item and zombie reservations prevent multiple controllers claiming one target.

## M3 — World interaction

Success means the survivor can safely use doors and windows, climb permitted obstacles, and barricade one valid window using real carried materials and normal world actions.

The active integration now includes room-aware locked-door recovery: preserve the
container goal, try a usable perimeter window through normal open/smash/climb behavior,
then attack the door with the equipped weapon only when no window route succeeds. State
deadlines cancel stalled movement and timed actions and release their reservations.

## M4 — Companions and settlement foundation

The code foundation is present; live verification is still required. Success means:

- occupation, traits, perk levels, and XP remain stable through body reconstruction;
- a nearby independent survivor can build trust, be recruited once, and leave NPC social AI;
- Follow and Hold persist, yield to threats and critical needs, then resume;
- Dismiss removes player ownership without losing the survivor's person record;
- the right-side HUD shows only that local player's companions and releases unloaded bodies;
- split-screen players receive separate HUDs and cannot command one another's survivors;
- a player home and categorized vanilla containers persist through save/reload;
- Return to Base reaches a loaded home before resident work becomes eligible;
- NPC faction safehouses produce stable base records and keep residents near home;
- interrupted task claims are recovered without duplicating or losing work.

M4 does not claim every registered job type is implemented. It establishes one owner for
affiliation, duty, base records, storage, work requirements, and task claims so each job can
be added as a small normal-world-action executor. Guard/patrol posts, one-item depot sorting,
one-plank barricading, and the first farming maintenance actions now have executable slices.
A resident with a reachable farming zone can harvest a ripe plant, water a dry seeded plant,
prepare one empty dirt square, or sow a carried seed through the vanilla timed actions. These
slices still require live in-game confirmation.

## Later milestones

Storage hauling, guard, patrol, one-plank barricading, crop maintenance, tree cutting,
log-to-plank production, and corpse hauling now have initial executors. Animal Care Areas
also have an initial trough executor:
residents can pour carried water or transfer a real animal-feed bag into a trough through
vanilla actions. Damaged doors, thumpable defenses, and barricades can be repaired through
the complete vanilla moveable-repair action and material definitions. Each slice must consume
real tools and materials where applicable, use normal timed actions, respect survivor skills,
and survive reload before the next one is added.

The next base-production boundary is deliberate construction and defense planning: choosing
needed walls, gates, and barricade upgrades instead of only maintaining existing structures.

After those jobs: the full Survivors Notebook, companion/base roster management, contextual
conversations and favors, firearms, vehicles, camps, raids, away teams, and unloaded-world
simulation. Multiplayer remains compatibility-only until authority and replication are
designed and tested.

The player-facing order vocabulary is now centralized in `KS_OrderCatalog`. Companion and
party dispatch normalize familiar legacy labels into the existing Knox primary orders,
directives, base preferences, and task-board roles. This is a compatibility layer only; it
does not duplicate task execution or persistence ownership. The next settlement gate is
live multi-resident work rotation with real storage/material transfers, defense coverage,
and save/reload continuity.

The first supply-return boundary is now connected: a resident sent out for a base
shortage keeps the recovered real item as a temporary work result, returns through
the existing base duty, and deposits it into assigned storage through the native
inventory-transfer path. The remaining settlement gate is multi-resident live
rotation and save/reload verification rather than another abstract stockpile.

Base residents can also receive an explicit, bounded Find Food/Water/Medical/Weapon/
Tools order through the shared player-facing catalogue. The request remains in base
duty, uses the same real-item search and return/deposit path as automatic shortages,
and expires after bounded failure instead of becoming a permanent directive. Live
menu execution and save/reload remain verification gates.

Faction shelter scouting now uses a nearest-first staged search (30, 60, then 90
tiles) and widens only when the earlier ring has no valid building. The search stays
loaded-world and preserves vanilla safehouse and persisted Knox-base ownership rules.
Live multi-resident settlement work and shelter selection remain verification gates.

When a resident is free to take a new duty, the settlement now checks genuine
food, water, medical, weapon, and tool shortages before assigning ordinary work.
Already-claimed native jobs are not interrupted; the shortage trip remains a
real loaded-world search and storage handoff.

Stable survivor IDs accumulate first/last meeting, nearby time, repeat meetings, and
shared survival activity. Two survivors can explicitly agree to form a travelling group.
An established group may invite a lone survivor through a separate consent dialogue.
Three members are necessary but not sufficient for faction formation: relationship
history must show nearby time or shared survival activity, but there is no arbitrary
minimum number of days together. A new faction's leader now scores loaded buildings,
persists the best candidate, leads the group to its perimeter, and records its stable
building ID and bounds after arrival. Existing vanilla safehouse overlap is rejected.
A namespaced vanilla safehouse boundary now protects the selected home from overlapping
player claims and is reconciled on load. Early shared base/storage/task records now exist;
world job executors and trespass behavior remain later integration boundaries.

Established NPC faction leaders can now make a bounded first-contact recruitment offer to
an eligible lone survivor. This closes the previous circular gate where joining required
shared activity that could only happen after joining. Ordinary independent groups retain
their familiarity/shared-survival requirement, and faction limits plus canonical ownership
transitions remain in force. Live recruitment and post-join settlement behavior remain
verification work.

Population refills also have a bounded opportunity to pair a replacement identity with a
nearby independent survivor through the existing travel-group record. This keeps later
world population replenishment from becoming a collection of isolated arrivals while
preserving rare, persistent group formation and the normal encounter rules.

Changing a resident to the Rest preference now releases any persisted base-task claim
through the existing task-board/persistence boundary before ambient recovery begins.
This prevents a resting resident from permanently occupying work intended for another
settlement member; live multi-resident rotation remains the next acceptance gate.

Automatic settlement selection now also reads already-claimed duties from the persisted
base when calculating security coverage and work-type fairness. Claimed tasks remain
ineligible for new claims, while queued tasks are distributed with the existing priority,
preference, and atomic-claim rules.

The automatic-duty admission list now includes the supported native task executors for
wood processing, corpse hauling, animal care, repair, and defense construction. This keeps
newer work areas on the same order/task path as guard, patrol, farming, and storage rather
than leaving them queued but invisible to automatic residents.

Resource away teams now have a bounded failure boundary: if no loaded-world executor collects
from the destination within 72 in-game hours, the team records an honest blocked result and
restores its members' previous duties. No resources are invented; the real destination
collection/return/deposit executor remains the next mission milestone.

Player-facing companion, party, vehicle, traversal, recruitment, and base-management
labels now resolve through the shared `KS_OrderCatalog`. This keeps the Superb-style
command surface consistent without duplicating execution or persistence logic.

Persisted and manually-created settlement tasks now normalize older names such as
`woodcutting`, `corpse_cleanup`, and `storage_sorting` into the current Knox executor
types. This keeps earlier saves and familiar work-area labels usable without restoring
the old task implementation.

Exact task names now take precedence over broad legacy aliases in catalogue lookup,
so concrete labels such as `Barricade` remain clear in player-facing menus.

Larger bases (4+ residents) now receive a second ordinary guard post (`Outer Watch`)
at a separate deterministic position. Existing task-board claims, fairness rotation,
native movement, and offscreen guard accounting remain authoritative; live multi-post
coverage is still pending verification.

Established bases (6+ residents) also receive a second ordinary patrol route (`Outer Patrol`).
Both routes stay on the existing persisted zone/task and waypoint systems, keeping patrol
coverage broader without adding a parallel scheduler or formation model.

Resident duty selection now uses a small capped affinity bonus from each survivor's persisted
skill profile. Explicit roles, shortage priority, hard requirements, and atomic task claims still
win; the affinity only breaks otherwise comparable choices so capable workers naturally gravitate
to matching settlement work.

The Notebook Work tab can now assign a specific queued task to a selected player-base resident.
The assignment uses the same ownership, eligibility, skill-gate, and atomic claim boundary as
automatic scheduling; it does not create a second order or task manager. Live assignment and
interruption/resume behavior remain verification gates.

Explicitly assigned tasks are marked as manual work. A resident's Rest preference releases
automatic work but does not silently cancel a concrete player assignment; the controller restores
manual claims before applying the Rest gate. Live behavior remains a settlement verification gate.

The Base tab now shows compact guard-post and patrol-route counts beside the resident/task summary,
so players can see whether a settlement has security coverage without opening another management
screen.

Resident rows now also show the canonical label of the task currently claimed by each base member,
or `Idle` when no work is active. This keeps the existing Notebook as the single player-facing
settlement view without adding another status panel.

The Base header now distinguishes staffed security from available coverage (`active/available`)
for guard posts and patrol routes, making settlement gaps readable at a glance.

Security coverage is now calculated by the same `KS_BaseJobs` boundary used for resident
selection. Guard posts and patrol routes, including legacy `patrol_area` records, share one
normalized staffed/available view in the scheduler and Notebook.

Settlement shortage selection is likewise centralized in `KS_BaseSupplyPlanner`. Loaded
residents use one conservative food, water, medical, weapon, and tool priority order before
claiming ordinary work; future resource-trip callers can reuse that decision without creating
a second scheduler.

Travelling companions can also receive payload-less Guard and Patrol orders. The shared
companion service creates a small native guard post or bounded patrol area around the companion;
base residents continue to use their persistent base-job preferences. This keeps the familiar
Superb-style order surface on one Knox-owned dispatch path.

Changing a player-base resident's preference now performs an explicit duty handoff for automatic
work: the old routine claim is requeued immediately while a manual Notebook assignment remains
protected. This keeps the shared order/task boundary responsive without adding another scheduler.

The loaded controller is notified in the same handoff, so its stale automatic task pointer and
transient action state are released immediately while manual work remains protected. Persistence
and the live controller therefore converge before the next autonomy tick.

When a resident leaves base duty entirely, the controller now clears any remaining base task,
including a formerly manual assignment, so settlement work cannot leak into companion or
independent behavior.

Selecting Rest while remaining in the base now releases automatic work only; explicit Notebook
assignments remain protected until their normal completion or cancellation boundary.

Resource away-team completion now has a strict return gate: destination collection cannot restore
the member's previous duty until the live executor explicitly enters the returning phase. This keeps
settlement ownership coherent while the real loaded-world collection/return executor is completed.

The loaded Rest preference now releases automatic work only, matching the companion-service handoff
and protecting explicit Notebook assignments after reload or delayed controller refresh.

Returning resource teams now also have a bounded 72-hour failure boundary. If a member never
acknowledges the final handoff, the mission records a return timeout, preserves the real collected
ledger, and restores prior duties instead of leaving a permanent away assignment.

Mission release also respects death races: a member who dies during return remains deceased while
the other members are released normally.

The unified order boundary now has a canonical resolver. Legacy labels and current commands are
classified once before entering the existing companion directive, base preference, or task-board
owners. This keeps future Superb-style command additions from creating a second routing path.

Patrol progress migration no longer assumes every saved area has exactly four route points. The
persisted step and completed-stop counters stay bounded, and the existing runtime patrol owner
normalizes them against the actual saved area when resumed. This keeps custom or migrated patrols
from silently jumping back to the wrong post without adding another route system.

Resource away teams now require every member to acknowledge destination collection before the
persistent mission can enter its return phase. An empty but valid search counts as an acknowledgement;
the item ledger still accepts only real executor-reported item types. This prevents a group mission
from restoring ownership while part of the group is still away. The loaded destination collector
and physical return remain the next integration boundary.

Away-team dispatches can now persist an explicit return point alongside the destination. The player
base scout handoff records the player's real dispatch square, while base-resident dispatches derive
the center of their saved territory when no explicit point is supplied. Older missions remain
compatible without inventing a world location, giving the future loaded collector a durable,
owner-neutral return target instead of forcing it to guess after a save/reload.

The first loaded resource-mission executor is now connected to the same population and autonomy
owners. When a destination or return point is loaded near the player, mission members can be
restored there, search through the existing native exploration/transfer path, acknowledge an empty
or successful search, and return to their persisted owner. Real item presence is checked before
anything enters the mission ledger; members cannot fall through into ordinary roaming while away.
Focused Lua checks pass. A real loaded resource run and save/reload through each mission phase
remain the next live acceptance gate.

Independent roaming now gives nearby building destinations a small, defensive
usefulness bonus for rooms, size, residential status, and available water. This
keeps the existing bounded scan and destination memory while making survivors
prefer plausible places to search instead of choosing strictly by distance.
Live multi-hour roaming remains the acceptance gate.

The unified order boundary now also exposes concrete base-task assignment through
the existing atomic task-board claim. A player-facing caller can submit a specific
resident, base, and queued task without bypassing ownership or skill checks; no
second scheduler was introduced. Live Notebook assignment remains part of the
settlement acceptance pass.

Catalogue actions now use that same player-facing boundary: individual recruit,
dismiss, needs, vehicle, and climbing actions delegate to their existing service
owners, while safe party needs/vehicle/climbing actions use the existing per-member
implementations. Recruit and dismiss remain deliberately individual-only. Live
context-menu execution remains part of the next settlement/order acceptance pass.

The party and survivor context menus now submit needs, vehicle, and climbing
actions through that same dispatcher instead of calling parallel service paths.
The underlying native executors and persistence owners are unchanged, keeping
the order surface consistent without adding another task manager.

Settlement definitions are also reconciled on the existing population cadence,
so bases that gain residents after world start receive their normal guard,
patrol, work-area, and storage defaults. The existing base manager remains the
only owner of those definitions; live admission and reload behavior remain
settlement acceptance checks.

The remaining individual and party companion callbacks now converge on the same
order boundary, including combat stance, weapon preference, vehicle actions,
recruit/dismiss, and temporary primary orders. Existing base-resident activation
stays explicit because it is an ownership transition. This unifies the player
command surface without changing native executors or persistence owners.

The shared order catalogue now disambiguates Patrol correctly: a payload-less
`Patrol` remains a resident preference, while a targeted or payload-bearing
call becomes the existing companion patrol-area directive. Party Patrol without
an area resolves a bounded local directive per companion. This closes a
player-facing routing gap without adding another executor or scheduler.

## Next gate — coordinated settlement workforce

The next settlement pass treats each base as one small workforce while keeping
the existing task board and native action executors as the only owners. The
coordinator boundary is deliberately narrow:

- reconcile stale and duplicate claims before assignment;
- evaluate real food, water, medical, weapon, tool, and building shortages;
- preserve explicit player assignments while rotating automatic duties;
- maintain required guard/patrol coverage before routine work;
- give each eligible resident one task or a bounded ambient recovery state;
- release or requeue work when a resident dies, leaves, unloads, or changes
  ownership;
- persist duty, claim, shortage, and return-home intent without serializing a
  live engine action.

Acceptance requires a base with at least three residents to distribute distinct
work, send no more than one shortage run per shortage type, keep security
staffed, let idle residents recover, and restore ownership and queued work
after save/reload. Automated checks must cover deterministic assignment,
manual-task protection, stale-claim repair, shortage de-duplication, and
resident death or unload. Live verification remains required before this gate
is considered complete.

The persistence layer now performs this claim repair at two boundaries: before
an automatic resident selects work, and across all bases during the existing
settlement reconciliation cadence. Invalid owners and duplicate claims are
returned to the queue deterministically, while manual assignments remain
owned only by valid residents. This is foundation work for the gate, not a
substitute for live multi-resident acceptance.

Automatic shortage trips now rotate across eligible loaded residents using
persisted last-run history instead of controller iteration order. An in-flight
trip has one durable duty record across reconstruction, while its path, chosen
world item, and native transfer action remain runtime-only. Completion and
bounded failure release both the shortage lease and durable trip owner. The
remaining gate is live proof with three residents performing real work and
supply return/deposit across interruption and save/reload.

Blocked settlement jobs now search only for requirements the assigned worker
still lacks. Already-carried tools no longer consume the bounded external
search budget while another declared material remains missing. Settlement
shortage planning also allows distinct food, water, medical, weapon, and tool
runs concurrently while retaining one lease per resource and one in-flight
lease per resident. Automatic workers fill the existing minimum Guard/Patrol
coverage before routine work, but player-selected non-security roles and
recurring watch relief remain authoritative. The task board and native action
executors remain the only work owners.
