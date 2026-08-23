# Knox Survivors

Knox Survivors is an NPC mod for Project Zomboid Build 42.20. It is being rebuilt from scratch around actual `IsoPlayer` characters instead of disguising zombies as survivors.

The idea is to make survivors feel like other people trying to live in the same world as you. They should be able to move around, fight zombies, find and carry supplies, use doors and windows, barricade buildings, get hurt, recover, and remember who they are between sessions. Later on this will grow into recruitment, groups, camps, base jobs, relationships, and factions.

This is still very early development. It is not ready to play as a normal mod yet.

## Where it is now

The Lua mod and Java agent load correctly in Build 42.20. We can spawn one visible human NPC without taking over the real player's slot. The current test is getting that NPC to walk to a nearby location using the game's pathfinding.

Population is deliberately locked to one survivor while the basic character lifecycle is being worked out. Movement, saving, loading, cell changes, and clean removal all need to be reliable before combat or looting is added.

The development checkpoints are kept in [docs/MILESTONES.md](docs/MILESTONES.md), and the main technical decisions are explained in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
The automatically enabled local test harness is documented in [docs/DEVELOPMENT_TESTING.md](docs/DEVELOPMENT_TESTING.md).

## Project folders

- `mod/` — Lua files and the Project Zomboid mod package
- `java/` — Java agent and engine-side NPC code
- `docs/` — milestones and architecture notes
- `tools/` — local build, launch, and log collection scripts

## Building locally

Copy `gradle.properties.example` to `local.properties` and fill in the Project Zomboid and Workshop paths for your machine. `local.properties` stays local and is not committed.

Build and deploy the development version with:

```powershell
.\gradlew.bat clean build deployDev
```

For the normal test loop, use `Run Knox Survivors Dev.bat`. It builds the latest code, deploys the mod, checks the Java-agent launcher setup, starts the game, and collects the new logs after the game closes.

To build and check the deployment without launching Project Zomboid:

```powershell
.\tools\run-dev.ps1 -BuildOnly
```

The Java side requires the development launcher because the agent has to be loaded when Project Zomboid starts. Steam's normal Play button does not do that.

## Current support

Development is focused on single-player Build 42.20. Multiplayer NPC AI is not supported at this stage.
