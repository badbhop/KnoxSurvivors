# Knox Survivors

Knox Survivors is a survivor/NPC mod for Project Zomboid Build 42, inspired by the idea behind Superb Survivors but rebuilt from the ground up by **.exe**. The goal is simple: add other human survivors without making Project Zomboid stop feeling like Project Zomboid.

The rebuild uses human, player-based NPC bodies and leans on the game's existing clothing, items, animations, world objects, combat systems, containers, farming and other vanilla systems wherever practical. Survivors are meant to feel like people trying to stay alive in the same world as you, not disposable followers or a free army.

**Current release candidate:** `0.3.0-rc1`, targeting Project Zomboid Build `42.20–42.21`.

**Build 42.21 compatibility is still being tested and is not yet verified.**
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

## Java runtime

Knox Survivors uses the separate KnoxBridge Runtime. Subscribe to both Workshop
items after KnoxBridge is linked as a Required Item. The Bridge Workshop item
provides the dependency marker, compile-time API, and setup/mod-author guides;
it does not install the runtime. Download the player setup package from
[KnoxBridge Releases](https://github.com/exe-create/KnoxBridge/releases/latest).

- **Windows:** run `KnoxBridgeSetup.exe`, choose install/update, and follow the
  prompts. It uses Project Zomboid's bundled Java; no separate Java install is
  needed.
- **Linux/macOS:** extract the release ZIP, close Steam, and run
  `sh scripts/setup-unix.sh` from the extracted folder. This requires Python 3
  and edits only the selected Steam account's Project Zomboid launch option.
  This route is implemented but has not been live-verified on either OS.

Enable KnoxBridge Runtime and Knox Survivors in the PZ Mods menu and start
through Steam. The Bridge-owned **Review Java Mods** gate opens at the main menu
and lists enabled-mod JARs before world entry. Unknown hashes stay blocked until
allowed. Turn on **Remember choices** to save exact-file allow/deny decisions
across launches; leave it off to apply them once. Restart only when a choice
changes which Java modules load. The displayed author is unverified metadata.
Java modules run with the game's full account permissions; KnoxBridge is not a
sandbox. This alpha8 Bridge UI update is staged but still needs a live Build 42
replay before its behavior can be called verified.

KnoxBridge loads only enabled PZ mods that declare its module descriptor and
implement the KnoxBridge API. Existing Java mods for other loaders do not load
automatically; their authors must port or explicitly support KnoxBridge.

The old Knox Survivors Launcher is deprecated and unsupported. Use only one
Java instrumentation runtime in a game process.

Use a new disposable save for testing. Runtime installation changes startup
configuration, not save files, but Knox gameplay/save compatibility is not
certified for important existing saves. Back up any save before testing. The
Knox Launcher is no longer a supported startup path; never combine a legacy
Knox agent with KnoxBridge or another instrumentation runtime.

## Confirming the runtime loaded

After reaching the Project Zomboid main menu, check
`%USERPROFILE%\Zomboid\KnoxBridge\knoxbridge.log` for a fresh
`module loaded id=com.knoxsurvivors.knox-module` line. Check
`Documents\Zomboid\KnoxIsoPlayer.log` for Knox module and patch diagnostics.

The most version-sensitive code remains Knox's narrow bytecode edits in `CombatManager`, `SwipeStatePlayer`, and `IsoZombie`. A Project Zomboid update or another Java mod patching the same exact methods still requires live compatibility testing.

Developer runtime/migration/signing details are consolidated in `docs/production/RUNTIME_AND_MIGRATION.md`.

## Support and testing

Windows is the primary test platform. For a useful bug report, include what the survivor was doing, your Project Zomboid version, whether the save was fresh, and the relevant `console.txt` / `KnoxIsoPlayer.log` files after checking them for personal information.

Discord: https://discord.gg/cTfd2WWD4s

## Development documentation

The Git repository contains internal production, architecture, design and test
records for maintainers. They are not part of the Workshop mod download or the
player installation package, and they are not player-facing feature promises.

ModForge is optional for development. It can index the canonical production
records, show tasks/bugs, prepare handoffs and regenerate its coordination
snapshot, but Codex, OpenCode and human contributors can work normally from
`AGENTS.md`, Git and `docs/production/` without ModForge installed or running.

OpenCode has two explicit local profiles. The default free profile is started
with `scripts/start-opencode.ps1`; it uses only the configured free model IDs.
The optional OpenCode Go subscription profile is started with
`scripts/start-opencode.ps1 -Profile go`; it uses only `opencode-go/...` models.
The profiles are separate, and the free profile never falls back to Go or a
paid API route automatically.

## Ownership and permission

Knox Survivors' original code and project framework were built from the ground up and are owned by **.exe**. Superb Survivors is an inspiration for the survivor-mod concept, not a source-code dependency of this rebuild. Project Zomboid and its base-game assets belong to The Indie Stone.

This repository is not open source. No permission is granted to copy, modify, redistribute, repackage, publish or reuse Knox Survivors code without written permission from .exe. See `LICENSE.md`.
