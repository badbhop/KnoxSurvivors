# Replacement quality: delivery and acceptance

Updated 2026-09-06. This is the delivery order for the existing feature specification,
not a claim that Knox is a finished or AAA-quality replacement. Current status belongs
in `FEATURE_AUDIT.md`; implementation ownership remains in `ARCHITECTURE.md`.

## Current assessment

Knox has a substantial persistent-person foundation, native-action integration,
survival behavior, group/base domains and player controls. The main risk is the gap
between isolated checks and whole gameplay sessions: movement, needs, combat, orders,
vehicles and streaming compete for the same body. New features must exercise those
handoffs, not just add another successful policy test.

The 2026-09-06 review began with 91 passing Lua scripts and passing Java verifiers.
The newest available collected run, `20260905-045153`, had no scenario results and
24 movement/combat failure lines. That older run does not validate today's fixes.
No new in-game acceptance or performance measurement was performed during this review.

## Delivery order

| Order | Deliverable | Evidence required to move on |
| --- | --- | --- |
| 1 | A reliable companion through one ordinary day | Recruit, travel, enter buildings, loot, eat/drink/treat, fight, board/exit, return home, save/reload. Same person, gear, injuries and orders; no duplicate body, stuck action owner or effect on real-player input. |
| 2 | Believable small-group travel and combat | One, four and twelve followers; turns, stairs, doors, windows, fences, a separated member and a downed target. Distinct preferred positions, bounded retries, recovery after danger, no repeated order loss or teleporting. Test both formation choices and spacing extremes. |
| 3 | A settlement that actually survives | Three in-game days with observed native resource transfers and completed jobs. Exhaust food/water/materials, interrupt workers, kill one resident, stream away and reload. No free supplies, duplicate claims, dead-worker assignments or false completion. |
| 4 | Responsive, understandable controls | HUD/card/Notebook agree about identity, order, actual activity and needs. Explain unavailable actions and failed requests. Check minimum supported viewport, larger fonts and two local players; selection and ownership remain correct. |
| 5 | Autonomous driving vertical slice | First prove one NPC can own one real driver seat, drive a short unobstructed route, stop and release controls safely. Then add obstacles, passengers, intersections and multiple cars. Passenger support is not proof of driving. |
| 6 | Sustainable world and release compatibility | Multi-day reload/streaming run with independent groups, factions, away teams and opt-in events; then measured frame pacing and memory at supported population settings. Verify matched Workshop payload plus launcher on actual supported operating systems. |

A failed identity, save, real-player ownership or body-action gate takes priority over
new breadth. Independent work can continue while a visual acceptance case is pending;
it stays marked implemented, unverified.

## Driving implementation boundary

Implement original Knox behavior against the exact installed engine. Keep routes,
seat reservations and vehicle intent in Knox; use native vehicle mechanics for actual
movement. Start with an experimental opt-in, disabled by default.

Before enabling a driver, establish a single control owner and verify that no real
player controls the seat. Revalidate the vehicle, driver, seat, fuel/engine state and
loaded route before moving. A player taking the seat, driver injury/death, unavailable
terrain, stuck timeout or cancelled order must stop and release control. Reload must
restore intent without automatically accelerating a vehicle before revalidation.

Follow with obstacle stopping and bounded recovery, then passenger coordination.
Convoys require following distance and stop propagation before route breadth. Do not
add convoy menu entries that only set a timer or position. Never report successful
arrival without observed vehicle position and a stopped vehicle.

## Player customization

Each option needs a live consumer, safe default, bounded numeric interpretation,
clear tooltip, old-save fallback and an explanation of what changing it preserves.

Available in this review: paired/single-file follow positions, spacing 1–3, and zero
refill days for no routine replacements/arrivals. Existing population, body budgets,
companion limits, recruitment, factions, hostility, events and presentation controls
remain available. Event entrants have a separate switch from routine population refill.

Add future driving/convoy settings when their implementation exists. Damage, loot or
skill multipliers should not substitute for better decisions. Preserve real supplies,
native injury mechanics and each survivor's persistent identity across presets.

## Verification and release gate

Run `tools/verify.ps1` for Lua syntax, all standalone Lua regressions, and Java
check/build. Read `build/verification/summary.json`; a skipped Java run is explicitly
recorded. Run the sibling launcher's `scripts/build.ps1` for its verifier, Windows
bootstrap checks and distributable archives. Neither command publishes anything.

For each live case record build/agent checksum, save sandbox settings, mod list,
survivor IDs, before/after state, exact reproduction and collected run folder. Synthetic
verifier logs are not gameplay evidence. A test blocked by setup is not a pass.

Before release require no open crash, save-corruption, identity-duplication or
real-player-ownership defect. Record actual frame-time percentiles, stalls and memory
for comparable vanilla and Knox runs on the same machine and route. Choose supported
population presets from those measurements; do not infer FPS gains from fewer calls.

Stage and validate the mod plus agent checksum only after automated checks. Perform
the ordinary subscriber launch path against that matched payload. Publish only after
the relevant live gates and release approval; archive a rollback package and notes.
