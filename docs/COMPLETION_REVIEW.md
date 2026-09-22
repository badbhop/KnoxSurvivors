# Completion review

This is a code-first completion pass requested on 2026-09-20. No new user
playtest is requested until the implementation review and preflight are ready.
Existing dirty worktree changes are preserved. Publication and launcher changes
remain postponed until mod stability has been established.

## Verified changes in this pass

- Persistence first capture accepts a new live native body without requiring an
  existing Lua identity. Failed serialization creates no ghost identity. Missing
  bodies and unavailable health state fail closed. Existing dead or departed
  identities, including developer survivors, cannot be resurrected by capture.
- Storage classifies weapon-capable hand tools before generic weapons. The
  previous order counted a stored hammer as a weapon, explaining the live
  `tools=0 hasHammer=true` result. Explicit Weapons assignments still accept tools.
- New behavioral regression tests cover first capture, failed capture, stale dead
  bodies, departed identities, missing bodies, native errors, and native tools
  that also satisfy `IsWeapon`.
- Offline verifier: 99 Lua files, 137 regression scripts, 237 checks, zero failures.

## Findings still requiring implementation review

- Firearm QA spawns its target three tiles away with an unloaded firearm kit;
  production reload fallback treats targets within 3.5 tiles as immediate danger.
  Thus `not_ranged` is not evidence of failed firearm recognition on its own.
  The test also requires the zombie to damage the survivor to pass. Redesign the
  firearm acceptance evidence around actual ranged firing, ammo consumption,
  reload completion and attributable target damage, without weakening combat.
- Reload stall detection now uses an elapsed 1800-controller-tick preparation
  budget rather than four polls. Installed vanilla magazine loading is
  animation-driven (`getDuration() == -1`). Repeated same-tick checks cannot
  exhaust the budget; ready state clears it. Immediate-threat melee fallback
  remains active. Behavioral tests cover duplicate polls, deadline boundaries,
  preparation transitions, reset, close threats and different floors. This is
  offline verified; native firing/reload acceptance remains open.
- Population QA currently compares the entire active NPC count with two. World
  survivors can prevent readiness despite both test fixtures existing. Scope
  readiness and cleanup to the identities owned by the probe.
- Prior persistence reconstruction comparisons were weakened to aggregate
  inventory counts and health summaries. These cannot establish preservation of
  ammunition, nested contents, wounds, or equipped slots. Audit full fidelity.
- Base movement entry recovery and faction indoor arrival remain unverified.
- Old developer fixtures and safehouses can contaminate reused QA saves. Fixture
  setup/cleanup must be explicit; ordinary persistence must never revive them.

## Scope ledger

All rows remain open until their production paths, failure paths, and evidence
are reviewed. Existing tests alone do not close a row.

| Requirement group | Current pass status |
| --- | --- |
| Identity, death, departure, capture | First-capture boundary fixed; lifecycle/recreation/migrations open |
| Needs, food, water, rest, wounds, medical | Open |
| Melee, unarmed, hostility, friendly fire | Open |
| Firearms, aiming, reload, effects, skills | Failure mechanism identified; implementation and acceptance open |
| Traversal, floors, doors, fences, routes | Open |
| Orders, formations, guard, patrol, return | Open |
| Corpse pickup, movement, deposit, cancellation | Open |
| Base jobs, resources, claims, outdoor zones | Open |
| Storage, reserve inventory, deposits, withdrawal | Tool summary fixed; remaining paths open |
| Autonomous scavenging, groups, factions, camps | Open |
| Recruitment, relationships, dialogue, emotes | Open |
| Spouse, UI, inventory, cards, sandbox | Open |
| Vehicles, passengers, driving, map navigation | Open |
| Performance, multiplayer ownership, save compatibility | Open |
| Final integrated QA and preflight | Pending full code review |
| Launcher, Workshop, release, launcher removal feasibility | Deferred until mod stability |

No claim of full completion or new live acceptance is made by this report.
