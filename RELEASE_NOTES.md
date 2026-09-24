# Knox Survivors 0.3.0-rc1

## Maintenance update — 2026-09-23

- Fixed runtime detection that left the bridge disconnected or reported the wrong ZombieBuddy version after launch; Knox Launcher/Steam startup still works.
- Fixed a health-probe scope error that caused repeated log errors.
- Removed automatic god/ghost/invisibility protection from the QA player; old QA flags are cleared on exit.

This release candidate is the public-facing checkpoint for the current human survivor rebuild. It does not turn experimental systems into promises; it packages and documents the systems that are actually present in the project today.

## Release focus

- Human/player-based survivor NPC runtime instead of the old zombie-shell approach.
- Persistent survivor identity, gear, needs, health, skills, relationships and save state.
- Autonomous survival/scavenging and world population behavior.
- Recruitment, companion orders, groups/factions, camps and settlements.
- Base storage/work areas and the implemented base-job set, including corpse hauling.
- Current combat, UI, hibernation and off-screen survival systems.
- Stable `knox-agent.jar` Workshop filename and an optional direct Steam launch
  option generator; the direct route still needs live startup acceptance.
- Optional cross-platform Knox launcher remains supported.

## Still experimental / incomplete

Multiplayer NPC support, survivor driving, raids/large faction events, away-team missions and full construction are not release promises. Real Build 42 testing is still expected to uncover bugs in pathing, combat, base work and long-session save/load behavior.

## Startup migration note

Normal Project Zomboid saves, sandbox/mod settings and the game's memory configuration are not owned by the Knox launcher and continue to use their normal locations. The Steam-only launch line passes `-javaagent` directly through Project Zomboid's Steam launch options and does not require a shell or persistent environment variable.

The launcher's own **Custom Launch Options** preference is launcher-specific and cannot migrate itself into Steam. Players moving to Steam-only startup should copy any custom game arguments they still need into Steam's launch-options field after the final `--`.
