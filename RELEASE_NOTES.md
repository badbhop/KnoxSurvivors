# Knox Survivors 0.3.0-rc1

## Runtime path update — 2026-09-29

- KnoxBridge is the only supported public Knox Java runtime/setup path.
- The separate Knox Survivors Launcher is deprecated and unsupported. The owner
  has requested that its source repository be made private; that repository
  setting remains pending confirmation. Do not download or use old launcher
  releases, and never combine them with KnoxBridge or external Java runtime.
- KnoxBridge player setup remains a separate GitHub Releases download. Its
  alpha8 Workshop candidate adds a full-screen main-menu review gate for
  enabled-mod JARs, with unknown files blocked by default and an optional
  remember toggle for exact-hash allow/deny choices. Changed module-load choices
  require one quit/relaunch; unchanged choices do not. The staged Bridge update
  still needs live Build 42 replay and Steam publication confirmation.

## Maintenance update — 2026-09-23

- Fixed runtime detection that left the bridge disconnected or reported the incorrect runtime version after launch; this historical note does not imply the old Knox Launcher remains supported.
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
- The cross-platform Knox launcher was a prior experimental option; it is now deprecated and unsupported.

## Still experimental / incomplete

Multiplayer NPC support, survivor driving, raids/large faction events, away-team missions and full construction are not release promises. Real Build 42 testing is still expected to uncover bugs in pathing, combat, base work and long-session save/load behavior.

## Startup migration note

The following launcher migration note is historical. Knox Survivors Launcher is no longer supported; current users should follow KnoxBridge setup instructions and should not add a direct legacy Knox `-javaagent` path.

Old launcher-specific **Custom Launch Options** are not part of current KnoxBridge setup. Do not copy its Knox agent arguments into Steam; use the current Bridge installation and trust instructions.
