# Knox Survivors

Knox Survivors is being rebuilt from the ground up for Project Zomboid 42.20.
Survivors now use contained `IsoPlayer` NPC bodies instead of the old zombie shell, with
Knox owning their identity, decisions, relationships, inventory, health, and save data.

The aim is a living world, not a free army. Survivors should be rare people who find
supplies, fight, get hurt, meet one another, form groups, settle somewhere, and keep their
history. Recruited survivors will travel with the player or live and work at a home base.

This repository contains a development build. The Workshop version is still the older
release and does not include this rebuild yet.

## Current rebuild

The active three-survivor test currently covers:

- persistent identity, appearance, clothing, bags, inventory, equipment, health, and needs;
- independent movement, container searches, useful looting, and automatic equipment choices;
- melee combat against zombies with normal animation, damage, endurance, and weapon wear;
- doors, windows, low fences, locked-entry recovery, resting, eating, drinking, and first aid;
- survivor meetings, short dialogue, travel groups, three-person factions, base scouting,
  and protected faction safehouses;
- a small vanilla-styled activity feed for encounters and important events.

The latest development pass adds the next layer:

- persistent production world population allocated from real Build 42 spawn regions, with
  separate active limits, distance-based materialization, hibernation, and gradual refill;
- stable occupations, traits, perk levels, and XP tied to each survivor identity;
- persistent player relationships, recruitment, Follow, Hold, Return to Base, and Dismiss;
- a compact right-side companion HUD with live portraits, health, needs, equipment, and
  current activity;
- one HUD per local player with split-screen-aware placement and ownership;
- persistent player and faction bases, work zones, storage categories, residents, and a
  guarded task queue;
- base return, guard and patrol work, depot sorting, window barricading, crop work,
  tree cutting, log sawing, corpse cleanup, trough feeding/watering, and damaged-structure
  repair through normal world actions.

That latest layer builds and passes standalone checks, but the newer base jobs still need
their in-game passes. Construction, the full Survivors Notebook,
firearms, vehicles, raids, and away teams are not being claimed as finished.

## Current live test

Use a backed-up or disposable Build 42.20 save. The development scenario spawns or restores
three survivors in a broad nearby band and leaves the save's normal zombie population alone.

For the next test, check that:

1. all three survivors restore with the same identity, look, gear, health, and needs;
2. occupation and traits stay the same after returning to the menu and reloading;
3. nearby independent survivors offer Talk and Recruit through the world context menu;
4. enough conversations raise trust, recruitment succeeds once, and the new companion HUD
   appears without affecting the real player's visibility;
5. Follow and Hold survive a reload and combat can interrupt them without deleting the order;
6. a player home can be established inside a building and its containers can be marked as
   depot, food, medical, weapons, tools, or other storage;
7. Return to Base makes a companion travel toward a loaded home, then remain around it;
8. faction survivors continue protecting their selected home instead of resuming endless
   building-to-building looting.

Please include `console.txt`, `KnoxIsoPlayer.log`, and the newest development-run summary
with any report. Exact setup and expected log lines are in
[Development Testing](docs/DEVELOPMENT_TESTING.md).

## Development setup

1. Copy `gradle.properties.example` to the ignored `local.properties` file and set the
   Project Zomboid, Workshop staging, and Java paths for the machine.
2. Run `./gradlew.bat clean build deployDev`.
3. Start the game with `Run Knox Survivors Dev.bat` so the Java agent is loaded.
4. Enable Knox Survivors on the test save and load it normally.

The ordinary Steam Play button does not load the Java agent used by the current rebuild.
The one-button player launcher is being kept for the eventual rebuild release; it should
not be distributed against the old Workshop package.

More detail is in [Architecture](docs/ARCHITECTURE.md),
[Feature Audit](docs/FEATURE_AUDIT.md), [Milestones](docs/MILESTONES.md),
[Sandbox Settings](docs/SANDBOX_SETTINGS.md), and [Launcher](docs/LAUNCHER.md).

Discord: https://discord.gg/cTfd2WWD4s

## Permission

Knox Survivors is publicly visible, but it is not open source. No permission is granted
to copy, modify, redistribute, repackage, publish, or reuse the project without asking
first. Authorized testers may use it only for the testing permission they were given.
See [LICENSE.md](LICENSE.md).
