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

The current integration gate runs this planner for two persistent identities at once.
Each owns its own action state, movement request, combat target, timers, and counters;
world-item and zombie reservations prevent both controllers claiming one target.

## M3 — World interaction

Success means the survivor can safely use doors and windows, climb permitted obstacles, and barricade one valid window using real carried materials and normal world actions.

The active integration now includes room-aware locked-door recovery: preserve the
container goal, try a usable perimeter window through normal open/smash/climb behavior,
then attack the door with the equipped weapon only when no window route succeeds. State
deadlines cancel stalled movement and timed actions and release their reservations.

## Later milestones

Recruitment, orders, base work, camps, factions, raids, away teams, vehicles, interfaces, and multiplayer authority are rebuilt incrementally after the core human lifecycle is stable.

Stable survivor IDs accumulate first/last meeting, nearby time, repeat meetings, and
shared survival activity. Two survivors can explicitly agree to form a travelling group.
An established group may invite a lone survivor through a separate consent dialogue.
Three members are necessary but not sufficient for faction formation: the newest member
must survive at least one day with the group and relationship history must show nearby
time or shared survival activity. Faction base
areas are a later integration and should reuse Build 42 safehouse boundaries if engine
inspection confirms they can safely represent NPC ownership.
