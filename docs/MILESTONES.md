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

The next vertical slices are animal care and repair. Storage hauling, guard, patrol,
one-plank barricading, crop maintenance, tree cutting, log-to-plank production, and corpse
hauling now have initial executors. Each slice must consume real tools and materials where
applicable, use normal timed actions, respect survivor skills, and survive reload before the
next one is added.

After those jobs: the full Survivors Notebook, companion/base roster management, contextual
conversations and favors, firearms, vehicles, camps, raids, away teams, and unloaded-world
simulation. Multiplayer remains compatibility-only until authority and replication are
designed and tested.

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
