# Feature-completion audit

This audit compares the current rebuild with the feature-complete goal. It is a
current-state map, not a claim that passing standalone checks proves gameplay.

Status meanings:

- **Working** — implemented and supported by current live evidence.
- **Partial** — a real implementation exists, but required behavior or integration is missing.
- **Implemented, unverified** — the code and focused checks exist, but no adequate live pass exists.
- **Missing** — no production implementation was found.
- **Conflicting** — code or behavior currently violates the intended architecture.

## Verification baseline

Audited on 2026-08-26 at commit `83f51d2` plus the uncommitted formation-recovery
fix described below.

- all 20 standalone Lua tests pass;
- all 53 mod Lua files parse with Lua 5.1;
- `:java:build` passes, including the three-call melee-transformer verifier;
- the latest collected live run is `dev-runs/20260825-231746`;
- that run contains no render-corruption line, but it does contain two Survivor Card
  exceptions, persistent `DETACHED` controllers, 640 movement/combat failure lines,
  and three horde/duel combat scenarios that only reached `PARTIAL`;
- commit `a00c8e2` restores `IsoPlayer.instance` immediately after the shell constructor,
  fixes the Survivor Card model-child order, and bounds detached-shell cleanup for every
  active survivor identity;
- commit `83f51d2` restores the native zombie attack lifecycle while keeping NPC shells
  out of local-player ownership branches;
- the current formation-recovery fix consumes movement failures into a bounded wait,
  preserves route cooldowns that were previously overwritten by the five-tick group
  refresh, cancels stale movement ownership, and records consecutive recovery attempts.

Neither uncommitted fix is considered working until a new live run confirms it.

## Goal status

| Goal area | Status | Current evidence and missing boundary |
| --- | --- | --- |
| 1. IsoPlayer foundation | **Partial / conflicting live behavior** | Stable Java records, contained shell, slot checks, reconstruction, health/inventory/appearance capture, teardown, durable death hooks, and multi-NPC registries exist. The latest live run contradicts completion: global instance ownership is wrong and several controllers remain `DETACHED`. Constructor ownership and universal detached cleanup are patched but not live-tested. Extended multi-survivor save/unload/death testing is still required. |
| 2. Survivor autonomy | **Partial** | Roaming, supply-aware exploration, container searching, ranked looting, equipment, needs, melee, rest, medicine, and traversal states exist in `KS_SurvivorAutonomyController.lua`. Firearms are absent; purposeful long-range goals and several failure paths remain incomplete. Live logs show frozen/detached actors and high failure counts. |
| 3. Priority/action ownership | **Partial, retry defect patched** | One Lua controller owns high-level state and Java owns movement/combat requests. Reservations, cancellation, deadlines, and task claims exist. Formation start/tick failures now cancel stale movement ownership and enter a bounded wait instead of immediately requesting another route; live verification is pending. |
| 4. Navigation/human movement | **Partial, retry defect patched** | Walking, running pace, formation catch-up, doors, windows, smashing, climbing, fences, alternate entry, cooldowns, and route abandonment exist. Consecutive formation failures now retain an escalating bounded cooldown. Multi-floor and alternate-route behavior remain unproven in live play. |
| 5. Full combat | **Partial** | Native melee attack integration, moving-target refresh, target reservations, zombie awareness, endurance, condition, injury capture, and group threat selection exist. Latest duel/horde tests are partial and zombie damage is inconsistent. Firearms, reloads, ammo policy, and survivor PvP are missing. |
| 6. Needs, health, medical, inventory | **Partial** | Real hunger, thirst, fatigue, endurance, food/water consumption, BodyDamage, self-bandaging, improvised bandage sourcing, inventory ranking, and equipment exist. The player lacks a finished inventory/equipment/medical management interface for survivors. Normal player-on-NPC treatment is not sufficiently live-verified. |
| 7. Skills, traits, occupations | **Implemented, unverified** | Deterministic Build 42 profession/trait generation, perk levels, XP capture/restore, and job requirement checks exist and pass standalone persistence checks. Long save/unload/reconstruction progression still needs a live pass. |
| 8. Social system | **Partial** | First/last meetings, nearby time, encounter counts, shared activity, trust, greetings, joining, declining, persistent hostility, robbery, player conversations, and recruitment exist. Dialogue is still small and repetitive; survivor PvP and deeper faction diplomacy/favors are absent. |
| 9. Natural groups | **Partial, recovery patched** | Consent-based two-person groups, lone invitations, three-person faction eligibility, persistent membership, formation slots, waiting, and leader retrieval exist. A focused regression now proves a moving-leader `MOVE_ALREADY_REQUESTED` failure enters bounded `GROUP_WAIT` without losing its cooldown; reliable live group travel/combat is still unproven. |
| 10. Factions | **Partial** | Persistent faction IDs, leaders, members, traits, relationships, home candidate/base IDs, safehouse ownership, and resident conversion exist. Broader faction goals, diplomacy, resource pressure, recruitment growth, and lifecycle simulation are missing. |
| 11. Base scouting/settlement | **Partial** | Loaded buildings are scored, safehouse conflicts are rejected, candidates persist, leaders travel to candidates, and faction bases/residents are created. Candidate breadth, repeated unloaded search, resource/water evaluation, and failure recovery need completion and live verification. |
| 12. Base domain | **Partial** | Player and faction base records, home/territory separation, residents, zones, storage policies, tasks, ownership protection, and save migration exist. Resource summaries, full management, NPC planning, and end-to-end settlement life are incomplete. |
| 13. Base Setup UI | **Partial** | Context menus can establish a base, redraw territory, create zones, categorize containers, and safely remove inactive work areas. A vanilla-style Base Setup window now opens from party/world menus with Overview, Residents, Work Areas, Storage, and Tasks tabs plus boundary editing, work-area selection, and party recall. Zone resizing, exact task assignment/control, and visual territory/zone management remain incomplete. |
| 14. Existing base jobs | **Implemented, unverified** | Guard, patrol, depot sorting, barricading, farming, tree cutting, log sawing, corpse hauling, trough water/feed, and structure repair have real executors and focused passing tests. Most lack live passes; task reservation across multiple residents and save/interruption still needs integration testing. |
| 15. Construction/defense planning | **Partial, static path verified** | Defense Construction Areas now plan a gate first, then wall frames and first-stage wooden walls using Build 42.20 entity recipes, native `ISBuildAction`, real materials, skill gates, XP, sounds, and world-object completion checks. Faction bases receive a conservative default perimeter. Live off-slot action, construction interruption, and multi-resident verification remain required; walls/gates beyond the first wooden stage are not yet implemented. |
| 16. Companions | **Partial** | Talk, trust, recruit, Follow, Hold, Return to Base, Dismiss, climbing policy, and area/building/corpse loot directives persist. Party Go To and Guard orders now persist and resume after ordinary interruptions. Base residents support persistent player-set job preferences that favor matching eligible work but safely fall back when needed. Exact task assignment, finished base roster exchange, and live verification of all companion order recovery remain incomplete. |
| 17. Companion HUD | **Partial** | Split-screen-isolated right-side HUD, portraits, needs, health, weapon, activity, individual menu, and party menu exist. It needs a complete live lifecycle pass, unloaded cleanup verification, urgency presentation, and final command coverage. |
| 18. Survivor Card | **Partial / live defect patched** | Identity, age, occupation, time alive/known, group/base/job/activity, conditions, weapon, and portrait scaffolding exist. Latest live opening throws before rendering; initialization order is patched but unverified. Traits, skills/XP, injuries, equipment detail, relationship depth, and actions are incomplete. |
| 19. Survivors Notebook | **Partial** | A vanilla-styled window has Party, Home Base, Survivors, and Factions text tabs. It is informational and shallow: no portraits, detailed rosters, away/mission state, selection, management actions, resource status, or rich base/faction views. |
| 20. Away teams/missions | **Missing** | No mission schema, planner, team lifecycle, destination, ETA, result, or world-resource accounting implementation was found. |
| 21. Unloaded-world simulation | **Missing** | Active bodies can hibernate and reconstruct, but no lightweight travel, needs, supply, recovery, mission, risk, or faction progression simulation exists while unloaded. |
| 22. Camps | **Missing** | A faction base may currently be labelled “Survivor Camp,” but there is no distinct temporary camp lifecycle or gameplay system. |
| 23. Vehicles | **Missing** | No survivor vehicle recognition, entry/exit, travel, group behavior, or persistence implementation was found. |
| 24. Raids/faction conflict | **Missing** | Hostility fields and base protection boundaries exist, but no causes, planning, travel, combat objective, retreat, resource transfer, or raid persistence exists. |
| 25. World population | **Implemented, unverified** | Region-balanced identities, persistent target, active-body limit, distant/hidden materialization, refill delay, origin reuse protection, hibernation candidates, and durable death records exist and pass standalone tests. Production-scale live streaming/refill is not proven. |
| 26. Lifecycle/hibernation | **Partial / live defect patched** | Capture, removal, stored records, activation candidates, reconstruction, grace checks, and death removal exist. Latest live logs show several long-lived `DETACHED` developer bodies; cleanup is now identity-agnostic and unit-tested, but the deterministic transition still needs a live pass. |
| 27. Failure recovery | **Partial, primary formation loop patched** | Cooldowns, reservations, task requeue, target re-resolution, movement deadlines, and alternate-entry abandonment exist. The 549-failure formation loop was traced to `finishDecision()` replacing a 180-tick route cooldown with a five-tick group refresh; the retry time is now preserved and consecutive failures back off to 720 ticks. A new live run must prove the failure storm is gone. |
| 28. Player-facing feedback | **Partial** | Speech bubbles, activity feed, HUD activity, need callouts, order messages, and Notebook summaries exist. Missing-tool/material/job failure feedback and richer status presentation are incomplete; repetition/spam needs a live pass. |
| 29. Save/load coverage | **Partial** | Core person, appearance, inventory, equipment, health, physiology, capabilities, social/group/faction, companion duty, base, zones, storage, and tasks are persisted. Missing systems cannot persist, and full multi-point acceptance reload/unload evidence does not exist. |
| 30. Debugging/testability | **Partial, strong foundation** | Java diagnostics, transition logs, scenario tools, log collection, 20 standalone tests, probes, and combat scenarios exist. Controller status now reports formation failure streak and retry tick; UI/lifecycle diagnostics and live movement/combat regression gates still need completion. |
| 31. Clean architecture | **Partial** | The repository contains only the IsoPlayer rebuild and keeps records separate from bodies. No active IsoZombie runtime was found. The autonomy controller is large but still the single owner; probes are gated. Missing systems should extend current boundaries instead of adding competing managers. |
| 32. Efficient implementation loop | **In use** | Focused executors and standalone tests are present, but many slices moved ahead without live verification. Future work must close current core/live defects before stacking additional gameplay systems. |

## Current critical path

The shortest path toward the acceptance loop is not to add every missing feature in
parallel. The current order is:

1. restore and prove local-player/global-instance ownership, fix the Survivor Card crash,
   and eliminate permanent `DETACHED` lifecycle states;
2. make loaded-world melee and zombie-to-survivor damage reliable in duel and horde tests;
3. reduce movement/action retry failures and prove group/companion travel recovery;
4. live-verify the existing base-job executors with multiple residents and save/reload;
5. add persistent replacement-door/basic-defense construction through real Build 42
   recipes, skills, tools, materials, placement, and actions;
6. finish player inventory/medical management and the Base Setup/Notebook management UIs;
7. add firearms, then unloaded simulation and away teams because both are required for
   production population and settlement supply loops;
8. add camps, vehicles, and raids only after ordinary survivor/faction life is stable.

## Acceptance status

The feature-complete acceptance test does **not** currently pass. The repository has a
substantial playable foundation and many genuine world-action executors, but major promised
systems remain missing and the latest live run still contradicts core lifecycle, combat,
group recovery, and Survivor Card requirements.
