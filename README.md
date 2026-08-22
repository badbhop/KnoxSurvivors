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

The development deployment target is configured in `local.properties`. The current machine deploys to `C:/Users/Gary/Zomboid/Workshop/KnoxSurvivorsRebuild` so it cannot collide with the previous implementation.

The Project Zomboid launcher must load the generated agent jar with `-javaagent`. Launcher changes are managed separately because Steam updates can replace them.

## Current acceptance gate

See [docs/MILESTONES.md](docs/MILESTONES.md). The next runtime gate is one stable `IsoPlayer` NPC that spawns, renders, moves, unloads, reloads, saves, and is removed without occupying or corrupting a local player slot.
