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
New identities originate from the map's real spawn-region point tables. A candidate is
rejected when its square is currently visible, occupied, unsafe, or too close to a
player. A valid identity may originate in another town and remain virtually simulated
until its cell loads; loading a cell activates the survivor at their recorded location
instead of relocating them toward the player.

The production population core now maintains a configurable persistent target, defaults
to 16 living identities, and limits physical materialization separately from world count.
Initial allocation is region-balanced across real player-spawn definitions. Death is durable
and does not trigger an immediate nearby replacement; after the configured refill interval,
one new identity is allocated at a still-unused origin. Active world survivors hibernate
when they leave the player band and restore at their saved square when that area becomes
relevant again. Developer scenarios remain available as a separate bounded test harness for
social, faction, base, and companion behavior.

## Minimal active-survivor loop

The first playable survivor is intentionally a small priority controller, not a complete
planner. Each decision update selects one state, and only one action owns the body:

1. **Threat** — flee when unsafe, otherwise equip and engage one nearby zombie.
2. **Injury** — stop somewhere safe and treat the most urgent wound with a carried item.
3. **Loot need** — approach one reachable container and take a small ranked set of useful
   items through normal inventory transfer actions, based on current equipment and stock.
4. **Idle travel** — choose a nearby reachable destination and walk there.

The controller chooses *what* to do. Small action executors own *how* to move, equip,
attack, transfer, or treat. Threats may interrupt travel and looting; an executor must
finish, fail, or be cancelled before another executor writes movement or combat input.
This keeps combat, inventory, and medicine independently testable.

The survivor initially uses the engine's real inventory, equipped-item slots, combat
pipeline, and `BodyDamage`. Knox persists a portable snapshot of those values rather
than treating the live `IsoPlayer` object as the save record. Directly applying damage,
teleporting items, or healing wounds is reserved for unloaded-world simulation; an
active survivor should use the same world actions and consume the same items as a player.

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

The shell supplies its controller-owned forward direction as its aim vector because it
has no mouse or controller input component. The combat executor synchronizes the human
AI control variables, target square, facing, charge, and attack request. If the normal
request does not enter `SwipeStatePlayer`, the executor makes one explicit state entry
and records that fallback in the diagnostic log. This is intentionally limited to
melee; firearm aiming and ballistics require a separate verified slice.

Combat approach targets are placed inside the equipped weapon's maximum range with
enough margin for the movement executor's arrival tolerance. A generic adjacent-square
center is not a valid melee stopping distance: it can report arrival while the weapon's
collision volume still cannot reach the target.

Live zombie targets are not treated as stationary after the first approach. If a target
moves beyond the equipped weapon's effective attack margin, the combat executor clears
the stale swing request, paths back into range, and then settles its aim again. Locked-door
combat remains fixed in place and does not use this re-approach rule.

Threat awareness distinguishes immediate proximity, visible zombies, and zombies already
targeting the survivor or a travelling companion. Active threats receive priority over an
idle visible zombie, and at most two survivors reserve the same zombie. This avoids both
single-file indifference and the whole faction chasing one distant target.

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

Ungrouped survivors notice one another within 24 tiles, but social work never interrupts
combat or an unsafe action. One approaches while the other waits, avoiding artificial
teleporting or constant magnetic movement. Stable identity traits supply sociability and
aggression; pair history then resolves the encounter as joining, declining, or hostility.
Declines cool down for six in-game hours. The first hostile executor is robbery through
normal timed inventory transfers, limited to two unequipped items. Hostility persists;
lethal survivor-versus-survivor combat remains behind a separate native PvP verification
gate because the current combat executor is proven only against zombies.

Purposeful exploration considers useful nearby supplies before undirected roaming. A
survivor searches reachable containers for stronger melee weapons, better protective clothing,
a wearable bag, limited food/water/medical stock, and missing essential tools. They play
the search animation when an uninspected container is already convenient. A visit may take
up to two ranked items. Survivors then travel before considering another optional stop;
blocked rooms are cooled down instead of repeatedly forcing entry.

## Player companions and presentation

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
was taken. Farming zones now have a small maintenance executor: the resident discovers the
first ripe or dry seeded plant in the loaded zone, walks to it, and queues the vanilla harvest
or watering action. An empty suitable square can then be plowed and a carried seed sown as
separate persisted tasks, again using the vanilla timed actions and state verification. A
woodcutting zone likewise resolves a loaded tree, requires a real axe, and queues the vanilla
`ISChopTreeAction`; completion is accepted only after the tree object is removed. Log-to-plank
production resolves a carried log and saw, validates the vanilla `SawLogs` recipe, and queues
`ISCraftAction`; completion is accepted only after the source log is consumed. Corpse handling,
animals, and repair remain later action boundaries.
Barricade work is the exception: when a resident carries a hammer, plank, and
nails, the controller discovers an unbarricaded loaded window inside the base and queues the
vanilla `ISBarricadeAction`; completion is accepted only after a real plank count increase.
Vanilla crop ownership is not treated as a Knox survivor ID because single-player off-slot
bodies do not provide a stable unique crop owner.

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

## Building entry policy

Entry selection belongs to the controller; crossing the selected edge belongs to the
traversal executor. The intended preference is:

1. Try a window first. Open it normally; if it remains closed, smash it and climb through.
2. If there is no usable window, try the door normally.
3. If a selected door is locked, search the destination room for a usable window and
   route to that window instead.
4. Optional loot abandons and cools down a room when alternate entry fails. Only urgent
   food, water, or medical needs may force the door with sufficient endurance.

Build 42 completes the world-state portion of `OpenWindowState` only for a local player.
The off-slot NPC traversal adapter therefore waits for the engine animation variable
`StopAfterAnimLooped=success` before calling the normal `IsoWindow.ToggleWindow(...)`
completion. It must not toggle on an attempt, struggle, or failed animation. This keeps
the animation, sound, exertion, lock outcome, alarm behavior, sprite change, path-map
invalidation, and synchronization in their engine-owned sequence without assigning the
NPC a local-player slot.

Barricaded or otherwise unsafe openings may be rejected. Forced entry must preserve
normal time, noise, equipment, injury, and zombie-attraction consequences. The current
M1 traversal slice executes window open, smash, and climb states on an already selected
route edge. Room-wide alternate-entry planning and legitimate door destruction remain
separate gates; traversal must never delete an obstacle or alter its health directly.
