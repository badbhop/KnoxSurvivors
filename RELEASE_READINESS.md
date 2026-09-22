# Knox Survivors release readiness

Audit date: 2026-09-21  
Authority: current workspace only. GitHub, remote branches and older payloads were not used as sources for this assessment.

## 1. Release blockers found and fixed

No new source-confirmed release blocker was found in this final audit, so no gameplay code was changed.

The current code already contains the safeguards needed for the major failure classes reviewed:

- controller exceptions enter an idempotent recovery path that releases transient movement, combat, action, task and reservation ownership;
- native base jobs use persistent task claims and explicit completion/failure cleanup;
- interrupted automatic claims are requeued at the save-load boundary;
- survivor save capture is isolated per active survivor, allowing later records to continue after one failure;
- hibernation captures the live body before removal and marks the serialized ledger stored only after native removal succeeds;
- materialization restores the stored needs state once and prevents the offscreen clock from moving backward;
- faction, group, base and event cleanup paths remove invalid ownership during the existing normalization and lifecycle transitions;
- the player-facing HUD and Survivor Card use the shared status projection instead of separate need values.

## 2. Release blockers still open

None confirmed by source inspection or offline verification.

This is a release-candidate assessment, not proof that every native Build 42 action works in the engine. A live failure that makes a common supported job, combat path, save/load transition or companion unusable would become a blocker and should be triaged from its newest DebugLog before publishing.

## 3. Live Build 42 acceptance tests required

These are classified as LIVE TEST REQUIRED because the native engine boundary is involved:

- recruit a survivor, issue follow/hold/guard/patrol orders, interrupt them with combat, and confirm they recover and resume the retained order;
- run one base through farming, cooking, woodcutting, log processing, repairs, corpse pickup/drop-off, guarding, patrol and wooden window barricading;
- verify real tools/materials are consumed only once and failed actions release claims without permanent idle or retry loops;
- verify firearms fire real rounds, cause native damage, reload, fall back to melee, and recover when targets die or switch between humans and zombies;
- move a companion out of range, hibernate and rematerialize them, then compare needs, equipment, activity, orders and inventory before and after;
- save and reload during a base job, combat, group travel, temporary shelter and active faction raid;
- verify faction defenders react to a real hostile raid, zombies can interrupt it, and the event resolves without permanent combat/event duties;
- verify faction leader death, final-member death, base abandonment and safehouse release in a real saved world;
- run a multi-day base test with real food/water storage and confirm no duplicate consumption or false hunger loop;
- verify NPC and companion vehicle entry, seat changes and long-distance travel where the feature is enabled.

## 4. Non-blocking known limitations

- Unloaded base supplies use a bounded reserve of real serialized items. Exact long-duration container escrow is intentionally not implemented.
- Farming, cooking and other physical production do not run abstractly while world squares are unloaded.
- Barricading is limited to supported wooden window barricades. Metal barricades, gates and general construction are outside the current scope.
- Animal care and the retired construction system are intentionally excluded.
- Detailed unloaded robbery, native combat damage and native animation behavior require loaded Build 42 actors.
- Offline tests use native API doubles and cannot prove engine animation, item transfer, projectile damage, or moodle behavior.

## 5. Experimental features that should remain disabled

Keep these disabled for the release candidate unless the live acceptance scenario specifically targets them:

- automated QA mode and developer scenario spawning;
- experimental automatic faction raids;
- experimental event/away-team dispatch features;
- any debug diagnostics, test-supply shortcuts or free job-resource option;
- vehicle autonomy if the live vehicle acceptance path has not passed in the target Build 42 build.

Normal survivor population, companions, base jobs, storage, needs, ordinary NPC conflict and standard faction lifecycle can remain enabled.

## 6. Post-release improvements

Classified POST-RELEASE:

- exact-item long-duration unloaded base escrow and reconciliation;
- broader raid objectives and looting;
- expanded barricade/construction types;
- richer unloaded human encounters and robbery simulation;
- launcher removal or Workshop-only distribution after release packaging is proven;
- additional dialogue, polish and visual presentation work.

## 7. Final verification results

- `gradlew build deployDev --console=plain`: passed.
- Lua syntax: 102 source files passed.
- Lua regression scripts: 142 ran.
- Full verification: 245 checks passed, 0 failed.
- Automated QA coordinator: passed.
- No commit, push, Workshop upload, launcher release or public state change was performed.

The workspace is suitable for a release-candidate live acceptance run. It should not be described as fully engine-accepted until that one comprehensive Build 42 test is completed and its logs are clean.
