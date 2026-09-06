# Long-session review — 2026-09-06

Source: `dev-runs/20260906-063939`, started 10:39 UTC and collected 14:49 UTC.
The player reported enabling normally-disabled experimental features for this
test. This is a gameplay diagnostic run, not a completed scenario acceptance run.

## Evidence

- Repeated detach hibernations around 85–93 tiles and restores around 84–91 tiles
  sometimes only 300 ticks apart indicate avoidable streaming-edge churn.
- `ks-world-8` repeatedly restored as Kerry Jennings with tracked inventory and
  injuries. At frame 202831, the log reports `state=DEAD persisted=true`,
  `remove=CORPSE_CREATED`, `reanimationScheduled=true`, `cleanupRetry=false`.
  The native agent also confirms corpse creation. No later restore was found in
  the inspected evidence. This supports that death transition, but does not
  establish corpse/save/reanimation correctness across subsequent reloads.
- `ks-world-4` shows sustained fleeing and declining health. Some flee targets
  changed after roughly 11–12 frames with zero escape lanes. The controller's
  five-tick replan after arrival could reset its own safe-scan confirmation;
  repeated sprinting also spent endurance beyond close contact.
- The movement failure evidence includes ordinary Failed/FailedObstacle results,
  four flee FailedStuck results and one formation obstacle failure. Failures are
  not themselves proof of a broken lifecycle or failed native recovery.
- Repeated offscreen starvation/dehydration entries for `ks-world-7` remain a
  useful follow-up: physiology applies damage while hibernated and must not be
  bypassed simply to quiet logs. Sustainable supply access needs multi-day play.
- The console includes unrelated sandbox parsing errors from ZomboidDrugzz,
  missing recipes/map content, and four native ThumpState null-target exceptions.
  Their cause was not established as Knox code; no speculative engine patch was
  made. No render-corruption match was reported by the run collector.

## Changes and limits

The feature audit records the implemented fixes. Cupboards reuse actual world
containers and inventory transfers; this pass does not add a furniture model or
Rust-style building authorization/upkeep. Formations are movement preferences,
not autonomous driving or new combat formations. Experimental defaults remain
unchanged. Spouse start is optional and applies only to new characters; it is
not a retroactive recruitment button or a full romance simulation.

Offline verification passed 180 checks. It cannot establish believable behavior
or stability in the live game. No new live session was launched by this pass.

## Next live acceptance session

1. Enable Spawn With Spouse before starting a new character. Check one companion,
   relationship label, follow orders and save/reload. Repeat with blocked spawn
   tiles. Dismissal/death must not create another starting spouse.
2. Recruit two companions. Use personal and party Orders → Formation; try both
   layouts at all spacings outdoors and through a doorway, then save/reload.
3. Designate a dry container inside a player base through its storage menu.
   Check 500 capacity, deposit a real tool/material, assign a resident job, and
   observe withdrawal and later deposit. Check full storage and reload. Move the
   designation to another loaded container and replace a destroyed cupboard.
4. Observe an NPC base acquiring an existing cupboard and performing real supply
   transfers. Confirm it cannot access unrelated player storage.
5. Enable survivor fleeing. Compare a distant threat, close pursuit, exhaustion
   and a blocked escape. Watch stamina, safe stopping and recovery from failed
   paths; survival remains dependent on the situation.
6. Cross the streaming boundary repeatedly, approach again and reload the save.
   Verify stable names, inventory, injuries, duties and counts. Observe death,
   corpse persistence and any scheduled reanimation, with no living duplicate.
