# Knox Survivors

Knox Survivors is a survivor/NPC mod for Project Zomboid Build 42, inspired by the idea behind Superb Survivors but rebuilt from the ground up by **.exe**. The goal is simple: add other human survivors without making Project Zomboid stop feeling like Project Zomboid.

The rebuild uses human, player-based NPC bodies and leans on the game's existing clothing, items, animations, world objects, combat systems, containers, farming and other vanilla systems wherever practical. Survivors are meant to feel like people trying to stay alive in the same world as you, not disposable followers or a free army.

**Current release candidate:** `0.3.0-rc1`  
**Target game version:** Project Zomboid `42.20.4`  
**Focus:** Single-player

## What is in the mod now

The current build includes working implementations of the following systems. They are still being polished and bugs are expected, but these are real parts of the mod rather than planned features:

- Persistent human survivors with their own identity, appearance, clothing, inventory, equipment, health, needs, traits, skills and relationships.
- A world population that can appear, roam, scavenge buildings, choose useful gear, eat, drink, rest, treat basic injuries and fight zombies.
- Melee combat and firearm/reload support using the current human NPC runtime. Firearms are newer and may be rougher than melee.
- Survivor meetings, dialogue, groups, factions and small camps/settlements.
- Recruitment and companion behavior, including Follow, Hold, Return to Base, Dismiss, Go To, Guard and loot-related orders.
- Player and faction bases with residents, work areas, storage categories and a task system.
- Base work including guarding, patrols, categorized storage/organizing, window barricading, farming, cooking, tree cutting, log sawing, corpse hauling/cleanup, and damaged-structure repairs.
- Companion HUD, survivor information/cards, inventory interaction, activity messages and the current Survivors Notebook work.
- Save/load support plus hibernation/off-screen survivor simulation so every survivor does not need to stay physically loaded at all times.

## What is not being promised yet

This release candidate is not advertising unfinished systems as complete. In particular:

- Full multiplayer NPC support is not ready.
- Autonomous survivor driving/vehicle behavior is experimental.
- Raids and larger faction-event systems are experimental and are not a release promise.
- Away-team/resource missions are not complete.
- Full player-style base construction is not part of the current production job set. Current defense work is limited to supported barricading and repair behavior.
- Live Build 42 behavior can still expose pathing, combat, save/load or job bugs that offline checks cannot reproduce.

Use a fresh save for this rebuild and back up saves you care about. Migration from old Knox Survivors NPC data is not guaranteed.

## Java runtime options

Knox Survivors needs its Java runtime, but **ZombieBuddy is optional**. Players can use either supported startup path:

- **Recommended: ZombieBuddy.** ZombieBuddy loads Knox's `java/knox-agent.jar` automatically. Knox does not need its old `-javaagent` line or Knox Launcher on this path.
- **Alternative: Knox Launcher.** Players who do not want ZombieBuddy can keep using the Knox Launcher / legacy Knox Java-agent startup path.

Do not use both startup methods intentionally at the same time. Knox contains duplicate-start protection, but one runtime path per launch is the clean setup.

### Option A - ZombieBuddy (recommended)

1. Install/configure ZombieBuddy using its supported instructions.
2. Enable Knox Survivors. Enabling the ZombieBuddy mod is recommended when using its runtime.
3. Remove old Knox-only launch options such as `-javaagent:...knox-agent.jar=pz-game` and do not use `knox-steam-launch.cmd` for this path.
4. Launch Project Zomboid normally through the ZombieBuddy-configured game launch.
5. If ZombieBuddy asks whether Knox Survivors' Java JAR may load, approve it only if you trust the build.

Successful log entry:

`runtime start PASS source=zombie-buddy-patch-api`

### Option B - Knox Launcher (no ZombieBuddy)

1. Enable Knox Survivors.
2. Do not use ZombieBuddy for this launch.
3. Start Project Zomboid through the Knox Launcher / existing Knox legacy Java-agent setup.
4. The launcher loads the same Knox `java/knox-agent.jar` through Knox's retained `premain` entry.

Successful log entry:

`runtime start PASS source=legacy-javaagent`

## Confirming the runtime loaded

After reaching the Project Zomboid main menu, check:

`Documents\Zomboid\KnoxIsoPlayer.log`

Look for a fresh runtime PASS line matching the startup method you chose. The combat callback and zombie visibility transformers also log their patch results when their target classes load or are retransformed.

If Java systems are unavailable, make sure you actually launched through one of the two supported Java-runtime paths. If using ZombieBuddy, also check whether it denied the Knox JAR and restart Project Zomboid after changing approval.

## Migration / rollback note

The ZombieBuddy integration changes the runtime bootstrap, not Knox's save schema or survivor record format. The legacy Knox `premain` entry remains in the JAR so the Knox Launcher remains a supported alternative for players who do not want ZombieBuddy.

The most version-sensitive code remains Knox's narrow bytecode edits in `CombatManager`, `SwipeStatePlayer`, and `IsoZombie`. A Project Zomboid update or another Java mod patching the same exact methods still requires live compatibility testing.

Developer runtime/migration/signing details are consolidated in `docs/production/RUNTIME_AND_MIGRATION.md`.

## Support and testing

Windows is the primary test platform. For a useful bug report, include what the survivor was doing, your Project Zomboid version, whether the save was fresh, and the relevant `console.txt` / `KnoxIsoPlayer.log` files after checking them for personal information.

Discord: https://discord.gg/cTfd2WWD4s

## Development documentation

The repository also contains internal production, architecture, design/research, audit and testing documents under `docs/`. Current engineering state lives in `docs/production/`; NPC design research lives in `docs/design/`. Those records may discuss incomplete work, test gates or future systems and are not player-facing feature promises.

## Ownership and permission

Knox Survivors' original code and project framework were built from the ground up and are owned by **.exe**. Superb Survivors is an inspiration for the survivor-mod concept, not a source-code dependency of this rebuild. Project Zomboid and its base-game assets belong to The Indie Stone.

This repository is not open source. No permission is granted to copy, modify, redistribute, repackage, publish or reuse Knox Survivors code without written permission from .exe. See `LICENSE.md`.
