# Knox Survivors

Knox Survivors is a ground-up Project Zomboid 42.20 mod that represents autonomous human survivors with `IsoPlayer` engine objects.

The long-term goal is for survivors to make decisions and use the same world-facing mechanics available to a player: movement, combat, inventory and equipment, looting, doors and windows, barricading, medical care, vehicles, camps, relationships, and persistent identity.

This repository is at the foundation milestone. The current build proves the Lua mod and Java agent load paths only. It does not yet spawn an NPC.

## Development layout

- `mod/` contains the Project Zomboid mod package.
- `java/` contains the Java agent and engine integration code.
- `docs/` contains architecture decisions and milestone acceptance criteria.
- `local.properties` contains machine-specific game and Workshop paths and is not committed.

## Build and deploy

```powershell
.\gradlew.bat clean build deployDev
```

The development targets are configured in `local.properties`. `deployDev` copies the loadable mod to `C:/Users/Gary/Zomboid/mods/KnoxSurvivors` and stages the Workshop package under `C:/Users/Gary/Zomboid/Workshop/KnoxSurvivors/Contents/mods/KnoxSurvivors`.

## Launching a development test

Double-click `Run Knox Survivors Dev.bat` in the repository root. It performs the following sequence every time:

1. builds the current Java agent;
2. deploys the current mod files to the local test and Workshop staging folders;
3. verifies that `ProjectZomboid64.bat` points at the newly built agent;
4. records the current log positions;
5. launches Project Zomboid through that patched batch file;
6. monitors the game and collects only the new log output after it closes.

Each run writes local diagnostics under `dev-runs/<timestamp>/`, including the new console output, the new Knox agent output, Knox-specific events, and a filtered possible-issues report. `dev-runs/` is ignored by Git and is never pushed to GitHub.

Do not use Steam's normal Play button for Java-agent development tests. Steam updates may replace the patched launcher; the development launcher detects that condition and stops with an explanation instead of silently starting without the agent.

To verify the complete build and deployment without opening the game, run:

```powershell
.\tools\run-dev.ps1 -BuildOnly
```

The Project Zomboid launcher must load the generated agent jar with `-javaagent`. Launcher changes are managed separately because Steam updates can replace them.

## Current acceptance gate

See [docs/MILESTONES.md](docs/MILESTONES.md). The next runtime gate is one stable `IsoPlayer` NPC that spawns, renders, moves, unloads, reloads, saves, and is removed without occupying or corrupting a local player slot.
