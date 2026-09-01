# Architecture

## Product boundary

A survivor is an autonomous human agent. It is not a scripted zombie and it is not a second local-input player.

Knox Survivors owns:

- persistent survivor identity;
- goals, planning, and decisions;
- movement and interaction intent;
- relationships, orders, camps, and factions;
- serialization and migration of Knox-specific state.

Project Zomboid owns the active `IsoPlayer` representation and normal world mechanics wherever those mechanics can be reused safely.

## Runtime layers

1. **Identity model** — stable IDs and persistent human state independent of a loaded engine object.
2. **World representation** — an `IsoPlayer` created only while its cell is active.
3. **Controller** — converts goals into movement, combat, and interaction intent.
4. **Actions** — executes player-valid actions such as equipping, transferring items, attacking, healing, and barricading.
5. **Simulation** — advances survivors away from loaded cells without keeping full engine objects alive.
6. **Persistence** — saves Knox-owned state and reconstructs world representations safely.

## Persistent person, temporary body

The Knox survivor record is the authoritative person. An off-slot `IsoPlayer` shell is
not trusted as a save-game entity and is never the survivor's identity. Before a shell
is removed, Knox snapshots its current world tile, inventory, worn slots, and hand
equipment. When that survivor's cell is active again, Knox creates a new shell with the
same stable ID and restores the snapshot. To the player this is the same person
continuing to exist; reconstruction is only an engine lifecycle detail.

Java survivor record schema 5 stores the engine human visual, name and voice, inventory and
equipment snapshot, native `BodyDamage`, and native physiology/nutrition state. Older
record schemas migrate forward by supplying engine defaults for fields they did not
contain. New survivors receive real wearable inventory items selected with Build 42's
default, profession, and trait clothing definitions; a restrained separate roll may add
a schoolbag or duffel bag.

Inventory sub-schema 3 captures each root item using native `InventoryItem.saveWithSize`, with
its native world version, total nested-item count, and existing worn/hand bindings. Native container
serialization carries bag contents and item-specific fields such as food state, fluids and rounds.
Restore preflights all native roots and nested counts before clearing the destination inventory;
missing mod items or incomplete decoding reject reconstruction while leaving the encoded record
intact. Schema-2 records remain readable with their old type/condition/uses/visual semantics. They
cannot recover nested contents or quantities that the old format never saved. A fresh capture
upgrades the inventory subrecord; old agent jars cannot read the new sub-schema.

Offscreen food/water consumption decodes detached native items, never an IsoPlayer or a new default
item inferred from its type. Ordinary safe food is reduced with `multiplyFoodValues`; pure clean
water uses native fluid quantity adjustment at the Build 42 bottle ratio of 0.12 fluid per 0.1
thirst. Consumed quantity determines relief. Reusable bottles and partial food remain serialized;
simple fully consumed food is removed from its actual saved container. Scripted food callbacks,
byproduct-producing food, unsafe food/fluids and legacy quantity-unknown snapshots are not consumed
offscreen. Those cases require loaded actions or further supported simulation work. Registry rejects
consuming an active identity, and Lua applies relief only after the updated record is committed.

Records are saved by stable ID under the rebuild-specific `KnoxSurvivors_IsoPlayer`
global ModData key. Every loaded survivor has a separate runtime containing its temporary
body, movement request, traversal route, combat controller, and latest record. Saving
captures all active runtimes rather than whichever NPC happened to act last. This key
remains separate from legacy IsoZombie-era Knox data.

The Lua domain has its own schema number. Schema 7 adds canonical profession and trait
IDs, perk levels and XP, player relationships, affiliation and duty, player factions,
stable bases, work zones, storage policies, and task records. Java record versions and
Lua domain versions are never advanced together by assumption. Migrations normalize
partial development saves in place and never erase an encoded person record.

Profession and trait generation uses Build 42's live definitions, costs, granted traits,
and exclusions. It is deterministic per stable survivor ID and is saved before the body
can be reconstructed. Existing bodies restore saved physiology after the engine applies
their identity rules, then restore saved perk progress. The active body is captured back
into the capability profile; translated labels are never used as save keys.

## Population and origin policy

Survivors are durable world inhabitants, not a refill effect around the active player.
New identities originate from the map's real spawn-region point tables, supplemented by
native ground-floor building room rectangles. A candidate is
rejected when its square is currently visible, occupied, unsafe, or too close to a
player. A valid identity may originate in another town and remain virtually simulated
until its cell loads; loading a cell activates the survivor at their recorded location
instead of relocating them toward the player.

The production population core now maintains a configurable persistent target, defaults
to 32 living identities, and limits physical materialization separately from world count.
Initial allocation is region-balanced, preferring player starts for two allocations out of
three and native building locations for the third when available. Metadata is cached once
per map; supplemental locations are thinned to one per 100-tile cell. Death is durable
and does not trigger an immediate nearby replacement; after the configured refill interval,
one new identity is allocated at a still-unused origin. Active world survivors hibernate
when they leave the player band and restore at their saved square when that area becomes
relevant again. Developer scenarios remain available as a separate bounded test harness for
social, faction, base, and companion behavior.

The optional `DisableSurvivorCaps` setting preserves those configured values but bypasses the
active-body and recruitment count checks. WorldPopulation remains a finite starting count; later
arrivals can exceed it, one identity per refill interval, from unused origins only. No numeric
faction count cap currently exists. The scheduler constructs at most two bodies per population
reconciliation in either mode; this is a rate limit, not another total-population cap. Disabling
caps is an explicit performance tradeoff. Re-enabling them preserves existing identities and
companions instead of deleting excess members. No infinity value is persisted in save records.

Before first materialization, an identity has a location-only `unloadedSurvival` ledger with
`pendingMaterialization=true`. It stores a short itinerary between nearby catalog locations,
departure/rest timestamps and lightweight destination memory. Population reconciliation advances
that itinerary without allocating a character, changing the birth origin, or moving it toward a
player. First activation uses the progressed position with the same hidden/standable/safe-square
requirements. This ledger contains no invented physiology or inventory and must never be applied
as real character stats. The first successful body capture replaces it with real needs and record
coordinates. Every subsequent capture also replaces stale virtual coordinates with the fresh
record position. Ordinary hibernated survivors continue through the existing survival simulation.

Pre-materialization travel is a coarse location simulation, not native offscreen pathfinding or
resource generation. Routes stay on the same floor, within 600 tiles of the last stop, at a net
40 tiles/game-hour with two-to-five-hour stops. Reconciliation performs at most eight legs and
48 hours of catch-up; older excess time does not trigger unbounded world scans. These constants
are implementation policy awaiting live density/pacing evidence, not claims of full offscreen
human simulation. Saved body records remain authoritative once they exist.

Captured independent survivors reuse that nearby-catalog itinerary through UnloadedSurvival;
they no longer drift 1.25 tiles/hour on an arbitrary heading. An unavailable catalog leaves them
at their current location. Explicit return-home trips use 40 net tiles/game-hour and refresh the
destination against the current assigned base; replacement companion duty cancels the old trip.
Virtual trips are coarse simulation, not loaded pathfinding or a guarantee of a traversable route.

Independent survivors, base residents and briefly stored companions split elapsed time between
awake activity and rest. Walking spends endurance; stationary time restores it. Fatigue rises while
awake only when the existing Needs sleep policy requires sleep, and decreases only during a saved
sleep phase. Rest starts at 0.30 endurance and ends at 0.80; sleep starts at 0.72 fatigue and ends
at 0.35. A maximum of eight transitions per six-hour physiology step bounds the work. These are
coarse Knox rates, not a claim to simulate the full native sleep/trait physiology offscreen.
Rest preserves the itinerary/base-return directive; real capture clears stale virtual phases.
Sleeping/resting/sheltering identities restore through the same hidden-square virtual-location
handoff as travelling identities. No world loot, wound healing or extra supplies are generated
by these travel phases. Away teams retain their existing mission travel/recovery policy.

Fully stored autonomous travel groups advance as one cohort in `UnloadedSurvival.advanceAll`.
The existing travel-group record owns one optional `unloadedTravel` itinerary; condition is derived
from the members' real ledgers rather than saved as a second group health/needs model. Shared
walking translates each member by the same delta, preserving their captured offsets. Highest
fatigue/lowest endurance determine shared rest timing; each member retains individual needs,
recovery and real encoded inventory consumption. A member more than 20 tiles away causes a
leader wait and bounded approach to within six tiles before shared travel resumes. No loaded
body is moved by this simulation, and different-floor groups do not invent offscreen stair routes.

Any active member or conflicting companion/base/mission duty prevents cohort travel. Stored
members still advance needs/rest in place; the active controllers retain navigation ownership.
Unequal capture clocks catch up physiology in place before the common travel interval begins.
Membership/leader/capture-clock changes rebase the saved itinerary from current member positions.
Death uses ordinary identity/social cleanup and ends that cohort update; the next reconciliation
rebuilds membership. Direct single-member simulation cannot move a group member independently.
Waiting/regrouping phases use the same hidden-square restoration boundary as travelling phases.

## Minimal active-survivor loop

The first playable survivor is intentionally a small priority controller, not a complete
planner. Each decision update selects one state, and only one action owns the body:

1. **Threat** — flee when unsafe, otherwise equip and engage one nearby zombie.
2. **Injury** — stop somewhere safe and treat the most urgent wound with a carried item.
3. **Critical thirst/hunger** — consume real safe food or water from carried inventory through
   the shipped timed actions.
4. **Exhaustion** — sit/rest for endurance, or enter the native sleeping event for fatigue when
   the current sleep rules require it.
5. **Loot need** — approach one reachable container and take a small ranked set of useful
   items through normal inventory transfer actions, based on current equipment and stock.
6. **Idle travel** — choose a nearby reachable destination and walk there.

The controller chooses *what* to do. Small action executors own *how* to move, equip,
attack, transfer, or treat. Threats may interrupt travel and looting; an executor must
finish, fail, or be cancelled before another executor writes movement or combat input.
This keeps combat, inventory, and medicine independently testable.

The survivor initially uses the engine's real inventory, equipped-item slots, combat
pipeline, and `BodyDamage`. Knox persists a portable snapshot of those values rather
than treating the live `IsoPlayer` object as the save record. Directly applying damage,
teleporting items, or healing wounds is reserved for unloaded-world simulation; an
active survivor should use the same world actions and consume the same items as a player.

Self-care is temporary action ownership, not a durable order. The controller records the real
need/BodyDamage state before queuing a native eat, drink, bandage, or improvisation action. An empty
queue is not considered success unless that authoritative state changed. Failure installs one
bounded retry instead of selecting the same action every tick. Immediate danger clears the native
action or wakes the survivor through `SleepingEvent.wakeUp`, then exposes the unchanged Follow,
Hold, group-travel, or roaming role after danger ends. Sitting remains native endurance recovery;
fatigue uses `SleepingEvent.setPlayerFallAsleep` without local-player fades or time-control writes.

## Confirmed 42.20 engine surface

Inspection of the installed `projectzomboid.jar` confirms:

- `IsoPlayer(IsoCell)` and `IsoPlayer(IsoCell, SurvivorDesc, int, int, int[, boolean])` constructors;
- `IsoPlayer.setNpc(boolean)`;
- local-player storage through `IsoPlayer.players[]` and `IsoPlayer.setLocalPlayer(...)`;
- the shipped Lua `SpawnRegionMgr.getSpawnRegions()` function and its loaded region point tables;
- `isNpc()` players skip ordinary local-input movement, then consume
  `AIComponent.getHumanControlVars()` during `IsoPlayer.updateInternal2()`;
- normal inventory and equipment live on `IsoGameCharacter` through `getInventory()`,
  `setPrimaryHandItem(...)`, and `setSecondaryHandItem(...)`;
- off-slot NPC combat input is represented by `AIComponent.getHumanControlVars()` together
  with the ordinary `IsoPlayer` aim, charge, and attack fields;
- injuries live in the normal `BodyDamage` and `BodyPart` objects, and the shipped Lua
  actions support a doctor and a separate patient.

These are confirmed entry points, not proof that an off-slot NPC is lifecycle-safe. Every affected subsystem must be tested in game.

## Off-slot melee integration

Build 42.20's `SwipeStatePlayer` animation callbacks restrict collision checks and swing
sounds to local players. Knox does not make a survivor local to bypass that restriction.
The Java agent redirects only the three relevant local-player predicates to a Knox-owned
predicate that accepts the real local player or the exact `KnoxIsoPlayerShell` class.
The rest of each callback remains unmodified engine code, including hit selection,
damage, endurance, weapon condition, sound, blood, reactions, and death.

Standing-zombie target visibility has one separate off-slot boundary in Build 42.20.3:
`IsoZombie.isTargetVisible()` reads the target player's local-lighting index, which a contained
shell intentionally does not own. A second transformer adapts only that method's `getIndex()` and
`isCouldSee(int)` calls for the exact Knox shell. Live combat refuses to start unless both this
two-call adapter and the three-call survivor-melee adapter report their expected patch counts.
Zombie target selection, approach, attack state, collision, hit rolls, BodyDamage, reactions, and
death remain native.

The shell supplies its controller-owned forward direction as its aim vector because it
has no mouse or controller input component. The combat executor synchronizes the human
AI control variables, target square, facing, charge, and attack request. If a melee
request does not enter `SwipeStatePlayer`, the executor makes one explicit state entry
and records that fallback in the diagnostic log.

Combat approach targets are placed inside the equipped weapon's maximum range with
enough margin for the movement executor's arrival tolerance. A generic adjacent-square
center is not a valid melee stopping distance: it can report arrival while the weapon's
collision volume still cannot reach the target.

Live zombie targets are not treated as stationary after the first approach. If a target
moves beyond the equipped weapon's effective attack margin, the combat executor clears
the stale swing request, paths back into range, and then settles its aim again. Locked-door
combat remains fixed in place and does not use this re-approach rule.

Combat is a temporary movement owner, not a durable order. Entry cancels the current engine
movement request while leaving the companion/group directive intact. Every terminal, invalid-target,
exception, and explicit-reset path clears the attack flags, `AttackType`, attack square, AI input,
combat route, and pathfinder before releasing ownership. The Lua controller then resumes its normal
decision loop, where an existing Follow/group directive can request movement again.

Threat awareness distinguishes immediate proximity, visible zombies, and zombies already
targeting the survivor or a travelling companion. Active threats receive priority over an
idle visible zombie, while bounded score hysteresis keeps a valid target until danger changes
meaningfully. Reservations scale with urgency: one survivor owns an ordinary distant target,
two may answer an immediate/group threat, and up to three may defend a survivor already under
attack. Companion/group role leashes prevent a visible zombie from pulling the whole party away.

Retreat remains part of this same small decision layer rather than a tactical planner. Low health
or three nearby zombies per nearby ally interrupts combat, chooses a standable direction weighted
away from the closest pressure, and starts one ordinary Java movement request. Short-lived group
plans keep loaded members moving roughly together. Two safe scans end retreat and expose the
durable Follow/Hold/travel order to the normal decision loop again.

## Off-slot firearm integration

Firearms preserve Build 42.20.3's split ownership instead of implementing Knox ammunition or
ballistics. Lua's shipped `ISReloadWeaponAction.canShoot` is the readiness authority;
`BeginAutomaticReload` and `ISRackFirearm` own magazine, loose-ammunition, chamber, jam, and timed
action transitions. Knox only selects a carried functional weapon and refuses to queue a second
preparation action while the first still owns that firearm.

Weapon preference lives in the existing persisted `survivor.policies.weaponPreference` field:
`auto` (legacy/default), `melee`, or `ranged`. Player changes pass through companion ownership
validation; there is no separate command/planner registry. `auto` favors a usable melee weapon
for novices and close threats. Native Aiming level 4+ with a same-floor target at least three tiles
away can prefer ranged combat. Explicit ranged preference still requires native viable ammo/reload;
explicit melee prefers melee when available, with a usable firearm as fallback if no melee remains.
Preference is considered at combat acquisition/preparation, not every frame. Existing native combat
owns close-range repositioning/fallback and threat selection. A changed preference releases attack/
reload ownership without erasing Follow/Hold/Guard. Unchanged controller sync does nothing.
The individual and party menus use native checked options; mixed party values show no active check.
Faction doctrines remain future integration, not inferred from faction names or hidden buffs.

Java captures the equipped firearm for the encounter, maintains facing and floor aim, and owns one
bounded approach or close-range reposition request. It does not call `pressedAttack()` for a ranged
request. Instead it returns `COMBAT_FIREARM_REQUEST`, and the Lua controller invokes the shipped
`ISReloadWeaponAction.attackHook` once. That native hook owns the ranged sound and world-noise event
and enters `DoAttack`; the normal `OnWeaponSwingHitPoint` callback remains responsible for
ballistics, damage, chamber state, magazine count, jamming, condition, and ammunition consumption.
`setAuthorizeMeleeAction(true)` is required because Build 42 uses the legacy-named method as the
general player attack authorization gate, including firearms.

An active rack/reload temporarily releases Knox combat ownership without clearing the underlying
Follow, Hold, or group directive. A missing compatible round or magazine selects an actual carried
melee weapon instead of retrying reload. If a close-range backing route fails, the ranged owner
returns a distinct fallback result and the controller switches to melee without placing the nearby
threat on the unreachable-target cooldown. Dead targets, weapon changes, terminal attacks, and
explicit resets clear ranged intent and the temporary route through the same combat teardown used
by melee.

The shell's LOS override must remain disabled because off-slot `IsoPlayer.updateLOS()`
writes into a real local player's render channel. A scheduled Lua awareness adapter restores
only the omitted vanilla discovery edge by calling `TestZombieSpotPlayer` for nearby zombies.
Vanilla still evaluates sight and owns zombie target selection; Knox does not assign targets
or make survivors immune. The adapter runs every 30 ticks rather than once per frame.

## Hard constraints

- Do not place NPCs into `IsoPlayer.players[]` unless a narrowly scoped experiment requires it.
- Do not use `IsoPlayer.setInstance(...)` for NPC ownership.
- Do not assign keyboard, mouse, controller, camera, or split-screen ownership to an NPC.
- Keep Knox identity separate from `onlineId`, `playerIndex`, and transient engine references.
- Prefer ordinary timed actions and inventory APIs when they work for an NPC.
- Treat multiplayer as compatibility-only until authority and replication are designed and tested.
- No feature is complete until save/load and cell unload/reload behavior are verified.

## Build 42 render-shell constraint

Build 42.20's FBO renderer excludes moving objects whose concrete class is exactly `IsoPlayer` and renders those objects only from the local-player array (or the multiplayer player map). Knox must not use either collection for NPC ownership.

The contained engine representation is therefore a minimal `KnoxIsoPlayerShell` subclass. It remains an `IsoPlayer` for engine gameplay checks while avoiding the renderer's exact-class branch. `KnoxNpc` remains the owner of identity and behavior; the shell must never become the persistent domain model or a local-player slot.

Build 42.20 also assigns the receiver to the global `IsoPlayer.instance` during every
`IsoPlayer` update, including a non-local subclass. The shell wraps its inherited update
and restores the actual pre-update instance before returning. Without that guard, the
last NPC updated can be mistaken for the local player by later camera, UI, rendering, or
Lua work. Periodic development diagnostics verify the global binding plus local-player
and NPC alpha, invisibility, and model-manager state.

The inherited `IsoPlayer.updateLOS()` is also local-player ownership code: it iterates
the cell's moving objects and writes their alpha values for `playerIndex`. Because an
off-slot shell uses channel 0 only so the renderer can display it, running that method
from an NPC overwrites the real player's visibility results. The shell therefore makes
`updateLOS()` a no-op. The actual local player remains the sole owner of channel 0 LOS
and naturally controls whether survivor bodies are visible from the camera.

## Implementation order

Engine pathfinding supplies a route, while Knox supplies human control intent to the NPC
component. Locomotion must pass before any other executor is added. The next supported
slice is then: inventory ownership and equip, one-zombie melee combat, one-container
transfer, normal injury reception, self-bandaging, and finally player-to-NPC treatment.
Each slice is live-tested alone and across save/reload before the next one begins.

The verified single-survivor runtime remains available through compatibility bridge
methods. Active survival is now scheduled by one Lua autonomy controller per stable ID;
movement and combat state remain inside that identity's Java runtime. Shared reservations
prevent two survivors from selecting the same zombie or world item. Expensive container
searches run only for an unmet need and use a retry cooldown instead of scanning every
frame. Group and faction state must never be inferred from transient engine bodies.

## Relationships and encounter history

Social history is owned by persistent survivor IDs, never by temporary `IsoPlayer`
shells. A low-frequency observer records an encounter only when two loaded survivors are
actually within awareness range on the same level. The save retains their names, first
and most recent meeting times, number of meetings, nearby world-hours, and shared
completed roaming, looting, and combat activity.

Active allegiance is also resolved only from persisted IDs. `affiliation` owns player/faction
membership, travel-group and faction records own their member and leader lists, and pair/faction
relationship records own disposition. Runtime character lists are derived caches used for movement
and ally assistance; they never decide membership. One deterministic classifier resolves self,
allied, neutral, or hostile, with shared player ownership/group/faction taking precedence over stale
pair hostility. Save-load normalization removes duplicate roster copies, repairs missing leaders,
and removes dead members from active groups, factions, and camps while retaining historical encounter
records. This prevents an unloaded shell or transient controller reset from changing allegiance.

An ungrouped pair that enters awareness range now interrupts only safe, non-combat work,
approaches, faces one another, and holds a short visible conversation. Mutual agreement
creates a persistent travelling group. The lowest stable ID is the initial route leader;
other members satisfy urgent personal needs but otherwise wait for or follow that leader.
Followers receive stable staggered slots behind the leader and refresh their destination as
the leader moves instead of all chasing one occupied square. The leader waits when a member
falls outside the soft travel leash and walks back toward a severely separated member.
This is the movement foundation for later selectable tactical formations; it does not yet
change combat roles or weapon positioning. An established group
can separately invite a lone survivor. Three consenting members unlock faction readiness,
and relationship history must show nearby time or shared survival activity. There is no
arbitrary minimum number of days together. Proximity alone
is not enough: greeting and agreement must complete without combat interruption.

Dialogue still calls the engine's normal `Say` method for world speech bubbles. The same
line and major encounter outcomes also pass through a client-side activity feed built from
vanilla `ISCollapsableWindow` and `ISRichTextPanel` components. This is separate from the
base game's chat window because Build 42 creates that window only for multiplayer clients.

Independent survivors notice one another within 14 tiles, but only consider a cautious
encounter within 10. Social work never interrupts combat or an unsafe action. One approaches
while the other waits, avoiding artificial teleporting or constant magnetic movement. A
persisted ally never starts a social encounter; a known hostile keeps distance rather than
falling back into a friendly greeting. Neutral first contact deterministically becomes either
a brief cautious greeting or no interaction, with a short memory cooldown. Joining requires
later familiarity plus shared activity, so proximity alone cannot form a party. Only one pair
may own a survivor in a social scan, and group leaders—not every member—initiate an invitation.
Completed greetings and interruptions release both controllers back to their durable behavior.

Stable identity traits supply sociability and aggression. Existing valid first aggression can
still produce the limited normal-timed-transfer robbery executor and durable hostility; it does
not add a new surrender or diplomacy system. Hostile loaded survivors and players now route
through the same live native-combat owner used for zombies, while the controlled combat gate
remains zombie-only. Human target routing and cleanup are focused-test verified, but lethal
human PvP remains behind a live Build 42 animation/collision/BodyDamage verification gate.

Purposeful exploration considers useful nearby supplies before undirected roaming. A
survivor searches reachable containers for stronger melee weapons, better protective clothing,
a wearable bag, limited food/water/medical stock, and missing essential tools. They play
the search animation when an uninspected container is already convenient. A visit may take
up to two ranked items. Survivors then travel before considering another optional stop;
blocked rooms are cooled down instead of repeatedly forcing entry.

Independent loaded roaming keeps one goal until movement completes, fails, or a higher-priority
danger/self-care owner interrupts it. Useful ranked containers remain the first choice. When none
is currently worthwhile, the survivor prefers a nearby unvisited building, then a safe nearby area,
rather than an arbitrary tile. Candidates near an obvious zombie concentration are rejected. A
bounded twelve-entry, loaded-session memory cools completed destinations briefly and failed ones
longer, so the survivor leaves exhausted areas without creating permanent world knowledge.
Container inspection memory also expires, allowing later reconsideration if the world changes.

Temporary camps remain lightweight faction shelter records rather than miniature bases. The camp
stores one building identity, loaded bounds, and the current durable faction-member IDs. Runtime
controllers derive camp assignment from that persisted faction link on registration and low-frequency
reconciliation; no second survivor affiliation is created. Members choose deterministic, reserved,
standable positions inside the shelter, with slot-staggered rest, reposition, excursion, and quiet-idle
choices. Needs and threats retain priority. An excursion uses ordinary roaming and at most one normal
ranked exploration opportunity before returning through native movement. Camp identity survives those
temporary owners and is cleared when the camp is removed or converted to a permanent faction home.
Nearby real containers remain available to the ordinary need/looting paths; camps create no abstract
stockpile, item generation, work board, territory, or storage ownership.

## Player companions and presentation

### Player trust and faction reputation

Personal trust remains in `survivor.playerRelationships[playerId]`; faction reputation extends the
existing canonical faction-pair relationship, not a second diplomacy registry. Positive contribution
records have fixed supported reasons, per-kind cooldowns and a rolling 24-hour budget (12 personal
trust, 8 faction reputation shared across members). Reward windows survive save/load and do not
reset on clock rollback. Faction relationship getters deep-copy nested reward data. Existing trust
continues to govern recruitment; explicit hostility always blocks Talk/recruitment and positive credit.

The native `OnZombieDead` boundary grants defense credit only when the dead zombie's actual attacker
is a real local player and its current target is a living loaded Knox survivor: same floor, zombie
within eight tiles of that survivor, player within twenty. Missing native evidence earns nothing.
A weak body-key set suppresses repeated callbacks; persisted cooldown/budgets bound separate kills.
No full-world scan, custom kill, inventory reward or damage mutation is involved. Positive help does
not automatically erase hostility or create an alliance. Credit acknowledgement uses existing speech.

A native player hit on a previously non-hostile survivor records a trust loss and, for NPC-faction
members, negative reputation plus hostile faction disposition through the existing relationship.
Repeated attacks on an already-hostile target are not additional unprovoked aggression. Player-owned
factions are not made hostile to themselves. Trade credit now follows verified exchange completion,
and quotation reads trust/faction reputation. Gift/treatment/construction credit reasons remain a
persistence contract; their gameplay completion adapters are still unfinished.

Recruitment is a persistent affiliation transition, not a UI flag. A namespaced player ID
owns one player faction; a survivor may belong to only one authority and cannot remain in
an NPC travel group after recruitment. Talk history and trust are saved per player. Follow,
Hold, Return to Base, and Dismiss update duty first, then the active controller reconciles
that durable order on its next update. Threats and critical needs remain above ordinary
orders, so survival can interrupt a command without deleting it.

Companion commands are split into three durable concepts. The primary order is Follow or
Hold. Vaulting/climbing is a standing traversal policy. Loot-area, loot-building, and
loot-corpses are temporary directives; after the target has been searched, the survivor
returns to the primary order. Header commands use the same service as individual and world
context menus. NPC travel groups and factions reject any survivor whose affiliation or duty
is player-owned, including stale pending meetings.

Follow reuses the existing staggered slot structure rather than targeting the player's
occupied square. Slots are refreshed on a bounded cadence and a route is replaced only when
the slot changes by a meaningful distance or floor; pace-only changes update the active Java
request without replacing its destination. Close followers walk, moderately separated
followers run, and far followers may request sprint. Each movement tick re-evaluates the
remaining route, real health, endurance, fatigue, and native `canSprint()` result, so sprint
downgrades to run and then walk as the gap closes. The implementation uses native
`setRunning`/`setSprinting` state and the existing NPC human-control variables; it never
changes coordinates or movement speed directly. Hold is an explicit guard at both follow
start and refresh boundaries.

The runtime registry is deliberately narrow. Gameplay and interface code may resolve a
temporary character or request a fresh semantic snapshot, but cannot take ownership of a
controller. The companion view model returns copied values for name, duty, activity,
health, needs, weapon, and distance. The right-side HUD only queries player-owned
companions, pools at most six live 3D portraits per local player, and releases every body
reference on unload or teardown. World and HUD context menus call the same companion
service.

## Base and work boundary

Player and NPC settlements share stable base records. A base keeps its original home
building separate from an editable territory boundary. Territory applies to its X/Y area
on every building floor and classifies ownership only; it never blocks navigation into,
out of, or through the building. A base owns its territory, work zones, storage policies,
residents, and queued tasks; it never stores a live square,
container, character, or controller reference. Storage markers use namespaced world-object
ModData plus coordinates, object index, and container index so multi-container furniture
does not collapse into one destination.

Duty, physical presence, capability requirements, and claim ownership are checked before
a resident can take work. Claims are released when a survivor leaves the base and are
recovered after an interrupted load. Guard and patrol zones now have a recurring executor:
the resident claims a persisted task, walks to a standable point in the zone, holds the
post for a bounded interval, records the result, and reopens the same task on its next
cycle. A depot policy can also pair with a categorized destination policy: the resident
finds one matching item in the loaded depot, walks to it, and moves it through the normal
off-slot inventory-transfer action. The persistent task stores stable policy keys and an
item full type rather than an engine object, so a save/reload can safely retry if the item
was taken. Before a claimed task starts its actual world action, a resident checks its
exact item requirements against their carried inventory plus currently loaded assigned base
containers. Missing items are collected one transfer at a time through the same off-slot
inventory action; streamed-out or absent storage blocks the task rather than becoming an
implicit supply pool. Farming zones now have a small maintenance executor: the resident discovers the
first ripe or dry seeded plant in the loaded zone, walks to it, and queues the vanilla harvest
or watering action. An empty suitable square can then be plowed and a carried seed sown as
separate persisted tasks, again using the vanilla timed actions and state verification. A
woodcutting zone likewise resolves a loaded tree, requires a real axe, and queues the vanilla
`ISChopTreeAction`; completion is accepted only after the tree object is removed. Log-to-plank
production resolves a carried log and saw, validates the vanilla `SawLogs` recipe, and queues
`ISCraftAction`; completion is accepted only after the source log is consumed. Corpse handling
now has the same kind of executor: a resident finds a loaded human or zombie body inside the
bounded base territory but outside its Corpse Drop Area, walks to it, unequips held items, then
uses the vanilla grab and drop actions to drag it toward the center of that area. The saved task keeps only corpse coordinates,
its inventory-item ID with a static-object fallback, and the destination zone ID; live object
references never enter ModData. Interrupted hauling releases the body before the claim is
closed. Animal Care Areas now discover loaded feeding troughs and create separate water or
feed tasks only when a resident carries a valid supply. Water uses Build 42's normal
`ISAddFluidFromItemAction`; feed uses the same inventory-transfer path as a player, which
lets `ItemContainer` notify the trough and update its animals and overlay. The task persists
only the master trough coordinates/index and the supply's item type/ID, then verifies that
the real trough water or feed amount increased. Structure repair delegates its entire ruleset
to Build 42's moveable-repair system. A resident scans a drawn Repair Area, or the loaded base
territory when no repair area exists, and considers only doors, thumpable structures, and
barricades between 20% and 95% health that vanilla `canRepairObject` approves. The task keeps
coordinates, object index, sprite name, and the concrete tools/materials found for that repair.
After travel, `ISMoveablesAction` performs the normal equip, animation, sound, skill-chance,
resource-consumption, multi-tile repair, and synchronization path. Knox records success only
if the actual object health rises; a legitimate skill failure remains a failed retryable task.
Barricade work is the exception: when a resident carries a hammer, plank, and
nails, the controller discovers an unbarricaded loaded window inside the base and queues the
vanilla `ISBarricadeAction`; completion is accepted only after a real plank count increase.
Vanilla crop ownership is not treated as a Knox survivor ID because single-player off-slot
bodies do not provide a stable unique crop owner.

Automatic discovery queues all currently executable job families before selecting work.
The shared task board chooses by persisted priority and filters each resident against skill,
trait, recipe, and real assigned-storage item requirements. This prevents renewable farming or tree work
from starving security and cleanup, while also preventing a resident without the exact tools
or materials from claiming a task another resident prepared.

Player territory is also sent to the Java traversal runtime as a protected structure area.
Friendly and neutral survivors may still use doors and try an unlocked window, but they
cannot escalate to smashing a window or breaking a locked door inside that territory.
Explicitly hostile survivors are exempt so later raids can use the same policy boundary.

## Faction base scouting

A faction home begins as persistent planning data before becoming a claimed engine object.
The leader periodically examines loaded buildings within 30 tiles. Candidates need at
least two rooms and 30 tiles; residential status, water, room count, and area improve the
score. Buildings overlapping an existing vanilla safehouse are excluded. The chosen
building ID, bounds, score, and an exterior approach square are stored before travel.

The group follows its normal leader while the leader travels to that approach square.
Arrival promotes the candidate to `homeBase`; a failed route rejects it for 24 in-game
hours so another building can be considered. A selected home receives a vanilla safehouse
boundary with a namespaced synthetic Knox faction owner. This makes vanilla overlap checks
reject player claims in that building. The boundary is reconciled on load and periodically
while the faction is active. A stable base record is then created and faction members become
residents. They return toward a loaded home and alternate between short local patrols and
idle periods while the first real job executors are built. Trespass hostility remains a
separate gameplay layer.

Captured route waypoints are not assumed to be unobstructed floor. Before crossing into
an adjacent square, the traversal layer asks the engine whether that edge contains a
door, window, window frame, low fence, tall climbable wall, or hard blockage. It pauses
walking while a normal engine interaction or climb state owns the body. Unloaded,
barricaded, unclimbable, and static obstructions produce an explicit route failure
instead of allowing the survivor to walk in place forever.

## Carried inventory cleanup

The existing Looting policy exposes `itemUtility` (retention priority, not a trade price) and
`cleanupPlan`. Cleanup begins above 90% of native maximum carry weight and, once active, stops
below 80%. Recursive inspection is cycle/depth bounded. Equipped, attached, hand-held, favorite,
medical, ammunition, essential-tool, best-melee, needed-food/water, valuable/accessory, unknown
modded and queued/claimed-job items remain protected. Favorited bags protect their contents;
nonempty bags themselves are not discarded. Surplus food/water and recognized base materials
are deposit-only. Inferior spare gear, broken weapons and known vanilla junk may be dropped.

The normal controller thinks about cleanup after threats/self-care, without interrupting a claimed
base task. It queues one item through the existing off-slot native inventory transfer adapter,
then verifies source removal plus destination/world receipt. Nearby reachable assigned storage
from the canonical player/faction base is preferred; categorized storage precedes depot/general.
Floor drops use a private native `ItemContainer("floor", nil, nil)` like the vanilla loot panel,
never a local-player indexed inventory. No item is manually deleted or recreated by cleanup.

Cleanup is temporary `INVENTORY_CLEANUP` ownership. Danger/new commands cancel it, timeout and
failure clear it, and Follow/Hold/Guard remain persistent underneath it. Evaluation and failure
cooldowns bound repeated attempts. Inventory changes use the ordinary snapshot/capture path;
transient item references are not serialized. Useful surplus can also initiate `MOVING_TO_DEPOSIT`
for a loaded owned container within 128 tiles on the current floor. The native adjacent-tile finder
selects the interaction side; the existing movement/traversal runtime owns the route. Companions,
directives, travelling groups, away duties and claimed jobs cannot take this autonomous detour.
Arrival recomputes canonical base ownership, item utility/job protection and the exact container
policy/capacity/interaction edge before queuing a real transfer. Movement failure or timeout cools
down that storage key for 1800 ticks (at most 16 remembered keys); cleanup retry waits 600 ticks.
Danger, new commands, detachment and shutdown discard transient trip ownership. No teleport,
abstract stockpile or persisted item reference is introduced. Cross-floor/distant deposits, broader
reserve/modded valuation and currency/trading prices remain separate work. Protected-heavy
inventories may remain overweight when no safe disposal or practical owned deposit is available.

## Independent survivor barter quotation

`KS_TradeValuation.quote(player, survivorId, playerItems, survivorItems)` is a read-only policy
boundary, not a completed trade or permission to transfer. It resolves the active body from the
existing runtime and life/affiliation/hostility/trust/faction reputation and base task needs from
existing persistence. A local real player and living non-player-owned survivor must be within three
tiles on the same floor. Quoting does not create relationships, award reputation, move items,
change orders or capture a second inventory record.

Actual inventory ownership is walked recursively, with 4096-item and 16-level bounds. Offers are
dense unique arrays of at most 32 item references per side. Stale ownership, shared inventory,
favorite/hidden/equipped/attached/hand items, favorite or hidden bag contents, nonempty bags, unsafe food/water,
broken weapons and unclassified items are rejected. Real food relief, fluid amount, bandage power,
condition, protection, bag capacity and weapon/ammunition fields drive the initial known-item
values. Native `AmmoType.getItemKey()` returns the `Base.*` key; compatibility is not guessed from
a name/category or a nonexistent `isAmmo()` method. Unknown modded items have no assumed price.

Whole-basket checks preserve existing food/water/treatment reserves, best carried melee capability,
compatible ammo/magazines and queued/claimed base job requirements. Real incoming replacements may
cover food/water/medical/melee/task reserves. Need urgency, carried stock and canonical job demand
affect value. Incoming duplicate utility falls with the whole basket, independent of selection
order; equivalent food portions retain equivalent value. Trust/reputation reduce a bounded spread,
but never eliminate it. Quotes contain a deterministic fair/low indication, not random acceptance
rolls. Values are initial barter utility, not vanilla prices or proof of a balanced economy.

Native 42.20.3 `ISTradingUI` resolves `getPlayerByOnlineID` and sends network trading messages.
Its unmodified multiplayer protocol cannot be used for off-slot bodies. `KS_TradeUI` uses native
collapsable-window, scrolling-list and button widgets, fonts, item icons and checkmarks instead;
it never registers the survivor as a real local/network player. The existing survivor context menu
exposes Trade for independent/non-player-owned survivors, with hostile/distant/multiplayer guards.
The stock lists expose only supported unlocked real items; reserves remain subject to the whole
basket quote. Selecting items does not move them. Quotes show fair/low or a concrete refusal reason.
Stock refresh is limited to once per second; selection changes explicitly refresh the quote.

`beginBrowse` acquires the same controller lease as an exchange, for at most two wall-clock minutes
or 7200 controller ticks. Closing, changing scenes/resolution, player death, distance, danger or a
new directive releases it. One window exists per actual local player viewport. Mouse and joypad
callbacks select real item references. `queue(..., session)` validates and hands off that exact
lease to one exchange action; stale browsing cleanup cannot release a newer owner. Closing during
the action cancels that trade before completion, not unrelated queued actions. One exchange is
allowed per window; reopen for another. Successful stock refresh cannot hide a failed queue result.

`KS_TradeAction.queue` provides the single-player exchange action used by that window.
It uses a short player `ISBaseTimedAction` and an identity-bound `TRADING` lease on the existing NPC
controller/runtime. It declines native traversal, active actions, claimed work and perceived danger;
it cancels existing movement only after those checks. The normal threat scanner remains active.
Combat, flee, new directives, detachment and shutdown cancel the lease; release cannot overwrite
a newer behavior. A 1800-controller-tick ceiling bounds the exchange-action lease. Persistent duty,
group/camp and identity records are not rewritten by the lease.

Completion rechecks real offers, canonical relationships, adjacent unobstructed squares, vehicles,
hit/attack state, native source-removal/destination-add rules, item ID collisions and root inventory
capacity. Native `hasRoomFor` receives net root weight; nested outgoing weight is conservatively
not credited, so a valid crowded bag trade may need more room. Both offers then move through native
`ISTransferAction.transferItem` in one non-yielding callback, with original instance/container
receipt checks. No fake TradeUI/floor stockpile or type-based item recreation is used. The existing
survivor snapshot must succeed before mutation and after both transfers; only then is bounded
trade reputation recorded. Reputation failure cannot reverse or repeat a completed exchange.

Transfer/final-capture failures restore the original item instances to their original containers
using native `AddItem(instance)` and verify both sides. The pre-exchange encoded survivor record is
retained if a restored inventory cannot be recaptured. Unexpected rollback/persistence-recovery
failure retains the journal's actual references in `KnoxTradeActions.failedExchange`, logs
`RECOVERY_REQUIRED` and blocks further trading for the session. This is a diagnostic stop, not a
durable recovery ledger or proof against process crashes. Ordinary cancel/queue removal before
completion never mutates inventory. Multiplayer is explicitly rejected; no network protocol is
being simulated. The window reports recovery failure and instructs testers to stop and retain logs;
it does not offer an unsafe retry. Rarity sourcing, additional medical/material classes, broader
currency coverage, durable fault recovery and live UI/save/animation/economy evidence remain unfinished.

## Native wallets and physical currency

`media/registries.lua` registers the namespaced `knoxsurvivors:wallet` ItemBodyLocation through the
native ModRegistries entry point, before script loading. Shared `KS_Wallets` requires the native
Human body locations and adds that location. After script loading, it changes only CanBeEquipped
on the four existing Base wallet container definitions (Wallet, Wallet_Female, Wallet_Male and
Wallet_Hide). Removed definitions or replacements that are no longer containers are skipped. No
item types are replaced and no contents, weights, capacity, sound, icons or acceptance rules change.
Other mods that alter those wallets' wearing slot may conflict; this is not a key-ring tag patch.

Exact 42.20.3 evidence: native inventory menus recognize `InventoryContainer.canBeEquipped`, native
`ISWearClothing.complete` calls setWornItem, and ISInventoryPage lists worn containers. Key rings
have a separate tag-based UI path and are not wearable examples to copy. InventoryContainer's load
restores contents while its wearing location comes from the item script/factory. Knox's existing
native-payload snapshot and worn-flag restoration therefore retain the same wallet type, contents
and slot alongside a backpack. Existing equipment evaluation can wear a carried wallet without a
new NPC action, model, automatic free wallet or per-tick inventory scan. The wallet has no added
visible 3D attachment. Unequip it before disabling the mod so a save does not retain a removed slot.

`KS_Currency` recognizes only real Base.Money, MoneyBundle, SilverCoin and GoldCoin objects. It
returns read-only descriptions, not an account balance. Cash bundles use the exact native recipe
ratio of 100 bills. Cash stock saturation counts bill equivalents so unpacking does not manufacture
value. Coins have initial barter utility, not claimed real-world/vanilla monetary values. Existing
quote needs, stock, relationship spread, reserves, item ownership and verified exchange govern
payment. Currency can be selected inside a worn wallet; a favorite/hidden wallet protects contents.
Trade receipts still go into normal root inventory, and players can move them with native inventory
controls. No automatic change, currency generation, account ledger or NPC-specific money storage.

Native wallet acceptance permits maps/literature/FITS_WALLET items with its original capacity 1
and maximum item size 0.2. Bills and gold/silver coins have FITS_WALLET; MoneyBundle does not. Native
UnbundleMoney is the way to put that cash in the wallet. Large gold bars cannot be squeezed into it.
Bars remain protected by cleanup but are not priced until conversion/rarity policy is verified.
Cleanup also explicitly protects cash bundles and both coin types instead of discarding bundled
cash as native-category Junk. Further currencies, precious-metal conversion, hiring contracts,
economy balance and live wallet/trade persistence remain separate unfinished work.

## Building entry policy

Entry selection belongs to the controller; crossing the selected edge belongs to the
traversal executor. The intended preference is:

1. Let the native path use an already-open edge or open a closed, unlocked door/gate.
2. If that preferred edge fails, select another usable door before a window where the
   target room exposes both choices.
3. Open a usable window through the native state, then climb through only after the
   window is genuinely passable. Open or broken windows still use native climbability.
4. Temporarily suppress only the failed XYZ edge and retain the original destination so
   another entrance, low fence, or other human-accessible route remains eligible.
5. Optional loot abandons and cools down a room when every scanned entry fails. Only urgent
   food, water, or medical needs may force the door with sufficient endurance.

Build 42 completes the world-state portion of `OpenWindowState` only for a local player.
The off-slot NPC traversal adapter therefore waits for the engine animation variable
`StopAfterAnimLooped=success` before calling the normal `IsoWindow.ToggleWindow(...)`
completion. It must not toggle on an attempt, struggle, or failed animation. This keeps
the animation, sound, exertion, lock outcome, alarm behavior, sprite change, path-map
invalidation, and synchronization in their engine-owned sequence without assigning the
NPC a local-player slot.

Barricaded or otherwise unsafe openings may be rejected. Forced entry must preserve
normal time, noise, equipment, injury, and zombie-attraction consequences. Ordinary
traversal never initiates window smashing. The current traversal slice executes native
door/gate opening and window, frame, fence, and climbable-wall states on an already selected
route edge; deliberate locked-door breaching remains a separate, survival-need-gated action.
Traversal must never delete an obstacle, fake passability, teleport across it, or alter its
health directly.
## 2026-08-31 native feedback boundaries

- Single-player survivor labels use vanilla text/camera projection and the real viewing player's
  `CanSee` plus NPC alpha. `showTag` is multiplayer faction metadata, not an SP rendering switch.
  Relationship lookups are cached at the existing 15-tick update; no NPC claims a viewer slot.
- Clothing replacement evaluates native mutually exclusive body locations, not just the exact
  worn slot. The native worn collection remains authoritative; unreadable metadata rejects upgrades.
- `KnoxSwipeStateTransformer` also handles one **audio-only** check in exact 42.20.3
  `CombatManager.attackCollisionCheck`: bytecode 1628 `IsoPlayer.isLocalPlayer()`, followed by
  the branch to 1822 and `HandWeapon.isRanged`. Same-length virtual-to-static substitution preserves
  the operand stack, exception tables and native impact body. Any shape mismatch fails closed.
  It does not grant local-player status to other combat, input, networking or rendering systems.
  The original three SwipeStatePlayer callback substitutions remain unchanged.

## Knox Events: persisted lifecycle and raid roster boundary

`KS_KnoxEvents` owns `KnoxPersistence.getKnoxEventState()` (additive Lua schema 14).
Event records contain IDs, phase/revision/timestamps, source and target base identity,
location fingerprints, and canonical survivor IDs. They never contain alternate actor,
inventory, health, faction, or companion records. Existing native survivor snapshots
remain authoritative. The event service does not write survivor duty or allocate actors.

The shared phase graph is scheduled -> spawning -> approaching -> active -> objective
-> withdrawing -> completed, with cancellation/failure edges. Callers supply the expected
revision; stale callbacks cannot advance a newer phase, and repeated same-phase callbacks
are idempotent. Timers may invalidate a plan or request withdrawal, but cannot manufacture
an arrival, victory, loot transfer, or completed return. An interrupted/deployed party
retains its roster until an actual dispatcher cleanup result. Malformed deployed metadata
also retains that roster for recovery instead of silently releasing potentially live actors.

The first policy is a raid proposal using an existing hostile faction relationship,
existing source/target bases, and living canonical source-faction residents with native
snapshots. No claimed job or away-team member is borrowed. At most 40% of the living
roster is proposed, with at least two available residents left home; five residents can
send two. Roster/ownership/location and remaining home strength are rechecked before
departure. Proposals do not override existing work: a member becoming unavailable cancels
an unstarted plan. `KS_EventRuntime` checks live health/loadout and takes a temporary
`duty.eventId` binding through all-member persistence validation. The base duty itself
retains home, faction, order, and job preferences. Base claims and Away Teams reject
event-bound residents. Releases compare the event ID and never overwrite a newer owner.

Maintenance uses the existing population interval, handling up to 16 records per call
(explicit maximum 32), with a persisted round-robin cursor. Finished history expires after
seven game days and is pruned toward 128 entries in bounded batches. A separate expiring
per-faction cooldown retains the 24-hour scheduling limit even when history is pruned.
These are initial internal policies, not new player-facing sandbox settings.

Explicitly scheduled raids now dispatch ready loaded residents; there is still no random
raid scheduler. `spawning` is the shared claim phase, not permission to create replacement
members. The runtime inspects up to eight events every 30 controller ticks. Controller
projection is transient: EVENT_TRAVEL/EVENT_WAIT yield to existing combat and self-care,
use normal native movement/pace requests, retain existing retry cooldowns, and reuse group
follow/regroup logic. Arrival points are distinct and outside the target building on the
approach side; short loaded segments lead toward an unloaded destination. Repeated route
failures or a member fleeing request whole-party withdrawal. No coordinates are written
on active actors, no local-player slot is claimed, and no combat state is forced.

Wholly stored event parties use the existing `advanceStoredGroup` cohort scheduler, not
parallel event physiology. It preserves relative positions, uses the weakest member's
endurance/fatigue for shared rest, advances real stored food/water consumption, and commits
route state back through the event's expected revision. A mixed loaded/stored party waits
for regroup rather than moving its hidden half independently. Individual stored updates
cannot snap event-bound base residents back to ambient home coordinates. A surviving
single-member withdrawal is supported; released members no longer block its cohort.

Loaded arrival at the target advances to active; offscreen arrival does not fabricate
combat/objective completion. Withdrawals release members when their real loaded square or
persisted virtual route reaches home. Death or a replaced duty resolves only that member;
a removed/lost home fails the event and retains faction identity under autonomous duty.
Malformed deployed records remain reserved for recovery rather than pretending to return.

Stored residents use fresh persisted physiology/home state plus a read-only decode of their
real equipped native item before an all-member event claim; this never reconstructs a body or
defaults equipment. Automatic scheduling runs only at the existing population interval and
uses a persisted next-check/cursor. It considers established explicitly hostile factions with
real bases and eligible real rosters, permits one automatic event at a time, rejects targets
over 600 tiles away, and then enters the same proposal/dispatch/objective path. Default sandbox
policy allows the first check after day seven and spaces successful checks by seven days.
Disabling automatic raids prevents new schedules but does not erase a deployed party.

Actual live raid combat/loot/return evidence and the other Knox Event faction policies remain
unfinished. Native human combat remains the existing authority and still needs its documented
live evidence. Named event factions may not bypass this common persistent-survivor lifecycle.

`KS_EventFactions` is the read-only catalog for Police, Scientists, Military, Black Division,
Scavengers and PMC policy identity. Catalog entries contain only naming, world-age, base,
objective, persistence and future loadout-theme constraints. They grant no actor, item, skill,
accuracy, damage, health or relationship state. When an existing ordinary NPC faction is bound
to one policy, `faction.eventIdentity` records the policy/source event on that same canonical
faction; survivor affiliation, duty, inventory and relationships remain in their existing domains.
Malformed identity metadata is dropped during save normalization and a faction cannot be rebound
to a different event identity. The catalog does not yet spawn or trigger a named faction.

Named-event entry preparation reuses the cached world population catalog. It chooses one unused
ground-floor player/building-spawn anchor within a bounded ring of the event target, rejects points
within 60 tiles of any supplied local player, and derives up to six compact distinct origins around
that anchor. `createEventFactionPopulation` preflights the full batch, allocates ordinary
population-managed `ks-world-*` identities, one normal travel group and one normal NPC faction in
one non-yielding persistence transaction. A failed allocation removes every new identity and
restores its world-ID serial; retrying the same source event returns the existing faction.

Before first real materialization, event entrants retain `pendingMaterialization` and wait at the
entry anchor rather than independently advancing the ordinary roaming itinerary. Normal hidden,
loaded, distance and standability gates still decide when each body may appear. The first real
capture clears entry waiting and transfers physiology/location ownership to the existing native
snapshot path.

Named arrivals now use `kind=faction_entry` in the same persisted event ledger. Scheduling stores
only policy, objective, party size and target; it creates no survivor. At due time the runtime
claims `scheduled -> spawning`, selects one safe cached-world anchor, invokes the idempotent entry
allocation, and commits faction/member/group identity plus every member's temporary `duty.eventId`
in one ModData transaction. A persisted 15-world-minute retry prevents missing-origin attempts
from becoming an update storm, while retry after reload remains safe because source-event binding
cannot allocate a second faction.

Entry parties use distinct common approach/return points and the existing loaded EVENT_TRAVEL and
stored-cohort movement. An incomplete mix of materialized and unmaterialized members waits rather
than splitting into independent itineraries. Real loaded positions establish arrival; no timer
fabricates it offscreen. The initial shared objective is deliberately only a bounded one-hour
presence state allowed by the selected policy. It grants no loot, combat outcome, faction-specific
behavior or items. Withdrawal returns toward the saved entry anchor, releases temporary event duty,
and leaves every surviving identity in the ordinary faction/world population.

The destructive developer action **Schedule Police Entry Here** is the first explicit live harness.
It is not an automatic Police event and does not yet apply themed appearance/loadouts. Automatic
named triggers, real faction objectives, disposition realization, loadout realization and
persist-after-event policy differences remain later event-runtime responsibilities.
