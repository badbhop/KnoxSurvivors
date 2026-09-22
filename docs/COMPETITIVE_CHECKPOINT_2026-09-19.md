# Knox Survivors competitive checkpoint — 2026-09-19

This checkpoint compares the current Knox Survivors worktree with the local
Project Remnants reference at
`C:\Users\Gary\Documents\Refrences\Refrences\ProjectRemnants`.

The reference was used for behavior ideas and player-facing patterns only. No
Project Remnants code, assets, names, or implementation structure were copied
into Knox Survivors.

## Current Knox baseline

- Branch: `main`, currently at `74a39b8` (`Prevent false fence vault failures`).
- The worktree contains the existing uncommitted development changes and was
  preserved.
- Last verified offline gate: 97 Lua files, 134 regression scripts, 232 checks,
  0 failures.
- `deployDev` completed successfully, including Java verification and Workshop
  staging.
- The latest available live log is
  `C:\Users\Gary\Zomboid\Logs\2026-09-19_12-30_DebugLog.txt`.
- Native movement, action animation, firearms, survivor inventory UI, and
  multi-resident save/reload still require live acceptance. Offline tests prove
  ownership and state boundaries, not the complete Build 42 animation loop.

## Behavior comparison

| Area | Reference behavior worth learning from | Knox position | Completion work that fits Knox |
| --- | --- | --- | --- |
| Storage | Typed container roles, visible assignment, contents preview, and clear role labels | Central cupboard and assigned typed containers already exist, with nested item discovery and native transfers | Finish live container assignment, icons/previews, capacity feedback, and resident deposit/withdrawal acceptance |
| Work areas | Explicit selection states, route/post previews, bounded area sizes, and clear cancel/confirm feedback | Base Setup, work zones, guard/patrol routes, and external areas exist; richer visual management remains partial | Make right-click cancel, second-click confirm, invalid-tile feedback, and selected-zone status reliable in live play |
| Jobs | Player can see jobs, roles, and results through one management surface | Real executors exist for farming, woodcutting, sawing, barricades, repairs, corpses, cooking, guard, and patrol | Complete the live loop: claim → supplies → route → native action → verified result → requeue/next job |
| Scavenging | Building loot orders, filters, stop controls, and readable result states | Knox has purposeful container selection, same-building continuation, faction pairs, away teams, and return/deposit foundations | Verify multi-container searches, personal-needs retention, return ownership, deposit, and interruption recovery |
| Groups/orders | Orders expose stance, rules, reload, loot, rest, and explicit result labels | Knox order catalogue, formations, guard/patrol, needs, reload, and dialogue ownership already share one dispatch boundary | Improve status text and failure reasons in existing menus; keep one command owner and avoid parallel order systems |
| Social life | Small contextual gestures, leisure actions, rest, reading, TV, and security checks make downtime visible | Knox has dialogue, activity feed, recreation, needs, and ambient base movement | Live-verify action cancellation, door discipline, non-spam chatter, and residents choosing useful downtime |
| Factions/safehouses | Safehouse selection, member/job management, farming, storage, and guard setup are presented together | Knox has persistent factions, leaders, camps, safehouse/base records, storage, zones, and task claims | Finish one readable faction/base management path and verify multi-day upkeep, resident conversion, and leadership continuity |
| Driving | Map destination order, driver/passenger ownership, road-grid staging, and controlled release | Knox has passenger actions and an opt-in native driver slice; long-distance routing and autonomous group travel remain partial | Prove safe endpoint selection, obstacle stop/release, route completion, group passenger handoff, and save/reload behavior |
| Combat/ranged | Explicit reload/fire statuses and guard weapon configuration are easy to inspect | Knox delegates aim, readiness, reload, firing, ammo, condition, and sound to native Build 42 behavior | Live-test aiming, magazine/chamber transitions, target selection, friendly-fire rules, and melee fallback |
| Progression | Skills and media/actions visibly feed survivor development | Knox persists skills, traits, XP, occupations, and job gates | Confirm live XP and skill effects through real work, combat, and reload cycles |

## What already puts Knox on a strong footing

Knox has the more explicit separation between persistent survivor records and
contained `IsoPlayer` bodies. Its Java bridge owns native movement and combat
boundaries, while Lua owns high-level decisions and persistence. That is the
right foundation for preserving saves and preventing a second system from
fighting the engine.

Knox also has a stronger offline verification base than the reference review
can establish: task claims, storage identity, nested containers, survivor
presence, faction return ownership, action receipts, inventory transfer safety,
unloaded survivor cards, and bounded movement recovery are covered by focused
checks. The main gap is live proof and player-facing clarity, not a need to
replace the architecture.

## Highest-value parity work

1. **Finish the base-job acceptance loop.** Run every existing job with real
   storage, tools, materials, route interruption, native action completion,
   resident interruption, and save/reload. Record the first failing boundary
   instead of adding another executor.
2. **Finish work-area feedback.** Keep the current Base Setup and zone model,
   but make selection state obvious: active, confirmed, cancelled, invalid,
   outside allowed area, and awaiting a loaded square. Show the same status in
   the Base tab and the world highlight.
3. **Finish storage usability.** Preserve the one central storage model and
   existing typed roles. Add only the missing player feedback: role label,
   assigned container, contents preview, unavailable/unloaded state, and the
   exact reason a resident could not deposit or withdraw.
4. **Finish resident autonomy at home.** After a job or need, residents should
   return to their duty, choose a bounded local activity, speak only on state
   changes, and remain inside their base unless a player order or approved
   expedition permits departure.
5. **Finish faction scavenging and safehouse upkeep.** Verify a faction can
   leave, search multiple useful containers, retain personal needs, return with
   real items, deposit them, recover from combat or route failure, and resume
   base duties over multiple in-game days.
6. **Finish vehicles after ordinary survivor life is stable.** Keep the
   current opt-in driver boundary. Prove road endpoint selection, stopping,
   passenger ownership, obstacle handling, and release before expanding travel
   distance or adding more vehicle behavior.

## Do not copy from the reference

The reference's storage role names, UI layouts, function names, road graph
format, animation assets, and framework calls remain reference material only.
Knox should express the same useful outcomes through its own persistence,
`KS_BaseStorage`, `KS_BaseJobs`, `KS_SurvivorAutonomyController`, existing
vehicle bridge, and current Base/Notebook surfaces.

## Checkpoint decision

Knox is competitive in system breadth and architecture, but it is not ready to
claim parity until the live base-job, storage, scavenging, faction upkeep, and
vehicle acceptance loops pass. The correct next step is completion and live
verification of those existing paths, followed by UI/status polish and
performance measurement. New feature families should wait until these gates
are closed.
