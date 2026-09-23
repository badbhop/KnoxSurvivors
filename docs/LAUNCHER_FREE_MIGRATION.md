# Launcher-free Workshop migration

## Goal

This document describes the long-term **zero-setup** target. The immediate Windows
route is the one-time Steam Java-agent option documented in `README.md`, which keeps
the current Java runtime and makes the external launcher optional. That route does
not require this native-backend migration. Do not treat the migration below as an
approved rewrite or as proof of parity on the currently installed game build.

A player subscribes to Knox Survivors in Steam Workshop, enables the mod in the
normal Project Zomboid menu, and starts the game through Steam. No separate
launcher, JVM argument, copied JAR, edited game JSON, or manual installation is
required.

The existing Java runtime remains the compatibility path through the Steam launch
option or optional launcher until the native runtime passes the acceptance gates
below. Do not retire that runtime while the Workshop-only backend is incomplete.

## Confirmed boundary

The current release architecture cannot meet this goal through packaging alone.
The game starts with only `projectzomboid.jar` on its configured classpath and
does not add the Knox Workshop JAR as a Java agent. The Steam launch option or
launcher supplies the required `-javaagent` argument before the game JVM starts.

Workshop `javaJarFile` and `javaPkgName` metadata do not start a Java agent. Other
installed Workshop projects that declare those fields still require users to copy
a JAR into the game directory and add a `-javaagent` argument. Dynamic attachment,
editing Project Zomboid's installation, or replacing game classes would preserve
the same trust and support problems as the launcher and are not acceptable.

Project Zomboid Build 42.20 does expose `IsoSurvivor.new(...)` to Lua. The shipped
class is a real `IsoLivingCharacter`; it owns a survivor descriptor, inventory,
equipment, moodles, health, animation state, pathfinding fields, vehicle state,
and registration in the cell survivor list. It avoids the renderer's exact-class
`IsoPlayer` exclusion and does not overwrite the global local-player singleton or
the local player's LOS channel.

`IsoSurvivor` is therefore the preferred Workshop-native body candidate. It is
not a drop-in replacement for the current `KnoxIsoPlayerShell`. Build 42's current
combat animation callbacks gate important collision and sound work behind local
`IsoPlayer` checks, player reload actions expect player-only behavior, and the
current Java runtime owns movement lifecycle, traversal, records, combat cleanup,
and shell safety. These gaps must be replaced deliberately in Lua.

## Architecture

Keep the stable Knox domain model unchanged:

- survivor IDs and persisted survivor records;
- affiliation, groups, factions, relationships, bases, work areas, and orders;
- dialogue, personalities, needs policy, jobs, storage, and unloaded simulation;
- save schema and migration rules.

Put all loaded-body operations behind one Knox runtime interface. The existing
Java bridge is one implementation during migration. The Workshop-native Lua
implementation is the release target.

The runtime interface owns:

- spawn, restore, lookup, hibernate, death, corpse conversion, and removal;
- equipment, clothing, inventory snapshots, health snapshots, and record capture;
- route start, route tick, cancellation, pace, traversal, and stuck recovery;
- melee, shove, firearm preparation, firing, damage, reactions, and cleanup;
- vehicle entry, seat ownership, driving input, exit, and recovery;
- diagnostics used by automated QA.

Gameplay controllers must call this interface instead of reading
`KnoxJavaBridge` directly. This lets the native backend be tested beside the Java
backend without changing saves or duplicating the survivor simulation.

## Native implementation order

1. **Body lifecycle**
   Create an `IsoSurvivor` from the persisted descriptor, register it in the
   square/cell, restore clothing and inventory, map it to the stable Knox ID, and
   remove it without leaving moving-object, model, survivor-list, or descriptor
   references behind.

2. **Save compatibility**
   Read the current encoded Java records and write the existing Knox survivor
   schema. Preserve IDs, names, appearance, inventory, health, affiliation,
   orders, base membership, relationships, and position. A save may move from the
   Java backend to the native backend without spawning a duplicate or losing a
   survivor.

3. **Movement and traversal**
   Drive inherited pathfinding and animation state from Lua. Implement one owner
   for movement requests, bounded retries, progress checks, door/window/fence
   traversal, floor validation, route cancellation, and clean return to the
   durable order. Do not teleport as normal locomotion.

4. **Inventory, health, and needs**
   Use the native character inventory, worn items, attached items, moodles, and
   body damage where exposed. Adapt timed actions that require `IsoPlayer` so
   survivor jobs cannot hijack the local player's queue or silently fail.

5. **Combat**
   Build a native-survivor combat executor that owns target validation, facing,
   range, animation, hit timing, damage, endurance, weapon condition, reactions,
   blood, sound, death, and friendly/neutral/hostile policy. It must not depend on
   the Java transform that relaxes `SwipeStatePlayer` local-player gates.

6. **Firearms**
   Preserve weapon preference and Aiming skill. Implement magazine, chamber,
   loose-ammo, rack, jam, reload, recoil, range, hit chance, projectile/tracer
   presentation, sound/world noise, damage, ammo consumption, and melee fallback
   against the native body. Do not treat the legacy `IsoSurvivor.DoAttack` ammo
   check as complete modern firearm behavior.

7. **Vehicles**
   Validate passenger entry and exit first. Then implement seat reservations,
   player seat changes, NPC driver ownership, road routing, obstruction recovery,
   safe stopping, and hibernation rules without assigning an NPC to a local-player
   slot.

8. **Cutover**
   Make the native backend the default only after all acceptance gates pass.
   Remove the JAR and launcher requirement from the Workshop payload and text.
   Keep one release rollback package until migrated saves have been verified.

## Acceptance gates

The launcher-free build is releasable only when a normal Steam launch passes all
of the following:

- no `KnoxJavaBridge`, Java agent, modified game JSON, or external executable is
  present or required;
- existing Knox saves load with the same survivors and no duplicated bodies;
- spawn, unload/reload, save/reload, death, corpse creation, succession, and
  removal work across repeated sessions;
- survivors render correctly and never replace the local player, camera, input,
  UI, LOS, or split-screen state;
- follow, hold, guard, patrol, formation, map travel, doors, windows, fences, and
  multi-floor routes complete or fail cleanly;
- melee, shove, knockdown, firearms, reloads, damage, death, faction combat, and
  friendly-fire rules work for player, zombie, and survivor targets;
- inventory, eating, drinking, medical care, storage, jobs, hauling, and base
  autonomy work without player-only timed-action failures;
- companions can enter vehicles, change seats safely with the player, and exit;
- independent groups can travel and use vehicles without stealing player seat or
  input ownership;
- automated Lua QA, syntax checks, save migration fixtures, and one comprehensive
  live test pass from a clean Workshop subscription.

## Decision

Do not invest further in launcher auto-update or Workshop JAR loading as the main
installation path. Preserve the current Java runtime as a known-good comparison
while implementing the native backend. Retire the launcher after native parity,
save migration, and a clean subscribed-copy test are complete.
