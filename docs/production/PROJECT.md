<!-- modforge-doc
authority: canonical
load: always
purpose: stable product vision and operating principles
-->

# Knox Survivors — production project definition

Updated: 2026-09-26

## Product

Knox Survivors is a single-player Project Zomboid Build 42 survivor/NPC mod rebuilt from the ground up by **.exe**. Its goal is a persistent living human population that uses Project Zomboid's existing systems wherever practical and still feels like the base game rather than a separate follower or colony game.

Current public release line: `0.3.0-rc1`.
Target game version: Project Zomboid `42.20.4`.

## Core NPC rule

> **A Knox survivor is another Project Zomboid survivor controlled by AI, not a colony-game pawn.**

Project Zomboid is the foundation. Other games may contribute individual design lessons, but Knox should translate those lessons into PZ's real world/items/actions rather than imitate their full game loops.

See `../design/NPC_SYSTEM_INSPIRATION.md`.

## Product principles

- Persistent survivor identity matters more than disposable NPC bodies.
- Vanilla systems, items, containers, actions, combat, farming, clothing and world objects are preferred where practical.
- Survivors should behave as people trying to survive, not as a free army or player-programmed colony workforce.
- Loaded and unloaded states should represent the same persistent person and continuing story.
- Real shortages/problems should create work; work should consume real resources.
- Survivors, specialists and established groups should be uncommon enough that finding or losing one matters.
- Single-player is the current supported focus.
- Experimental vehicle autonomy, raids/large faction events, away-team missions, full construction and multiplayer NPC support are not current release promises.
- Save integrity, identity/lifecycle correctness, native action ownership and real-player/IsoPlayer ownership take priority over feature breadth.

## Engineering principles

- One authoritative owner per system boundary.
- Prefer one primary survivor intention/job plus bounded emergency reactions over competing permanent controllers.
- Existing systems should be connected through shared arbitration/claims/needs/history where useful, not rewritten merely to look uniform.
- Smallest architecture-safe fix at the first confirmed failure.
- No fabricated supplies, native success, damage or verification.
- Live engine behavior requires live engine evidence.
- Historical evidence is useful but does not automatically represent current truth.

## Project operating model

ModForge is the production desk and source-of-truth index. Codex and OpenCode remain the normal implementation tools.

- ModForge keeps roadmap, tasks, bugs, decisions, design intake, documentation map, collaboration ledger, evidence state and handoffs aligned.
- Codex/Astra is the primary engineering authority for difficult architecture-sensitive implementation, expansion, debugging and broad release-hardening work.
- OpenCode is the budget-engineering authority for confirmed bugs, support work, focused implementation, cleanup and compatibility/collaboration support.
- The human owner remains final for product direction, source-write permissions, release decisions, collaborators and public commitments.

## ModForge source boundary

ModForge-managed production/design records may be maintained automatically. Gameplay/source code is read-only by default unless the owner explicitly enables a source write.

Any owner-approved ModForge source write must leave a change note and remains unverified until the normal Git diff + Codex/OpenCode/QA path validates it.

## Operational scale

As of 2026-09-26, the owner reports Knox Survivors is approaching 26,000 active users. Treat that as owner-reported operational context, not independently verified analytics. At that scale, support triage, compatibility records, collaborator tracking, release evidence and careful public wording are production responsibilities.

See `AI_WORKFLOW.md` for the operating loop.
