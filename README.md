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
- Base work including guarding, patrols, storage sorting, window barricading, farming, tree cutting, log sawing, corpse hauling/cleanup, trough feeding and watering, and damaged-structure repairs.
- Companion HUD, survivor information/cards, inventory interaction, activity messages and the current Survivors Notebook work.
- Save/load support plus hibernation/off-screen survivor simulation so every survivor does not need to stay physically loaded at all times.

Knox Survivors is intentionally a living-world mod. Independent survivors are expected to survive for themselves, meet other survivors, form groups, settle somewhere and sometimes die. Recruited survivors can travel with you or live and work at a base.

## What is **not** being promised yet

This release candidate is not advertising unfinished systems as complete. In particular:

- Full multiplayer NPC support is not ready.
- Autonomous survivor driving/vehicle behavior is experimental.
- Raids and larger faction-event systems are experimental and are not a release promise.
- Away-team/resource missions are not complete.
- Full player-style base construction is not complete; only the currently implemented limited construction/defense work should be expected.
- Live Build 42 behavior can still expose pathing, combat, save/load or job bugs that offline checks cannot reproduce.

Use a fresh save for this rebuild and back up saves you care about. Migration from old Knox Survivors NPC data is not guaranteed.

## Launching Knox Survivors

The Java runtime used by the current human NPC rebuild must be loaded when Project Zomboid starts. There are two supported ways to do that. **Use one method, not both.**

### Option A - launch normally from Steam on Windows

Subscribe to the Workshop item, let Steam finish downloading it, then open:

`Steam > Project Zomboid > Properties > General > Launch Options`

For the default Steam library, use:

```text
"C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\3749727604\mods\KnoxSurvivors\knox-steam-launch.cmd" %command%
```

If the Workshop item is in another Steam library, change only the path to
`knox-steam-launch.cmd`. The wrapper ships inside Knox Survivors and is updated by
Steam with the mod.

The wrapper does three things only for the Project Zomboid process it starts:

- puts Project Zomboid's bundled `jre64\bin` and `jre64\bin\server` first on that
  process PATH, preventing an unrelated system Java such as Zulu from supplying
  incompatible DLLs;
- preserves existing `JAVA_TOOL_OPTIONS` and appends the Knox agent;
- forwards the original Steam command and its launch options unchanged.

It does **not** edit Windows environment variables, `ProjectZomboid64.json`, the BAT
launcher, saves, sandbox settings or the enabled mod list.

#### Keep other Steam launch options

Do not delete launch options required by other mods.

If your existing options do **not** contain `%command%`, keep them after the game
placeholder. For example ZombieBuddy's Windows option becomes:

```text
"C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\3749727604\mods\KnoxSurvivors\knox-steam-launch.cmd" %command% -agentlib:zbNative --
```

If your existing options already contain one `%command%` wrapper, keep that existing
line intact and place the Knox wrapper path in front of it. Do not add a second
`%command%`.

The helper `tools/get-steam-launch-options.ps1` can discover the subscribed Workshop
path, verify the Knox JAR/checksum, and print the merged Steam line when
`-ExistingOptions` is supplied. It does not write Steam settings.

Remove any older Knox `-javaagent:...knox-agent.jar` launch entry before using this
wrapper so Knox is not loaded twice. Other compatible `-javaagent`, `-agentlib`,
`-agentpath` and game arguments are left in place.

Use Steam's normal Project Zomboid launch mode. The alternate BAT launch path is
separate and is not changed by this setup. A command window may be visible while the
game is running because the bootstrap is a Windows CMD file.

Preserving another mod's launch arguments does not guarantee that two mods patching
the same game code are gameplay-compatible; that still requires testing the actual
mod combination.

### Option B - Knox Survivors Launcher

The optional Knox Survivors Launcher verifies the Workshop install and runtime checksum, then starts the normal Project Zomboid executable with the Knox runtime enabled only for that game process. It does not patch the game, change your Project Zomboid memory setting, require admin access, or set permanent environment variables.

Launcher releases: https://github.com/exe-create/KnoxSurvivorsLauncher/releases

The launcher is useful if you do not want to maintain the Steam launch-option line, use multiple Steam libraries, want the install verifier, or need its custom launch-option/debug controls.

## Confirming the runtime loaded

After reaching the Project Zomboid main menu, check:

`Documents\Zomboid\KnoxIsoPlayer.log`

A successful startup should contain a new, timestamped `agent start arguments=pz-game`
entry for this launch. An older entry is not confirmation. If the activity feed says
the Java systems are unavailable, re-check the launch option or remove it before using
the launcher, then restart the game.

## Support and testing

Windows is the primary test platform. Linux and macOS launcher packages have automated checks, but real game behavior on those platforms can still differ.

For a useful bug report, include what the survivor was doing, your Project Zomboid version, whether the save was fresh, and the relevant `console.txt` / `KnoxIsoPlayer.log` files after checking them for personal information.

Discord: https://discord.gg/cTfd2WWD4s

## Development documentation

The repository also contains internal development, audit and testing documents under `docs/` plus release-readiness planning files. Those are engineering records and may discuss incomplete work, test gates or future systems; they are not player-facing feature promises.

## Ownership and permission

Knox Survivors' original code and project framework were built from the ground up and are owned by **.exe**. Superb Survivors is an inspiration for the survivor-mod concept, not a source-code dependency of this rebuild. Project Zomboid and its base-game assets belong to The Indie Stone.

This repository is not open source. No permission is granted to copy, modify, redistribute, repackage, publish or reuse Knox Survivors code without written permission from .exe. See [LICENSE.md](LICENSE.md).
