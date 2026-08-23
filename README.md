# Knox Survivors

Knox Survivors is being rebuilt from scratch for Project Zomboid 42.20. The new version
uses `IsoPlayer`-based NPCs instead of the old zombie shell.

The goal is to make survivors feel like real people living in the same world as the
player. They will eventually travel, loot, equip what they find, fight zombies, treat
injuries, build relationships, follow orders, work around bases, form camps, and keep
living when they are outside the loaded area.

This is an early test build, not a normal playable release yet.

## What works right now

- One visible human NPC can exist without replacing the real player.
- Basic pathfinding and movement work.
- The NPC can use doors, climb low fences, and handle open or locked windows.
- The NPC can compare carried melee weapons and equip the better one.
- New survivors receive randomized skin, hair, names, and real starting clothes.
- Some survivors have a small chance to start with a bag.
- Identity, map position, appearance, clothing, inventory, and equipped hands now have a
  first persistence implementation.

Combat, autonomous looting, medical care, recruitment, base work, factions, and normal
population spawning are not playable yet. The development population is still limited
to one test survivor.

## Current test

The active test checks appearance, equipment, and save persistence.

On the first load, a survivor appears near the player, receives randomized player-style
clothing, chooses between a hammer and baseball bat, and has their temporary NPC body
rebuilt. On the second load of the same save, they should return on the same tile with
the same skin, hair, clothing, inventory, and equipped bat.

If you are testing, please report:

- whether the survivor appeared clothed;
- whether their skin, hair, clothing, and colors stayed the same after reload;
- whether they returned in the same place holding the baseball bat;
- any repeated errors from `console.txt` or `KnoxIsoPlayer.log`.

Use a backed-up or disposable save. This is experimental engine work and may break a
test save.

## Running a development test

1. Clone or download the repository after receiving testing permission.
2. Copy `gradle.properties.example` to `local.properties` and set the four paths for your
   computer.
3. Build and deploy with `./gradlew.bat clean build deployDev`.
4. Configure `ProjectZomboid64.bat` to load the built Java agent. Ask in the Knox
   Survivors Discord if your test setup has not already been prepared.
5. Run `Run Knox Survivors Dev.bat`, enable Knox Survivors on the test save, and load it.
6. Quit normally after the result so Project Zomboid writes the survivor record.
7. Launch again and load the same save to test restoration.

The normal Steam Play button does not load the Java agent used by this rebuild.

More technical details are in [Development Testing](docs/DEVELOPMENT_TESTING.md),
[Milestones](docs/MILESTONES.md), and [Architecture](docs/ARCHITECTURE.md).

Discord: https://discord.gg/cTfd2WWD4s

## Permission

Knox Survivors is publicly visible, but it is not open source. No permission is granted
to use, copy, modify, redistribute, repackage, publish, or reuse the project without
asking first. Authorized testers may only use it for the testing permission they were
given. See [LICENSE.md](LICENSE.md).
