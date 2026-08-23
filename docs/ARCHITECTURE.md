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

## Minimal active-survivor loop

The first playable survivor is intentionally a small priority controller, not a complete
planner. Each decision update selects one state, and only one action owns the body:

1. **Threat** — flee when unsafe, otherwise equip and engage one nearby zombie.
2. **Injury** — stop somewhere safe and treat the most urgent wound with a carried item.
3. **Loot need** — approach one reachable container and take one useful item through a
   normal inventory transfer action.
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
- `SpawnRegionMgr.getSpawnRegions()` and region point tables in the shipped Lua layer.
- `isNpc()` players skip ordinary local-input movement, then consume
  `AIComponent.getHumanControlVars()` during `IsoPlayer.updateInternal2()`;
- normal inventory and equipment live on `IsoGameCharacter` through `getInventory()`,
  `setPrimaryHandItem(...)`, and `setSecondaryHandItem(...)`;
- player combat entry points and state exist on `IsoPlayer`, but must be verified with an
  off-slot NPC before selecting the supported attack sequence;
- injuries live in the normal `BodyDamage` and `BodyPart` objects, and the shipped Lua
  actions support a doctor and a separate patient.

These are confirmed entry points, not proof that an off-slot NPC is lifecycle-safe. Every affected subsystem must be tested in game.

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

## Implementation order

Engine pathfinding supplies a route, while Knox supplies human control intent to the NPC
component. Locomotion must pass before any other executor is added. The next supported
slice is then: inventory ownership and equip, one-zombie melee combat, one-container
transfer, normal injury reception, self-bandaging, and finally player-to-NPC treatment.
Each slice is live-tested alone and across save/reload before the next one begins.

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
4. Only when the room has no usable window may the survivor force the door using a real
   equipped tool or weapon and the normal destruction action.

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
