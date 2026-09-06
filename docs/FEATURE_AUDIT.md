# Feature-completion audit

### Notebook, lifecycle presentation and diagnostic cleanup — 2026-09-05

**Implemented; offline checks pass.** Current code is broader than the historical
feature table below; historical entries are not a current completion percentage.

- Exact installed vanilla `ISScrollingListBox.addItem(name, item, tooltip)` stores
  the first argument as visible text. Notebook rows passed internal keys first,
  hiding descriptions, stock counts, task status and faction details. All six tabs
  now bind readable text and full-text tooltips while retaining stable row keys and
  the existing task/zone data used by commands.
- Vanilla `ISLabel.new` right-aligns unless its final argument is true. Notebook
  headings now explicitly left-align, correcting negative heading positions.
- Notebook updates only its visible tab, on activation and every two seconds.
  Selection follows stable identity across reordering; scroll and the selected
  resident are retained. Hidden/collapsed pages perform no periodic data refresh.
- Away only projects the local player's active teams and owned unloaded survivors;
  completed/blocked teams, unrelated faction residents, and duplicate team-member
  rows are excluded. Existing mission records and execution are unchanged.
- Survivor presentation respects durable death even after body removal; stale dead
  companions are excluded from the HUD. Assignment to a base no longer implies
  physical presence there. Loaded containment uses the existing base boundary.
- Java verifiers now write under `java/build/verification-logs/<task>` through an
  optional log-directory property. The game's default log path stays unchanged.
  Synthetic failure tests no longer pollute player logs or suggest a fresh live run.

Verification: 89 Lua tests, full mod Lua syntax, Java check/build and Workshop staging
pass. Gameplay log length was unchanged by the full verifier run. Added behavioral
tests cover tab ownership, row descriptions/tooltips, bounded active-only refresh,
selection retention, persisted death, and base presence. No launcher protocol or
packaging change is required. Nothing was published to Workshop or as a release.

Remaining route: finish existing movement/traversal and combat recovery at demonstrated
boundaries; prove native corpse/settlement jobs consume resources and complete; then
finish population/group/base integration and responsive UI layout across small viewports.
Driving, expanded foraging/cooking, advanced construction and broader offscreen encounters
remain separate unfinished breadth, not implicitly supplied by generic job infrastructure.
Runtime animation, crowded-area decisions, all-resolution layout, multi-day persistence
and measured gameplay FPS still require deferred in-game acceptance. Offline test success
does not establish a finished replacement or a defensible overall completion percentage.

### Companion synchronization recovery — 2026-09-05

Implemented; behavioral regression passes, live follow/base-supply verification pending.
The recent synchronization cache recorded success before setters completed, ignored
replacement player bodies/late Java bridge availability, and skipped base supply-trip
reconciliation whenever persisted duty was unchanged. Cache entries now commit only
after successful synchronization, compare the resolved player and bridge, and leave
base reconciliation active. Weak controller keys release retired runtime entries.
The regression executes the service with failure injection and covers retry, reverting
after partial failure, unchanged-update suppression, roster changes, player replacement,
late bridge availability, and base progress/replacement. No save schema or launcher change.

This audit compares the current rebuild with the feature-complete goal. It is a
current-state map, not a claim that passing standalone checks proves gameplay.

Status meanings:

- **Working** — implemented and supported by current live evidence.
- **Partial** — a real implementation exists, but required behavior or integration is missing.
- **Implemented, unverified** — the code and focused checks exist, but no adequate live pass exists.
- **Missing** — no production implementation was found.
- **Conflicting** — code or behavior currently violates the intended architecture.

## Verification baseline

Audited on 2026-08-27 against the current working tree. The Workshop staging folder
contains the same Java/Lua build described here; these changes are not yet committed.

- all 29 standalone Lua tests pass, including movement/flee policy and virtual-world travel;
- all mod Lua files parse with Lua 5.1;
- `:java:check :java:build stageWorkshop` passes, including the shell verifier under the
  game's Java 25 runtime plus the melee and zombie-visibility transformer verifiers;
- the 2026-08-27 logs exposed a malformed generated `getAlpha(int)` Code attribute that
  stopped every spawn/restore. Its byte count is corrected, the Java 25 verifier prevents
  recurrence, and the subsequent live run restored two saved survivors and moved them;
- survivor render alpha now fades against the real local player's square visibility while
  companion-duty survivors remain readable near their leader. Gameplay invisibility remains
  false, so render fog of war is not reused as targetability;
- commit `a00c8e2` restores `IsoPlayer.instance` immediately after the shell constructor,
  fixes the Survivor Card model-child order, and bounds detached-shell cleanup for every
  active survivor identity;
- commit `83f51d2` restores the native zombie attack lifecycle while keeping NPC shells
  out of local-player ownership branches;
- the current formation-recovery fix consumes movement failures into a bounded wait,
  preserves route cooldowns that were previously overwritten by the five-tick group
  refresh, cancels stale movement ownership, and records consecutive recovery attempts.

Neither uncommitted fix is considered working until a new live run confirms it.

### Movement ownership/recovery pass — 2026-08-28

**Status: Implemented, focused verification passes, live verification pending.**

Exact defects found:

- Java returned `MOVE_ALREADY_REQUESTED` for both an identical active destination and a
  changed destination, leaving Lua to cancel and retry instead of having one explicit
  replacement boundary.
- movement start/tick exceptions and terminal results could release the Java request flag
  without clearing every engine path, captured route, and human movement input;
- engine cancellation stopped at its first reflection failure instead of attempting the
  remaining cleanup steps;
- ordinary Lua movement failures used full dynamic result strings and a flat delay, which
  fragmented failure history and prevented bounded consecutive-failure backoff;
- formation refresh explicitly cancelled before requesting its replacement destination,
  creating an unnecessary gap between ownership release and reacquisition;
- controller shutdown did not explicitly cancel its current movement request.

Exact fix:

- `KnoxMovementRequest` now classifies a request as start, identical/keep, or replace.
  Identical destinations retain the active engine request and changed destinations cleanly
  release the previous request before starting the replacement.
- success, failure, cancellation, replacement, start failure, tick failure, stuck failure,
  and shutdown now converge on engine cleanup and Java ownership release. Cleanup attempts
  pathfinder cancellation, path detachment, captured-route clearing, and human-input clearing
  even if an earlier reflection call fails.
- Lua records stable movement failure categories, applies bounded exponential backoff, keeps
  that cooldown through ordinary decision/group refresh, and resets movement and formation
  failure streaks after successful movement. Temporary directive interruption still preserves
  the underlying companion Follow order.

Focused verification run:

- Lua 5.1 syntax check for `KS_SurvivorAutonomyController.lua`;
- `tools/test-autonomy-formation.lua`, including cooldown preservation, bounded backoff,
  stable diagnostic grouping, recovery reset, and interruption/order preservation;
- `:java:verifyMovementOwnership :java:build`, including duplicate suppression,
  destination replacement, release, failure recovery, and resume checks. The full Java check
  dependency set also passed against the locally configured Project Zomboid installation.
- the installed Build 42.20.3 `projectzomboid.jar` confirms the cancellation boundary used
  here: `PathFindBehavior2.cancel()`, `IsoGameCharacter.setPath2(Path)`, and the existing
  `pathToLocationF(float,float,float)` / `PathFindBehavior2.update()` request lifecycle.

Pending live acceptance is intentionally narrow: repeatedly change one follower/traveller's
destination across ordinary terrain and encounter at least one blocked route. Pass requires no
`MOVE_ALREADY_REQUESTED` storm, no stale-owner permanent idle, bounded failure recovery,
effective destination replacement, reset after success, and continued movement afterward.

### Multi-floor / Z-level navigation pass — 2026-08-28

**Status: Implemented, unverified.**

Exact defects found:

- the movement request preserved target Z and passed it to `pathToLocationF`, but runtime
  arrival, status, and stuck-distance checks compared only X/Y;
- the captured native route retained every node's Z, but the manual route consumer advanced a
  node using X/Y alone and explicitly failed every node on a different Z level;
- a native `Succeeded` result was accepted without independently confirming that the survivor
  reached the requested floor;
- route-length calculation ignored the Z component;
- formation proximity and direct companion-point arrival treated matching X/Y on another
  floor as close enough, although formation refresh already noticed target-Z changes.

Build 42.20.3 behavior inspected from the locally installed `projectzomboid.jar`:

- `IsoGameCharacter.pathToLocationF(float,float,float)` supplies the destination XYZ to
  `PathFindBehavior2`;
- `PathFindBehavior2.update()` submits start XYZ and target XYZ to native/PolygonalMap path
  requests, attaches the resulting `Path` to the character, evaluates the current XYZ against
  that path, and moves through normal `IsoGameCharacter.moveUnmodded(float,float)` behavior;
- native `PathNode` values contain X, Y, and Z, including floor-spanning routes;
- stair geometry is represented by `IsoGridSquare` stair direction/top/below state and
  min/max stair heights. Normal character movement owns the actual stair-height/Z transition.

Exact fix:

- `KnoxMovementGeometry` centralizes Z-aware arrival, route-node completion, and route-distance
  comparisons. Arrival now requires both XY tolerance and the destination floor.
- runtime completion re-reads the survivor's post-update position/current-square Z and converts
  a native success on the wrong floor or position into a normal movement failure before cleanup.
- captured native route nodes are retained until both their XY and Z are reached. A native path
  node changing one floor is consumed through ordinary human movement so engine stair geometry,
  not Knox, changes Z; larger Z jumps fail cleanly. No code sets, increments, snaps, or teleports Z.
- Lua formation/follow and companion-point proximity now reject wrong-floor closeness. A moving
  leader's target-floor change supersedes the active request through the Pass 1 ownership boundary.
- unreachable cross-floor paths continue through the existing stable failure category and bounded
  retry/backoff system.

Focused verification run:

- Lua 5.1 syntax checks for the controller and focused formation test;
- `tools/test-autonomy-formation.lua`, including same-XY/wrong-floor follow refresh, destination-Z
  retention, no cancellation gap, and bounded cross-floor failure recovery;
- `:java:verifyMovementOwnership :java:build`, including same-XYZ arrival, wrong-floor rejection,
  Z-preserving request construction, Z-aware route-node retention/release, floor replacement,
  terminal cleanup, and recovery. The complete Java check dependency set passed.

Pending live verification: in one loaded vanilla two-story building, send one survivor from
outside/ground floor to a destination away from the upstairs landing, then back to a destination
away from the downstairs landing, and repeat while following a leader who changes floors. Pass
requires native walking up and down stairs, continued travel after each landing, correct final-floor
arrival, no teleport/Z snap, request storm, stair stall, or wrong-floor completion. If convenient,
observe two survivors sharing the stairs without requiring any crowd/formation changes in this pass.

### Building traversal / obstacle interaction pass — 2026-08-28

**Status: Implemented, unverified.**

Exact defects found:

- after one native window-open attempt, the captured-route driver unconditionally started
  `smashWindow` if the window remained closed. Ordinary travel therefore escalated a locked or
  failed window into destructive entry without a survival or hostile reason;
- alternate entry recovery searched only windows, accepted closed locked/permanently locked or
  otherwise unusable windows, and could immediately select the edge on which the survivor was
  already standing;
- only a locked-door result entered alternate-entry recovery. Barricaded doors and failed,
  barricaded, or unclimbable windows abandoned the destination without checking another usable
  building entrance;
- traversal interaction state was cleared on route advance/cancellation, but a disappearing or
  replaced world obstacle on the current edge did not explicitly invalidate staged interaction
  intent.

Build 42.20.3 behavior inspected from the locally installed `projectzomboid.jar`:

- `IsoGridSquare.getDoorTo` supplies both ordinary `IsoDoor` and door-like `IsoThumpable`
  boundaries. Their native `ToggleDoor(IsoGameCharacter)` path owns locks, keys, obstruction,
  double-door, and gate behavior, so Knox continues to delegate the actual opening attempt;
- `OpenWindowState` owns the real opening animation and locked/permanently-locked outcome. Its
  success callback toggles the world window only for `IsoPlayer.isLocalPlayer()`, confirming the
  existing narrow Knox completion bridge is required for the contained off-slot shell while the
  surrounding native state remains intact;
- `IsoWindow.canClimbThrough(IsoGameCharacter)` and the native character window/frame climb APIs
  remain authoritative for open or broken windows. Knox does not remove glass, fake a world state,
  or move the survivor across the edge;
- `IsoGridSquare.isHoppableTo`, `IsoGameCharacter.climbOverFence`, `getWallHoppableTo`, and
  `climbOverWall` remain the native low-fence/wall boundary. No non-human obstacle class was added.

Exact fix:

- `KnoxTraversalPolicy` now makes the reflective execution boundary explicit: open doors pass,
  closed non-barricaded doors receive one native opening attempt, and barricaded doors fail safely.
  Windows receive one native open attempt, then either use native climbing once genuinely passable
  or fail as locked/unusable. Normal traversal no longer initiates window smashing;
- the existing off-slot window bridge runs only after native `OpenWindowState` reports success.
  Door, window, frame, fence, and wall interactions remain native actions/states, with no teleport
  or manual obstacle bypass;
- alternate-entry selection now considers open/unlocked doors and gates before usable windows,
  rejects locked/barricaded/permanently locked or unclimbable candidates, and excludes the exact
  edge that just failed. The Java cooldown still suppresses only that XYZ edge, leaving every other
  edge eligible;
- entry-specific failures share the same bounded alternate-entry recovery. Deliberate locked-door
  breaching remains restricted to the pre-existing urgent food/water/medical policy and protected-
  structure check; this pass did not broaden destructive behavior;
- traversal stays a sub-action of the original route. Advancing one obstacle node clears only the
  interaction target and retains later nodes/final destination; failure/cancellation clears both
  route and interaction ownership, and a changed/disappeared edge invalidates stale intent.

Focused verification run:

- Lua 5.1 syntax validation for `KS_SurvivorAutonomyController.lua`;
- `tools/test-autonomy-formation.lua`, including entry-failure classification and rejection of
  locked/unclimbable alternate candidates while preserving open door/window candidates;
- `:java:verifyTraversalPolicy :java:build`, including open/unlocked door policy, non-destructive
  locked-window failure, open/broken window climbing policy, exact-edge cooldown with another edge
  still eligible, interaction target replacement, route continuation, and interruption cleanup.
  The complete Java verifier/check dependency set passed against the configured game installation;
- `git diff --check` reported no whitespace errors (only the repository's existing line-ending
  conversion warnings).

Pending live verification is the pass's full acceptance gate: use one ordinary loaded vanilla
building to enter through a closed unlocked door, continue beyond it, exit by another door/gate,
climb a low fence, then enter through a usable window and continue to the final destination. Finally,
make the preferred edge locked/unusable and confirm the survivor abandons that exact edge for an
available entrance. Pass requires visible native interactions, no teleport or unnecessary damage,
no stop at the obstacle, retained final destination, no permanent idle, and no movement/traversal
request storm. If practical, repeat a doorway segment with two survivors.

### Companion follow / locomotion pass — 2026-08-28

**Status: Implemented, unverified.**

Exact defects found:

- companion slots were offset behind the leader, but the two-square arrival tolerance also
  considered the leader's exact tile close enough to the nearest diagonal slot. A companion could
  therefore deliberately stop stacked on the player rather than occupying its trailing square;
- pace was selected only when a follow route started or its destination materially changed. A
  follower whose destination remained stable could retain a stale sprint/run request as the gap
  closed;
- an explicit sprint request was not reduced according to remaining route distance. Physical
  condition could block sprint, but an eligible survivor could keep sprint intent through the final
  approach;
- sprint eligibility used Knox thresholds but did not consult Build 42's native `canSprint()` gate;
- successful close-range wait branches reset only the formation failure count, leaving the general
  movement recovery streak stale;
- normal decision flow respected Hold, but the follow start/refresh methods themselves had no Hold
  guard if stale state invoked them directly.

Build 42.20.3 behavior inspected from the locally installed `projectzomboid.jar`:

- `IsoGameCharacter.setRunning`, `setSprinting`, `isRunning`, `isSprinting`, and `canSprint` are the
  native locomotion state boundary. Native sprint eligibility can reject sprint independently of a
  Knox request;
- `AIComponent` exposes `AIBrainPlayerControlVars.running`, `justMoved`, `strafeX`, and `strafeY`
  for NPC player control, and `postUpdatePlayer` applies its running/just-moved state to the
  `IsoPlayer`;
- `IsoPlayer.updateInternal2` consumes native running/sprinting state for movement speed,
  animation, endurance, injury, and collision consequences. Knox therefore continues to request
  those states and does not modify position or speed values directly.

Exact fix:

- arrival now requires the follower to reach its actual trailing grid square. Primary slots remain
  stable and distinct by companion index, and the fallback refuses the leader's exact square;
- the existing 30-tick refresh cadence and meaningful slot-shift threshold remain intact. A new
  pace-only bridge updates the active Java movement request without cancelling, replacing, or
  duplicating its destination;
- distance-based selection remains calm: close followers request walk, moderate gaps run, and only
  far gaps request sprint. `KnoxLocomotionPolicy` then downgrades sprint to run and run to walk from
  remaining route distance and permits sprint only when health, endurance, fatigue, and native
  `canSprint()` allow it;
- sharp direction/floor changes still supersede the destination through the Pass 1 ownership
  boundary, while one-tile leader movement creates no replacement request;
- reaching the follow slot resets both formation and general movement recovery. Separated Follow
  companions continue to prioritize their durable follow order after legitimate survival
  interruptions; Hold is rejected at follow start and cancels any stale follow refresh.

Focused verification run:

- Lua 5.1 syntax validation for `KS_SurvivorAutonomyController.lua`;
- `tools/test-autonomy-formation.lua`, including non-leader/distinct slots, refresh cadence,
  sprint-to-run-to-walk pace-only changes without route requests, one-tile suppression, one sharp-
  direction replacement, catch-up recovery reset, and Hold protection;
- `:java:verifyCompanionLocomotion :java:verifyMovementOwnership :java:build`, including native
  sprint denial, health/endurance/fatigue eligibility, distance downgrades, and an active pace-only
  update that preserves movement ownership. The full Java verifier/check dependency set passed.

Pending live verification: recruit at least two companions, walk, run away, open a far sprint gap,
slow down, make repeated sharp turns, pass through the already-tested doors/stairs, stop, and move
again. Pass requires visible believable walk/run/sprint transitions, reliable catch-up and slowdown,
distinct trailing positions without permanent stacking, no request storm or stranded turn, and no
Follow behavior while a companion is on Hold. Static checks establish policy and ownership only;
the off-slot shell's visible native sprint speed/animation remains part of this live gate.

### Zombie / survivor melee parity pass — 2026-08-28

**Status: Implemented, focused verification passes, final live acceptance pending.**

Exact Build 42.20.3 boundary confirmed:

- standing and crawling zombies share native `AttackState`. Its collision callback checks range,
  floor/Z and world obstruction, then calls the target's real
  `BodyDamage.AddRandomDamageFromZombie(...)`, updates BodyDamage, applies hit reaction/death, and
  can repeat through later native attack cycles. Knox does not replace or imitate this damage;
- the contained shell has no local-player lighting entry. The one incompatible standing-zombie
  edge is `IsoZombie.isTargetVisible()` reading `IsoGridSquare.isCouldSee(shell.getIndex())`.
  The existing transformer remains limited to those two calls in that one method and accepts only
  the exact `KnoxIsoPlayerShell`; crawler logic remains untouched;
- survivor melee still enters `SwipeStatePlayer`. The existing three-call transformer remains
  limited to its collision and two swing-sound callbacks, leaving native hit selection, damage,
  endurance, weapon wear, blood, reactions, and death intact;
- `AttackState.AttackCollisionCheck` rejects a frontal bite while the target advertises a nonempty
  `AttackType`. Combat teardown previously cleared boolean attack input but not that animation
  variable or the attack-target square.

Exact defects found and fixed:

- live combat could begin even when the zombie-visibility transformer had failed or patched an
  unexpected Build 42 shape. Live combat now requires both the three-call survivor-melee patch and
  the exact two-call zombie-visibility patch to report ready;
- completion, invalid/unloaded combatants, pursuit failure, approach failure, and attack stall did
  not all release Java combat ownership themselves. Terminal results now converge on one reset;
- a thrown combat tick returned `COMBAT_FAILED` without resetting its controller. The registry now
  resets before returning that failure;
- reset did not cancel the combat route/pathfinder, clear `AttackType`, or clear the native attack
  target square. It now clears those independently from ordinary attack flags and AI control input;
- the Lua success path released its reservation and high-level state but did not explicitly reset
  Java combat. It now does so symmetrically with failure, while preserving the durable Follow/group
  order for the normal decision loop to resume;
- a dead survivor, detached survivor shell, or unloaded live zombie is abandoned immediately rather
  than leaving a combat owner pointed at an invalid world object.

Verification run:

- locally installed `projectzomboid.jar` bytecode inspected for `IsoZombie.getShouldAttack()`,
  `IsoZombie.isTargetVisible()`, `AttackState.animEvent/triggerPlayerReaction`, and
  `SwipeStatePlayer`; the native BodyDamage and exact off-slot visibility boundaries above are
  confirmed for Build 42.20.3;
- `:java:verifyMeleeCombatLifecycle` passes terminal attack-flag, `AttackType`, attack-square,
  AI-input, pathfinder, captured-route, and ownership cleanup;
- `:java:verifyCombatTransformer` passes with exactly three transformed calls;
- `:java:verifyZombieVisibilityTransformer` passes with exactly two transformed calls and a ready
  gate, and `:java:verifyZombieVisibilityRuntime` defines the transformed class under the game's
  Java 25 runtime;
- the full `:java:build` verifier set passes, including shell isolation, native corpse lifecycle,
  movement ownership, traversal, and companion locomotion regression checks;
- Lua 5.1 parses the affected autonomy and combat-scenario files;
  `tools/test-autonomy-formation.lua` and `tools/test-combat-scenario-reporting.lua` pass;
- the most recent available live log already contains repeated standing-zombie native evidence:
  `engineTargetVisible=true`, `bAttack=true`, `AttackDidDamage=true`, real survivor BodyDamage
  falling below 100, injured/bleeding parts, bite reactions, and repeated later attacks. That run
  predates this terminal-cleanup change, so it supports the native chain but not final acceptance.

Pending live acceptance remains the requested three scenarios: Survivor vs Zombie, Survivor vs
Crawler, and Survivor vs Zombie Group. Pass requires visible repeated native attacks and injuries,
survivor melee damage/kills and moving-target re-engagement, no attack-state or movement-request
storm, and ordinary movement/Follow resuming after combat. Firearms and tactical combat remain out
of scope.

### Survivor melee combat intelligence pass — 2026-08-28

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- threat selection performed two effectively identical zombie-list passes, so the second pass did
  not provide a real fallback and repeated the most expensive part of the scan;
- target relevance was mostly expressed as large bonuses plus distance. Retarget hysteresis was
  only one tile and could be bypassed by any candidate within two tiles, permitting target churn
  without a meaningful danger change;
- a current target that died, unloaded, changed floor, left the survivor's awareness, or pulled a
  follower away from its role had no decision-layer abandonment gate before the next native combat
  tick;
- defensive companions protected only themselves and the owning player, not another nearby group
  member under attack. Aggressive companions had no group/leader chase leash;
- ordinary visible threats allowed three reservations, causing avoidable dog-piling even when other
  threats existed;
- symmetric threat positions selected a random flee direction on each attempt, and a completed
  group flee could reuse the same short-lived destination;
- `FLEEING` was considered a movement state for timeout accounting but was absent from the movement
  branch that calls `tickNpc`, so a valid flee request could remain owned without completing through
  the normal success/failure lifecycle;
- retreat never required a bounded safe confirmation to disengage. A failed flee start could clear
  native combat but leave the Lua state in combat or reacquire an attack during the same danger
  scan, bypassing movement recovery cooldown.

Exact fix:

- one bounded scan now evaluates each loaded same-floor zombie once. Immediate threats, zombies
  attacking the survivor, and zombies attacking a nearby ally have explicit priorities; distance
  and existing reservations break ties without replacing a valid target for marginal gains;
- retargeting requires a meaningful score improvement, with a stricter emergency threshold during
  the cooldown. Dead, unloaded, wrong-floor, irrelevant, or role-leash-breaking targets are dropped
  before native combat is ticked;
- defensive companions can help any nearby tracked group member. Follow/group combat remains
  anchored to a twelve-tile role leash unless the survivor itself is the target; ordinary distant
  visible zombies permit one attacker, immediate/group/player threats two, and a survivor's active
  attacker three;
- retreat geometry is weighted away from close threat pressure, selected deterministically when
  vectors cancel, and biased toward the prior safe direction for the short flee-plan lifetime.
  Loaded group members keep the existing shared destination with separate arrival offsets. The
  original fixed health/three-zombies-per-ally trigger was replaced by the capability-and-pressure
  assessment documented in the 2026-08-30 retreat-risk follow-up below;
- flee movement now runs through the same Java movement tick and terminal cleanup as other travel.
  Two consecutive safe scans end retreat, while failed route acquisition and failed movement retain
  bounded retry timing and cannot reacquire combat in the same scan;
- native Pass 5 melee approach, moving-target pursuit, attack animation/collision, BodyDamage,
  weapon/endurance effects, death, and terminal combat cleanup remain unchanged. This pass adds no
  alternate damage, coordinate movement, firearm logic, or tactical framework.

Verification run:

- Lua 5.1 syntax validation passes for all 62 mod Lua files;
- `tools/test-combat-intelligence.lua` passes immediate-vs-distant priority, stable current target,
  emergency retarget, dead/unloaded cleanup, nearby ally defense, leader chase leash, reservation
  deconfliction, deterministic flee direction, two-scan safe exit, one owned flee movement, arrival
  cleanup, and preservation of the durable Follow order;
- `tools/test-autonomy-formation.lua`, `tools/test-combat-scenarios.lua`, and
  `tools/test-combat-scenario-reporting.lua` pass as movement/group/scenario regressions;
- full `:java:build` passes against the configured Build 42.20.3 installation, including native
  melee lifecycle, zombie visibility, movement ownership, traversal, locomotion, corpse lifecycle,
  and transformer verifiers. No Java or engine-adapter change was needed for this decision pass;
- `git diff --check` reports no whitespace errors; existing line-ending conversion warnings remain.

Pending live acceptance: run one survivor and then a small companion/group against one zombie,
several spaced zombies, a small cluster, and an overwhelming group. Pass requires stable sensible
target choice, visible native spacing/repositioning, nearby ally defense, no blind charge into the
overwhelming case, coherent injured/outnumbered retreat, no immediate turn-back or request storm,
and resumption of the prior Follow/Hold/travel role after danger clears. Firearms remain explicitly
out of scope.

### Survivor firearm / ranged combat pass — 2026-08-28

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- live combat never assigned the captured weapon to `rangedWeapon`, so a firearm entered the melee
  request path despite the existing distance calculation;
- ranged stance set `setAuthorizeMeleeAction(false)`, but Build 42.20.3 uses that legacy-named method
  as the general `IsoPlayer.DoAttack` authorization gate. The shipped firearm hook therefore refused
  the off-slot survivor's shot;
- Java called `pressedAttack()` directly. That bypassed the shipped Lua firearm hook that plays the
  gun sound, adds normal world noise, and enters `DoAttack`;
- readiness was checked before combat selection but not while combat owned the survivor. Empty,
  unchambered, jammed, or actively reloading weapons could therefore continue through attack logic;
- the reload planner treated any compatible magazine as usable, including an empty magazine with no
  loose rounds, and treated any character timed action as reload ownership. This could produce reload
  retries or suppress combat for an unrelated action;
- a loaded weapon needing a rack had no native rack path, and no-ammo fallback reported melee without
  ensuring that a carried melee weapon was equipped;
- ranged combat had no bounded close-distance policy, always aimed above floor targets, and did not
  fail if the weapon changed while the encounter still owned the old one.

Exact fix:

- live combat now captures firearm identity and ranged mode. Weapon changes terminate the stale owner;
  dead/unloaded targets and all terminal paths still converge on the existing combat teardown;
- Java owns facing, floor aim, useful range, and one native path request, then emits
  `COMBAT_FIREARM_REQUEST`. Lua answers it once through Build 42.20.3's exact
  `ISReloadWeaponAction.attackHook`; Knox adds no bullet counters, ranged damage, or duplicate sound;
- the native hook now receives the required general attack authorization. Vanilla remains responsible
  for `DoAttack`, ranged collision/ballistics, damage, chamber and magazine mutation, jamming, weapon
  condition, gunshot audio, and zombie-attracting world sound;
- the firearm planner uses `canShoot`, `canRack`, `ISRackFirearm`, `BeginAutomaticReload`, and the real
  timed-action queue. Only a loaded compatible magazine or compatible loose ammunition makes an empty
  weapon reloadable, and an action owns preparation only when it references that firearm or its
  compatible magazine;
- combat yields while native rack/reload owns the survivor, then reevaluates the real equipped weapon.
  No compatible ammunition equips the best actual carried melee weapon instead of looping;
- close ranged pressure uses an existing native range-route helper with a 60-tick reposition cooldown.
  It stops backing away at useful distance; a blocked close reposition produces a dedicated melee
  fallback without suppressing the adjacent threat. Long-range unreachable targets retain the normal
  bounded failure cooldown;
- underlying Follow, Hold, and group directives are not rewritten by firearm preparation or combat;
  the normal controller decision loop exposes them again when ranged ownership ends.

Verification run:

- exact installed Build 42.20.3 Lua and bytecode were inspected for
  `ISReloadWeaponAction.canShoot/canRack/BeginAutomaticReload/attackHook`, `ISRackFirearm`,
  `IsoPlayer.DoAttack`, `CombatManager.pressedAttack`, and `OnWeaponSwingHitPoint`; these confirm the
  authorization, sound/world-noise, native attack, and ammunition/chamber ownership boundaries above;
- `tools/test-firearm-support.lua` passes loaded and partially loaded readiness, native automatic
  reload, duplicate reload suppression, reload completion, native rack, no-ammo and safe-mode melee
  fallback, explicit close-position fallback, and single native firing-hook ownership;
- `:java:verifyMeleeCombatLifecycle` passes ranged identity cleanup, general authorization, Java-to-Lua
  attack handoff, bounded distance/reposition policy, and the existing melee ownership checks;
- Lua 5.1 syntax validation passes for all 62 mod Lua files;
- `tools/test-combat-intelligence.lua`, `tools/test-autonomy-formation.lua`,
  `tools/test-combat-scenarios.lua`, and `tools/test-combat-scenario-reporting.lua` pass as
  target/retreat, durable-order, movement, and scenario regressions.

Pending live acceptance: run a survivor with a loaded pistol and spare ammunition, a partially loaded
weapon, an empty weapon with compatible ammunition, an empty weapon without compatible ammunition,
and zombies closing from useful range to point-blank range. Pass requires visible native aim/fire,
real damage and ammunition consumption, visible native reload and resumed firing, no reload/fire loop,
bounded reposition or melee fallback, normal gunshot sound/attention, clean combat completion, and
resumption of the prior companion/travel order. Advanced tactical/group firearm behavior remains out
of scope.

### Human survival autonomy pass — 2026-08-29

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- the priority order already placed threats, bleeding, thirst, hunger, endurance, and fatigue in a
  sensible sequence, and item consumption/treatment already used native actions, but the controller
  treated an empty timed-action queue as successful self-care without verifying a real stat or
  `BodyDamage` change;
- an invalidated or failed eat, drink, bandage, or improvised-treatment action could therefore count
  as completed and be selected again after the ordinary short think delay;
- action ownership did not retain the selected need, original stat state, treatment body part, or
  item long enough to distinguish completion from cancellation;
- danger cleared native timed actions indirectly when combat began, but self-care had no explicit
  interruption record. Rest posture and sleep ownership were not one coherent cancellation boundary;
- fatigue selected the existing sit/rest path. Build 42 sitting restores endurance, but it does not
  provide the native sleep-driven fatigue recovery required by that decision;
- rest timeout released the state without distinguishing real recovery from a posture/action that
  never changed endurance.

Exact fix:

- the priority remains deliberately small: immediate danger, bleeding treatment, critical thirst,
  critical hunger, low-endurance rest, sleep-required fatigue, then the existing normal activity;
- carried safe food and clean water are still selected recursively and consumed only by
  `ISEatFoodAction` and `ISDrinkFromBottle`. Basic treatment still uses the real `BodyDamage` part,
  carried bandage item, `ISApplyBandage` behavior, and existing real-item improvisation recipe;
- each queued self-care action now owns an intent containing its kind and authoritative pre-action
  state. Queue completion counts only after hunger, thirst, bandage/bleeding state, produced medical
  supply, endurance, or fatigue changes through the native mechanic;
- a no-change completion or action-construction failure receives a 300-tick need-specific retry.
  The need remains visible, but Follow, Hold, group travel, or roaming can proceed during that bound
  instead of requesting the same action every tick;
- immediate danger explicitly interrupts the self-care owner, clears its timed action or movement,
  releases reserved furniture, and wakes a sleeping survivor through the native sleeping event.
  The durable companion/group order is never rewritten, so the need can be reconsidered after danger
  and the prior activity resumes after successful care;
- endurance continues to use `ISRestAction`/`ISSitOnGround` and real `CharacterStat.ENDURANCE`.
  Fatigue now uses Build 42.20.3's `setBed`, `setBedType`, `setForceWakeUpTime`, `setAsleep`, and
  `SleepingEvent.setPlayerFallAsleep` boundary. Knox does not modify fatigue or endurance directly and
  does not invoke local-player fade, save, or time-speed controls for the off-slot shell;
- sleep searches only actual bed furniture before using the native floor fallback; ordinary rest may
  still choose the most comfortable valid seat. Native wake or a bounded stuck-sleep safeguard must
  produce a real fatigue decrease before sleep is counted as complete.

Verification run:

- exact installed Build 42.20.3 Lua was inspected for `ISEatFoodAction.complete`,
  `ISDrinkFromBottle.complete`, `ISApplyBandage.complete`, `ISRestAction`, and the player sleep context
  transition; installed `SleepingEvent` bytecode confirms off-slot wake avoids local-player UI work;
- `tools/test-survivor-needs.lua` passes meaningful thresholds, danger/bleeding/thirst/hunger priority,
  safe carried food and water selection, no-resource handling, one native action owner, real-state
  completion verification, endurance recovery, native sleep, and danger wake;
- `tools/test-combat-intelligence.lua` passes bounded self-care retry, danger interruption, stale-owner
  cleanup, and durable Follow-order preservation alongside its combat/retreat regressions;
- `tools/test-autonomy-formation.lua` and `tools/test-unloaded-survival.lua` pass as durable-order,
  movement-interruption, and stored-survival regressions.

Pending live acceptance: observe one survivor becoming thirsty, hungry, low on endurance, fatigued,
and mildly bleeding while carrying the appropriate real supplies. Introduce a zombie during one
self-care action. Pass requires visible native actions where supported, real inventory/stat/BodyDamage
changes, no repeated action storm, danger interruption and later reconsideration, native fatigue and
endurance recovery, and resumption of the prior Follow or roaming behavior. No camp, job, advanced
looting, crafting, UI, dialogue, or social behavior was added in this pass.

### Loaded roaming autonomy pass — 2026-08-29

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- useful ranked containers already outranked optional wandering, but the fallback selected the first
  random standable tile within 6–18 squares and carried no reason or destination identity;
- completed and failed plain-roam destinations had no short-term memory, allowing immediate return,
  two-point bouncing, or repeated requests toward the same failed area;
- container arrival marked the container inspected for the controller's entire loaded lifetime,
  rather than using lightweight expiring knowledge that can reflect later world changes;
- roaming checked danger frequently, but meaningful hunger, thirst, treatment, or recovery needs
  were reconsidered only after the current movement ended;
- no-destination fallback retried after the ordinary short think delay instead of an explicit bounded
  no-goal delay.

Exact fix:

- the existing ranked looting planner and traversal executor remain unchanged. Nearby useful items
  are still selected first and inventory capacity still limits actual transfers;
- when no worthwhile container is available, loaded independent survivors now prefer a nearby
  standable building interior, then a nearby standable area. Distance is bounded to the existing
  6–18-square roaming envelope, so low-value fallback travel cannot become a cross-map route;
- candidates with more than two zombies within six squares are rejected before movement begins.
  Existing combat and flee policy remains authoritative once a threat engages or becomes immediate;
- each destination has a building/area identity. A bounded twelve-entry loaded-session memory cools
  completed/current areas for 900 ticks and failed destinations for 1800 ticks. Entries expire and
  are not persisted as permanent world knowledge;
- movement owns the chosen goal until success, explicit interruption, timeout, or failure. Success
  and failure release its identity; repeated failures therefore force a different candidate while
  the existing movement backoff remains intact;
- every 90 ticks, active roaming may yield to an existing real self-maintenance decision. It cancels
  only the roam movement owner, then lets the normal needs controller execute and later reselect a
  roaming goal. Threat scans retain higher priority;
- completed looting/searching still forces travel away, but inspected-container memory now expires.
  No new planner, looting categories, camp, faction, mission, UI, or social behavior was introduced.

Verification run:

- `tools/test-roaming-autonomy.lua` passes useful-over-arbitrary selection, recent-failure
  suppression and expiry, obvious-danger rejection, active-goal stability, self-care preemption,
  destination cleanup, and bounded no-goal reconsideration;
- `tools/test-survivor-looting.lua` now exercises the exported real planner and passes the existing
  Build 42 item-without-`isAmmo` regression; exporting the already-global module changes no gameplay;
- `tools/test-survivor-needs.lua`, `tools/test-combat-intelligence.lua`, and
  `tools/test-autonomy-formation.lua` pass as self-care, threat/flee, durable-order, and movement
  interruption regressions;
- Lua 5.1 syntax validation passes for all 62 mod Lua files.

Pending live acceptance: observe one independent survivor for several in-game hours in a normal
urban area. Pass requires a plausible nearby destination, normal travel and building entry, at least
one useful search/transfer, departure or reselection afterward, danger response, self-care when
needed, and resumed autonomy without back-and-forth movement, repeated failed destinations, idle
stalling, goal churn, dangerous-area selection, or movement-request spam.

### Temporary camp living pass — 2026-08-29

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- temporary camps persisted one faction/building marker, but loaded controllers were never assigned
  that camp, so members had no return intent, occupancy slot, camp idle state, or post-combat resume;
- the camp record did not retain its loaded building bounds or a synchronized member list, leaving no
  stable save/load boundary for occupant positioning or duplicate/stale-member cleanup;
- camp reconciliation only created/touched the leader's record. It did not bind other active faction
  members or clear runtime ownership after camp removal or permanent-home conversion;
- no camp behavior selected distinct standable positions, natural bounded rest/idle, or an ordinary
  survival excursion. Existing faction formation behavior therefore remained the only loaded activity;
- real nearby containers were already reachable through needs/ranked looting, but camps correctly had
  no abstract storage and this pass found no safe reason to create one.

Exact fix:

- camp records now retain building bounds and a deduplicated living-member snapshot synchronized from
  the durable faction, which remains the single source of survivor affiliation. Registration restores
  the link immediately and low-frequency reconciliation repairs it thereafter;
- each active member receives a stable slot. Loaded standable squares inside the exact camp building
  are sorted deterministically, rotated by slot, and protected by short-lived runtime reservations so
  members do not intentionally stack. No coordinates or movement speed are modified;
- a member away from camp starts one native movement request back to an available camp square. Success
  enters bounded camp idle; failure releases the square and retains existing movement backoff for a
  later retry;
- camp idle choices are deliberately small and slot-staggered: use normal sitting/rest furniture or
  ground rest, reposition to another valid shelter square, wait quietly, or begin a bounded survival
  excursion. This avoids synchronized behavior, constant pacing, and indefinite frozen idle;
- excursions preserve camp identity, use Pass 9 roaming, permit at most one existing ranked container
  exploration outside, then return. Hunger, thirst, injury, fatigue, inventory capacity, traversal,
  and real item transfers remain owned by their established systems;
- nearby danger and combat still preempt camp activity through the existing threat/group-defense path.
  Camp fields are not cleared, so return/idle resumes after combat rather than rebuilding the camp;
- clearing the camp or establishing a permanent faction home removes the persisted camp link and the
  next reconciliation releases runtime position ownership. Shutdown also releases its camp square;
- real camp-building containers can satisfy ordinary carried-supply searches. No abstract stockpile,
  generated resources, camp jobs, construction, mission, strategy layer, or UI was added.

Verification run:

- `tools/test-faction-camps.lua` passes one-camp identity, durable member linkage, duplicate-free
  reconciliation, deliberate removal/replacement, and permanent-home conversion cleanup;
- `tools/test-camp-living.lua` passes exact shelter containment, distinct member positions, stable
  member slots, staggered ambient choices, assignment during combat, preserved excursion/home intent,
  native return request, and runtime cleanup;
- roaming, ranked looting, self-maintenance, combat intelligence, formation/movement, ambient rest,
  and faction persistence regression suites pass unchanged;
- Lua 5.1 syntax validation passes for all 62 mod Lua files.

Pending live acceptance: use one temporary shelter with at least two survivors. Pass requires distinct
occupancy, at least one natural idle/rest/self-care action, one normal excursion and return, nearby
zombie defense followed by resumed camp behavior, and save/reload restoration of the same camp/member
links without stacking, pacing, permanent freeze, duplication, or detachment.

### Group and faction relationship coherence pass — 2026-08-29

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- persisted affiliation, travel-group rosters, and faction rosters could contradict one another after
  an interrupted migration or stale copy; `getTravelGroupFor` returned the first `pairs()` match, so
  the selected group was not deterministic;
- death marked the survivor inactive but left the ID in travel groups, faction leadership, and camp
  occupancy, allowing dead leaders and stale active membership to survive reload;
- joining a group wrote an allied encounter flag, but friend/neutral/hostile classification had no
  single persisted authority shared by loaded ally assistance and future survivor-combat gates;
- player recruitment removed ordinary NPC copies but could retain a contradictory player-faction copy,
  while dismissal removed only the affiliation's expected faction rather than every stale roster;
- transient controller group lists recognized only currently assigned character references, so a loaded
  same-faction ally outside that cache was not protected by the existing ally-under-zombie-attack score.

Exact fix:

- schema 12 retains the existing identity, affiliation, duty, group, faction, camp, pair relationship,
  player trust, and faction relationship records. No competing social manager or runtime ownership was
  added;
- `getSurvivorDisposition` now derives self/allied/neutral/hostile from stable IDs. Shared player owner,
  travel group, or faction is allied; explicit personal hostility and then symmetric faction disposition
  apply across different memberships; unrelated living survivors remain neutral. Dead IDs are never
  active hostile targets;
- group creation/join records mutual alliance. Existing hostile encounter records remain durable, but a
  valid shared membership overrides stale pair hostility instead of permitting friendly targeting;
- save-start normalization deduplicates living rosters, honors a valid player/companion owner first,
  rejects player survivors from NPC travel groups, removes contradictory group/faction copies, repairs
  missing leaders deterministically, synchronizes camp occupants, and clears orphan camps/factions;
- group lookup is deterministic even before normalization and prefers the group matching authoritative
  faction affiliation. Group removal clears every stale group copy rather than one arbitrary match;
- death releases base claims and removes the ID from active group, faction, and camp rosters, repairs
  surviving leadership, and records a deceased duty/affiliation while preserving former affiliation and
  historical relationship records;
- the existing zombie threat score now resolves a loaded target character back to its stable survivor ID
  and recognizes persisted allies. This extends ally protection only; survivor PvP, raids, tactics, and
  diplomacy progression remain outside this pass.

Verification run:

- `tools/test-relationship-coherence.lua` passes same-membership ally precedence, neutral default,
  persistent personal/faction hostility, contradictory membership normalization, player-companion
  ownership, leader replacement after death, camp cleanup, and relationship/group/faction restoration
  after a simulated Lua reload with no runtime cache;
- `tools/test-combat-intelligence.lua` passes persisted-ally protection outside transient group-character
  lists as well as its established target, retreat, self-care-interruption, and order-resume checks;
- faction persistence, faction diplomacy, companion/base domain, faction camps, temporary camp living,
  and formation/movement focused regressions pass unchanged;
- Lua 5.1 syntax validation passes for all 62 mod Lua files and all 40 focused Lua tests pass. The one
  stale companion-vehicle source assertion was updated to the already-correct Build 42
  `Vehicles/TimedActions` module path; no vehicle behavior changed;
- `gradlew :java:build stageWorkshop` passes all 17 tasks, including movement, traversal, locomotion,
  melee, corpse, shell-policy, and zombie-visibility verifiers. The staged persistence/controller files
  match the repository byte-for-byte.

Pending live acceptance: use a player companion, two members of one NPC group/faction, one neutral, and
one existing hostile survivor. Pass requires no friendly targeting, visible help for an ally under zombie
attack, stable membership through separation/combat/camp activity, unchanged neutral and hostile states,
save/reload and unload/restore preservation, and clean surviving membership after one member dies. The
current survivor combat executor still targets zombies only, so this pass validates persisted hostility
and target legality but does not claim live survivor PvP.

### Human-to-human encounter pass — 2026-08-29

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- every eligible nearby independent pair could begin a meeting from the old 24-tile attraction range;
  the result forced immediate joining, declining, or first-aggression without a calm neutral outcome;
- one observer scan could queue two pending meetings for the same survivor, especially around a small
  cluster, producing repeated greeting/approach ownership;
- direct persisted hostility was stored correctly but could re-enter the friendly greeting flow; and
  aborted/membership-changed meetings could clear their pending record without reliably resuming both
  controllers;
- group followers could independently initiate a social encounter even though the durable group leader
  is the social owner.

Exact fix:

- the existing persisted self/allied/neutral/hostile classifier is now consulted before encounter work.
  Allies never start a social interaction; known hostile pairs keep distance and preserve hostility;
  neutral survivors remain neutral unless the established first-aggression path selects hostility;
- awareness remains 14 tiles but cautious approach is bounded to 10. A neutral first meeting resolves
  deterministically to a brief greeting or a short keep-distance memory, never forced joining;
- joining now requires at least two recorded meetings plus shared survival activity. Existing player
  recruitment rules, trust requirements, refusal handling, and group/faction restrictions remain the
  authoritative recruitment path. A failed low-trust player recruitment now stores a half-hour retry on
  that existing player relationship rather than accepting repeated context-menu requests;
- a scan reserves each participant after its first interaction decision and only a persistent group
  leader may initiate with a loner. Completed greetings store a six-hour neutral cooldown; avoided pairs
  receive a shorter cooldown; aborts receive a bounded recovery cooldown;
- completed, timed-out, combat-interrupted, membership-changed, or unloaded meetings resume any loaded
  waiting controller. No combat, raid, faction, camp, UI, mission, or diplomacy feature was added;
- existing first-aggression robbery remains unchanged. Native survivor-versus-survivor combat is still
  absent, so a known hostile pair is deliberately not routed through zombie-only combat code.

Verification run:

- `tools/test-human-encounters.lua` passes allied/neutral/hostile classification, cautious neutral
  greeting without automatic group creation, greeting cooldown, single-pair ownership in a three-survivor
  cluster, normal controller resumption, and hostile social suppression;
- `tools/test-relationship-coherence.lua` passes persistent hostility, companion ownership, group/faction
  normalization, camp linkage, death cleanup, and simulated reload restoration;
- `tools/test-companion-base-domain.lua` passes the persisted player recruitment-refusal cooldown alongside
  existing recruitment, companion ownership, base-resident, and task-domain checks;
- combat-intelligence, companion/base, faction/camp, formation, and prior relationship focused tests are
  rerun with the cumulative verification below;
- Lua syntax and full Java checks are run after the pass. No Build 42 engine hook changed because this
  slice only coordinates existing loaded `IsoPlayer` controller states.

Pending live acceptance: use two neutral independent survivors, then recruit one through the existing
player interaction. Confirm one cautious greeting at most, no neutral fighting or repeated greeting,
normal roaming afterward, and correct companion takeover after recruitment. Observe a pre-existing hostile
pair separately: it must not perform friendly greeting and hostility must persist through reload. Human PvP
is intentionally not claimed until its native engine boundary is implemented and verified.

### Companion command reliability pass — 2026-08-29

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- Follow or Hold replaced only the saved primary order. A previously issued Move or Guard directive
  remained attached, so the controller could continue the old point command instead of honoring the
  player's replacement order;
- a companion moved to a base could retain a runtime-only directive until a later controller refresh;
- directive persistence accepted non-finite coordinates and inverted rectangles, allowing malformed
  old save data to keep a controller in an impossible temporary command.

Exact fix:

- `updateCompanionOrder` now clears the temporary directive in the same persisted duty revision. The
  primary Follow/Hold order remains the sole durable intent after replacement; Guard keeps its existing
  underlying Follow/Hold duty and therefore resumes it after combat, self-care, traversal, or movement
  recovery;
- controller cleanup now treats its temporary directive as companion-owned runtime state and clears it
  with the companion order when a survivor changes to Base or autonomous duty;
- `isValidCompanionDirective` validates kind, finite bounded coordinates, and rectangle order at
  the persistence boundary. The loaded controller clears a malformed restored directive once and resumes
  the saved primary duty instead of retrying it indefinitely.

Verification run:

- `tools/test-companion-commands.lua` passes primary-order replacement, Guard's preserved underlying
  Hold order, malformed directive rejection and cleanup, Return to Base duty replacement, and safe
  Dismiss ownership release;
- existing companion/base-domain, unloaded-base-return, and formation/recovery regressions pass unchanged;
- Lua 5.1 syntax validation passes for all 62 mod Lua files;
- `gradlew :java:build stageWorkshop` passes all 17 tasks, including the movement, traversal,
  locomotion, melee, corpse, shell-policy, and zombie-visibility verifiers. The changed Lua files are
  staged for the Workshop build.

Pending live acceptance remains the requested Follow, Hold, Move, Guard, Return to Base, save/reload,
and Dismiss sequence; no new command type or UI behavior was added.

### Group travel and cohesion pass — 2026-08-29

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- leader-relative slots were already distinct in open space, but every group controller refreshed on the
  same cadence, making a tight group more likely to request a shared doorway/window edge together;
- an existing dead or stale runtime member could still be chosen as the leader's most distant member,
  leaving the leader in unnecessary retrieval/wait behavior;
- known door/window traversal failures during group travel entered the generic formation-failure path,
  raising the failure streak instead of giving the group a short bounded chance to clear the bottleneck.

Exact fix:

- existing formation slots remain unchanged. Group-only refreshes now use a tiny deterministic per-slot
  offset, so members retain their nearby distinct destinations while avoiding synchronized refresh bursts;
- dead members are excluded from the existing leader retrieval scan. No group membership or persistence
  behavior changed;
- known existing traversal-block results during Group Follow/Regroup now release the active move and enter
  a 90-tick `GROUP_WAIT`. This does not retry every tick or grow the formation-failure streak; ordinary
  failures still use the established bounded backoff and all native door/stair/window/fence handling stays
  in its existing traversal boundary;
- combat, self-care, command, group roster, and travel intent boundaries were left intact. Temporary
  interruption continues to retain group leader/member references so normal group movement can resume.

Verification run:

- `tools/test-autonomy-formation.lua` now passes three distinct group targets, staggered refresh behavior,
  bounded door/window bottleneck waiting without a formation-failure increment, dead-member retrieval
  exclusion, group interruption preservation, and existing movement/recovery coverage;
- companion-command and relationship-coherence regressions pass unchanged;
- Lua 5.1 syntax validation passes for all 62 mod Lua files and all 42 focused Lua tests pass;
- `gradlew :java:build stageWorkshop` passes all 17 tasks. Java movement/traversal/locomotion verifiers
  remain green, and the changed controller is staged for the Workshop build.

Pending live acceptance is the requested three-survivor outdoor/building/door/stair and deliberate-separation
sequence. No formation type, crowd simulation, command, or tactical behavior was added.

### Human perception and awareness pass — 2026-08-29

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- an idle zombie inside the 3.5-tile immediate radius was treated as perceived even when Build 42's
  `IsoGameCharacter.CanSee` returned false, allowing survivor awareness through an adjacent wall;
- survivor combat dropped a valid target immediately after line-of-sight was lost, permitting
  acquire/drop flicker, while all controllers initialized their loaded-zombie scan on the same tick;
- the off-slot zombie-awareness adapter selected the nearest NPC inside 20 tiles using distance and Z
  only. It also refreshed `lastSeen` whenever the NPC remained the assigned target, so its nominal
  180-tick memory could never expire behind a wall;
- ordinary human encounter proximity used distance and Z only, allowing meetings and greetings without
  either survivor having native line-of-sight.

Exact Build 42.20.3 boundary and fix:

- the installed `projectzomboid.jar` confirms `IsoGameCharacter.CanSee(IsoObject)` calls
  `LosUtil.lineClear(...)` between the two grid coordinates and accepts every result except `Blocked`.
  Knox now uses this native geometry result for loaded survivor-to-zombie, zombie-to-survivor, and
  human-to-human acquisition; no custom raycast, room graph, render visibility, or local-player LOS slot
  was added;
- same-floor, distance, validity, role-leash, and native targeting gates remain intact. Immediate distance
  now increases priority only after ordinary native visibility succeeds. A zombie already targeting the
  survivor or a nearby ally remains meaningful native evidence rather than an omniscient radius result;
- survivors retain a lost visible threat for at most 120 controller ticks and only inside the existing
  disengage range. The memory does not refresh without new perception and clears on expiry, death,
  unload, floor change, failure suppression, or role-leash loss;
- the zombie adapter now discovers only same-floor NPCs which pass the zombie's native `CanSee` result.
  Its 180-tick memory updates only on real perception (or an explicit developer combat scenario), and
  close attack-gate refresh stops when native LOS is blocked. A native target assignment may seed that
  bounded memory once as engine hearing/awareness evidence; after the memory expires, Knox releases only
  that stale NPC target because the off-slot visibility adapter has no local-player lighting slot through
  which vanilla can expire it. The existing narrow off-slot visibility transformer remains unchanged;
- human encounter observation now requires at least one participant's native `CanSee` result as well as
  the existing same-floor/range gate. Existing ally, neutral, hostile, recruitment, and cooldown state is
  still authoritative;
- controller threat scans retain their 15-tick cadence but receive a deterministic per-survivor offset,
  spreading a group's loaded-zombie list work rather than performing all scans on one tick;
- no synthetic hearing radius was added. Build 42 exposes zombie world-sound handling, but no verified
  automatic off-slot survivor sound-consumer boundary was found; existing native target/noise state is
  used where it already supplies evidence.

Verification run:

- `tools/test-combat-intelligence.lua` passes visible acquisition, blocked-LOS rejection, bounded lost
  memory and expiry, different-floor rejection, stable target behavior, deterministic scan staggering,
  and its prior combat-intelligence regressions;
- `tools/test-zombie-awareness.lua` passes native-LOS discovery, blocked-LOS rejection, bounded adapter
  memory, expiry without false refresh plus stale-target release, different-floor rejection, stable
  active-target refresh, close attack refresh, and balanced player/NPC target switching;
- `tools/test-human-encounters.lua` passes blocked-LOS and different-floor rejection plus its existing
  classification, single-owner greeting, cooldown, resume, and hostile-suppression checks;
- all 42 focused Lua tests pass and Lua 5.1 syntax validation passes for all 62 mod Lua files;
- `gradlew :java:build stageWorkshop` passes all 17 tasks, including the unchanged off-slot visibility,
  shell ownership, movement, traversal, locomotion, melee, and corpse verifiers. The updated Lua is staged.

Pending live acceptance is the requested outdoor, exterior wall, adjacent room, upstairs/downstairs,
approach, loss/death, and ally-threat sequence. Pass requires believable acquire/lose timing, no
through-wall or cross-floor awareness, no target flicker, bounded clearing, ally response, and resumption
of the survivor's prior roaming/follow behavior. Sound-specific survivor reactions are not claimed until
a real off-slot Build 42 sound input can be verified.

### Equipment and inventory intelligence pass — 2026-08-29

**Status: Implemented, focused verification passes, live acceptance pending.**

Exact defects found:

- the existing Java melee helper selected the best carried weapon but equipped it every time a caller
  asked, even when the current usable melee weapon was effectively equivalent;
- firearm preparation could select a different ready/reloadable gun on each refresh and re-enter the
  Java equip bridge even when the current gun was already the stable choice;
- autonomous loot completion used direct Lua worn-item assignment and always called the melee helper.
  That bypassed the existing record-capture boundary for worn gear and made a tiny post-loot upgrade able
  to trigger needless visual/model changes;
- existing recursive loot classification safely handled the known missing `isAmmo()` method, but other
  unknown/modded subtype methods could still be called directly.

Exact fix:

- added a small loaded-world equipment evaluator. It examines only items already in the survivor's root
  inventory, never searches containers/world squares, creates no items, consumes no food/water/medical
  reserve, and runs only when idle or once after a completed loot action;
- usable melee requires a real non-broken `HandWeapon`. It switches only for a 1.25-point meaningful
  score gain; a ready non-broken firearm is retained for the firearm controller rather than displaced by
  idle melee management;
- ready and reloadable firearms now choose by the existing real Build 42 readiness/action metadata, keep
  the current viable gun unless another exceeds it by 1.5 points, and skip the bridge entirely when the
  same gun is already equipped. Native reload/rack/ammo/chamber ownership remains unchanged;
- meaningful carried bag and clothing upgrades use a new Java owned-item wear bridge. It locates the
  actual carried item, applies the real character worn slot, refreshes the model, and captures the record
  in the same successful transition. It does not create or delete clothing. Bag and clothing upgrades use
  separate 1.0/0.5 hysteresis margins;
- loot-completion equipment work now delegates to the stable evaluator rather than direct worn-item
  writes plus unconditional best-melee equipment. Item inspection paths are guarded so absent or modded
  subtype APIs fail as ordinary non-candidates instead of stopping autonomy;
- inventory/equipment persistence remains the existing `captureRecord`/restore authority. A successful
  owned weapon or worn-item transition captures its current real state immediately; no parallel equipment
  record was added.

Verification run:

- new `tools/test-equipment-intelligence.lua` passes better-melee selection, broken-weapon rejection,
  viable-firearm retention, meaningful backpack and protective-clothing upgrades, hysteresis/no repeated
  re-equip, and safe unknown/modded-item classification;
- `tools/test-firearm-support.lua` passes ready firearm stability, native reload/rack ownership, no-ammo
  melee fallback, safe-mode rejection, and native firing/sound ownership;
- `tools/test-survivor-looting.lua` now passes both missing-`isAmmo()` and arbitrary unknown-item safety;
- all 43 focused Lua tests pass and Lua 5.1 syntax validation passes for all 63 mod Lua files;
- `gradlew :java:build stageWorkshop` passes all 17 tasks. The staged Workshop mod matches the updated
  Lua equipment files, and the Java wear bridge is included in the rebuilt agent jar.

Pending live acceptance: give one survivor the requested mixed carried inventory, allow an idle/loot
completion evaluation, then observe normal roaming and combat. Pass requires one sensible meaningful
choice at a time, no repeated hand/worn-slot changes, usable firearm/reload compatibility, melee fallback
when no firearm can fire, retained food/water/medical supplies, and the same primary/worn state after
save/reload. Nested bag contents are intentionally not auto-rearranged in this pass; the evaluator only
uses root inventory items already ready for vanilla equip/wear.

## Pass 17 — Death / corpse / reanimation / cleanup

**Status:** Implemented; focused verification passed. Live acceptance remains pending.

### Defects found

- The native `IsoDeadBody` constructor has an immediate world side effect. If contained-shell removal failed after it succeeded, the old retry path could construct a second corpse on the next lifecycle tick.
- A quit immediately after native death detection could capture the still-registered shell before the normal autonomy tick retired it, leaving a living persistence record at risk of restoration.

### Fix

- Added a small per-runtime corpse-handoff marker. Once the native corpse exists, later attempts retry only shell cleanup; they never construct another corpse. The marker is cleared only after teardown completes.
- Kept Build 42's native `shouldBecomeZombieAfterDeath()` predicate and `IsoDeadBody.reanimateLater()` scheduling path. Knox does not create a replacement zombie or maintain a second infection timer.
- Marked the survivor dead once before teardown retry, so relationship cleanup remains durable and idempotent.
- Retire dead controllers before capture on the main-menu/save boundary, preventing dead shells from being serialized as active survivors.
- Blocked restoration of a persistence record whose identity is already dead; population activation already excludes those records.

### Verification

- `KnoxNpcRegistryVerifier`: native reanimation predicate/schedule behavior and corpse-handoff cleanup-retry state.
- `test-survivor-lifecycle-policy.lua`: corpse handoff, cleanup retry, dead persistence, and save-boundary source guards.
- Full 43-test Lua suite, Lua 5.1 syntax validation for all 63 mod files, and `gradlew :java:build stageWorkshop` passed.

### Pending live verification

- Kill a non-infected survivor, an eligible reanimating survivor, a companion, and a group member; save/reload shortly after each death. Confirm one corpse, natural inventory retention, durable dead identity, correct companion/group cleanup, and exactly one native reanimation where applicable.

## Pass 18 — NPC behavior integration

**Status:** Focused integration checks passed; mixed live acceptance remains pending.

### Defect found and fixed

- A shell could temporarily lose its grid square while streaming, enter `DETACHED`, then regain a square before the population owner completed hibernation. There was no recovery transition, so that still-loaded survivor could remain inert with stale temporary movement, combat, action, or task state.
- `recoverFromDetached()` now clears only transient owners (route, combat, queued action, supply/rest reservations, temporary task claim, self-care intent, and formation pace), applies a bounded retry to interrupted self-care, and returns the controller to `IDLE`. It deliberately preserves the durable companion order, group membership/leader, camp assignment, base assignment, and persisted directive, allowing the existing priority loop to resume one coherent behavior.

### Integration boundaries reviewed

- Combat and retreat clear temporary combat ownership while retaining companion/group roles; existing combat-intelligence coverage exercises Follow → retreat → Follow and self-care interruption.
- Traversal resumes its pending movement decision only after the native crossing completes; failed crossings abandon temporary ownership through the shared failure path.
- Needs, reloads, looting, base tasks, and rest remain temporary owners. Existing finish/failure paths return to `IDLE`, where durable command, camp/home, or roaming selection wins by normal priority.
- Hibernation/shutdown captures durable records after clearing live actions. Restore creates a fresh controller, so no live action/combat target is restored from a saved runtime state.

### Verification

- Added `tools/test-behavior-integration.lua`: detached recovery, one-time normalization, transient-owner cleanup, bounded self-care retry, and preservation of companion/group/camp/base intent.
- Existing focused suites continue to cover combat/retreat order preservation, self-care interruption, group movement recovery, camp return, command replacement, traversal continuation, and movement ownership.
- Full Lua suite, Lua syntax validation, and Java checks are run after this change; live evidence remains deliberately separate.

### Pending live verification

- Run the single mixed scenario defined for Pass 18: roaming survivor, companion, travelling group, and camp member; trigger movement, traversal, combat, retreat, self-care, regroup, command interruption, camp return, hibernation/restore, and save/reload in one session. The outstanding criterion is coherent recovery without state thrashing or orphaned ownership.

## Pass 19 — Long-session hardening / final QA

**Status:** Static and current-session log audit complete; final extended live acceptance remains pending.

### Verified

- The latest dedicated Knox run was separated from historical August logs. It contains native combat callbacks, real zombie-to-survivor damage, ordinary door/fence traversal, native corpse creation with reanimation scheduling, and hibernation followed by restoration.
- That run contains no current `MOVE_ALREADY_REQUESTED` storm, `RESTORE_FAILED`, `CAPTURE_FAILED`, or Java transformer/runtime error storm. Individual blocked-route outcomes remain bounded failure evidence, not a current ownership loop.

### Defect found and fixed

- An unarmed survivor is a legitimate state, but every automatic equipment evaluation logged `NO_MELEE_WEAPON`. During a longer session this created unnecessary repeated Knox log entries without changing a decision or helping diagnosis.
- `KnoxNpcRegistry` now keeps meaningful equipment changes and real failures in the diagnostic log while suppressing only the expected `NO_MELEE_WEAPON` result. The returned result and all equipment/combat behavior are unchanged.

### Verification

- `tools/test-equipment-intelligence.lua` now guards the expected-unarmed log policy alongside its existing safe inventory/equipment checks.
- Full standalone Lua tests, Lua 5.1 syntax validation, and the Java build/transformer verifiers were run after this change.

### Remaining live-only acceptance

- Run one ordinary extended session containing independent roaming, one companion, a travelling group, a camp-associated survivor, melee/firearm combat, normal traversal, self-care, scavenging, save/reload, hibernation, and restoration.
- Treat only a newly reproducible current-run crash, error storm, duplicate/resurrection, permanent stuck state, command loss, or repeated ownership loop as a blocker. Individual navigation failures and cosmetic tuning remain follow-up defects unless they recur as a loop.

## 2026-08-30 live regression pass — inventory, Survivor Card, traversal, stealth, combat

**Status:** Confirmed defects corrected and staged; focused/full verification passed. New live evidence is pending.

### Current-run defects found

- Equipment evaluation could index a Java null sentinel briefly exposed by an inventory list after item removal, producing the repeated `IsClothing of non-table: null` error around combat and death.
- Loot classification called the absent `InventoryItem:isAmmo()` method. Although wrapped in `pcall`, Kahlua still logged an exception for every scanned item. Build 42.20.3 exposes the authoritative `ItemTag.AMMO` path instead.
- The Survivor Card Skills view passed the survivor's off-slot player index to vanilla `ISSkillProgressBar`. Vanilla resolves `getSpecificPlayer(playerNum)` in the progress-bar constructor, returned null for the off-slot shell, and produced a render-frame `getPerkLevel of non-table: null` storm.
- The Health view manually ran `createChildren()` before `ISTabPanel:addView()` added it. The normal UI child lifecycle then ran it a second time, explaining the duplicate body diagrams.
- Threat acquisition could interrupt the native climb/window action, cancel its route, and immediately approach a zombie from the just-crossed edge. This matched the observed fence turn-back/stall boundary.
- Combat approach used `AdjacentFreeTileFinder` directly, which could choose an arbitrary far/opposite side of the zombie rather than the nearest standable side to the follower.
- Target hysteresis did not distinguish a knocked-down non-crawler from a standing zombie actively reaching the survivor, allowing the survivor to keep finishing the downed target while being attacked.
- Cautious locomotion treated any nearby zombie as a reason to sneak and lacked an explicit Java combat-owner signal during approach.

### Exact corrections

- Inventory/equipment walkers now reject both Lua nil and the Java null sentinel before any item method is accessed. Ammunition uses `item:hasTag(ItemTag.AMMO)` and no longer probes the missing subtype method.
- Skills UI retains the valid local UI owner index required by vanilla construction, then rebinds every vanilla progress bar to the selected survivor's real perk/XP state before rendering. Health controls are created once through the normal tab-child lifecycle.
- Native climb/vault/window actions temporarily suppress the global threat preemption scan. The scan becomes immediately eligible again after traversal finishes; combat itself is otherwise unchanged.
- Melee approach selects the closest standable adjacent square on the survivor's current side before falling back to the vanilla adjacent-square helper.
- A knocked-down non-crawler remains attackable but receives lower urgency than a standing attacker. Crawlers remain full immediate threats.
- Java combat explicitly owns a non-sneaking state until reset. Outside combat, automatic stealth is limited to an undetected same-floor crowd of at least three nearby zombies. The Lua threat scan now preserves the current roam/travel owner while that crowd remains unaware instead of immediately attacking a merely visible zombie. Once the survivor, an ally, or the nearby player is targeted, stealth is released and the existing fight/flee policy decides the response.

### Verification

- All 44 focused Lua tests pass, including new Java-null inventory, ItemTag ammo, single Health lifecycle, off-slot skill binding, traversal-preemption, current-side approach, standing-attacker retarget, and crawler-priority regressions.
- Lua 5.1 syntax validation passes for all 63 mod Lua files.
- `gradlew :java:build stageWorkshop` passes all 17 tasks. Transformer, movement, traversal, locomotion, corpse, zombie-visibility, and melee lifecycle verifiers pass; combat cleanup now also verifies release of stealth/combat locomotion ownership.
- `git diff --check` reports no whitespace errors. The updated build is staged to the local Workshop test installation.

### Pending live verification

- Kill a zombie and confirm no new Knox error icon/storm; open one survivor's Skills and Health tabs and confirm live XP bars plus one body diagram; climb a fence near zombies and continue away without turning back; approach a crowd and confirm crouch only while unnoticed, then immediate stand/fight-or-flee after detection; finally knock one zombie down while a second approaches and confirm the survivor can switch to the standing attacker.

### Unified order/work-duty integration (2026-09-04)

**Status: Implemented; focused verification passes. Live gameplay remains pending.**

The shared order catalogue already described both companion directives and concrete
settlement task names, but the companion service rejected concrete task names instead
of routing them to the existing resident-duty preference owner. That made the visible
order vocabulary broader than the executable dispatch boundary.

The service now maps concrete task names such as `farm_seed`, `animal_feed`,
`haul_corpse`, and `construct_defense` through `preferenceForTask` and the existing
`setBaseJobPreference` path for both individual and party dispatch. No second task
manager or task executor was added. Remaining task execution and claims stay owned by
the base task board and autonomy controller.

Party-order category and location labels now also resolve through the shared catalogue,
with safe literal fallbacks for early-load/test contexts. This keeps UI wording and
dispatch vocabulary together without changing gameplay ownership.

Verification: all 79 standalone Lua tests pass, all mod Lua files parse with Lua 5.1,
`stageWorkshop` completes successfully, and `git diff --check` reports no whitespace
errors. Live verification of resident assignment, party dispatch, and interruption/
resume remains pending. No launcher patch is required because the runtime and Java
packaging contract did not change.

The selector also canonicalizes each task type before comparing it to a resident
preference. Legacy or in-memory labels such as `storage_sorting` therefore remain
eligible for the current depot executor even before a save migration rewrites them.

### Controller task-vocabulary boundary (2026-09-04)

**Status: Implemented; focused verification and staging pass. Live settlement behavior remains pending.**

The persistence migration and task board already normalize legacy task names, but a
restored claim or direct developer/UI path could still enter the loaded controller
before that normalization was guaranteed. The controller now canonicalizes a task
when a restored claim, newly claimed task, or work-move dispatch is accepted. The
base-job resolver and timing helpers apply the same normalization for direct
callers as well. All existing base executors therefore receive one current task
vocabulary without a second scheduler or duplicated task state.

Verification: `tools/test-base-jobs.lua` and `tools/test-base-task-board.lua` pass, all mod Lua files parse with
Lua 5.1, and `stageWorkshop` completes successfully. No Java or launcher change was
required. Live verification still needs a saved resident with an older task record,
an automatic task, and a player-assigned task to confirm each dispatch reaches the
intended native executor and resumes after interruption.

### Payload-bearing patrol order convergence (2026-09-04)

The shared companion dispatch boundary now treats a familiar `patrol` order with
an area payload as the concrete `patrol_area` directive. Previously that label
could be routed to the resident base-preference branch, silently discarding the
player-selected patrol area. Payload-less `patrol` remains the base preference.

Focused `test-order-routing.lua` coverage now verifies individual and party
payload-bearing patrol dispatch, while preserving targeted guard, resident guard,
and concrete settlement-task routing. Full Lua tests and Lua 5.1 syntax parsing
pass. This is a loaded-world live verification item; no launcher or Java change
was required.

### Expanded legacy order vocabulary (2026-09-04)

The shared Knox catalogue now accepts additional familiar order labels such as
`return_home`, `go_home`, `stay`, `wait`, `recover`, `search_building`,
`chop_wood`, and `pile_corpses`. These are aliases only and converge on the
existing return, hold, relax, search, woodwork, or hauling owners; no legacy
task implementation or second scheduler was imported.

`test-order-catalog.lua` and `test-order-routing.lua` cover the new mappings.
The full Lua suite, Lua 5.1 syntax checks, Workshop staging, and whitespace
validation pass. Live menu execution remains pending; no launcher or Java
change was required.

### Patrol task-label migration guard (2026-09-04)

Persisted settlement records using the older `patrol_area` task label now
normalize to the existing recurring `patrol` executor. This is separate from
the live companion `patrol_area` directive and prevents an old task record from
being queued without a matching base executor. The normalization is deliberately
limited to that label: discovery work areas such as `farming` must continue to
emit concrete actions such as planting or watering rather than becoming generic
tasks.

The order-catalogue regression, full Lua suite, Lua 5.1 syntax checks,
Workshop staging, and whitespace validation pass. Live migrated-save behavior
remains pending; no launcher or Java change was required.

## Goal status

| Goal area | Status | Current evidence and missing boundary |
| --- | --- | --- |
| 1. IsoPlayer foundation | **Partial** | Stable Java records, contained shells, off-slot player indices, global-instance restoration, reconstruction, health/inventory/appearance capture, teardown, durable death hooks, and multi-NPC registries exist. The generated-shell class-format regression is corrected and prevented by a Java 25 load verifier; a subsequent live run restored and moved saved survivors. Extended multi-survivor save/unload/death testing remains required. |
| 2. Survivor autonomy | **Partial / loaded roaming implemented, live pass pending** | Independent loaded survivors keep one bounded goal, prefer useful supplies then nearby buildings/areas, avoid obvious zombie concentrations, use expiring destination/container memory, yield to danger or self-care, and reselect after completion/failure without permanent world knowledge. Existing ranked looting, equipment, needs, melee, rest, medicine, traversal, fleeing, and firearms remain integrated; roaming, ranged, retreat, and self-care live acceptance remain pending. |
| 3. Priority/action ownership | **Implemented, unverified** | One Lua controller owns high-level state and Java owns exactly one movement request. Identical destinations are suppressed, changed destinations replace the prior request, and success/failure/cancel/interruption paths release engine and Java ownership. Focused lifecycle checks pass; the narrow live acceptance remains pending. |
| 4. Navigation/human movement | **Partial / multi-floor and companion locomotion implemented, unverified** | Normal travel walks. Companion follow uses distinct trailing slots, bounded meaningful destination refresh, pace-only ownership-safe updates, and distance/condition-aware walk-run-sprint downgrade. XYZ requests, arrival, captured native route nodes, route distance, and floor-changing destination replacement are Z-aware. Native Build 42 path nodes and ordinary character movement remain responsible for stairs and locomotion; no Knox code mutates coordinates or speed. Stairs and visible off-slot sprint transitions still need their narrow live passes. Other routing quality and flee behavior remain separate. |
| 5. Full combat | **Partial / melee and firearm slices implemented, live passes pending** | Native melee attack integration, moving-target refresh, zombie awareness, real BodyDamage, endurance, condition, injury capture, death, and terminal ownership cleanup exist. Loaded melee decisions use bounded priority scoring, target hysteresis, group defense, role leashes, reservation spreading, coherent retreat, and durable-order resumption. Firearms now delegate readiness, rack/reload, `DoAttack`, ballistics, ammo/chamber changes, condition, sound, and world noise to Build 42.20.3 while Knox owns bounded target range and cleanup. Standing/crawler parity, melee intelligence, and firearm acceptance still require their requested live scenarios. Survivor PvP and advanced tactical firearm behavior remain absent. |
| 6. Needs, health, medical, inventory | **Partial / loaded self-maintenance implemented, live pass pending** | Loaded survivors prioritize danger, bleeding, critical thirst/hunger, endurance rest, and fatigue sleep; use real carried food, water, and bandages through native actions; verify authoritative stat/BodyDamage changes; apply bounded retry; and resume durable orders after interruption. Fatigue now uses the off-slot-safe native sleeping event rather than a parallel stat. The player inventory and medical-management surfaces remain available. Live self-care, off-slot treatment, nested transfer, and sleep/wake acceptance remain incomplete. |
| 7. Skills, traits, occupations | **Implemented, unverified** | Deterministic Build 42 profession/trait generation, perk levels, XP capture/restore, and job requirement checks exist and pass standalone persistence checks. Long save/unload/reconstruction progression still needs a live pass. |
| 8. Social system | **Partial / relationship and encounter coherence implemented, live pass pending** | Persistent IDs provide one deterministic self/allied/neutral/hostile classification across pair history, player ownership, groups, factions, and symmetric faction disposition. Loaded ally assistance derives from that authority; neutral contact is cautious rather than forced, greetings are single-owner and cooldown-bound, joining requires familiarity/shared activity, and interruptions resume durable behavior. Survivor PvP and deeper faction favors remain absent. |
| 9. Natural groups | **Partial / membership coherence implemented, live pass pending** | Consent-based groups now have deterministic persisted lookup, duplicate membership normalization, stable leader repair, death cleanup, and runtime caches derived from the saved roster. Separation, combat, roaming, and camp activity do not mutate membership. Z-aware recovery and formation behavior remain internally verified; live social cohesion and cross-floor group travel/combat are still unproven. |
| 10. Factions | **Partial / membership coherence implemented, live pass pending** | Persistent faction IDs, leaders, members, traits, relationships, home candidate/base IDs, safehouse ownership, and resident conversion exist. Save-start normalization prevents contradictory faction ownership, preserves player companions, repairs dead leaders, and synchronizes camp occupancy. Established NPC faction leaders now have a bounded first-contact recruitment path with a persistent cooldown; resource expeditions, diplomacy expansion, and full faction progression remain incomplete. |
| 11. Base scouting/settlement | **Partial** | Loaded buildings are scored, safehouse conflicts are rejected, candidates persist, leaders travel to candidates, and faction bases/residents are created. Candidate breadth, repeated unloaded search, resource/water evaluation, and failure recovery need completion and live verification. |
| 12. Base domain | **Partial / relocation implemented, live pass pending** | Player and faction base records, home/territory separation, residents, zones, storage policies, tasks, ownership protection, and save migration exist. New player building claims receive a six-tile yard perimeter. Moving homes retains the stable base/resident ownership ID and leaves physical world items untouched while transactionally replacing the home/territory and clearing old location-bound zones, storage policies, and unclaimed work. A resident-owned task blocks relocation rather than being orphaned. NPC faction planning fills only missing zones, binds available real containers without creating supplies, and relies on priority ordering plus atomic task claims so residents distribute across available work. The Notebook can now assign a specific queued task to a selected player-base resident through the guarded service/task boundary. Loaded resource acquisition and return/deposit now have an executor foundation; complete settlement life and live end-to-end verification remain pending. |
| 13. Base Setup UI | **Partial / selector crash corrected, live pass pending** | Context menus can establish or confirmation-move a base, redraw territory, create zones, categorize containers, and safely remove inactive work areas. Build 42 modal callbacks now consume the real target/button signature, and both corner selectors use the native `skipWalk2` opt-out so selecting ground cannot queue player movement. A vanilla-style Base Setup window opens from party/world menus with Overview, Residents, Work Areas, Storage, and Tasks tabs plus boundary editing, work-area selection, party recall, persistent resident job preferences, guarded assignment of queued tasks to selected residents, and safe queued-task cancellation/resume. Cancellation cannot interrupt a claimed native action and preserves the task signature so automatic planning does not immediately recreate it. Zone resizing and richer visual territory/zone management remain incomplete. |
| 14. Existing base jobs | **Implemented, unverified** | Guard, patrol, depot sorting, barricading, farming, tree cutting, log sawing, corpse hauling, trough water/feed, and structure repair have real executors and focused passing tests. When no ready task or patrol is selected, a resident can now make a bounded ambient rest decision that reuses normal furniture/ground sitting rather than standing motionless; it releases its seat/posture before the next decision. A claimed task collects missing exact requirements from currently loaded assigned storage through normal inventory transfers before work begins; it blocks safely when that storage is absent. Most lack live passes; task reservation across multiple residents and save/interruption still needs integration testing. |
| 15. Construction/defense planning | **Partial, static path verified** | Defense Construction Areas now plan a gate first, then wall frames and first-stage wooden walls using Build 42.20 entity recipes, native `ISBuildAction`, real materials, skill gates, XP, sounds, and world-object completion checks. Faction bases receive a conservative default perimeter. Live off-slot action, construction interruption, and multi-resident verification remain required; walls/gates beyond the first wooden stage are not yet implemented. |
| 16. Companions | **Partial / follow locomotion implemented, unverified** | Talk, trust, recruit, Follow, Hold, Return to Base, Dismiss, climbing policy, and area/building/corpse loot directives persist. Follow now uses distinct trailing slots, ignores insignificant leader motion, refreshes pace without replacing the route, catches up with bounded walk/run/sprint policy, resets recovery on arrival, and explicitly respects Hold. Return to Base hands a companion off transactionally to a persisted virtual route when the destination cell is unloaded. Party Go To and Guard persist and resume after ordinary interruptions. Combat stances and normalized duty data remain intact. Exact task assignment is implemented for player bases; finished base roster exchange and live verification of follow transitions/order recovery remain incomplete. |
| 17. Companion HUD | **Partial** | Split-screen-isolated right-side HUD, portraits, needs, health, weapon, activity, individual menu, and party menu exist. It needs a complete live lifecycle pass, unloaded cleanup verification, urgency presentation, and final command coverage. |
| 18. Survivor Card | **Partial / lifecycle patch unverified live** | Identity, age, occupation, time alive/known, group/base/job/activity, conditions, weapon, faction, trust, persistent traits, and top learned skills are shown. The card now follows Build 42's `ISHealthPanel:initialise()` → `createChildren()` lifecycle and safely omits that optional tab if the engine rejects it. Its Knox tab has direct Inventory and Medical Check shortcuts, both delegated to the existing vanilla inventory bridge and medical timed action rather than duplicating those mechanics. Standalone UI coverage passes, but a new live opening/render/action test is still required. Detailed relationship history and richer equipment presentation remain incomplete. |
| 19. Survivors Notebook | **Partial** | A vanilla-styled window now has Base, Residents, Work, Missions, Survivors, and Factions tabs. It distinguishes loaded people from stored survivors, lists durable individual activity/role state, shows faction member counts, base/shelter status, and the current player-faction relation, and keeps mission progress separate from ordinary unloaded people. Portraits, richer selection/actions, resource status, and detailed base/faction views remain incomplete. |
| 20. Away teams/missions | **Partial** | Persistent teams now have an owner, members, mission type, destination, departure, ETA, state, result, and preserved prior duties. The unloaded simulation advances completed scout missions and restores every participant's prior duty; scouting deliberately returns no items. Away members remain excluded from proximity activation, while their persisted needs, rest, endurance, inventory consumption, and health continue advancing in the off-screen ledger. Both scout dispatchers validate owner, members, duty, and destination before taking a loaded shell down; the player command sends one available loaded resident at a time. Resource missions now reach a durable awaiting-collection state and have a per-member real-item ledger: a future live executor can record only item types actually moved from world containers, then restore duties only after every member returns. Destination materialization, the transfer/return executor, risk, mission-selection UI, and live verification remain incomplete. |
| 21. Unloaded-world simulation | **Partial, focused checks pass** | Hibernated survivors carry a persisted survival ledger: needs advance, rest/endurance recover, real stored food/water is consumed, and deprivation can cause durable death. Autonomous survivors, travel groups, away teams, and unloaded returning base residents make deterministic low-cost virtual progress; a base return starts at the freshly captured origin, travels at the normal virtual rate, then changes to base life only on arrival. Group members share a heading, base residents take deterministic ambient positions inside their own saved territory, companions preserve their reunion point, and away-team travel/result ownership remains separate from physiology. A hidden loaded square transactionally updates the Java record before rematerialization. Detailed offscreen pathing, injury treatment, encounters, supply gathering, faction growth, and a multi-day live return remain incomplete. |
| 22. Camps | **Partial / temporary living implemented, live pass pending** | Homeless NPC factions create one lightweight persistent shelter in an unclaimed loaded building. Durable faction membership restores camp linkage without duplication; loaded members take distinct reserved shelter positions, stagger bounded idle/rest/reposition behavior, use ordinary needs and real nearby containers, take short roaming/scavenging excursions, return through native movement, defend group members, and retain camp identity through interruption. Camp conversion clears stale ownership. Player camps, fortification, jobs, strategy management, and richer social behavior remain outside this slice. |
| 23. Vehicles | **Partial / passenger slice unverified** | Companion Orders now expose Enter My Vehicle and Exit Vehicle. The passenger-only implementation uses Build 42's native path-to-seat, enter, exit, and door-close timed actions, refuses occupied/locked/uninstalled/blocked seats, and never takes driver seat zero or changes keys/engine ownership. A seated shell is excluded from detached hibernation so its native seat relationship is not destroyed while the player drives. NPC driving, autonomous/group vehicle travel, vehicle-specific persistence/reconstruction, and live verification remain incomplete. |
| 24. Raids/faction conflict | **Experimental dispatch/travel, unverified** | Symmetric persisted faction relations and hostile base-protection rules exist. Knox Events proposes real minority parties and can dispatch ready loaded residents from explicitly scheduled plans. Temporary duty bindings, native travel, shared stored travel/rest, and return/casualty cleanup have focused checks. No random scheduler is enabled. Actual combat/loot objectives, dispatch of already-stored parties, event factions, and live verification remain incomplete. |
| 25. World population | **Implemented, unverified** | Region-balanced identities, persistent target, active-body limit, distant/hidden materialization, refill delay, origin reuse protection, hibernation candidates, and durable death records exist and pass standalone tests. Initial populations form compact cohorts, and a bounded deterministic refill chance can pair a replacement with a nearby independent survivor through the canonical travel-group path. Production-scale live streaming/refill is not proven. |
| 26. Lifecycle/hibernation | **Partial / focused checks pass** | Capture, removal, stored records, activation candidates, reconstruction, grace checks, and durable death exist. A dead shell first becomes a real `IsoDeadBody`; Knox then uses the native `shouldBecomeZombieAfterDeath()` predicate and `IsoDeadBody.reanimateLater()` only when the current sandbox transmission/infection rule calls for it. Failed engine removal retains the runtime for bounded retry, preventing duplicate resurrection. Detached cleanup and native corpse/reanimation scheduling are covered by focused checks; a live infected and non-infected death/reload gate remains required. |
| 27. Failure recovery | **Partial, movement boundary internally coherent** | Cooldowns, reservations, task requeue, target re-resolution, movement deadlines, and alternate-entry abandonment exist. Java ownership is released on every movement terminal/interruption path, ordinary and formation failures retain bounded cooldowns, dynamic details no longer fragment streaks, and success resets recovery state. A narrow live run must still prove the failure storm and stale idle are gone. |
| 28. Player-facing feedback | **Partial** | Speech bubbles, activity feed, HUD activity, need callouts, order messages, and Notebook summaries exist. A base worker now says and reports when an assigned-storage requirement blocks a job. Other missing-tool/material/job failure feedback and richer status presentation are incomplete; repetition/spam needs a live pass. |
| 29. Save/load coverage | **Partial** | Core person, appearance, inventory, equipment, health, physiology, capabilities, social/group/faction, companion duty, base, zones, storage, tasks, and unloaded survival state are persisted. Missing systems cannot persist, and full multi-point acceptance reload/unload evidence does not exist. |
| 30. Debugging/testability | **Partial, strong foundation** | Java diagnostics, transition logs, scenario tools, log collection, standalone tests, probes, combat scenarios, and Java runtime verifiers exist. Movement ownership now has a focused Java verifier plus Lua recovery coverage; `MOVE_ALREADY_REQUESTED` remains diagnostic evidence rather than normal refresh control flow. UI/lifecycle diagnostics and live movement/combat regression gates still need completion. |
| 31. Clean architecture | **Partial** | The repository contains only the IsoPlayer rebuild and keeps records separate from bodies. No active IsoZombie runtime was found. The autonomy controller is large but still the single owner; probes are gated. Missing systems should extend current boundaries instead of adding competing managers. |
| 32. Efficient implementation loop | **In use** | Focused executors and standalone tests are present, but many slices moved ahead without live verification. Future work must close current core/live defects before stacking additional gameplay systems. |
| 33. Human perception | **Implemented, live pass pending** | Loaded zombie and human acquisition now requires same-floor native Build 42 geometry visibility instead of distance-only awareness. Lost threats have short non-refreshing memory, dead/unloaded/cross-floor targets clear, and group scans are cadence-staggered. Existing native target state can still signal a threat to self/allies. The requested building/floor/live acquire-and-clear sequence and any future verified off-slot survivor hearing boundary remain pending. |
| 34. Equipment intelligence | **Implemented, live pass pending** | Loaded survivors make bounded, inventory-only equipment decisions: meaningful usable melee upgrades, stable real firearm choice, retained supplies, and one-at-a-time carried bag/clothing upgrades through the existing body/inventory state. Unknown item APIs fail safely, and successful hand/worn changes capture persistence immediately. Mixed-inventory and reload acceptance plus save/reload visual confirmation remain pending. |

## Current critical path

The shortest path toward the acceptance loop is not to add every missing feature in
parallel. The current order is:

1. live-verify the existing multi-resident settlement loop: shortage priority, task
   rotation, real storage/material transfers, guard/patrol coverage, idle recovery,
   and save/reload continuity;
2. live-verify faction shelter selection and the new bounded leader-to-loner recruitment
   path, including the staged 30/60/90-tile search and post-join settlement handoff;
3. complete the player-facing order and roster surfaces around the now-canonical
   catalogue, including Notebook/base resident management and clearer status feedback;
4. finish real resource away-team execution and return/deposit handling so settlement
   supply loops can operate beyond the loaded area;
5. live-verify native firearms, death/reanimation, unloaded recovery, and long-session
   performance together rather than treating isolated checks as release proof;
6. add vehicles, raids, named events, and deeper diplomacy only after ordinary
   survivor/faction life is stable.

### Faction leader first-contact recruitment (2026-09-04)

- **Gap:** faction recruitment was gated on prior familiarity and shared activity.
  A lone survivor could therefore never qualify for the activity required to join.
- **Fix:** the existing encounter decision now gives an established NPC faction
  leader a modest, deterministic chance to recruit an eligible loner on first
  contact. Independent groups keep the earlier familiarity/shared-survival gate;
  hostility, cooldowns, faction limits, and the canonical membership transition
  remain unchanged.
- **Verification:** `tools/test-human-encounters.lua`, full Lua suite, full Lua
  syntax scan, and `git diff --check` pass. Live recruitment and post-join travel
  or base behavior remain pending.

Faction recruitment also records a twelve-hour cooldown on the existing travel-group
record after a successful admission. This prevents an established leader from emptying
the surrounding population in one encounter sweep while keeping the state persistent and
lightweight.

### Guard order routing (2026-09-04)

- **Gap:** `guard` is shared by the resident job preference and the companion location
  directive. The dispatch method checked preferences first, so a concrete guard-post
  command with a target payload could silently change a job preference instead.
- **Fix:** payload-bearing `guard` orders now route through the existing directive
  executor; payload-less `guard` continues to set the base preference. Party dispatch uses
  the same rule.
- **Verification:** full Lua suite, full Lua syntax scan, and `git diff --check` pass.
  Live confirmation of an owned companion receiving a guard-post order remains pending.

The new `tools/test-order-routing.lua` regression explicitly covers both sides of this
shared vocabulary: targeted `guard` reaches the companion directive executor, while
payload-less `guard` remains a resident preference.

### Player-base resident ownership at task assignment (2026-09-04)

- **Gap:** the Notebook and service validated the player base, but the task-board
  boundary itself did not verify that the selected survivor was actually owned by
  that player. A future caller could therefore attempt to assign a faction or
  independent survivor to a player task.
- **Fix:** `KnoxBaseTaskBoard.claimSpecific` now requires the canonical persisted
  affiliation `{ kind = "player", ownerId = playerId }` before checking eligibility
  or claiming the queued task. The existing atomic claim and manual-task marker are
  unchanged.
- **Verification:** `tools/test-base-task-board.lua`, the full standalone Lua suite,
  the complete Lua syntax scan, and `git diff --check` pass. Live Notebook assignment
  and multi-resident rotation remain pending.

### Legacy haul task convergence (2026-09-04)

- **Gap:** the public task vocabulary still accepted the early `haul` name even
  though the current native executor is `sort_depot`; a manually-created or old
  save task could therefore remain queued under a type with no executor.
- **Fix:** `KS_OrderCatalog.normalizeTaskType` now maps `haul` to `sort_depot`
  before queueing or selection. The existing `haul` label remains readable for
  older UI data, but execution converges on the real depot-transfer path.
- **Verification:** order-catalogue regression, full Lua suite, Lua syntax scan,
  workshop staging, and `git diff --check` pass. Live depot work remains pending.

### Off-screen physical base-task claim handoff (2026-09-04)

- **Gap:** an automatic resident sent beyond the loaded world with a physical
  job could retain its claim indefinitely even though the native world action
  could not execute until the square streamed back in.
- **Fix:** after twelve off-screen hours, automatic physical claims are released
  through `KnoxPersistence.releaseBaseTaskClaim`, marked as a bounded blocked
  retry, and made available for another eligible resident. Explicit Notebook
  assignments are preserved and are never silently released by this path.
- **Verification:** full Lua suite, complete Lua syntax scan, Java/workshop
  staging, and `git diff --check` pass. Live unload/reload rotation remains
  pending; no world-changing action is simulated off-screen.

The loaded controller also clears the persisted off-screen wait budget whenever
it restores or claims a task. A resident that returns before the handoff limit
therefore receives a full native execution window instead of inheriting stale
unloaded time.

### Refill group continuity (2026-09-04)

- **Gap:** population refills restored the headcount one survivor at a time but
  never restored the small-group character of the world after deaths.
- **Fix:** a new refill identity now has a 40% deterministic chance to form a
  compact pair with the nearest eligible independent identity within 64 tiles.
  The existing persisted travel-group API owns membership; no body teleport or
  synthetic activity is introduced.
- **Verification:** full Lua tests, syntax scan, Java build/staging, and diff
  validation pass. Production-scale refill and live group behavior remain pending.

## Acceptance status

The feature-complete acceptance test does **not** currently pass. The repository has a
substantial playable foundation and many genuine world-action executors, but major promised
systems remain missing and the latest live run still contradicts core lifecycle, combat,
group recovery, and Survivor Card requirements.

## Player-facing population, identity, and human-combat pass

**Status:** focused verification complete; live verification pending.

- Fixed the Base notebook creating every tab twice through a manual `createChildren()` call before vanilla `ISTabPanel:addView()`. The window now targets a centered 760x600 size, clamps to each player viewport, and trims long list rows.
- New worlds default to 32 persistent survivors and 12 active shells. Configurable limits are now 256 persistent and 48 active; existing save state and user sandbox values remain authoritative.
- Persistence schema 13 gives NPC factions deterministic leader-derived names and the player faction the stable `Your Group` label. Names are assigned once, saved, and shown in the activity feed and Notebook.
- Added sandbox controls for survivor speech, line-of-sight player-style name tags, name distance, and survivor/player combat. Native name tags map hostile/neutral/friendly/ally to red/white/blue/green and refresh on a bounded cadence.
- Expanded encounter and companion speech through small deterministic contextual line banks without changing existing cooldown or single-speaker ownership.
- Hostile loaded survivors and players now route into the existing native live-combat owner. The controlled zombie gate remains zombie-only, zombie-only visibility/state calls are not applied to human targets, and a real player hit records durable retaliation only after Build 42 emits `OnWeaponHitCharacter`.
- The existing companion inventory still uses vanilla equipped-item dots through its guarded/restored player lookup; no second inventory renderer or custom marker was added.

Verification: Lua 5.1 syntax passes all 65 mod files; all 45 focused Lua tests pass; `gradlew :java:check` passes all 14 tasks, including the extended live-human/controlled-zombie combat boundary verifier.

Pending live evidence: name-tag visibility/colors and split-screen choice; every Notebook tab at the intended resolution; equipped-dot refresh without inventory flicker; and full survivor-vs-survivor plus survivor-vs-player native animation, hit, BodyDamage, death, cleanup, and retaliation. Static/build checks prove routing and ownership, not Build 42's live PvP collision result.

## Base selection and relocation pass — 2026-08-30

**Status:** Confirmed live selector crashes corrected; relocation and default perimeter implemented. Focused/full verification passed; live acceptance remains pending.

### Defects confirmed from the latest live log and Build 42.20.3

- `KS_BaseTerritorySelector.lua:131` and `KS_BaseZoneSelector.lua:178` treated the first modal callback argument as the button. Build 42.20.3 `ISModalDialog:onClick` invokes callbacks as `(target, button, param1, param2)`, so the nil target caused `attempted index: internal of non-table: null` on every confirmation.
- Build 42.20.3 `ISSelectCursor` sets `skipBuildAction` but inherits `ISBuildingObject:walkTo`. `tryBuild()` calls that walk boundary before `create()`, which allowed both corner-selection clicks to enqueue player movement.
- The world context menu hid all building-claim choices once the player already owned a base. Initial territory also ended at the building definition rather than including the requested yard/perimeter.

### Exact corrections

- Both modal closures now accept the native target argument before the button.
- Every first- and second-corner cursor sets the engine's existing `skipWalk2` flag; no custom input hook or coordinate movement was added.
- New player bases use the real building definition as `home` and a six-tile expanded, all-floor `territory` after overlap validation.
- Right-clicking a different building now offers **Move Home Base Here** and an explicit confirmation. Relocation retains the same base ID and resident duties, rejects overlapping bases/faction safehouses, and refuses while a resident owns a claimed task. On success it updates home/territory and clears only old coordinate-bound zones, storage policies, and tasks; world items and structures are not modified.

### Verification

- `tools/test-base-selectors.lua` executes both two-corner flows, asserts `skipWalk2` on both cursor instances, invokes the real target/button callback shape, and verifies exactly one territory/zone save.
- `tools/test-companion-base-domain.lua` proves active-task relocation rejection is atomic, successful relocation keeps the base/resident identity, applies the padded territory, and clears old location metadata.
- `tools/test-base-setup-ui.lua` verifies the confirmation-backed relocation remains wired into the unified base menu.
- All 46 focused Lua tests pass; Lua 5.1 syntax validation passes all 65 mod Lua files.
- `gradlew :java:build stageWorkshop` passes all 17 tasks and stages the corrected package.
- `git diff --check` reports no whitespace errors; existing line-ending conversion notices remain informational.

### Pending live verification

1. Edit the existing home boundary and create one work area; confirm both modals save without an error icon and the player does not walk toward either selected corner.
2. Right-click inside a different unclaimed building, choose **Move Home Base Here**, cancel once, then confirm once.
3. Confirm the same residents remain assigned, the new default territory extends six tiles beyond the building, and old physical containers/items remain in place but no longer appear as assigned storage.
4. Claim a base task with a resident and confirm a move is safely refused until that task finishes.

## Combat-risk retreat follow-up — 2026-08-30

**Status:** Fixed-ratio retreat policy replaced; focused/full verification passed. Live combat-risk
acceptance remains pending.

### Exact defect found

- `fleeAssessment()` reduced the decision to `health <= 25` or `zombies >= allies * 3`. It treated
  three distant zombies the same as three bodies collapsing into melee range and ignored active
  attackers, approach directions, viable escape space, real bleeding/severe wounds, endurance,
  weapon condition/reach/skill, and nearby allied capacity. This contradicted the intended behavior
  where a capable survivor can handle one to several spaced threats but retreats from a dangerous
  close collapse.

### Exact correction

- The existing flee destination, shared group plan, movement ownership, cooldown, and recovery code
  remain unchanged. Only the assessment boundary now calculates a small observable risk snapshot.
- Same-floor loaded threats contribute by distance and whether they target the survivor or an ally.
  Contact pressure, distinct approach sectors, and the number of standable directions that actually
  increase separation represent collapse/surrounding and escape space.
- Real `BodyDamage` parts contribute untreated bleeding, cuts, deep wounds, bites, and fractures.
  Real endurance and health contribute vulnerability. The equipped real weapon contributes its
  Build 42 condition, maximum range, and `getWeaponSkill(character)` result; nearby loaded allies
  reduce risk.
- Critical health, four contact-range zombies, multiple active attackers collapsing at contact
  range, or a blocked multi-direction surround are explicit retreat gates. Other combinations use
  one documented risk threshold. The assessment log now records reason, total risk, immediate
  pressure, and escape-lane count so live tuning is evidence-based instead of another ratio patch.
- Java/Kahlua item and body-part methods are guarded. Missing or modded item APIs degrade to an
  unarmed/unknown contribution rather than throwing or producing a parallel health system.

### Verification

- `tools/test-combat-intelligence.lua` now proves a healthy skilled armed survivor may hold against
  three spaced zombies; four contact-range zombies force retreat; critical health, two untreated
  bleeding wounds, and exhaustion influence the result; and nearby allies reduce risk.
- `tools/test-autonomy-formation.lua` now protects removal of the old three-to-one trigger while
  retaining a contact-collapse group regression.
- All 46 standalone Lua tests pass and Lua 5.1 syntax validation passes all 65 mod Lua files.
- `gradlew :java:build stageWorkshop` passes all 17 tasks, including movement, traversal,
  locomotion, melee, corpse, shell, visibility, and transformer verifiers, and stages the Workshop
  test package.

### Pending live verification

Test one healthy armed survivor against one zombie, three spaced zombies, and four or more zombies
closing from several sides; then repeat while exhausted or carrying multiple untreated bleeding
wounds and once with nearby allies. PASS requires restrained fighting against manageable spacing,
prompt coherent retreat from a close collapse, no immediate flee/re-engage oscillation, no movement
request storm, and normal Follow/group/roaming behavior resuming after the danger clears.

## Base corpse-hauling handoff follow-up — 2026-08-30

**Status:** Confirmed native handoff defect corrected and staged; focused/full verification passed.
Live pickup, dragged movement, and placement remain pending.

### Exact defect found

- Build 42.20.3 `ISGrabCorpseAction:complete()` calls `pickUpCorpse(body, "BwdDrag")`.
  `IsoGameCharacter.pickUpCorpse()` begins a native grapple handshake, while
  `isDraggingCorpse()` becomes true only after the grapple target is accepted. Knox tested
  `isDraggingCorpse()` as soon as the timed-action queue emptied, then called `pickUpCorpse()` as a
  fallback and tested it again synchronously in the same Lua call. A valid asynchronous pickup could
  therefore be failed and its task released before attachment completed.
- Build 42's `ISDropCorpseAction:start()` has the mirror behavior: it requests
  `setDoGrappleLetGo()` and the actual release resolves through the native grapple state. Knox again
  treated the empty action queue as proof that release had already completed.
- `ISDropCorpseAction` does not path to its constructor's square. The existing Knox sequence of
  pickup, separate Java-owned movement to the corpse zone, then native drop is the correct boundary
  and was retained.

### Exact correction

- Corpse pickup now observes `isDraggingCorpse()`, `isGrappling()`, and the native performing-grapple
  state through one bounded settle window. If the first handoff remains idle, Knox requests the
  exact native `pickUpCorpse(body, "BwdDrag")` once, waits once more, and then either advances only
  on real dragging state or fails the task cleanly.
- Corpse release uses the same bounded terminal-state rule. It completes the job only after the
  character is no longer dragging, permits one native `setDoGrappleLetGo()` retry, and does not
  pretend an animation request moved or removed the body.
- Per-task pickup/drop verification and retry ownership is reset at task completion and before a
  new corpse phase. Combat or another ordinary interruption still clears the timed action, releases
  the dragged corpse, and closes the claimed task through the existing interruption path.
- Corpse discovery, stable item identity, hand unequip, real `IsoDeadBody`, destination selection,
  Java movement ownership, native animations, and the real corpse object remain unchanged. No fake
  inventory corpse or coordinate movement was added.

### Verification

- The installed Build 42.20.3 Lua actions and `IsoGameCharacter` bytecode confirm the asynchronous
  `pickUpCorpse`/grapple and `setDoGrappleLetGo` boundaries described above.
- `tools/test-base-corpse-handling.lua` now covers discovery, animal filtering, stable corpse
  identity, held-item unequip, initial settle, one bounded pickup retry, transition wait, real drag
  recognition, one bounded release retry, and real release recognition.
- The existing autonomy regression still proves combat interruption clears timed actions, releases
  a dragged corpse, and closes the task claim.
- All 46 standalone Lua tests pass and Lua 5.1 syntax validation passes all 65 mod Lua files.
- `gradlew :java:build stageWorkshop` passes all 17 tasks and stages the Workshop test package.

### Pending live verification

Create one Corpse Drop Area with a human corpse elsewhere inside the loaded base territory. A base
resident must unequip held items, play the native pickup, visibly remain attached to the same body,
walk it to the chosen zone, play the native release, leave the real body in the zone, and complete
the task once. Interrupt a second attempt with combat and confirm the body is released and the task
is retryable. Failure evidence is a `corpse-grab-retry`, `corpse-drop-retry`,
`corpse_grab_not_attached`, `corpse_drop_not_released`, movement failure, or repeated task claim;
collect the corresponding current-run log rather than adding another timing patch.

## Survivor melee approach-range follow-up — 2026-08-30

**Status:** Confirmed approach-boundary defect corrected and staged; focused/full verification
passed. Visible moving-target approach remains pending live verification.

### Exact defect found

- Knox sent melee movement toward a point 0.40 tiles inside the weapon's nominal reach, but the
  `APPROACHING` phase cancelled that route as soon as center distance entered the wider
  `desiredRange + 0.20` re-approach band. For a baseball bat this meant requesting 0.85 tiles but
  stopping as far away as 1.05 tiles. The 0.20 margin was valid hysteresis for deciding when to
  chase a target that moved away; it was not a reliable attack-entry boundary.
- Melee setup read the weapon's raw script maximum. Build 42.20.3
  `IsoGameCharacter.isMeleeAttackRange()` instead uses
  `weapon.getMaxRange(character) * weapon.getRangeMod(character)` before testing the target's
  nearest hit position. The two calculations could therefore disagree for skill-adjusted weapons.
- The captured-route consumer accepted its final waypoint within 0.35 tiles, independently of
  combat's entry threshold. Worse, `APPROACHING` ignored a successful route result while the target
  remained too far away: a moving zombie could leave a completed route behind and combat would keep
  ticking that terminal route rather than issuing one bounded replacement.
- Current live evidence shows normal `ATTACK_REQUEST` events cause native damage, while the bad
  sequences repeatedly reached `COMBAT_STARTED` without an attack request. This supports an
  approach/entry defect rather than another damage-callback or fake-health problem.

### Exact correction

- Attack entry and re-approach now use separate thresholds. An active approach continues until
  `desiredRange + 0.05`; only a survivor already fighting uses `desiredRange + 0.20` to decide that
  a moving target is far enough away to require another chase.
- Melee effective range now mirrors Build 42's character-adjusted maximum and range modifier.
  Knox still leaves a 0.40-tile safety margin, routes to a point on the selected/current side, and
  never targets the zombie's occupied center or modifies coordinates directly.
- Only the final waypoint of a combat-owned captured route now uses a 0.04-tile tolerance,
  inside the 0.05 attack-entry margin; ordinary waypoint and non-combat arrival remain unchanged.
  Meaningful target movement (0.75 tiles) may refresh a manual combat route at most once per 30
  combat ticks. Completed out-of-range routes are also reconsidered, but only two stationary-target
  retries are permitted before normal combat failure cleanup. Active traversal is never cancelled
  by this refresh. Replacement clears the old captured/native route before starting the new one.
- Existing native facing, aim/floor aim, `SwipeStatePlayer`, hit selection, damage, endurance,
  weapon wear, reactions, death, missed-swing recovery, and combat/movement ownership are unchanged.

### Verification

- Installed Build 42.20.3 bytecode was inspected for
  `CombatManager.isUnhittableMeleeTarget()`,
  `CombatManager.getNearestMeleeTargetPosAndDot()`,
  `IsoGameCharacter.isMeleeAttackRange()`, `HandWeapon.getMaxRange(character)`, and
  `HandWeapon.getRangeMod(character)`.
- `KnoxCombatControllerVerifier` now protects the narrower attack-entry boundary, wider
  re-approach hysteresis, final-waypoint tolerance, bounded moving-target refresh, traversal
  preservation, and placement inside native reach.
- `gradlew :java:verifyMeleeCombatLifecycle :java:build stageWorkshop` passes all 17 Java tasks.
- All 46 standalone Lua tests pass and Lua 5.1 syntax validation passes all 65 mod Lua files.

### Pending live verification

Observe one melee survivor approach a stationary zombie and then a moving zombie. The survivor
must continue to useful striking distance, face and damage the target through native combat, pursue
a target that leaves the wider band without constant route replacement, and resume the prior
Follow/group/roaming duty afterward. Failure evidence is repeated `COMBAT_STARTED` without
`ATTACK_REQUEST`, repeated `REAPPROACH` around the threshold, swinging outside useful range, walking
inside the zombie, or a movement/combat ownership storm.

## Contextual travel pace follow-up — 2026-08-30

**Status:** Implemented — live verification required. All 46 Lua tests, 65 Lua syntax checks,
and the full 17-task Java build/staging pass succeed.

The native locomotion executor already supported condition-aware walking, running and sprinting,
but ordinary autonomous routes always requested the default walking pace. Long roaming/scouting,
directed movement, returning home and urgent supply travel now request native running at bounded
distance thresholds. Short routes, movement within the same building, local patrol/work, corpse
dragging and movement to rest remain walking. Build 42's run state supplies its ordinary jog/run
animation; Knox does not invent a fourth speed, modify coordinates, or multiply movement speed.

The existing Java policy still reduces running near arrival and rejects it when endurance, fatigue
or health require walking. Existing native sprint eligibility governs fleeing and serious follow
catch-up, and the existing stealth posture can override ordinary running. Pace selection happens at
route creation, not through repeated path requests. `test-autonomy-formation.lua` now checks short
and long route thresholds, indoor walking and local-work walking.

Pending live check: observe a healthy independent survivor on a long outdoor goal, entering a
building, searching locally and returning home; then repeat while exhausted. Confirm natural
run-to-walk transitions, no indoor sprinting or request churn, and unchanged follow/flee behavior.

## Persistent world presence follow-up — 2026-08-30

**Status:** Implemented — live verification required. This advances P1 distribution and
pre-materialization progression; it does not yet complete the population/caps/offscreen-life scope.

### Evidence and defects

- The reviewed console initialized 32 living identities with no active bodies. Its first recorded
  natural activation was `ks-world-19` at frame 323701, roughly 86 tiles from the player. Allocation
  was happening; a guaranteed spawn beside the player was neither missing nor desired.
- Every new identity was confined to player-start locations. `advanceAll()` explicitly skipped
  identities without a Java body record, so unseen inhabitants never left those locations.
- After real loaded travel, `captureLoaded()` refreshed needs but retained old virtual XYZ. A later
  inactive advance could resume from an obsolete offscreen position rather than the fresh record.
- Population status reported only missing saved squares, omitting unmaterialized origins and
  virtual-square rejection. `waitingSquares=0` therefore did not mean activation was unobstructed.

### Changes

- Cached native world-building metadata supplements player starts. One actual ground-floor room
  rectangle per 100-tile cell can supply an origin; whole building bounding boxes are not treated
  as standable interiors. Allocation preserves region balance and normally uses two player starts
  for each supplemental building start, falling back when a source is exhausted. Birth origins
  remain unique and deaths do not immediately refill them.
- Never-materialized identities now keep a serializable location-only itinerary in the existing
  unloaded ledger. They travel between nearby catalog locations, stop for bounded intervals and
  remember their previous stop. No player position participates in choosing or advancing a trip.
  Spatial buckets bound candidate searches; eight legs/48 hours bound catch-up work.
- Initial activation considers the progressed location, still requiring a real loaded, hidden,
  standable, unoccupied, non-burning square outside the player exclusion radius. It does not fall
  back to the birth origin if the progressed square is unavailable.
- Position-only ledgers cannot apply unknown health/needs to a new body or enter stored-inventory
  physiology. Actual capture clears the pre-body itinerary and records fresh body XYZ and needs.
  The view model marks uninitialized vitals unknown rather than presenting made-up readings.
- Distant origin/virtual candidates are rejected before square-ring scans. A full activation budget
  skips candidate work instead of rewriting virtual survivor records that cannot activate.
- Catalog logs report native building/player-start counts; population status now distinguishes
  waiting origins, waiting virtual squares, outside-band identities and inactive progression.

### Verification

- Inspected the installed Build 42.20.3 `IsoWorld.getMetaGrid`, `IsoMetaGrid.getBuildings`,
  `BuildingDef.getRooms`, `RoomDef.getZ/getRects` and `RoomRect` coordinate/dimension getters.
  `LuaManager.Exposer` explicitly exposes these classes. Actual Muldraugh spawn tables confirm
  global `posX/posY/posZ` coordinates; no old-build world-cell coordinate conversion was introduced.
- Added `tools/test-world-presence.lua`: native metadata source selection, ground-floor filtering,
  bucket thinning/caching, mixed origin allocation, pre-body travel, deterministic ordinary
  refresh/reload, bounded old-save catch-up, hidden/occupied/fire/unloaded/near-player rejection,
  no relocation toward the player, activation-budget protection, real capture handoff, stale-XYZ
  cleanup, active/dead exclusion and legacy ledger initialization.
- All 47 standalone Lua tests and syntax validation of all 65 mod Lua files pass.

### Remaining / next

- Pending live: confirm catalog building counts on the installed map, observe at least one ordinary
  first activation after virtual travel, save/reload and revisit a survivor that moved while loaded.
  It must retain identity/gear/health and appear at the current valid position, not its birth house
  or old offscreen coordinates. Check activation counts during normal neighborhood exploration.
- Thirty-two identities across the county remain intrinsically sparse. This change removes static
  pre-body inhabitants and expands plausible locations; it does not prove a satisfactory encounter
  rate. Density policy and fuller inactive life remain P1 work; the cap option is covered below.
- Offscreen routes are lightweight same-floor abstractions, not native pathfinding through every
  obstacle. Native square validation still gates activation. Unloaded looting, full needs for
  never-materialized inhabitants, rural/road-zone distribution and broader faction/job progression
  remain pending; no fake items, health, bodies or second NPC simulation were added here.

## Optional survivor-cap policy — 2026-08-30

**Status:** Implemented — live verification required. Current verification: all 48 standalone
Lua tests, syntax validation of all 65 mod Lua files, translation JSON parsing, `git diff --check`,
and `gradlew :java:build stageWorkshop` pass (17 Java/build tasks). Workshop test files staged.

- Added **Disable Survivor Caps**, off by default. Existing configured values remain untouched.
  When enabled, neither the configured active-body count nor companion count blocks the operation.
  No numeric faction count cap exists in the current relationship/persistence path. Trust,
  independence, existing ownership, refusal cooldown and death restrictions are not bypassed.
- World Population stays the starting allocation size. Uncapped saves permit later arrivals above
  that number, at most one per refill interval. The persisted clock and permanently used origins
  prevent per-tick spawning, bulk catch-up arrivals or reuse of dead identities. Exhausted catalogs
  stop arrivals cleanly. A zero starting population can still receive later uncapped arrivals.
- Runtime population reconciliation constructs at most two bodies per update. This is a streaming
  rate limit, not a concealed total-body cap. There is no new claim that unlimited active characters
  are cheap: the setting explicitly warns of performance costs. Re-enabling caps stops excess new
  allocation/recruitment without deleting identities, forcibly dismissing companions or moving bodies.
- `test-sandbox-settings.lua` protects default/configured/disabled count behavior and construction
  rate. `test-world-population.lua` covers arrivals above target, interval enforcement, no same-tick
  duplication, bounded long-time catch-up, re-enable preservation and finite-origin exhaustion.
  `test-companion-cap-policy.lua` exercises the real recruitment gate and proves that disabling
  its count restriction does not bypass trust, group membership, refusal cooldown or death.
- Updated player-facing sandbox documentation to the actual current defaults/ranges and explained
  initial population versus uncapped later arrivals. No launcher, GitHub visibility or Workshop
  publication action was performed.

Pending live: on a disposable save set low companion/active limits, confirm they apply with caps
enabled, then disable caps and recruit an otherwise eligible extra survivor. Nearby saved bodies
must activate gradually beyond the configured active limit, retaining identities. Confirm one
later arrival after the configured interval, no repeated same-time arrivals, and save/reload with
surplus companions intact. Re-enable caps and confirm no existing companion or identity is removed.
Observe frame time during crowded tests before recommending this option for ordinary play.

## Native stored inventory / offscreen consumption — 2026-08-30

**Status:** Implemented — live verification required. This is a prerequisite correction for P1
offscreen survival and P2 real-item management, not completion of the full offscreen-life scope.

### Exact defects

- Inventory sub-schema 2 stored only root item type, condition, uses, favorite, worn/hand flags and
  visual bytes. It omitted nested bag contents, actual fluid quantities, food state, rounds and
  chamber state. Recreating item types cannot preserve those values.
- Unloaded survival classified brand-new default items by type. Any nonempty fluid was treated as
  water; it removed the whole saved item and reset the need to 0.22 regardless of the resource's
  actual contents/value. Supplies inside bags were not consumed.
- An absent needs ledger was initialized with zero health before inactive simulation, allowing
  an unknown stored survivor to be incorrectly declared dead.

### Changes

- Inventory sub-schema 3 uses native `saveWithSize`/`loadItem` payloads and preserves the native
  world version. Existing worn/primary/secondary bindings remain Knox-owned. Native serialization
  includes nested containers and subtype state. Buffer growth is bounded at 16 MiB per root; cycles
  and excessive nesting fail capture rather than recurse indefinitely.
- All native roots decode and validate type/nested count before destination clearing. Missing
  native/modded items or truncated nested inventories fail safely, preserving the saved record.
  Old sub-schema 2 is still readable and upgrades on fresh capture. Previously omitted values
  cannot be recovered retroactively, and older agent jars cannot read new sub-schema 3 saves.
- The new stored-supply bridge operates on detached decoded items, rejects active identities and
  returns an updated record with quantity-based relief. It searches actual nested contents, keeps
  reusable bottles, reduces partial food through native `multiplyFoodValues`, and removes ordinary
  fully consumed food from its saved container. It accepts pure clean water, not arbitrary liquid.
- Rotten/poisonous/dangerous-raw food, callback/byproduct-dependent food, and quantity-unknown legacy
  records are left for loaded handling. It does not invent a character to run those actions.
- Lua no longer classifies default items or grants a fixed reset. It commits the new inventory
  before granting the reported hunger/thirst change, including hydration from ordinary food.
  Up to four small supplies per need per six-hour step can be used, then the normal bounded update
  ends. A missing real needs snapshot now waits for real capture instead of manufacturing health.

### Verification and limits

- Inspected the exact installed Build 42.20.3 InventoryItem size-prefixed save/load, native
  InventoryContainer nested serialization, Food value multiplication, FluidContainer APIs and
  shipped ISDrinkFromBottle ratio. Shipped Apple/Banana data confirms ordinary food can use this
  path without scripted callbacks/byproduct handling.
- New `KnoxInventorySnapshotVerifier` exercises the Knox codec with native-method-shaped fixtures:
  nested contents, food state, fluid quantities, rounds/chamber, worn/hand bindings, schema-2
  migration, grown buffers, cyclic inventories, preflight refusal of missing items, immutable source
  records, partial/complete consumption, unsafe resource rejection and legacy no-invention policy.
  This is not a real initialized-game native serialization round trip; that remains a live check.
- Full verification passes: all 48 Lua tests, all 65 Lua syntax checks, `git diff --check` and
  `gradlew :java:build stageWorkshop` (18 tasks, including the new inventory verifier). Staged
  Java/Lua hashes match the source build. The installed Lua exposer explicitly supports
  `LinkedHashMap`, used for the supply transaction result; the bridge exposes its public methods.
- Updated unloaded-survival tests protect proportional relief, retained bottles, failed-commit
  behavior, missing-ledger safety, no same-time duplicate consumption and bounded small portions.
- Remaining: full offscreen food aging/nutrition/temperature, callback/byproduct foods, other drinks,
  injury treatment and world-resource acquisition. Need accumulation, rest and travel still use
  the existing lightweight policy; do not describe this as complete native offline human simulation.

### Pending live verification

Back up a disposable test save first and restart through the launcher so the new agent is loaded.
Give a survivor a worn bag containing a partially filled clean-water bottle, partially eaten safe
food, a spare magazine and medical items; equip a loaded firearm with known rounds/chamber state.
Save/reload and verify all contents, amounts, condition and bindings. Then hibernate the survivor,
advance game time, return and verify actual partial consumption with the bottle retained and no
unrelated items lost. Repeat with an unsafe fluid/rotten food and confirm they are not consumed.
Check for `CAPTURE_FAILED`/`RESTORE_FAILED`; do not reuse the old jar to load the upgraded test save.

## Stored independent travel / rest integration — 2026-08-30

**Status:** Implemented — live verification required. Advances P1 offscreen progression; this
does not complete shared group simulation, resource acquisition or the broader living-world goal.

### Defects and changes

- Stored independent survivors and return-home trips used arbitrary 1.25-tile/hour drift; all
  inactive time reduced fatigue and restored endurance even while travelling. Independent stored
  survivors now use the existing nearby-location catalog itinerary, including its destination
  memory and stops. The common itinerary reports actual moving hours; no second planner is added.
- Return-home travel now advances at 40 net tiles/game-hour, retains its current origin, refreshes
  against the assigned base and cancels when that duty no longer owns the survivor. The target
  floor is applied at arrival rather than immediately at departure. This is virtual progression,
  not new native routing or permission to move a loaded body by coordinates.
- Independent/base/companion ledgers split awake activity, endurance rest and sleep. Endurance
  spends while walking and recovers while stationary; fatigue no longer heals during travel.
  Existing Needs sleep policy controls whether sleep is required. Rest uses hysteresis, preserves
  the trip and resumes it afterward, with at most eight transitions per six-hour update step.
- Capture discards stale virtual rest/travel state. New rest phases were also added to the virtual
  restoration gate: without this integration they would fall back to the old captured tile after
  travel. All three phases retain hidden/standable-square checks. Existing activity labels now
  show resting, sleeping and returning-home status without a new UI.

### Verification

- Focused unloaded-survival tests cover meaningful travel, travel costs, sleep/rest pause/resume,
  sleep disabled, missing catalog, home relocation, cancelled return duty and preserved Hold.
- World-presence tests exercise the production itinerary and real Lua persistence (not only a
  mocked travel function), reload during sleep, segmented/single-step equivalence, duplicate-clock
  suppression, fresh-capture cleanup and progressed-location activation for every new rest phase.
- All 48 standalone Lua tests and all 65 mod Lua syntax checks pass. The Java build/checks and
  Workshop staging pass (18 tasks, including native transformer and inventory verifiers).
  Source/staged hashes match for all three changed runtime Lua files and the agent jar;
  `git diff --check` passes. No live game run, Git publication or visibility change was performed.

### Remaining / live check

Group-wide coordinated travel/rest and away-team policy remain unchanged; independently pausing
one group member would cause separation. These are the next offscreen coordination dependency,
not claimed complete by the independent-survivor tests. Offline injuries, native food aging and
real world-resource acquisition also remain unfinished. No simulated loot or healing was added.

Back up a disposable save and restart the launcher. Hibernate a rested independent survivor and
one with high fatigue/low endurance. Advance several hours: the first should travel to nearby
locations, the second pause then resume. Save/reload during rest; both must return at progressed
safe locations, never the old capture tile. Send a companion home several hundred tiles away,
verify gradual progression and arrival, then repeat with base relocation or replacement Follow.
Check identity, real supplies/needs, no duplicate bodies and no restore errors. Group/mission
regression observations remain required; no new live evidence was collected in this pass.

## Stored group travel / rest coordination — 2026-08-30

**Status:** Implemented — live verification required. Continues P1 offscreen life; full world
resource acquisition, injury/job simulation and remaining objective scope are still unfinished.

### Exact boundary and changes

- Previous group progression advanced each member independently along a 1.25-tile/hour heading,
  including while another member was loaded. Rest was unconditional recovery during that drift.
- Fully stored autonomous groups now use one nearby-catalog itinerary on their existing group
  record. Members retain their captured offsets and move by one shared delta; itinerary selection
  happens once per shared phase instead of once per person. No second survivor registry exists.
- The existing rest splitter accepts the cohort: highest fatigue/lowest endurance govern the
  shared pause, while actual individual ledgers retain separate fatigue/endurance and inventories.
  Supplies are consumed once per member through the existing real-record transaction. The group
  itinerary stores no duplicate health/needs values.
- A separated member triggers a leader wait and gradual approach at the existing virtual travel
  speed. Rejoin at six tiles releases the wait; different floors wait for native loaded navigation.
  Active members, absent real snapshots or conflicting duties suppress shared virtual movement.
  Stored members still advance physiology/rest. Unequal capture clocks align in place first.
- Membership/leader/capture changes invalidate stale shared routing. Death invokes existing
  social/identity cleanup and stops the old cohort update; surviving membership is rebuilt next
  reconciliation. Waiting/regrouping states retain progressed hidden-square restoration and
  readable activity labels. Away-team mission travel/recovery remains unchanged.

### Verification

- New `test-unloaded-groups.lua` exercises actual Lua persistence, production nearby-location
  selection and batch simulation: one decision for three members, preserved offsets, exhaustion
  pause/resume, sleep/reload equivalence, partial activation, unequal/rollback clocks, gradual
  regroup, different-floor waiting, missing snapshot, member/leader death, leader replacement,
  sleep-disabled policy and exactly-once per-member supply consumption.
- Updated individual simulation checks require group waiting outside the cohort scheduler.
  World-presence checks cover virtual restoration for both new group phases, including refusal
  to materialize at visible squares.
- All 49 standalone Lua tests and all 65 mod Lua syntax checks pass. Java build/checks plus
  `stageWorkshop` pass (18 tasks). All three changed runtime Lua files and the agent jar match
  staged hashes. `git diff --check` passes. These are automated checks, not live game evidence.

### Pending live and remaining work

Hibernate a three-person travelling group with one exhausted member; advance time and save/reload.
Confirm all three remain the same people, pause together, later travel and restore with spacing.
Repeat with a separated member, then with one member kept loaded: no silent virtual drift of the
stored members, no teleport regroup and no duplicate body. Test a member/leader death and confirm
the remaining group resumes with valid leadership. Verify personal supplies are consumed once.
The fixtures do not prove streamed-world routes, restoration animation or live native regrouping.
Away-team sleep, offscreen real-resource acquisition, wounds, jobs and wider P2/P3 scope remain
open. No game launch, Git publication or repository visibility change occurred in this pass.

## Carried utility / cleanup / nearby deposits — 2026-08-30

**Status:** Implemented — live verification required. First production P2 inventory-cleanup
boundary; long-range deposit routing and the full trade/value economy are not claimed complete.

### Defects and changes

- Looting prevented some new acquisitions but never removed obsolete carried gear/junk. Added
  retention utility and cleanup planning to the existing Looting module, using native carry weight
  with 90% start/80% stop hysteresis and bounded nested-bag inspection.
- Protects equipped/attached/hand-held/favorite items, favorite-bag contents, nonempty bags, medical
  supplies, ammo/magazines, essential tools, best melee, useful upgrades, near-term food/water,
  accessories/valuables, unknown mod items and current base task requirements. Extra food/water
  and known base materials are deposit-only; broken/inferior gear and known junk are droppable.
- Canonical owned-base nearby storage is preferred to dropping. Only adjacent, same-floor, clear
  interactions with assigned real containers are selected; full/blocked/foreign storage is not a
  cleanup target. The storage capacity helper previously called nonexistent `hasRoomFor(item)`
  and treated its exception as success. It now uses the exact native character/item overload and
  fails closed. Ammo classification also uses the authoritative ItemTag instead of `isAmmo`.
- One native transfer action owns cleanup at a time, using the existing off-slot transfer adapter.
  Floor drops construct the same native floor-container form as vanilla without borrowing a
  real player's indexed UI. Completion requires source removal AND destination/world receipt.
  Failure/timeout releases transient ownership with cooldown; combat and replacement commands
  interrupt it without replacing persistent duties. No custom delete/create inventory mutation.

### Evidence / checks

- Inspected installed Build 42.20.3 `ISInventoryTransferAction`, vanilla drop handling and
  `ISInventoryPage.GetFloorContainer`, plus exact ItemContainer constructor/capacity overloads,
  carry-weight and square-interaction APIs. Bytecode confirms `isEquipped` does not include
  attached items, so those receive their own guard. Shipped gold necklace data uses Accessory.
- New cleanup regression covers utility order, protected categories, weight hysteresis, reserves,
  favorite/nested/cyclic bags, job resources, canonical-base deposits, no duplicate actions,
  threat interruption, failed transfer cooldown, actual receipt verification and off-slot floor
  action construction. Storage tests now enforce native capacity arguments and check full,
  blocked and missing-owned-storage rejection.
- All 50 standalone Lua tests, all 65 mod Lua syntax checks, Java build/checks and Workshop staging
  pass (18 Gradle tasks). The four changed runtime Lua files and agent jar match staged hashes.
  `git diff --check` passes. No new live engine evidence was collected.

### Remaining / live verification

Run the carried cleanup/deposit gate in DEVELOPMENT_TESTING: overload one survivor with eligible
spares/junk and protected gear, test away from storage and next to owned categorized/depot storage,
then repeat with full/blocked/foreign storage, combat, Hold/Follow replacement and save/reload.
Verify items physically remain on the ground/in containers with no duplicate or missing items.
No live engine run was collected; fixture success is not proof of native animation/transfer.

Unknown/modded valuation deliberately keeps items instead of guessing they are worthless. All
medical/ammo reserves are currently conservative; no long detour overrides a companion order.
Longer useful-loot deposit trips, broader reserve balancing, trade prices and wider P2/P3 scope
remain open. No Git publication or visibility change was performed.

## Loaded owned-storage deposit trips — 2026-08-30

**Status:** Implemented — live verification required. Continues P2 carried-inventory management;
does not claim the full inventory/trading goal or offscreen resource logistics complete.

### Missing boundary and changes

- Cleanup previously deposited only within arm's reach. Useful surplus now permits a bounded
  local trip to a loaded assigned container at the survivor's canonical base. Real categorized
  storage is preferred, with depot/general fallback. Scope is same-floor, within 128 tiles;
  native `AdjacentFreeTileFinder.Find` selects a valid interaction side and existing movement/
  traversal performs the route. No new pathfinder, teleport or base-job registry.
- `MOVING_TO_DEPOSIT` participates in existing movement completion/failure/timeout/threat handling.
  Duplicate cleanup evaluation cannot replace active travel. Failed destinations receive 1800-tick
  suppression (maximum 16 remembered keys) plus 600-tick cleanup retry; other storage remains
  eligible. Native movement success resets movement failure state.
- Arrival recomputes current utility, job requirements and canonical ownership, then validates the
  exact assigned storage policy, proximity, clear interaction edge and real capacity before one
  native transfer. Equipped/favorited/newly-required items cannot transfer from a stale plan.
- Companion orders/directives, travelling groups, away duties and claimed jobs forbid this detour.
  Combat/new orders/streaming recovery/shutdown clear transient trip ownership while preserving
  inventory and persistent duty. Trip/action failures use existing cleanup and retry boundaries.

### Verification

- Inspected the exact installed 42.20.3 adjacent-square helper: checks standability, floor, wall
  edges and reachability; no new engine hook was needed. Existing capacity/transfer native evidence
  from the previous cleanup pass remains applicable.
- Expanded storage fixtures cover native approach selection, failed-key expiry/alternative, bounded
  distance, floor/edge rejection and exact policy revalidation. Expanded controller fixtures cover
  role guards, duplicate suppression, arrival/native transfer, changed item/base/order/container,
  danger/directive cancellation, bounded memory and failed-request fallback. Actual controller
  tick dispatch covers success/reset, native failure, timeout and detach recovery.
- All 50 Lua test scripts and 65 mod Lua syntax checks passed. Java build/checks and Workshop staging
  passed (18 Gradle tasks). No live game run was performed.

### Pending live / next dependencies

Run the extended carried-cleanup gate in DEVELOPMENT_TESTING, particularly a real trip through a
door, blocked storage, changing orders and save/unload mid-trip. Automated fixtures do not prove
streamed native movement or real-world inventory animation. Cross-floor/distant storage logistics,
reserve balancing, base relocation/yard follow-up, trade/currency and wider goal work remain open.
No commit, push, repository visibility change or external publication occurred.

## Weapon preference / companion policy — 2026-08-30

**Status:** Implemented — live verification required. P2 weapon-preference foundation; faction
doctrine and broader P2/P3 features remain open. Existing relocation/six-tile-yard implementation
was confirmed in current code/audit and left intact rather than reimplemented.

### Defects and changes

- Firearm preparation unconditionally preferred any ready/reloadable gun. The existing persisted
  survivor policies now hold `weaponPreference` (`auto`, `melee`, `ranged`), normalized for older
  saves. Companion commands validate ownership, life state and duty. Identical preferences do not
  increment revisions; policy writes cannot create a missing survivor identity.
- Survivor Choice normally selects usable melee. A native Aiming level 4+ survivor with at least
  three tiles of same-floor aiming space can favor a gun. Explicit ranged still passes all real
  weapon/ammo/reload checks, and unusable guns fall back to melee. With no usable melee, a usable
  gun remains a survival fallback rather than treating preference as a ban. No ammo or damage is
  invented; existing firing, sound, positioning and callbacks remain authoritative.
- Individual and party menus expose Prefer Melee / Prefer Ranged / Survivor Choice. Existing
  native checked-option rendering uses the game's positive-highlight color. Party Follow/Hold,
  climbing and combat stance also show honest shared-state checks; mixed parties have no false
  single selection. No UI replacement or custom checkmark renderer.
- Preference changes release native attack/reload ownership but preserve underlying commands.
  Normal sync is idempotent. Combat preparation receives the current target even after combat
  ownership is released, so automatic ranged decisions retain legitimate distance context.
- The firearm scenario explicitly sets its test survivor's ranged policy, preserving its purpose
  despite ordinary novice melee preference. Faction doctrine is not silently inferred/implemented.
- During duty inspection, the prior deposit-trip guard was found to exclude explicit `autonomous`
  duties. It now permits those while retaining owned-base, group, companion and job restrictions.

### Evidence / verification

- Exact installed 42.20.3 PerkFactory exposes native Aiming; existing native firearm action paths
  remain unchanged. Inspected `ISContextMenu.setOptionChecked` and rendering: native tick texture
  and `getGoodHighlitedColor`, not a guessed icon/color API. Java's existing best-melee selector
  rejects ranged/broken weapons and retains stable near-equivalent equipment.
- Expanded firearm fixtures exercise novice/trained choice, distance/floor, explicit preference,
  real no-ammo fallback, native reload cancellation and broken-melee fallback. New preference
  tests execute real persistence, ownership validation, no-op revisions, module reload, service,
  controller combat/reload interruption, individual/party menus and their callbacks. Mixed-party
  checkmarks and command preservation are asserted. Scenario wiring and autonomous deposit guard
  have regression coverage.
- All 51 Lua test scripts and 65 mod Lua syntax checks pass. Java build/checks and Workshop staging
  pass (18 tasks). No live game run was performed; native combat timing remains live-unverified.

### Pending / continuation

Use the weapon-preference gate in DEVELOPMENT_TESTING: real loaded/dry gun, reload interruption,
combat interruption, mixed party menu, existing Follow/Hold/Guard, save/reload and firearm scenario.
The full objective is not complete. Trust/reputation/trading/wallets, persistent resource acquisition,
Knox Events/faction variants and other documented goal requirements still need development/evidence.
No commit, push, publication or repository visibility change occurred.

## Player trust / reputation contribution foundation — 2026-08-30

**Status:** Implemented — live verification required. P2 relationship foundation with real defense
and aggression entry points; trade/gift/medical/construction action adapters remain unfinished.

### Defects and changes

- Existing personal trust increased through Talk but not verified defense. Existing faction-pair
  relationships had disposition but no numeric contribution reputation. Reused both records, with
  bounded per-kind cooldowns and rolling 24-hour reward budgets: personal trust +12 maximum,
  faction reputation +8 shared across members. Reward reasons are fixed, not arbitrary growing keys.
  Save/load preserves budgets; rollback does not reset them; unknown identities/players/times reject.
- `OnZombieDead` checks native death, actual player attacker and current living loaded survivor
  target before credit: same floor, at most eight threat-to-survivor tiles and twenty player-to-
  survivor tiles. No nearby-population reward scan. Duplicate callbacks use weak body-key suppression;
  missing native evidence fails closed. Credit speaks through the existing activity/speech system.
- Native unprovoked player hits now cost personal trust and NPC-faction reputation and record hostile
  faction disposition. Existing-hostile retaliation does not repeat the initial aggression penalty;
  player-owned factions are not made hostile to themselves. Real combat/damage is unchanged.
- Talk/recruitment lacked hostility guards. Both now reject canonical personal/faction hostility,
  and existing context-menu labels explain that refusal. Positive help cannot clear hostility or
  silently create alliances. Personal trust remains the existing recruitment input.
- Faction relationship readers now deep-copy nested contribution counters to preserve their stated
  read-only contract. No alternate trust/faction/identity registry or survivor body architecture.

### Engine evidence / verification

- Inspected exact installed 42.20.3 bytecode: `IsoZombie.onKilled` emits `OnZombieDead` before
  `DoDeath`; the base `IsoGameCharacter.onKilled` is empty. Confirmed native `getAttackedBy`, `getTarget`
  and death APIs. `OnWeaponHitCharacter` provides the actual attacker/target/weapon/hit value on the
  existing human-hit path. No new engine patch or fabricated health/kill signal.
- New reputation tests execute actual persistence and event handlers with native-shaped objects:
  native player-defense attribution, independent/faction records, cooldown/daily limits, time
  rollback, save/module reload, nested copy safety, invalid identity/time, duplicate events, hostile
  targets, other floors/distant/unrelated/NPC kills, split-screen ownership and aggression cleanup.
  Existing menu tests also exercise hostile Talk/Recruit labels and service guards.
- All 52 Lua scripts and 65 mod Lua syntax checks pass. Java build/checks and Workshop staging pass
  (18 tasks). Automated tests do not prove live death-event target availability or combat reactions.

### Pending / next work

Run the contribution/reputation gate in DEVELOPMENT_TESTING. Verify native target/attacker evidence
at actual death, card trust updates, faction hostility, bounded speech, save/reload and split-screen.
Missing evidence receives no credit rather than guessing. Gift/trade/treatment/construction reasons
exist as a completion-only recording contract; no automatic rewards for those actions are claimed.
Trading, currency/wallets, other reputation influences, event factions/raids and broader goal work
remain open. No commit, push, external publication or repository visibility change was performed.

## Independent survivor trading — quotation boundary — 2026-08-30

**Status:** Partially implemented. Read-only quote policy and focused checks are complete for the
initial supported item classes. Exchange, UI, currency and broader valuation remain unfinished.

### Missing boundary / changes

- Native trading was not an off-slot barter service. Exact installed `ISTradingUI` looks up the
  partner by online ID, sends network offer/seal/accept messages and registers real-player UI slots.
  Reusing that protocol unchanged would cross Knox's player-identity boundary. No engine patch or
  player-index workaround was added.
- Added `KS_TradeValuation`: real local player + loaded living non-owned neutral/friendly survivor,
  canonical personal/faction relationships and base work requirements, same-floor nearby quotes.
  Bounded recursive real-item ownership and unique dense offer validation reject stale/duplicate,
  equipped/favorite, unsupported/unsafe and corrupt inventory offers before valuation.
- Initial food/water/bandage/weapon/ammo/magazine/bag/clothing/tool values use actual subtype state.
  Stock and needs affect demand; canonical queued/claimed faction task requirements affect demand
  and reserve protection. Trust/faction reputation alter terms without random rerolls or zero-spread
  equivalent-item cycling. Whole baskets cannot sell the last reserve repeatedly; weaker treatment
  supplies cannot replace stronger reserves by item count alone. Known compatible ammo stays kept.
- No actual exchange, no free access to independent inventories, no rewards for merely quoting, no
  changes to current companion inventory/actions/orders, no new persistent inventory/economy ledger.

### Verification

- Inspected installed 42.20.3 native trading UI and inventory-transfer action, item subtype APIs,
  fluid quantities, and `AmmoType.getItemKey`/`ItemKey.toString` bytecode (`Base.*` keys). No inferred
  `InventoryItem.isAmmo` or fabricated vanilla price metadata.
- New `test-trade-valuation.lua` executes actual quote policy and actual Knox persistence, covering
  quantity/condition, need/stock, whole-basket reserves, ammo compatibility, base tasks, duplicate
  and stale offers, nested/corrupt inventories, player ownership/life/distance, trust/reputation,
  reload, selection-order stability, equivalent portion splitting and no item/reward mutation.
- All 53 Lua tests and 66 mod Lua syntax checks pass. Java build/checks and local Workshop staging
  pass (18 tasks). No new live game test was run; checks do not prove final transaction integrity
  or economic balance.

### Next dependency / remaining

Implement real-item exchange with completion-time revalidation, capacity/reach/danger checks,
temporary ownership and cancellation safety, then a native-looking Trade UI/context interaction.
Do not compose two cancellable one-way transfers that let one side pay while the other keeps its
goods. Quote results alone are not transaction authorization. Currency/wallets, rarity inputs,
broader medicine/material coverage and the rest of the full goal remain open. Follow the barter
gate in DEVELOPMENT_TESTING once the action/UI exists. No commit, push or visibility change.

## Independent survivor trading — real exchange action — 2026-08-30

**Status:** Implemented — live verification required for the exchange/action boundary. Overall
trading remains partial: no user-facing Trade menu/window, currency or complete valuation coverage.

### Changes / native evidence

- Added `KS_TradeAction.queue` for single-player real-item barter. It creates one short native
  player timed action, copies selected references and acquires a temporary lease in the existing
  controller/runtime. No new identity/inventory registry, fake network player or abstract stockpile.
- Queue and completion validate native item ownership, ID collisions, removal/add rules and final
  root capacity. Completion re-quotes current needs/relationships and checks adjacent unobstructed
  same-floor squares, life, vehicles, hit/attack state, recruitment and the same loaded NPC body.
  Native traversal, active actions, claimed jobs and perceived threats cannot be interrupted for
  trading. Nested outgoing weight is conservatively not credited toward destination capacity.
- `TRADING` retains the normal threat scan. Combat/flee, new directives, detached/shutdown bodies,
  action cancellation and a bounded lease timeout release ownership without erasing group/camp/
  command intent or overwriting a newer combat state. Transient action references are not persisted.
- The installed shared `ISTransferAction.lua` moves actual objects through `DoRemoveItem`/`AddItem`.
  Exact Java `ItemContainer` inspection confirms ID collision handling, original-owner detachment,
  dirty/process-item updates, add callbacks and native `hasRoomFor` behavior. Exchange delegates to
  the native helper inside one non-yielding callback, verifies both receipts, and captures the normal
  survivor record before awarding completion-only trade reputation. It does not queue two separately
  cancellable payment transfers. Native multiplayer is explicitly not supported by this adapter.
- Transfer/final-capture exceptions restore original instances to original containers and verify
  rollback; pre-exchange capture is retained if recapture fails. A failed rollback retains exact
  journal references, emits `RECOVERY_REQUIRED` and blocks further trading. This is a diagnostic
  failure path, not a durable crash-recovery guarantee; UI/recovery behavior still needs completion.

### Verification / remaining

- New `test-trade-action.lua` runs installed native transfer/base-action Lua with native-shaped
  inventory objects, real Knox quote/controller/runtime/persistence, and a mocked native capture.
  Covers success/receipt/idempotence, capacity, rule/ID rejection, cancel/queue failure, stale offers,
  danger/recruitment/death/distance, transfer failures before/after insertion, capture rollback,
  reputation errors, directive interruption, lease expiry, unload and retained fault evidence.
- All 54 Lua scripts and 67 mod Lua syntax checks pass. Java build/checks and local Workshop stage
  pass (18 tasks). No live run; animation, real Java container side effects and save/reload integrity
  are not proven by mocks. The existing gameplay has no new Trade menu yet.
- Next: native-style stock/offer UI and context interaction, safe bounded browsing ownership,
  clear cancellation/failure feedback and the documented live barter gate. Currency/wallets,
  broader value/rarity inputs, fault recovery and the rest of the full objective remain open.
  No commit, push, publication or repository visibility changes were made.

## Independent survivor trading — interaction / browsing UI — 2026-08-30

**Status:** Implemented — live verification required for the initial Trade interaction. Broader
trading/economy and the full playtest-review goal remain incomplete.

### Missing boundary / changes

- The tested exchange action was not reachable through normal play. Added Trade to the existing
  non-player-owned survivor context menu and a two-column offer window using native collapsable
  window/list/button widgets, fonts, item icons and green checkmarks. No network trading protocol,
  fake player slot, companion inventory replacement or separate inventory ledger.
- Browsing acquires the existing controller's temporary trading ownership, bounded by two minutes
  of wall time and 7200 controller ticks. Normal threat checks continue. Close, expiry, distance,
  danger, directives, scene/resolution changes and player death release browsing. Exchange replaces
  that exact lease; stale window cleanup cannot cancel a newer owner. Persistent duties survive.
- Stock lists refresh at most once per second and expose supported real items; selection never
  transfers anything. Quotes distinguish fair/low offers and reserve failures. Capacity/preflight
  errors remain visible until the offer changes. One accepted exchange runs per window; reopening
  starts another conversation. Closing during the action cancels it before mutation.
- Inventory review found stock browsing lacked the quotation's shared-inventory rejection, and
  hidden container contents were not inheriting protection. Both now fail safely, with regression
  coverage. Hidden, favorite, equipped and unsupported goods are not advertised as available.
- Initial UI uses the local player's viewport, native font metrics and joypad focus restoration.
  Existing independently owned inventories still cannot be opened for free looting through Trade.
  Multiplayer trading remains explicitly unavailable.

### Verification

- `test-trade-ui.lua` executes real UI/context callbacks, quote/action/controller/persistence and
  installed native transfer Lua with widget/native-object stubs. Covers selection and one exchange,
  close-before/during-exchange, stale offers, persistent failure messages, expiry/danger cleanup,
  menu/death/resolution cleanup, joypad selection/focus and hostile/multiplayer context guards.
- Layout assertions cover 1280x720 and 480x360 viewports with small and large font metrics; these
  are not rendered visual proof. Action coverage protects browsing lease handoff and late cleanup;
  valuation coverage protects hidden items/container contents and shared inventory.
- All 55 Lua test scripts and 68 mod Lua syntax checks pass. Java build/checks and local Workshop
  staging pass (18 tasks). Five changed trade/controller/context files match staged SHA-256 hashes.
  No new live test, commit, push, publication or repository visibility change.

### Pending live / next dependency

Use the barter gate in DEVELOPMENT_TESTING: right-click a nearby independent survivor, compare a
low offer with a fair one, complete a real exchange, check both inventories, cancel/interfere with
browsing/action, then save/reload. Confirm readable layout/scrolling/controller focus, native action
animation, no lost/duplicated items, completion-only reputation and normal survivor behavior afterward.
`RECOVERY_REQUIRED` remains a hard stop for the test, not a promise of durable crash recovery.

Next independent dependency is the native wallet/currency foundation, followed by supported value/
rarity and medical/material coverage. Durable exchange-fault recovery, broader reputation adapters,
offscreen progression, events/factions/raids and the rest of the objective remain open. Do not treat
passing this UI boundary as completion of the economy or the full development goal.

## Wearable wallets / physical currency foundation — 2026-08-30

**Status:** Implemented — live verification required. Initial cash/coin barter and native wallet
wearing are present; broader economy/currency/rarity requirements and the full goal remain open.

### Native findings / changes

- Exact 42.20.3 wallets already are real containers with capacity 1, max item size 0.2, native sounds
  and Wallet acceptance (maps/literature/FITS_WALLET). Key rings use a separate tag-driven inventory
  UI path, not a worn location. Retained the wallet container path instead of adding key-ring tags.
- Added a namespaced ItemBodyLocation in the native `media/registries.lua` entry point. Shared
  setup adds it to the Human body group and patches only CanBeEquipped on the four existing Base
  wallet definitions. No replacement items, contents migration, new inventory UI or capacity boost.
  Missing/noncontainer definitions are skipped; missing registry leaves native wallets unchanged.
- Native inventory menus/WearClothing completion and existing Knox equipment policy handle wearing.
  The slot is distinct from a backpack. Exact InventoryContainer save/load and Item factory code
  show contents remain native while wearing availability is reconstructed from the item script;
  existing Knox snapshot worn flags restore that slot. No production Java changes were necessary.
- Added a read-only physical currency descriptor for Money, MoneyBundle, GoldCoin and SilverCoin.
  Native UnbundleMoney yields 100 bills, so bundle/bill units and saturation are consistent. Currency
  uses existing quote/ownership/needs/stock/spread and real exchange, not a bank balance, generated
  change, free starting money or parallel transaction system. Worn-wallet contents can be offered;
  favorite/hidden wallet protection remains. Trade receipts still go to normal root inventory.
- Concrete cleanup defect: native MoneyBundle is categorized Junk and could be discarded despite
  holding real spending value. Cleanup now protects bundles, coins and small gold bars. Large gold
  bars retain native size/weight and cannot fit in wallets. Gold-bar trading rates remain unpriced
  pending native conversion/rarity review; gold coins provide the initial gold currency item.

### Verification

- New wallet/currency tests inspect installed wallet definitions and cash recipe, execute native
  acceptance/wear-completion Lua with native-shaped objects, then actual equipment policy and barter
  callbacks. Covers setup bounds/idempotence, unknown currency, denomination ratio, capacity-policy
  inputs, native wear, no repeated equip, wallet cash payment, remaining coin ownership and saturation
  equivalence after unbundling. The actual game bootstrap/registry and Java objects are not mocked
  into proof of live functionality: those remain explicitly unverified.
- Extended inventory snapshot Java regression: worn wallet plus backpack round-trip to distinct
  locations with the same two bills/one gold coin, then re-encode unchanged. Existing cleanup tests
  protect currency even when presented as Junk. Native serialization remains the production path.
- All 56 Lua test scripts and 71 mod Lua syntax checks pass. Java build/checks and local Workshop
  staging pass (18 tasks). Gradle reports existing deprecated-feature warnings; no build failure.
  No live run, commit, push, publication or repository visibility change.

### Pending live / next work

Run the wallet/currency gate in DEVELOPMENT_TESTING: normal Wear and bag switching, native capacity/
acceptance, NPC auto-equipment, unload/restore, save/reload, and real wallet-cash barter/cancellation.
Verify no wallet or cash is created by loading Knox. Unequip wallets before disabling the mod; a
custom worn slot is a mod dependency. Other mods changing these wallet wearing slots may conflict.
No visible 3D wallet attachment is added or promised.

Next is broader practical trade valuation (medicine/materials, rarity and conversion safety), then
remaining reputation/raids/events and offscreen-life dependencies in the full objective. Initial
coin utility and cash acceptance require live economy balance; PMC payments, other currencies,
precious-metal conversion and durable exchange fault recovery are not complete.

## 2026-08-31 — live-playtest failures and player-facing feedback

Status: targeted corrections implemented, focused/full automated checks passed, staged locally.
No new live run, commit, push or public release. These checks do not establish audible/visual acceptance.

### Evidence and corrections

- Return to Base: console frames 48347–48833 show four controllers stopping in
  `KS_BaseJobs.itemRequirements` while scheduling farming. Kahlua has no `select` global.
  Requirements now use `pairs({...})`, retaining optional arguments after nils. Regression runs
  the real job planner with `select=nil` and checks that seed requirements survive.
- Nameplates: setting `showTag` alone does not render a single-player username. Exact 42.20.3
  `IsoGameCharacter.renderlast` uses the multiplayer-client branch for usernames; the SP branch
  is vehicle-key text. Added a native Small-font label renderer with each real viewer's camera,
  same-floor/range/CanSee checks and NPC alpha. Relation colors refresh on the existing bounded
  update, not every render. No local-player slot, remote flag or native visibility override added.
- Clothing oscillation: logs alternate shorts/trousers. The policy compared only the exact worn
  location, overlooking native mutually exclusive slots. It now compares the total displaced
  gear, using `WornItems.getBodyLocationGroup().isExclusive`, as vanilla's wear tooltip does.
  Unknown/unreadable worn metadata fails closed. Same-type duplicate-item selection in the
  full-type Java equip bridge remains a separate limitation; this patch addresses slot oscillation.
- Trade: console frame 11341 confirms a completed exchange. The window now closes only after
  `action.finished && action.success`; a rejected/rolled-back exchange remains readable. No early
  close on confirm, no transfer changes and no duplicate exchange queue.
- Native impact audio: exact `CombatManager.attackCollisionCheck` bytecode 1628 rejects an off-slot
  attacker's standing-target impact sound via `IsoPlayer.isLocalPlayer`. The existing transformer
  now redirects only that audio guard through the existing shell predicate. The 42.20.3 offset,
  method reference, branch and following ranged test must match; otherwise it fails closed.
  Native hit/floor/gunshot callbacks, FMOD material parameters, damage and world noise remain native.
  The original three animation callback gates remain unchanged. Actual audible playback is pending.
- Melee cadence/posture: live melee recovery increased from 24 to 30 runtime ticks; firearms retain
  24. During recovery, native aiming input stays on without initiating an attack or restoring
  AttackType. This preserves the intended defense/hit-reaction interval and ready posture.
- Reputation: successful talk, trade and credited defense report actual personal trust gains in the
  activity feed after the response. Conversation displays the participant first. Capped gains use
  the real delta; cooldowns do not manufacture rewards. Personal reputation is not faction reputation.
- Locked entrances/roaming: locked windows were excluded even for urgent needs, leaving door breaking
  as the only destructive fallback. Usable alternate windows now rank before other door alternatives;
  locked windows are last-resort candidates only for an actual shortage, sufficient endurance and
  permitted structure damage. Barricades remain excluded. Failed container routes now also suppress
  the room/building in roaming and force onward travel rather than retrying sibling containers.
- Loaded roaming previously searched only 18 tiles and remembered a visit for 900 ticks. A bounded
  two-tile grid samples out to 48 tiles, retains the closest sampled position per building, and
  checks zombie pressure once per eligible building. Visit/failure memory is now 7200 ticks with
  the existing 12-entry bound. Outdoor fallback retains travel direction; no unloaded-world routing,
  teleportation or new planner. Tests execute actual next-block selection, blocked-room avoidance,
  expiring/no-goal state and outward fallback, rather than only checking source strings.
- Area highlights: cleanup iterated current zones, so removed zones/old boundaries could not be
  cleared. Track actual touched floor objects, clear them before reapplying all enabled viewers,
  and refresh both remove-area UI entry points. Removed invalid per-tile area-highlight fallback.
  Tests cover deletion, boundary replacement, base removal, split-screen overlap and new-game reset.

### Verification and remaining live checks

- 59 Lua test scripts pass; 72 mod Lua files pass syntax checks. Java build/checks and Workshop
  staging pass (18 tasks), including movement/locomotion, traversal, corpse, inventory, combat
  lifecycle and transformer checks. Impact audio's transformed class defines under the game's
  Java 25 with `-Xverify:all`; the patch rejects an already-transformed/unknown gate shape.
- Existing Gradle deprecation warning remains. Pre-existing map/fluid-definition errors in the
  console were not attributed to Knox or patched speculatively.
- Live: restart through the Knox launcher; Return to Base with farming enabled; adjacent nameplate
  visibility/fade/colors; shorts/trousers stability; completed/failed trade; conversation capped
  reputation; bat and firearm sound; natural ready stance and continued zombie bites between swings;
  locked-door/window alternative then onward travel; remove a highlighted zone/boundary.
- Engine/source inspection and mocked tests cannot prove sound playback, animation appearance,
  real-world path reachability or all modded clothing combinations. No blanket "all live bugs fixed"
  or public-release readiness claim.

### Preserved in-progress trade valuation work

The prior medicine/material valuation work was retained and checked rather than discarded during
this playtest pass. Focused tests now exercise remaining native dose fractions, medical reserves,
sheet-unit equivalence and bounded cached procedural-loot hints. These are relative barter weights,
not exact spawn probabilities. No world scans, abstract money balance or trade transfer rewrite.
Live economy balance, additional conversion families and the larger goal's raid/event work remain pending.

## 2026-08-31 — Release packaging / private-source boundary

Status: packaging and launcher checks pass locally; Steam upload/download and real cross-platform
game launches remain pending. Source repository is private; launcher repository remains public.

- Confirmed native `SteamWorkshopItem.getContentFolder()` uploads `Contents`, not its parent.
  The agent/sidecar were staged outside that tree. They now ship inside
  `Contents/mods/KnoxSurvivors/java/`; the development launcher uses that same path.
- Staging is now a Sync restricted to the generated mod payload, not Workshop metadata.
  This removes obsolete Lua files and old agent versions. An obsolete `KS_BaseSetup.lua`
  was present in staging and is now absent. Previous payload and both repositories were
  backed up outside the repositories; legacy staged Java files were moved into that backup.
- The separate launcher needed three Windows startup corrections: a PowerShell VDF
  replacement expression was being passed as two List.Add arguments; Start-Process lost
  quoting around the extracted JAR; cmd /s removed the only quotes around the game path.
  Native child-process tests with spaced paths and Windows PowerShell 5.1 bootstrap tests
  now exercise these boundaries without starting a game or touching a save.
- Launcher checks both mod.info files, rejects missing manifests safely, and has negative
  coverage for missing/corrupt checksums, version/compatibility mismatch, old Workshop
  builds and duplicate runtimes. Private source access is not a launch dependency.
- All 59 Lua tests / 72 syntax checks and Java checks pass. The installed Java 25 can run
  `WorkshopPayloadVerifier` against the actual native mod-folder/file-type validators;
  the staged Contents also passes the separate launcher's real package validator.
- Launcher main-branch pushes now run Windows/Linux/macOS CI; tagged archives remain drafts
  until the owner publishes them. Unix source argument files preserve paths with spaces.
- Remaining release gate: this staging root lacks `workshop.txt` and `preview.png`. Restore
  the existing item's metadata/preview (ID 3749727604), review the upload, then test a normal
  Steam-downloaded copy with the release launcher. Do not equate fixtures/CI with live
  Linux/macOS, Flatpak or large-population gameplay verification.

## 2026-08-31 — Workshop upload preparation

- Reused the old subscribed mod's original 512x512 poster and 256x256 icon unchanged;
  root/Build 42 mod.info reference those assets. The same poster is the upload preview.
- `prepareWorkshopUpload` explicitly stages the runtime and writes existing item
  3749727604 metadata from the versioned player-facing BBCode description. It does not
  publish. Copy explains launcher requirement, fresh-save testing, unfinished behavior,
  42.20.3/single-player focus and unverified Linux/macOS live launches.
- Native `SteamWorkshopItem.validateContents()` now passes on the complete prepared
  folder, including the PNG. Launcher validation passes on the actual staged Contents.
  Java checks pass; no gameplay code changed in this packaging pass.
- Launcher preview tag `v0.2.0-preview.1` targets the previously verified 5c949b3 code;
  release automation prepares a draft rather than advertising an untested Workshop pairing.
- Normal subscribed-install testing remains pending. Two local Mod ID KnoxSurvivors
  copies must be moved aside with the game closed; neither has been moved during
  packaging while the game is running. See NORMAL_PLAYER_TEST.md.

## 2026-08-31 — Flee speed and blocked escape recovery

Status: implemented; focused/full automated checks pass. Actual escape gait and
post-fence recovery still require live verification.

Evidence from `dev-runs/20260831-043503`:

- `ks-world-113` repeatedly switched from FLEEING to retreat-complete/exploration,
  failed movement against static blockages around 10709,9964, and died. The run
  also contains a fence climb followed by FailedStuck. Logs do not prove the exact
  tall-fence animation failure reported visually, so no speculative animation or
  off-slot engine patch was added.
- Factory locomotion compared native `IsoGameCharacter.getHealth()` against
  15/25-point run/sprint thresholds. Exact 42.20.3 bytecode initializes that raw
  field to 1; real human BodyDamage exposes `getOverallBodyHealth()` on a 100-point
  scale. Healthy characters could therefore be denied all running.
- `KS_FirearmSupport.cancelPreparation` inspected `action.gun:IsWeapon()` when
  an unrelated queued action had no gun. A pcall caught it but Kahlua still logged
  the error every policy refresh.

Changes:

- Movement eligibility now reads real BodyDamage first, with a normalized native
  raw-health fallback. Existing endurance/fatigue/native sprint restrictions stay
  authoritative. Explicit run/sprint movement no longer becomes crowd/player sneaking.
  Lua danger evaluation also prefers real BodyDamage health.
- Escape candidates and shared group escape targets validate short loaded segments
  with native `isBlockedTo` and `isHoppableTo`. A standable tile beyond a wall or
  fence is no longer assumed to be an immediately clear escape lane. Tangential and
  shorter alternatives are considered; native movement still owns actual coordinates.
- Failed flee requests release movement and preserve escape intent with 15/30/60-tick
  bounded backoff plus short failed-destination memory, rather than normal long travel
  waiting/returning to loot. Arrival does not end retreat while close/targeting threats
  remain. Two clear observations release retreat and reset movement recovery.
- When no clear escape exists, an adjacent reachable attacker can pass to existing
  native combat (respecting companion stance), instead of leaving FLEEING helpless.
  This is not a guarantee of survival when trapped, exhausted, or badly injured.
- Unrelated timed actions are no longer dereferenced as firearm preparation.

Verification:

- All 59 standalone Lua tests and 72 Lua syntax checks pass. Added blocked-lane,
  failed-destination, bounded retry, ongoing pursuit, trapped defense, retained Follow,
  successful recovery, and no-nil-gun-error regressions.
- `:java:build prepareWorkshopUpload` passes, including native health-scale adapter
  coverage, movement/traversal/combat/corpse checks, and Java 25 transformer verification.
- Native complete Workshop upload validation passes. Staged agent and sidecar match
  SHA-256 `15dea740a2f33b04b2c7a84c8b83e215b03904c67b8ecb31a874da6ebe870015`.
- The actual v0.2.0-preview.1 Windows release JAR accepts the updated staged package;
  launcher protocol/version did not change, so no launcher binary replacement is needed.
- At the owner's request the launcher preview is now public under tag v0.2.0-preview.1;
  anonymous downloads and checksums of all four release assets were verified. Source
  stays private. Steam upload and subscribed-install gameplay were not performed here.

Pending live: a healthy pursued survivor runs, chooses a clear route beside a blocking
fence where possible, recovers after a failed route without a request storm, does not
resume looting while still pursued, and resumes prior duty once safe. Severe exhaustion
or injury can still legitimately limit speed. Verify the updated Steam payload, not a
shadowing local copy. Linux/macOS real game launch remains unverified.

## 2026-08-31 — Empty-hand errors, medical checks, and retreat reversal

Status: implemented, regression checks pass; live verification pending.

Latest test evidence (run 20260831-051303 and its console log):

- Repeated `IsWeapon of non-table: null` at KS_FirearmSupport.lua:193 comes from
  `primary:IsWeapon()` with an empty hand. The previous patch guarded queued
  `action.gun`, but missed this separate primary-hand dereference. Both empty-hand
  cancellation and firing preparation now stop before subtype inspection; the
  regression counts caught exceptions, not just the function's false result.
- Exact 42.20.3 `ISHealthPanel.canPerformMedicalCheck(target, requester)` calls
  `luautils.walkAdj(target, requester:getCurrentSquare())`. It moves the patient;
  it is not a read-only distance check. The old context handler called it, changed
  the companion to Hold, then captured the patient's position before approach
  finished. Native medical actions invalidate when that position changes.
- Medical Check now validates availability and native approach feasibility first,
  keeps the existing companion Hold behavior, and queues only the real player's
  approach. Its scoped native ISMedicalCheckAction instance anchors the patient at
  action start, rechecks real reach/body identity/death, and keeps native animation,
  duration and health-window completion. No global vanilla override or custom heal.
  Duplicate clicks are suppressed. Failed/interrupted checks report a short message
  and a Medical log entry. Moving/dangerous patients can still interrupt treatment.
- `ks-world-5` repeatedly logged retreat-complete then COMBAT_STARTED about five
  tiles from a zombie five ticks later (for example frames 53718–53843). The previous
  fix prevented three-tile pursuit exits, but still permitted this fresh chase.
  Retreat now requires eight-tile clearance plus existing danger checks and two
  distinct safe observations. A bounded 600-tick post-retreat chase restriction
  leaves adjacent self-defense available without immediately reapproaching a crowd.
- Flee scoring previously checked obstacle-free segments but only measured zombie
  safety at endpoints. Short candidate segments now reject passing closer through
  a nearby zombie, and their endpoints must improve nearest-threat separation.
  Existing group escape targets use the same checks. No teleporting or pathfinder rewrite.
- Native NO_EQUIPPED_WEAPON rejection now records an unarmed survival fallback and
  uses a short retry boundary, rather than a long failed-combat idle. If still
  unequipped and threatened, the next danger check chooses retreat. A usable weapon
  removes that extra retreat pressure. This does not add unarmed melee mechanics.

Verification: all 59 standalone Lua tests and 72 Lua syntax checks pass, including
behavioral medical tests (the old check was source-string-only), nil-hand exception
coverage, post-retreat acquisition, adjacent defense, cooldown expiry, blocked crowd
segments, and unarmed escape fallback. Java source and runtime protocol are unchanged;
`:java:jar stageWorkshop` passes. Full prepared-payload and released-launcher validation
pass with the same agent checksum as the preceding entry. No launcher patch required.

The staging directory was absent at packaging time; it was regenerated from source
with the existing Workshop ID and versioned preview/description. Prior release backups
remain available. No Steam upload or save edits were performed.

Pending live: right-click Medical Check on a stationary nearby companion opens the
native treatment window after the doctor's approach; a moving/unloaded patient cancels
cleanly. Escape from a crowd must continue without immediate chase reversal and return
to prior activity once safe. No new nil-hand Kahlua errors. Existing stair/path failures
and unrelated map/recipe warnings are not claimed resolved by this patch.

### Local test deployment follow-up

The latest console session ended at 08:09 on 2026-08-31, before the 09:50
medical/retreat fix commit. Its errors therefore do not establish a regression
in that patch. The prepared Workshop files already matched the fixed source,
but the installed local test copy of the three affected Lua files still matched
the preceding commit. Backed up those local files and applied only the verified
medical-menu, firearm-support, and retreat-controller patch; unrelated in-progress
event work was not deployed.

Verification: all three installed files now hash-match the fixed source and pass
Lua syntax checks. Medical-menu, firearm-support, and combat-intelligence focused
tests pass. The released launcher JAR passes validation against the prepared
Workshop Contents; no launcher patch is needed. In-game medical completion and
escape behavior remain live-unverified. Steam was not uploaded in this follow-up.

## 2026-08-31 — Knox Events persistence and real-roster raid planning

Status: framework/proposal boundary implemented and automatically checked; actual raids
are not enabled or claimed complete. The full development goal remains active.

The missing dependency was a durable event lifecycle tied to existing people and factions,
not a new event NPC spawner. Added `KS_KnoxEvents` and an additive schema-14 domain with
revision-checked phases, event IDs, timestamps, owner/location fingerprints, canonical
member IDs, and expiring cooldowns. Scheduled proposals require existing hostility and
bases, take no more than 40% of living members, leave at least two available residents,
and exclude claimed workers and away-team members. Planning never creates survivors,
weapons/ammunition, inventory snapshots, or replacement duties.

Validation found and closed three edge cases in the initial foundation:

- Losing a non-raiding defender could leave an oversized party even with two defenders
  still present. Pre-departure validation now rechecks the minority proportion too.
- Pruning completed history could erase a faction's cooldown. Expiring cooldown records
  now survive history pruning and save-state reconstruction.
- Malformed deployed bookkeeping could discard its roster. Recovery now requests
  withdrawal and retains members/owners for real cleanup rather than pretending they
  returned. Invalid serials/floor data/member lists fail safely; serial collisions do
  not overwrite another event.

Existing population maintenance processes the ledger at its normal interval; there is
no extra per-frame listener or automatic raid trigger. Death, peace, relocation, and
new job ownership cancel unstarted plans or request deployed withdrawal. A timer cannot
report a raid victory, actor arrival, or completed return. Finished records have bounded
retention; active withdrawals are never pruned to conceal incomplete cleanup.

Verification: all 60 standalone Lua tests and 73 source syntax checks pass. The new test
covers real-roster selection, no generated actors/gear, unchanged persistent duty, phase
ordering/idempotency/stale callbacks, reload, death, strength loss, claimed work, relocation,
peace, malformed data, bounded processing, and cooldown retention. `:java:jar stageWorkshop`
passes; no Java sources changed. Exact installed 42.20.3 native Workshop payload validation
and the actual released launcher JAR validation pass. Agent SHA-256 remains
`15dea740a2f33b04b2c7a84c8b83e215b03904c67b8ecb31a874da6ebe870015`.

The previous staged upload was backed up before replacement. This pass stages the verified
foundation but does not upload Steam or publish a launcher update. No launcher patch is
required; runtime protocol is unchanged. Local gameplay after schema migration remains
unverified.

Next dependency: runtime dispatch must verify actual member health/loadout, claim existing
duty/movement ownership safely, preserve native resources across loaded/unloaded travel,
execute real objectives, then reconcile casualties and return surviving members home.
Only after those boundaries are verified should automatic triggers and incremental Police,
Scientists, Military, Scavenger, PMC-contract, and Black Division event policies be enabled.
Other outstanding full-goal requirements and earlier live gates are not closed by this pass.

## 2026-08-31 — Real event dispatch, travel, and return ownership

Status: implemented — live verification required. The dispatcher handles explicitly
scheduled plans; random raids and complete raid objectives are not enabled.

- Added a temporary event binding to the existing base duty. All members are validated
  before any are claimed; home, affiliation, job preferences, native inventory and
  equipment remain authoritative. Existing base jobs/Away Teams cannot take dispatched
  members. A mismatched release cannot erase a newer duty.
- Dispatch checks each selected loaded resident's actual needs, carried weapon, firearm
  readiness, home location and busy state. Injured/exhausted/unarmed/busy members defer
  the plan; a restored claim phase cannot bypass readiness for unclaimed members.
- Event movement uses the existing Java movement request and Lua failure/recovery path,
  contextual pace, and group follow/regroup structure. Destinations are distinct near
  the target building's approach side. Projection refresh does not cancel a valid route
  or reset backoff. Combat/self-care can preempt travel without deleting event/home intent.
- Reused the stored group scheduler for wholly hibernated parties: shared progress,
  preserved spacing, weakest-member rest, existing physiology/resource use, and persisted
  route state. Mixed loaded/stored parties wait together; stored residents cannot jump
  back to ambient base coordinates while dispatched. One surviving member can return.
- Real loaded positions establish arrival. Withdrawal completes from loaded home arrival
  or completed virtual travel home, not a timer. Death, peace, duty replacement, repeated
  approach failure, fleeing, and lost homes have explicit cleanup paths. Native death and
  corpse creation remain untouched. Malformed deployed rosters fail closed without
  silently discarding living members.

Focused tests caught and corrected two integration assumptions: territory uses inclusive
maxX/maxY rather than the building's width/height shape, so readiness/return reuse the
existing BaseManager containment function; absent controller expressions returned false
instead of nil and broke stored-return checks. No engine workaround was needed.

Verification: all 61 standalone Lua tests and 74 syntax checks pass. New runtime tests
execute the canonical persistence service, native-move request entry point, and existing
unloaded cohort scheduler with engine fixtures. They cover readiness, atomic claim,
ownership exclusion, stable sync/backoff, combat resume, reload, loaded/stored travel,
shared rest, mixed-loaded waiting, return, death, corrupt records, and lost-home release.
These tests do not prove live navigation, firearm damage, or a complete raid objective.

Packaging verification: `:java:jar stageWorkshop`, exact installed 42.20.3 native Workshop
payload validation, and released-launcher validation pass. The staged payload was backed
up first. Java source, agent checksum, and launcher protocol are unchanged, so no launcher
patch is needed. Steam was not uploaded and the launcher release was not modified.

Next dependency: real raid objectives and their completion/failure evidence, readiness
for already-stored factions, safe automatic scheduling, and convenient live scenario
tooling. Event factions/PMC contracts, other full-goal requirements, and previous live
acceptance gates remain open. The overall goal is not complete.

## 2026-08-31 — Native raid supply objective and evidence

Status: implemented — live verification required. Explicitly scheduled real-roster
raids now proceed from arrival into a bounded supply search, then withdraw through
the existing return duty. Automatic raid triggers and event-faction rollout remain
disabled/unimplemented; this is not a claim that full raids are release-tested.

- The active phase previously had no objective owner. The dispatcher now starts one
  persisted two-hour search with a small party quota (two useful items per member,
  at most six). Existing ranked looting selects carried supplies/equipment; existing
  movement, traversal, reservations, inventory capacity and timed actions perform it.
  No new loot planner, abstract stockpile, actors or free raid equipment are created.
- Event search misses have their own bounded counter and existing search cooldown.
  They cannot clear an unrelated companion directive. Three unproductive searches
  per member or the deadline cause withdrawal, not indefinite rummaging.
- Objective success is not inferred from an empty action queue or animation ending.
  Exact installed 42.20.3 `ISInventoryTransferAction:perform()` batches items and calls
  `transferItem()` for each. The Knox-derived action observes the native transfer only
  after the original item leaves the source and the returned native item actually
  belongs to the destination inventory. No-op, floor fallback and duplicate callbacks
  earn no receipt. Native replacement items use their returned identity.
- Receipts persist only item ID/type, member, time and source coordinates. They never
  recreate inventory. Malformed objectives/receipts withdraw without a success claim.
  Quota completion, partial loot and no useful supplies have distinct outcomes.
- The action validates event membership, current body, target base location, hostility,
  deadline and quota before further transfers. Peace, death, changed duties, target
  relocation or withdrawal prevent remaining event transfers. The native batching
  predicate also preserves event context instead of merging unrelated ownership.
  Ordinary transfers with no event context retain their native path.
- Returning home, combat preemption, death, group cleanup and stored travel remain
  owned by the preceding dispatch implementation. Objective completion does not
  release a party at the enemy base or move goods into a fictional home stockpile.

Verification: 62 standalone Lua tests and 74 mod Lua syntax checks pass. New behavioral
coverage exercises real persistence/event services, the derived inventory action,
source/destination membership, batched transfers, replacement items, quota, failed
transfers, peace/death/duty/relocation cancellation, cooldowns, corrupt state, saved
receipts and honest outcomes. A second run loads the installed 42.20.3 native Lua
`perform`, `checkQueueList`, `canMergeAction` and `transferItem` functions over Java/UI
fixtures. This checks actual Lua callback compatibility, not live engine animation,
Java transfer correctness, navigation, damage or a complete encounter.

Pending live: explicitly schedule a hostile five-member faction's two-person raid
against a loaded stocked base. Observe travel, existing combat interruptions, real
container/item changes, bounded search, withdrawal and return. Reload during search
and return; confirm no duplicated supplies or changed defenders. Repeat with an empty
base and peace during a queued transfer. Native human combat, automatic scheduling,
already-stored dispatch readiness, convenient event scenarios, faction-specific events
and the other full-goal deliverables remain open. Next work should close those common
event dependencies before enabling event factions or random attacks.

Packaging: backed up the previous staged payload, then ran `:java:jar stageWorkshop`
successfully. Exact native Workshop validation (including existing item/preview) and
the released launcher verifier pass. The agent SHA256 remains
`15dea740a2f33b04b2c7a84c8b83e215b03904c67b8ecb31a874da6ebe870015`.
No Java/protocol or launcher change is required. This updates staging only, not Steam
or the already-installed local test copy; fully restart after deploying a new test build.

## 2026-08-31 — Stored event-party readiness

Status: implemented — focused/full automated verification passes; live verification required.
This closes the already-hibernated readiness dependency for explicit real-roster raids. It
does not enable automatic events or claim that raid travel/objectives are live-proven.

### Exact defect and correction

- Event dispatch previously required a loaded controller for every selected member. A healthy,
  equipped faction whose residents were correctly hibernated at home could therefore never
  leave for an event; the dispatcher returned `member_unavailable` indefinitely.
- Stored members now qualify only from a fresh real unloaded-survival snapshot, their persisted
  home position, and their existing encoded native inventory. Health, bleeding, endurance,
  fatigue, hunger, thirst, rest/return state and activation ownership must all be safe before
  the party can be claimed.
- A read-only Java bridge probe decodes only the saved equipped-primary item and applies the
  exact Build 42.20.3 usable-weapon boundaries needed for departure. It neither reconstructs
  an `IsoPlayer`, equips/defaults an item, consumes ammunition nor changes the encoded record.
  Invalid, legacy, modded or incomplete snapshots fail closed.
- All selected members are validated before any event duty is claimed. A Lua controller or
  Java-active identity cannot fall back to an older stored snapshot. Failed native inspection
  retries at a bounded three-world-minute interval instead of deserializing inventory on every
  event update. Successful dispatch continues through the existing stored-group travel path.

### Verification

- Exact installed 42.20.3 `InventoryItem`/`HandWeapon` signatures were inspected for weapon,
  broken, ranged, safety, jam, chamber and ammunition state.
- `tools/test-event-stored-readiness.lua` covers healthy/unsafe/missing state, all-floor home
  containment, active-body guards, old/missing bridge behavior, atomic party rejection,
  bounded recovery, save reconstruction and no actor/item creation.
- `KnoxInventorySnapshotVerifier` covers loaded melee/ranged, empty/unchambered/jammed/safe/
  broken firearms, spare-vs-equipped state, legacy records and mutation-free round trips.
- All 63 standalone Lua tests and 73 mod Lua syntax checks pass. `:java:build
  prepareWorkshopUpload` passes, including Java 25 class/transformer verification and the
  complete inventory/persistence verifier set.

### Pending live and next dependency

Schedule an explicit raid while every selected resident is hibernated at its real faction base.
Confirm the same IDs activate/travel with their existing equipment, an unready member defers the
whole party without partial duty claims, and a later-ready party departs once. Reload before
departure and during stored travel. Automatic scheduling remains disabled; the next common
event dependency is a conservative scheduler using the existing proposal/cooldown system and
convenient development scenarios, before any faction-specific event rollout.

## 2026-08-31 — Conservative automatic faction-raid scheduling

Status: implemented — automated policy/integration checks pass; live verification required.
This activates only the generic real-faction raid path. Police, Scientists, Military,
Scavengers, PMC contracts and Black Division remain unimplemented.

### Missing boundary and implementation

- Raids previously required a direct API call even when two established factions were explicitly
  hostile. The existing event ledger, proposal, dispatcher and real supply objective were never
  selected by normal world updates.
- The population interval now invokes one persisted scheduler. It waits for the configured world
  age, evaluates only existing non-player factions and existing hostile target bases, rejects
  source/target distances over 600 tiles, and permits only one automatic event at a time.
- Candidate rotation and next-check time persist under `knoxEvents.automatic`. A successful check
  defaults to seven in-game days before another; a world with no eligible pair retries after six
  hours rather than scanning every tick. Selection is deterministic and bounded.
- Scheduling still calls the existing `proposeRaid`/`scheduleRaid` boundary: at most 40% of living
  members leave, at least two eligible defenders stay home, base workers/Away Teams/event members
  are excluded, and no survivor, relationship, item, weapon or ammunition is created.
- New sandbox settings control whether new faction raids may be scheduled, the first possible
  raid day and the global scheduling interval. Disabling factions or hostile encounters also
  disables new automatic raids. Active parties retain their return/cleanup ownership.
- A destructive developer context action schedules the next eligible raid immediately through
  the same policy. It does not create a test faction, force hostility or bypass roster strength.

### Verification

- `tools/test-event-automatic-scheduler.lua` covers settings/world-age gates, neutral rejection,
  hostile real-roster scheduling, no duty/inventory/identity mutation, due-time bounds, one-active
  policy, persisted interval/cursor, reload, faction cooldown, distance rejection and corrupt
  scheduler-state normalization.
- `tools/test-sandbox-settings.lua` covers defaults, dependency gates and integer clamps.
- All 64 standalone Lua tests and 73 mod Lua syntax checks pass. `:java:build
  prepareWorkshopUpload` passes, including the full Java 25 shell/transformer/inventory suite.

### Pending live and next work

On a disposable save with two hostile based factions, enable destructive developer tools and use
**Schedule Eligible Faction Raid Now**. Verify one real minority party is announced, departs with
the same IDs/loadout, navigates and loots real supplies, withdraws, returns and releases its event
duty across save/reload. Then test natural scheduling after the configured day without using the
developer command. The staged package is not a Steam upload or local subscribed-install update.
Faction-specific event policies must wait for this common live gate; the next safe independent
dependency is defining the reusable event-faction identity/policy records without spawning them.

## 2026-08-31 — Shared named event-faction policy boundary

Status: policy/persistence foundation implemented and automatically verified. No named event
faction is spawned or enabled by this boundary.

- Added one immutable policy catalog for Police, Scientists, Military, Black Division,
  Scavengers and PMC. Definitions express only stable display identity, earliest world day,
  base policy, permitted future objectives, persistence intent and loadout theme. Scavenger boss
  spawning is explicitly disabled and PMC contract eligibility is retained as a future hook.
- The policies contain no damage, health or accuracy multiplier. Black Division difficulty is
  not implemented as hidden stat inflation; later behavior must use real training, skills,
  equipment, accuracy and the common combat controller.
- Event identity binds to the existing canonical NPC faction through `faction.eventIdentity`.
  It does not create a parallel roster/relationship/inventory domain, alter duties or allocate
  survivors. Repeating the same binding is idempotent; rebinding to another identity fails.
- Save normalization rejects malformed policy/source/base/time metadata without touching the
  faction's ordinary membership. Player factions cannot be relabeled as event factions.

Verification: `tools/test-event-factions.lua` covers six deterministic policies, defensive
copies, objective/age constraints, no multiplier fields, disabled boss, PMC hook, real faction
binding, unchanged encoded inventories/duties/affiliations, rebind rejection, player rejection,
malformed persistence and zero survivor allocation. Existing faction persistence coverage passes.

Remaining: named-faction trigger/entry, believable spawn location, survivor allocation,
appearance/loadout realization, objective execution, withdrawal/persistence outcome and live
encounters are all unimplemented. The next architecture dependency is an event-entry transaction
that allocates ordinary persistent survivor identities at a validated world location, binds one
ordinary faction once, and rolls back atomically if materialization/loadout preparation fails.

## 2026-08-31 — Atomic named-event party entry

Status: persistence/world-entry transaction implemented and automatically verified. No named
event trigger, body materialization or themed loadout is enabled yet.

### Boundary implemented

- The existing cached player-spawn/native-building catalog now selects a compact party anchor in
  a bounded target ring. Candidate origins are unused, ground-floor and at least 60 tiles from
  supplied local players. The selector never loads squares or places a party beside the player;
  existing first-materialization visibility/standability/distance checks remain final.
- One non-yielding transaction preflights 2–6 distinct origins, then allocates ordinary
  population-managed `ks-world-*` identities, one existing-format travel group and one canonical
  NPC faction with the selected event policy. It creates no IsoPlayer, inventory item, skill,
  relationship domain or combat controller.
- A mid-batch allocation failure removes all new identities and restores the world survivor serial
  before returning. Group/faction state is committed only after all identities exist. Repeating
  the same source event returns the existing faction rather than duplicating people after reload.
- Unmaterialized event members retain normal origin records but wait together at their event entry
  instead of taking separate independent itineraries. They remain visible to the ordinary
  activation catalog. First real body capture clears the wait marker and hands location/needs to
  the existing native capture path.

### Verification and corrected limit

`tools/test-event-entry.lua` covers cached origin selection, compact/distinct positions, local
player distance, real persistent identity/group/faction ownership, activation eligibility,
no-scatter behavior, idempotent retry, injected second-member failure rollback, serial restoration,
world-age policy and first-capture cleanup. The transaction intentionally does not roll back a
durable identity because a later engine materialization attempt is temporarily unavailable; normal
activation retries are safer than deleting persistent people. The earlier audit wording implying
materialization/loadout rollback is therefore corrected at this boundary.

Remaining at this historical boundary was the persisted named-event caller, common travel duty,
loadout realization and objectives. The following entry records the implemented caller/runtime;
appearance/loadout and faction-specific behavior remain open.

## 2026-08-31 — Persisted named-event entry lifecycle

Status: common named-entry runtime implemented and automatically verified; live verification and
faction-specific behavior/loadouts remain required.

### Missing boundary and implementation

- Policy and entry allocation previously had no durable caller. A named faction could be created
  only by invoking the persistence helper directly, with no schedule, retry ownership, approach,
  objective, withdrawal or cleanup record.
- `faction_entry` now uses the existing Knox Events phase/revision ledger. Scheduling records no
  actor. Due dispatch claims the spawning phase, chooses a compact cached-world origin 100–600
  tiles from the target and at least 100 tiles from supplied local players, then calls the existing
  idempotent persistent-party transaction.
- A second atomic commit validates the canonical faction, ordinary travel group, all members,
  affiliations, duties and source-event identity before writing the roster and temporary event
  ownership. Reload/retry returns the same faction; a partial duty claim cannot occur.
- No safe entry origin leaves the event in spawning with a persisted 15-world-minute retry. It
  creates no people and cannot retry every controller update.
- Named parties reuse distinct loaded event destinations and the existing stored cohort scheduler.
  Real loaded positions establish arrival. The initial policy-allowed objective is a bounded
  one-hour presence state only; it manufactures no items, results, combat, reputation or lore.
- Withdrawal returns to the saved entry anchor and releases event duty. The later event-departure
  lifecycle section records how policy now distinguishes persistent parties from parties that
  leave Knox County without being marked dead.
- A destructive developer action can explicitly schedule a three-person Police entry at the
  selected world location. It does not bypass world-age or safe-origin policy and is not an
  automatic event trigger.

### Verification and remaining evidence

`tools/test-named-event-runtime.lua` covers zero-actor scheduling, due-time one-shot allocation,
world-age/objective policy, atomic duty, unique destinations, player separation, real-position
arrival, bounded objective, withdrawal, persistent survivors/faction, fully stored cohort travel,
same-time no-double-advance, no-origin retry cooldown, entry-wait cleanup and no duplicate party.
All 67 standalone Lua tests and all 75 mod Lua syntax checks pass. `:java:build
prepareWorkshopUpload` passes all Java 25 shell/transformer/inventory verifiers and stages the
current Lua payload. Existing raid, entry, objective, readiness and scheduler regressions pass.

Pending live: use **Schedule Police Entry Here** on a disposable save and confirm the same three
identities enter, approach, survive reload/hibernation, withdraw and release ownership without a
duplicate or movement storm. This is not a completed Police faction feature: themed appearance,
real Police equipment, disposition/reputation behavior, automatic triggers and meaningful Police
objectives are still unimplemented. Scientists, Military, Scavengers, PMC contracts and Black
Division remain policy-only. No Java/launcher protocol changed in this pass.

## 2026-09-01 — Police first-materialization identity and equipment

Status: implemented and automatically verified; live appearance/equipment persistence remains
required. Police encounters are still explicit developer schedules with the bounded common
presence objective, not a completed automatic law-enforcement event.

### Missing boundary and implementation

- Named Police entrants previously materialized through the ordinary randomized profession and
  starter-item path, so their persisted faction policy had no visible or mechanical identity.
- `KS_EventFactions.materializationPolicy` now derives a defensive policy from the survivor's
  canonical faction identity only when its persistent origin is `knox_event`. It allocates no
  actor/item and cannot retheme ordinary or previously materialized survivors.
- First materialization asks the existing capability generator for Build 42's real
  `base:policeofficer` profession. The normal vanilla-point balancing still chooses compatible
  traits, the existing appearance path consequently applies
  `ClothingSelectionDefinitions.policeofficer`, and the resulting profession/traits/clothing are
  captured by the normal survivor snapshot.
- The existing starter-gear service applies a restrained `police` theme: one real
  `Base.Nightstick`, one real `Base.WalkieTalkie4`, and the ordinary bounded food/water/medical
  rolls. Existing equipment selection equips the owned useful weapon. No firearm, ammunition,
  artificial skill, accuracy, health or damage multiplier is granted.
- A survivor with an existing capability/native record is restored normally; policy arguments
  cannot rewrite its profession or reissue the starter kit. Temporary materialization failure
  still follows the existing body removal/retry path.

### Verification and remaining evidence

- `tools/test-survivor-capabilities.lua` covers strict preferred-profession selection, vanilla
  point balance, explicit missing-definition failure and persisted-profile non-rewrite.
- `tools/test-survivor-starting-gear.lua` covers exact real Police items and unchanged ordinary
  starter behavior. `tools/test-event-entry.lua` covers canonical/defensive policy lookup.
- All 68 standalone Lua tests and all 74 mod Lua syntax checks pass. `:java:build
  prepareWorkshopUpload` passes the full Java 25 shell/transformer/inventory suite and stages the
  current payload.

Pending live: schedule Police entry on a disposable day-one-or-later save. Confirm entrants wear
recognizable ordinary Police clothing, own/equip a nightstick, carry a Police radio, retain the
same profession/clothing/items after save/reload and do not receive the kit twice. Disposition,
automatic triggers and meaningful Police objectives remain unfinished. No Java or launcher
protocol changed, so this increment requires no launcher patch.

## 2026-09-01 — Evidence-backed Police secure-area objective

Status: implemented and automatically verified; live combat/objective evidence remains required.
This completes one narrow Police objective, not automatic event scheduling or the broader Police
faction feature.

- `secure_area` previously placed entrants at the target and waited exactly one hour. The timer
  proved only elapsed time and could not distinguish an occupied area from one actually cleared.
- The event objective now persists a bounded scan schedule, last real threat count and the start
  of a clear confirmation window. `KS_EventRuntime` checks the loaded Build 42 zombie list only
  when that persisted scan becomes due, counts living same-floor zombies within 18 tiles of the
  event target, and caps work/evidence at 24 threats.
- This observation does not choose targets, force aggro, apply damage or claim a victory. Existing
  perception, native combat, retreat and group behavior remain authoritative while members hold
  their event positions.
- A threat resets the clear window. Two separated clear observations covering at least 0.05 world
  hours produce the durable `area_secure` outcome and withdrawal. If the world/objective cannot
  provide that evidence, the existing one-hour deadline ends with the honest `elapsed` outcome.
- Scan mutations are revision/phase/deadline checked, limited to one per 0.02 world hours and
  persist across save/reload. Corrupt counts/times make the objective invalid and enter existing
  recovery rather than fabricating completion.

Verification: `tools/test-named-event-runtime.lua` covers a real nearby threat keeping the
objective active, threat removal starting but not instantly completing the confirmation window,
and a later clear observation recording `area_secure`. All 68 standalone Lua tests, all 74 mod
Lua syntax checks and `:java:build prepareWorkshopUpload` pass; the staged runtime matches source.

Pending live: schedule Police near a small loaded zombie presence. Police must reach and hold the
target, fight only through existing combat, remain in the objective while a nearby zombie lives,
then withdraw after the area stays clear. Save/reload during the clear window and confirm it neither
completes twice nor restarts from fabricated evidence. Existing player aggression already changes
the canonical faction relationship to hostile; neutral/reputation behavior is reused rather than
duplicated. Automatic Police triggers and the `assist` objective remain unfinished. No Java or
launcher protocol changed, so no launcher patch is required.

## 2026-09-01 — Event-only party departure lifecycle

Status: implemented and automatically verified; loaded-shell teardown and save/reload remain live
verification gates. This is shared Knox Events lifecycle work, not a Scientists/Military content
implementation.

### Defect and implementation

- Every named entry party previously became permanent world population after withdrawal, even when
  its canonical policy declared `persistsAfterEvent=false`. Releasing `duty.eventId` alone turned
  Scientists, Military, PMC and Black Division entrants into ordinary roaming survivors.
- Departure is now a durable state distinct from death and hibernation. A member must first reach
  its real saved entry anchor. Persistence then records `pending` departure, which immediately
  excludes that identity from activation, world-population counts and offscreen simulation without
  changing `alive=true` or deleting its native record, equipment, identity or history.
- A loaded member is captured and removed only by the existing autonomy lifecycle owner. Successful
  engine teardown finalizes `departed`; capture/removal failure retains the stopped runtime and
  pending ownership under bounded exponential retry instead of creating a duplicate or per-tick
  teardown storm. An unloaded member with no runtime shell finalizes directly. A pending state
  restored after process restart also finalizes only when the bridge confirms that no shell exists.
- Finalization releases group/faction/camp/job ownership and records a non-actionable `departed`
  duty. The empty named faction remains as historical event identity rather than becoming a live
  resource roster. Police and Scavengers retain their ordinary persistent survivors because their
  policies explicitly opt into persistence.
- Real death wins over same-tick departure: the pending marker is cleared and the existing native
  corpse/reanimation lifecycle remains authoritative.

### Verification and pending evidence

`tools/test-named-event-runtime.lua` now covers both policy branches: Police returns and remains
present, while a Scientists party returns through distinct entry positions, holds loaded departure
pending until shell teardown, finalizes stored members directly, remains alive as history, keeps
its record, disappears from activatable/living population, preserves one departed faction record
and completes the event only after every shell is retired. All 68 standalone Lua tests pass.

Pending live: use **Schedule Scientists Exit Test Here** on a disposable day-14-or-later save,
observe loaded members return to their entry boundary and disappear only
after reaching it, then save/reload. The same identities must remain departed and never reactivate;
there must be no corpse, duplicate shell, `RESTORE_FAILED`, or lost event completion. Kill one
member during withdrawal and confirm only that member follows the normal corpse lifecycle. No Java
or launcher protocol changed, so this increment requires no launcher patch.

## 2026-09-01 — Scientist first-materialization identity and field kit

Status: implemented and automatically verified; first live materialization and save/reload remain
required. This is a narrow medical-research identity slice, not research gameplay or a completed
Scientist faction.

- Build 42.20.3 exposes no dedicated Scientist profession. The canonical Scientist policy now
  requests the real zero-cost `base:doctor` profession, which still passes the existing vanilla
  profession/trait point-balancing path rather than receiving custom skills or stats.
- Existing creator clothing remains native. The policy adds the real `Base.JacketLong_Doctor`
  through the existing wear bridge after Doctor clothing, making the theme recognizable without
  a custom outfit engine or synthetic appearance state.
- The existing starter-gear service provides only real ordinary `Base.Clipboard`, `Base.Pen` and
  `Base.Scalpel` items plus bounded normal water, food and medical rolls. It grants no research
  vial/result, firearm, ammunition, accuracy, health, damage or other artificial advantage.
- Policy is consulted only on canonical `knox_event` first materialization. The first successful
  native capture clears pending materialization, after which persisted profession, clothing,
  equipment and inventory remain authoritative and the kit cannot be reissued on restore.
- `tools/test-character-appearance.lua`, `tools/test-survivor-capabilities.lua`,
  `tools/test-survivor-starting-gear.lua`, `tools/test-event-factions.lua` and
  `tools/test-named-event-runtime.lua` cover clothing application, real balanced profession,
  exact item types, immutable policy and propagation into the named-event roster.
- All 69 standalone Lua tests and all 74 mod Lua syntax checks pass. `:java:build
  prepareWorkshopUpload` passes the full Java 25 verification suite and stages the current
  Workshop payload.

Pending live: use **Schedule Scientists Exit Test Here** on a disposable day-14-or-later save.
Confirm both entrants first appear with plausible Doctor clothing plus lab coats and ordinary field
items. Save/reload while they are present and verify the same appearance, profession and inventory
return without duplicate items; then let the existing withdrawal/departure gate complete. No Java
or launcher protocol changed, so this increment requires no launcher patch.

## 2026-09-01 — Military first-materialization identity and field kit

Status: implemented and automatically verified; native reload/firearm behavior, appearance and
save/reload remain live gates. This is a narrow conventional Military entrant slice, not Military
doctrine, automatic scheduling or a completed faction.

- Installed Build 42.20.3 defines `base:veteran` with cost -8, native Aiming 2/Reloading 2 boosts
  and Desensitized. Military event policy requests that real profession through the existing
  balanced vanilla trait-point generator; no custom skill or artificial accuracy is applied.
- Event appearance policy now supports a bounded validated list of real item full types. Military
  entrants retain native Veteran creator clothing and add real army hat, camo jacket, camo trousers
  and army boots through the existing wear bridge. Scientist's lab coat moved to the same list
  representation with unchanged behavior.
- The real M9 metadata requires `Base.9mmClip` and `base:bullets_9mm`. The field kit therefore owns
  a real Hunting Knife, M9, one compatible magazine, three native five-round `Base.Bullets9mm`
  stacks and `Base.WalkieTalkie5`, plus bounded ordinary survival supplies. Knox does not prefill
  the magazine, chamber the weapon, fake ammo counters or alter damage/health.
- Existing equipment and ranged-combat systems remain authoritative for choosing, loading and
  firing the owned weapon. First successful capture makes normal persistence authoritative, so
  restore cannot issue a second kit.
- Added the destructive, sandbox-gated **Schedule Military Exit Test Here** action. It uses the
  existing named-entry transaction, secure-area objective and event-only departure lifecycle; it
  is not an automatic Military trigger.
- Focused capability, appearance, starter-gear, event-policy and named-runtime tests pass, as do
  all 69 standalone Lua tests and all 74 mod Lua syntax checks. `:java:build
  prepareWorkshopUpload` passes the full Java 25 verification suite and stages the current
  Workshop payload.

Pending live: on a disposable day-14-or-later save, schedule the Military test. Confirm three
entrants wear stable army clothing, own exactly one M9/magazine and 15 rounds each, reload/fire only
through native behavior, hold/clear the selected area, and depart at their real entry anchor. Save
and reload while present; no item or identity may duplicate and no departed member may reactivate.
No Java or launcher protocol changed, so this increment requires no launcher patch.

## 2026-09-01 — Evidence-backed Scavenger world search

Status: implemented and automatically verified; live container search, transfer animation and
save/reload evidence remain required. This is one explicit Scavenger objective, not automatic
scheduling, base theft, a boss encounter or a completed faction.

- Named `scavenge_world` objectives now reuse the existing real-item event transaction. Each
  loaded member receives the current `loot_area` directive bounded to 18 tiles around the persisted
  target; no second looting controller or abstract stockpile was added.
- A source must be a real world container on the target floor and inside that radius. Character
  inventories, outside containers, queued actions and transfers that leave the original in place
  cannot count. The existing post-transfer observer records the actual item ID/type only after it
  is present in the member's real inventory.
- The objective requires at most six unique receipts. Three exhausted searches per member, the
  two-hour deadline, or the real-item target produces honest `no_supplies`, `partial_supplies` or
  `supplies_taken` evidence. Malformed/duplicate receipts remain rejected by the shared validator.
- Scavengers remain varied ordinary survivors rather than receiving a forced profession or magic
  gear. Because their policy persists after the event, the same identities and actually carried
  items rejoin normal world life. The boss hook remains disabled.
- Added the destructive, sandbox-gated **Schedule Scavenger Search Here** live harness. It invokes
  the normal entry transaction and is not an automatic trigger.
- Focused named-runtime coverage verifies zero initial loot, bounded controller delegation,
  inside/outside container eligibility, one durable real-item receipt, evidence-backed partial
  outcome, withdrawal and persistent faction membership. Existing raid objective and runtime
  suites also pass unchanged. All 69 standalone Lua tests, all 74 mod Lua syntax checks and
  `:java:build prepareWorkshopUpload` pass the full Java 25 verification/staging gate.

Pending live: schedule the search near real containers on a disposable day-7-or-later save. Confirm
the three members visibly travel/search, real items leave their source containers and enter their
inventories, the search ends without fabricated loot, and save/reload neither repeats a receipt nor
duplicates an item. No Java or launcher protocol changed, so no launcher patch is required.

## 2026-09-01 — Optional recruitment trust sandbox policy

Status: implemented and automatically verified; the two live recruitment paths remain to be
confirmed in game.

- Added **Require Trust to Recruit** to the normal Knox Survivors sandbox page. It defaults off,
  so an otherwise eligible independent survivor can be recruited immediately. Enabling it restores
  the existing 50-trust threshold and half-hour refusal cooldown.
- The option changes only personal trust gating. Hostility, NPC group/faction ownership, companion
  limits, life, loaded availability, distance and the master mod switch remain authoritative.
  Existing trust/reputation data is preserved and continues to affect trade and social presentation.
- A trust refusal cooldown is consulted only while the trust policy is enabled, so an old low-trust
  refusal cannot contradict the default no-trust policy.
- Fixed the existing refusal path resolving `playerId` after it had already tried to record the
  refusal. It now resolves ownership before eligibility and records the cooldown against the correct
  split-screen player when trust gating is enabled.
- Sandbox review found no other missing setting that is both currently implemented and useful to
  ordinary players. Internal AI distances, cadence, risk and objective limits remain implementation
  details rather than cluttering the menu.
- Focused settings, companion policy, reputation and context-menu suites pass. Static coverage also
  verifies the option declaration defaults false and has player-facing English text. All 69
  standalone Lua tests, all 74 mod Lua syntax checks and `:java:build prepareWorkshopUpload` pass;
  the four changed Workshop runtime/content files match their staged copies byte-for-byte.

Pending live: on one disposable save, leave the option off and recruit an eligible independent
survivor immediately. On another, enable it and verify low trust refuses, the refusal cooldown is
bounded, and 50 trust permits recruitment. Confirm grouped/hostile survivors remain unavailable in
both cases. No Java or launcher protocol changed, so no launcher patch is required.

## 2026-09-01 — Balanced public-playtest sandbox defaults

Status: implemented and automatically verified; encounter frequency and performance remain pending
live playtest evidence.

- Raised the whole-map persistent population from 32 to 48 and the active-body ceiling from 12 to
  16. These are separate limits: the active value remains a ceiling and does not force a crowd near
  the player.
- Reduced first-materialization distance from 60 to 40 tiles. Existing hidden-square and line-of-sight
  safety remains authoritative, so this improves encounter opportunity without visible pop-in.
- Slowed one-at-a-time population replacement from three to five in-game days so survivors remain
  consequential rather than instantly replenished.
- NPC factions and hostile encounters remain enabled for the intended living-world loop. Automatic
  faction raids now default off, their earliest opt-in day is 14, and unfinished human/faction
  systems are plainly labeled Work in Progress or Experimental in the sandbox UI.
- Companion count, recruitment policy, HUD, speech, nameplates and normal cap enforcement retain
  their established defaults. Internal AI timings and distances remain out of the player menu.
- These defaults affect newly created sandbox rules. Existing saves can retain previously stored
  values and require manual adjustment or a fresh playtest save.
- All 69 standalone Lua tests, all 74 mod Lua syntax checks and
  `:java:build prepareWorkshopUpload` pass. The three changed Workshop runtime/content files match
  their staged copies byte-for-byte.

Pending live: start a normal new urban save and record time to first survivor, encounters over the
first seven in-game days, peak active count and any frame-time impact. The intended result is an
encounter during ordinary exploration without repeated crowds or obvious materialization. No Java
or launcher protocol changed, so no launcher patch is required.

## 2026-09-01 — Live-test flee, firearm, dialogue and companion polish

Status: implemented and automatically verified; native firearm animation timing, retreat-off combat,
speech bubbles, vehicle timed actions and responsive UI remain pending live verification.

- The latest long-session evidence contained no Knox Lua exception. It did show healthy survivors
  repeatedly entering `FLEEING` against three zombies, then retaining retreat ownership through
  blocked escape lanes and accumulating failures. **Allow Survivor Fleeing (Experimental)** now
  defaults off. The gate exists at assessment, direct retreat acquisition and active-state cleanup,
  so disabling it cannot leave a stored survivor in stale retreat. Combat remains enabled.
- Periodic controller/render status dumps now require developer diagnostics, and that option defaults
  off. Error reporting and explicit test scenarios remain available. This removes routine high-volume
  diagnostic work from normal sessions without hiding actual failures.
- Ranged reposition now clears all native aiming/attack input on every movement tick and drops the
  running flag before returning to aim. This closes the confirmed ownership gap that allowed the
  Build 42 firearm hook to observe a queued shot while the survivor was still running.
- Added a persisted **Relax and Recover** companion order. Existing needs remain authoritative:
  eating, drinking, treatment and sleep still use real state/items, while an otherwise stable
  companion finds real furniture or sits through the existing recovery posture. **Stop Relaxing**
  returns them to Follow and interruption cleanup releases the rest action.
- Existing passenger-only **Enter My Vehicle** and **Exit Vehicle** commands were verified to remain
  exposed under Orders and continue using vanilla path/enter/exit timed actions. NPC driving remains
  intentionally out of scope.
- Added a nearby **What do you need?** interaction backed by real hunger, thirst, fatigue, endurance,
  bleeding and health state. Loot/search actions now use short deterministic callouts with a bounded
  cooldown. All speech still goes through native `Say`, so the game owns bubble replacement while the
  activity feed keeps the named transcript.
- Base-management summary/help text is clipped to the active viewport, and an existing Notebook is
  resized and recentered when reopened after resolution, window-mode or split-screen changes.
- Modded clothing remains on the existing safe path: items registered by the game as clothing use
  native body locations, wear state and protection metadata; unknown items fail classification
  safely. No third-party art or textures were copied.
- All 69 standalone Lua tests, all 74 mod Lua syntax checks and `:java:build prepareWorkshopUpload`
  pass. The Workshop payload is staged. The contained off-slot `IsoPlayer` architecture is unchanged.

Pending live: with fleeing left off, place one survivor near a crowd and confirm they fight rather
than entering retreat. Test a firearm survivor at close range and verify no shot/sound occurs while
running, then confirm visible aim and fire after stopping. Ask what a survivor needs, order a companion
to relax/stop, enter/exit a vehicle, and reopen Base Management at a second resolution. Group-at-world-
creation, a higher organic faction threshold, broader idle animation selection and automatic vehicle
boarding were not folded into this safety pass because they require separate persistence/engine
boundaries rather than a speculative patch. The Java agent payload changed, but its launcher protocol
did not; Workshop staging updates the agent JAR and no launcher code patch is required.

## 2026-09-03 — Starting-region world presence

Status: implemented and automatically verified; a new-world encounter pacing test remains required.

- Initial population allocation previously balanced every identity evenly across all map regions.
  That produced a durable whole-map population but gave the player's starting region no stronger
  presence than a distant town, making normal early encounters unnecessarily rare.
- New worlds now reserve a bounded cohort of four to twelve identities in the region nearest the
  primary player's starting square, based on total population and region count. The remaining
  identities retain map-wide balanced allocation.
- This does not spawn around the moving player, relocate an existing survivor, or bypass visibility,
  distance, loaded-square, occupancy or safety checks. Survivors still originate from cached native
  player-spawn/building anchors and follow their existing offscreen itinerary.
- The selected region and target cohort are persisted on the population record for diagnostics.
  Existing initialized saves are intentionally unchanged; use a new save to evaluate this policy.
- Valid pre-materialization identities can now enter the canonical travel-group domain. A starting
  cohort attempts one compact pair and, when large enough, one compact three-person group using only
  origins within 64 tiles. It never forces a distant collection of survivors into a fake group.
- These groups share one pre-materialization itinerary and retain their original relative offsets.
  Once any member owns a real body record, remaining pending members wait instead of independently
  drifting away. Existing loaded and fully captured group travel remains authoritative afterward.
- All 69 standalone Lua tests and all 74 mod Lua syntax checks pass. The complete Java verifier set,
  `:java:build`, Workshop staging and `prepareWorkshopUpload` also pass.
- No Java or launcher protocol changed, so this slice does not require a launcher patch.

Pending live: start a fresh urban save with default population settings, explore ordinary nearby
streets/buildings, and record the first natural encounter. Pass requires an encounter opportunity
without visible pop-in, repeated crowds, duplicate identities or obvious player-following behavior.

## 2026-09-03 — Autonomous life-intent continuity

Status: implemented and automatically verified; natural multi-hour behavior remains pending the
combined live-test phase.

- Independent roaming previously persisted the survivor and their location but not why they were
  moving. A completed action or restore therefore returned directly to a fresh local choice, which
  made individually correct actions read as aimless behavior over time.
- Lua persistence schema 16 now stores one validated autonomous `lifeIntent`: food, water or medical
  search; scavenging; building investigation; or onward area travel. It stores a coarse phase and an
  optional target identity/position, never native movement, combat or timed-action ownership.
- Existing need evaluation remains authoritative. An unresolved supply need survives travel and
  temporary interruption; once the real need evaluator no longer requests it, the intent clears.
  Ordinary scavenging clears on completion, and failed destinations enter the existing bounded
  cooldown before intent returns to reassessment.
- Companion, player-base, faction-base, camp and group-follower ownership supersede incompatible
  independent intent. Persisted companion/base transitions clear it at the domain boundary, so an
  unloaded recruit or resident cannot restore an old scavenging purpose.
- `tools/test-roaming-autonomy.lua` verifies readable goal mapping and preservation of urgent purpose.
  `tools/test-companion-base-domain.lua` verifies validated persistence, rejection of unknown plans,
  and cleanup on recruitment. Both focused tests and changed-file syntax checks pass.

Pending live: included in the later combined session. Observe an independent survivor travel to a
building, scavenge, leave, survive a combat/self-care interruption, and continue with a coherent
purpose. No Java or launcher protocol changed, so this slice does not require a launcher patch.

## 2026-09-03 — Travelling-group to faction threshold

Status: implemented and focused verification passes; organic promotion remains part of the later
combined live test.

- Normal autonomous groups previously became factions at three members. A new concise sandbox rule,
  **Survivors Needed to Form a Faction**, supports 3-8 and defaults to four. This lets pairs/trios
  travel together and encounter others before claiming a faction identity and shelter.
- The number does not bypass relationship coherence: every non-leader must still have the existing
  nearby/shared-roam, loot or combat history with the leader. Named event factions and explicit
  developer scenarios retain their deliberate setup path instead of being silently resized.
- Persistence promotion accepts the threshold as an explicit policy input; it does not read sandbox
  state inside the data domain. Relationship coordination is the normal-play owner that supplies the
  configured value. Focused sandbox, faction-persistence and human-encounter tests pass.

Pending live: allow a starting pair/trio to meet and recruit a fourth survivor, verify it remains an
informal group below four, then promotes once both count and shared-survival evidence are satisfied.
Existing factions are not dissolved if the setting later increases. No Java or launcher protocol
changed, so no launcher patch is required.

## 2026-09-03 — Companion survival missions and event gate

Status: implemented — focused verification pending rerun; live verification pending.

The existing companion directive system now exposes three small survival missions: Find Food, Find
Water, and Find Medical Supplies. They reuse the current native nearby supply search, movement,
traversal, inventory and timed-action paths. A mission searches a bounded area for real items and
then resumes the underlying Follow/Hold order. Three unproductive attempts clear the directive and
report a contextual failure instead of looping forever. The persistence validator accepts only
finite, bounded ground selections; malformed mission directives fail closed.

The menus present these as **Survival Orders**, keeping the player-facing model simple: orders are
what the player asks for, jobs are ongoing base duties, and “mission” only describes the bounded
execution of a temporary order internally.

Automatic scripted Knox events remain disabled by default through `EnableKnoxEvents`. Enabling the
option is an explicit experimental choice, and developer event/raid requests refuse cleanly while
it is disabled. Existing event records are retained for compatibility and inspection.

Pending verification: rerun the full Lua suite, all mod syntax checks and the Java build after the
mission edits. Live testing is still required for menu selection, native search animation/item
transfer, interruption/resume and no-supply failure. No launcher or Java protocol change is
required; these changes do not alter the launcher payload or install contract.

## 2026-09-03 — Party recovery and vehicle orders

Status: implemented — focused verification passed; live verification pending.

The party menu now exposes the existing durable **Relax and Recover** order, so companions can
eat, drink, sit and recover together until the player gives a normal Follow/Hold replacement.
When the player is in a vehicle, the same menu also exposes **Get In My Vehicle** and **Get Out of
Vehicles**. These are only party-level wrappers around Knox's existing per-companion vanilla
passenger-seat/path/enter/exit actions: no seat is fabricated, driver seat zero remains reserved,
and a full vehicle reports that there are no passenger seats.

Verification: companion vehicle, weapon-preference and companion-command tests pass, along with
syntax and diff checks. Pending live: mixed party boarding, a full vehicle, exiting after combat,
and recovery interruption/resume. No Java, packaging, or launcher change is required.

## 2026-09-03 — Party needs check

Status: implemented — focused verification passed; live verification pending.

The party order menu now has **Check Party Needs**. It calls the existing per-survivor real-needs
report for each loaded companion, so speech still comes from their actual BodyDamage, hunger,
thirst, fatigue and endurance state. It does not invent a party-health meter or change their order.

Verification: companion-command and party-menu tests plus changed-file syntax/diff checks pass.
Pending live: confirm several companions report in sequence without unreadable speech overlap. No
Java, packaging, or launcher change is required.

## 2026-09-03 — Find Better Weapon order

Status: implemented — focused verification passed; live verification pending.

Individual and party Survival Orders now include **Find Better Weapon**. The search is bounded to
real nearby containers and accepts only a usable weapon that is a meaningful upgrade. Melee scoring
remains conservative; a firearm is accepted only when Build 42's existing firearm readiness check
confirms usable ammo/magazine/chamber state. It will not select a broken weapon or create any
equipment. Normal native transfer and Knox's existing equipment reconsideration own
the pickup/equip result; three unsuccessful local searches end cleanly with a contextual response.

Verification: equipment-intelligence and companion-command tests cover usable/broken weapons,
meaningful upgrade threshold, usable-firearm preservation, directive persistence, Lua syntax and
diff checks. Pending live: issue the order beside containers with a weak current weapon, better
melee weapon, broken weapon and firearm; confirm one real pickup/equip and no repeated swapping.
No Java, packaging, or launcher change is required.

## 2026-09-03 — Clean Up Inventory order

Status: implemented — focused verification passed; live verification pending.

Added the reference-style **Clean Up Inventory** order to individual and party Survival Orders.
It reuses the existing real-item cleanup policy: surplus can be deposited into an available base
container or dropped through the normal world-transfer path, while useful food, water, medicine
and equipped gear remain protected. Completion clears the temporary order; unavailable storage or
an interrupted transfer follows the existing bounded retry path.

Verification: inventory-cleanup, companion-command and equipment tests pass, with changed-file
syntax and diff checks. Pending live: issue the order with mixed junk, supplies and equipment near
an owned base, then interrupt it with combat and confirm it resumes or clears cleanly. No launcher
or Java protocol change is required.

## 2026-09-03 — Survival-order parity expansion

Status: implemented — full Lua suite and syntax checks pass; live verification pending.

The player-facing Survival Orders now cover the practical, bounded requests needed for a
modernized Superb-style replacement without introducing a second planner: Find Food, Find Water,
Find Medical Supplies, Find Better Weapon, and Clean Up Inventory. The existing loot directives are
labelled **Explore and Search Area**, **Loot This Building**, and **Loot Dead Bodies** so they read as
ordinary orders in the context menu. Party orders expose the same set and retain the existing
Follow/Hold/Relax, stance, vehicle, needs, and return-to-base controls.

All of these orders continue to use Knox's authoritative native inventory, equipment, movement and
timed-action paths. They have bounded search/ retry behavior and do not create items, duplicate
mission state, or change the launcher payload. This is intentionally the last expansion before a
live pass: the next evidence should confirm one individual order and one party order with real
containers, interruption by combat, completion, and return to the prior companion duty.

Verification: the complete local Lua test suite reports 69 passing tests and 74 syntax checks;
focused equipment, inventory-cleanup, companion-command, base-UI, and party-vehicle checks pass;
`git diff --check` passes. No launcher patch is required because no Java/protocol/package contract
changed. Live in-game transfer, animation, equipment, and party behavior remain pending.

## 2026-09-03 — Starting survivor cohort pacing

Status: implemented — focused population and sandbox checks pass; live verification pending.

Initial world allocation now has a bounded, configurable chance to form one compact starting
travelling cohort from nearby player-origin survivors. The new **Chance of Starting Survivor
Groups** and **Maximum Starting Group Size** settings default to 65% and four members. A cohort
never increases the total population, consumes distant origins, or replaces the later relationship
and faction rules; additional groups still form through ordinary encounters and shared survival.
Setting the chance to zero restores an all-independent opening, while a high value makes the first
area feel inhabited without turning the world into an army.

Verification: world-population and sandbox-settings checks pass; Lua syntax and diff checks pass.
No Java or launcher contract changed. Live verification remains pending for a fresh save: confirm
the configured cohort appears as a small group and that independent survivors remain discoverable
elsewhere on the map.

## 2026-09-03 — Human encounter approach range

Status: implemented — relationship-focused checks pass; live verification pending.

Independent survivors now notice one another within a bounded 24-tile same-floor awareness range and
can begin a cautious approach within 16 tiles, provided native line-of-sight succeeds. This closes
the old “walk past each other” gap without granting through-wall, cross-floor, or long-distance
awareness. Existing cooldowns, participant ownership, hostility classification, and normal roaming
resume behavior remain unchanged.

Verification: full Lua suite, relationship checks, syntax checks and `git diff --check` pass. No
Java or launcher contract changed. Live verification remains pending for two independent survivors
crossing paths in open space and near a building corner.

## 2026-09-03 — Population activation pacing

Status: implemented — population and sandbox checks pass; live verification pending.

The population stream no longer assumes a fixed two-body activation budget. **Survivors Loaded Per
Update** is now a bounded sandbox setting from 1–4, defaulting to 2 for the existing performance
profile. Raising it lets nearby members of a persistent group materialize in the same update more
often, while the active-survivor cap, hidden-square checks, and distance band remain authoritative.
It is intentionally a per-update ceiling, not a population multiplier or cap bypass.

Verification: full Lua suite, population/sandbox checks, syntax checks and `git diff --check` pass.
No Java or launcher contract changed. Live verification remains pending for a three-member group at
the default and maximum activation settings.

## 2026-09-03 — Cohort-aware materialization

Status: implemented — full Lua suite passes; live verification pending.

Activation now keeps persistent travel groups together when their eligible members fit the current
activation budget. A group is selected as a cohort only when every eligible member is available and
the cap has room; otherwise the normal nearest-survivor selection remains in force. This avoids
half-loaded groups without teleporting members, bypassing active limits, or loading distant bodies.

Verification: all 69 Lua tests pass, including world-presence/population coverage; syntax and diff
checks pass. No Java or launcher contract changed. Live verification remains pending for a three-
member persistent group entering the encounter band with activation budgets of two and four.

## 2026-09-03 — Contextual survivor communication layer

Status: implemented — focused and full Lua verification pass; live presentation pending.

A dedicated dialogue owner now provides short, contextual callouts for building travel, onward
roaming, searching, useful finds, failed searches, food/water/medical needs, resting, regrouping,
combat, retreat, camp return, and base work. Dialogue uses per-survivor event cooldowns plus a short
global cooldown, so one survivor cannot stack several lines at once or repeat the same action every
decision cycle. Selection is deterministic enough for debugging while still varying over time.

The autonomy controller now routes roaming, supply search, combat, fleeing, regrouping, camp return,
base work, and existing loot-action speech through this owner. The existing Show Survivor Speech
setting disables the entire layer, and runtime cooldowns reset cleanly when a game starts. Dialogue
does not own behavior, change relationships, or fabricate actions; it only reports decisions that
the established systems have already begun.

Verification: a new focused dialogue test covers banks, event/global cooldowns, settings and reset;
roaming and combat-intelligence checks pass; the complete Lua suite now reports 70 passing test
files and 75 syntax-checked Lua files. No Java or launcher contract changed. Live verification is
pending for readability, overlap, and timing during a mixed survivor session.

## 2026-09-03 — Configurable encounter band

Status: implemented — population, world-presence and sandbox checks pass; live verification pending.

The hard-coded 220-tile activation band is now the **Survivor Encounter Distance** sandbox setting,
defaulting to 280 tiles and clamped to 120–500. Persistent survivors can therefore be discovered
more reliably during normal exploration without raising the world population or bypassing hidden,
standable-square checks. Hibernation follows the selected band with a small 40-tile buffer, avoiding
rapid load/unload churn at the edge of the encounter area.

Verification: world-population, world-presence and sandbox-settings checks pass; modified Lua syntax
and `git diff --check` pass. No Java or launcher contract changed. Live verification remains pending
for a fresh save at the default distance and at a deliberately smaller distance.

## 2026-09-03 — Persistent shared group purpose

Status: implemented — focused verification passed; live verification pending.

Travel groups now persist one validated, revisioned objective copied from their current leader's
autonomous life intent. Followers can observe that purpose but never receive a second movement
owner: loaded locomotion remains leader plus formation-following. Repeating the same objective is a
no-op, non-leaders cannot replace it, and leader death/removal clears the old plan before a successor
can choose another.

Fully hibernated groups now continue a coordinate-bearing shared objective as one cohort. Members
retain their offsets and individual needs ledgers; the shared record owns only coarse destination
progress. Reaching the destination changes the leader and group intent to `reassess`, releases the
explicit objective route, and applies a short shelter interval before ordinary world travel can
resume. Malformed or leader-mismatched objectives are removed during schema-17 normalization.

At a loaded shared building/scavenging goal, nearby followers can assist with the existing ranked
container search. Existing item/container reservations divide useful work naturally; formation-slot
delays and bounded cooldowns prevent every member starting at once. Assistance is limited to members
within eight tiles of their leader, never copies the leader's intent into follower persistence, and
does not turn one survivor's food/water/medical need into a group-wide command.

Verification: relationship-coherence, unloaded-group, formation, roaming, and behavior-integration
tests cover leader authority, copy safety, revision stability, unload travel, arrival, reassessment,
leader replacement, reload/corruption normalization, bounded follower assistance, and personal-need
isolation. The complete suite reports 70 passing Lua test files, 76 syntax-checked Lua files, and a
successful Java build with every transformer/runtime verifier passing. `git diff --check` passes.
No launcher patch is required because this changes only Workshop Lua state and uses the existing
package/runtime contract. Live verification remains pending for one
group beginning a building trip, leaving the loaded area, and later restoring with the same purpose.

## 2026-09-03 — Loaded group survival cooperation

Status: implemented — automated verification passed; live verification pending.

Loaded travel groups can now respond collectively when a nearby member lacks food, clean water, or
immediate bandaging material. A healthy donor offers one real carried surplus item through Knox's
existing native inventory-transfer action. The policy preserves at least one donor reserve, protects
an additional reserve if the donor shares the shortage, and excludes equipped or favorite items.
Medical need outranks water, which outranks food. Both the recipient and exact item are reserved so
several members cannot pile transfers onto one person, and source/destination containers must prove
the transfer completed.

When nobody can safely share, a nearby follower reports the shortage and remains with the group.
The loaded leader selects the most urgent member shortage and owns the ordinary world search; the
resulting life intent becomes the existing shared group objective. Distant members still handle
urgent needs independently. Combat, detachment, failure, timeout, and normal completion release the
temporary transfer state. This adds no abstract group inventory and performs no offscreen item
transfer.

Verification: new group-support coverage proves need priority, donor reserves, same-floor/range
limits, duplicate-recipient protection, native transfer queuing, and real completion evidence.
Formation coverage proves controller ownership and cleanup plus follower need delegation. The full
suite reports 71 passing Lua test files and 77 syntax-checked Lua files. The complete Java build and
all movement, traversal, combat, corpse, inventory, locomotion, and transformer verifiers pass;
`git diff --check` also passes. Live
verification remains pending for sharing each resource type, combat interruption, leader-owned
search, and group resumption.
## Persistent base-duty fairness (offline verification, live pending)

The automatic base scheduler now evaluates all currently queued, eligible work
before assigning a resident.  A persisted `lastClaimedBy` marker applies a small
fairness penalty to the same resident on near-equal recurring tasks, while the
existing preference pass and materially higher task priority remain authoritative.
This keeps guards, cleanup, farming, hauling, repairs, and other existing duties
from being monopolized by the first resident evaluated without adding a second
task database or changing task execution.

Verification:

- `tools/test-base-jobs.lua` passes the existing automatic-job coverage plus
  preferred-role selection, ineligible-task filtering, equal-priority rotation,
  and higher-priority override checks.
- Full Lua suite: 71 focused scripts pass; all mod/test Lua files pass syntax checks.
- `:java:build` passes, including the existing movement, traversal, combat,
  lifecycle, inventory, and visibility verifiers.

Status: implemented and internally verified.  Live in-game confirmation of
multiple residents sharing recurring base work remains pending.  No launcher
change is required because this pass only changes loaded Lua scheduling logic.
## Base-job failure backoff (offline verification, live pending)

Failed base actions now enter a persisted, bounded retry cooldown.  Each failed
run increments `failureStreak` and backs off from 0.25 hours to a maximum of 8
hours; a successful run resets the streak.  This prevents missing materials,
blocked geometry, or temporarily unavailable targets from reopening every
controller tick while still allowing the same durable task to recover later.
The existing native action, task ownership, and requeue paths are unchanged.

Verification:

- `tools/test-companion-base-domain.lua` covers first-failure cooldown,
  suppression before `retryAtHours`, reopening afterward, and durable run history.
- Full Lua suite: 71 focused scripts pass; all 148 Lua files pass syntax checks.
- `:java:build` passes with all existing runtime/transformer verifiers.

Status: implemented and internally verified; live multi-resident/job interruption
testing remains pending.  No launcher patch is required.
## Initial survivor cohort distribution (offline verification, live pending)

World initialization now forms more than one compact starting cohort when the
population is large enough, while retaining the single-pair behavior for small
test saves.  A standard 48-survivor population can create up to three small
groups, each selected from nearby player-spawn origins with deterministic rolls.
The groups remain ordinary persisted travel groups and are not an army-wide
formation; later meetings and faction rules still control further growth.

Verification:

- `tools/test-world-population.lua` continues to pass the six-survivor compact
  cohort, origin reuse, shared travel, and save/restore coverage.
- Full Lua suite: 71 focused scripts pass; all 148 Lua files pass syntax checks.
- `:java:build` and all existing verifiers pass.

Status: implemented and internally verified; a normal-population live check of
cohort visibility and spacing remains pending.  No launcher patch is required.
## Profession-aware automatic base duties (offline verification, live pending)

Residents left on `Auto` now receive a non-persistent profession hint during
task selection: security/veteran roles favor guard work, carpenter/construction
and mechanic roles favor woodwork, farmers/gardeners favor farming, and ranch or
animal roles favor animal care.  Explicit player-selected duties remain
authoritative.  The hint does not bypass skill, trait, material, priority, or
fairness checks, and unmatched professions remain fully automatic.

Verification:

- `tools/test-base-jobs.lua` covers explicit-role preservation, profession hints,
  unmatched fallback, and all existing task-selection checks.
- Full Lua suite: 71 focused scripts pass; all 148 Lua files pass syntax checks.
- `:java:build` and all existing verifiers pass.

Status: implemented and internally verified; live confirmation of mixed-profession
resident behavior remains pending.  No launcher patch is required.
## Base-duty completion pacing (offline verification, live pending)

Successful recurring base work now has a short persisted cooldown before the
same task can be reopened: 0.5 world-hours for normal duties and 0.1 for depot
sorting.  This keeps workers from instantly repeating a completed action, gives
other residents a chance to claim available work, and leaves room for normal
rest/idle behavior.  Failed tasks still use the separate bounded backoff policy;
explicit claimed-task ownership is unchanged.

Verification:

- `tools/test-companion-base-domain.lua` verifies the new completion cooldown,
  delayed requeue, repeated-failure backoff, and success reset.
- Full Lua suite: 71 focused scripts pass; all 148 Lua files pass syntax checks.
- `:java:build` and all existing verifiers pass.

Status: implemented and internally verified; live observation of resident pacing
and multi-worker turnover remains pending.  No launcher patch is required.
## Configurable starting-cohort count (offline verification, live pending)

Added the `Maximum Starting Groups` sandbox setting, clamped to 1–4 and defaulting
to three.  It controls only how many compact cohorts may be formed during the
one-time initial population pass; group chance, nearby-origin requirements,
maximum group size, total population, and later faction rules remain separate.
This gives players a simple way to tune how social the opening world feels
without adding a large settings surface.

Verification:

- `tools/test-sandbox-settings.lua` validates the default and declaration.
- `tools/test-world-population.lua` continues to pass the small-population
  single-cohort path and shared travel coverage.
- Full Lua suite: 71 focused scripts pass; all 148 Lua files pass syntax checks.
- `:java:build` and all existing verifiers pass.

Status: implemented and internally verified; normal-population live balancing
remains pending.  No launcher patch is required.
## Companion tool-supply order (offline verification, live pending)

Individual and party Survival Orders now include **Find Useful Tools**.  The
directive uses the same bounded nearby real-container search and native transfer
path as existing supply orders.  It recognizes only unbroken essential tools
already supported by Knox's looting policy (such as axes, hammers, saws,
screwdrivers, wrenches, jacks, and tire pumps), reserves the selected item, and
returns to the prior companion duty after success or three clean misses.  It
does not fabricate tools or treat arbitrary modded items as compatible.

Verification:

- `tools/test-companion-commands.lua` covers persistence of the new directive.
- `tools/test-survivor-looting.lua` covers usable/broken/unknown tool safety.
- Full Lua suite: 71 focused scripts pass; all 148 Lua files pass syntax checks.
- `:java:build` and all existing verifiers pass.

Status: implemented and internally verified; live transfer/animation and
interruption behavior remain pending.  No launcher patch is required.

## Base-worker material resupply (offline verification, live pending)

Claimed base tasks that cannot start because a required item is missing now make
a bounded supply run before giving up.  The worker searches nearby real
containers for an exact declared requirement, reserves one matching item, uses
the existing native transfer path, and then resumes the same claimed task.
Three unsuccessful attempts release the task into the existing persisted retry
backoff; successful work still clears the failure streak.  No abstract stockpile
or fabricated item is created, and normal companion/base ownership remains
unchanged.

Verification:

- `tools/test-base-supply-planner.lua` covers exact full-type matching, positive
  counts, sorting, and malformed/nil input safety.
- Full Lua suite: 72 focused scripts pass; all 78 current Lua files pass syntax
  checks.
- `:java:build` and all existing Java verifiers pass.

Status: implemented and internally verified; live pickup, return, and task
completion animations remain pending.  No launcher patch is required because
this pass changes only Lua behavior.

## Base-needs scheduling (offline verification, live pending)

Automatic base work now considers the honest storage snapshot before selecting
among already-queued tasks. Low food/water, misplaced depot items, building
shortages, and corpse cleanup receive small bounded priority boosts; normal
priorities remain the baseline and are preserved in `basePriority`. This does
not create supplies, bypass skill checks, or add a second scheduler. It helps a
settlement address relevant existing work while retaining task fairness and
resident preferences.

Verification:

- `tools/test-base-needs.lua` covers shortage boosts, priority preservation,
  urgent cleanup, and adequate-stock behavior.
- Full Lua suite: 73 focused scripts pass; all 79 current Lua files pass syntax
  checks.
- `:java:build` and all existing Java verifiers pass.

Status: implemented and internally verified; live multi-resident balancing and
real storage behavior remain pending. No launcher patch is required.

## Persistent workforce rotation (offline verification, live pending)

Base claims now persist `lastClaimedAtHours` in addition to the existing worker
identity. Equal-priority recurring tasks receive a small, bounded recent-claim
penalty, allowing another eligible resident to take a turn while still letting
urgent or substantially higher-priority work win. The rule is applied in both
automatic selection and the task-board fallback path, so the two schedulers keep
the same behavior after reload.

Verification:

- Existing base-job fairness and priority tests pass unchanged.
- Full Lua suite: 73 focused scripts pass; all 79 current Lua files pass syntax
  checks.
- `:java:build` and all existing Java verifiers pass.

Status: implemented and internally verified; multi-worker live rotation remains
pending. No launcher patch is required.

Recurring security work now also prefers relief from another eligible resident
when alternatives exist. The previous worker can still reclaim the post if no
one else qualifies, so this remains a soft rotation policy rather than a hard
assignment or new scheduler.

Verification: base-job regression coverage includes relief selection; all 76
Lua tests, Java build/verifiers, Workshop staging, and `git diff --check` pass.
Live resident rotation remains pending. No launcher patch is required.

Off-screen guard and patrol shifts now requeue their recurring task after a
completed watch interval. This lets another resident take relief while the
base is unloaded, instead of leaving one identity permanently associated with
the post until the next full load. The normal retry window and task history are
preserved through the existing persistence API.

Verification: all 76 Lua tests, Java build/verifiers, Workshop staging, and
`git diff --check` pass. Live multi-resident relief rotation remains pending.
No launcher patch is required.

## Resident supply runs (offline verification, live pending)

When a base resident has no executable local job and the shared storage
snapshot is genuinely short on food, water, or medical supplies, the resident
now gets a bounded opportunity to use the existing real-item nearby search.
This preserves the resident's base duty, uses the normal inventory/action path,
and backs off between attempts; it does not create abstract stock or a second
mission system.

Verification: all 76 Lua tests, Java build/verifiers, Workshop staging, and
`git diff --check` pass. Live confirmation of supply runs leaving and returning
to a base remains pending. No launcher patch is required.

## Off-screen base duty progression (offline verification, live pending)

Unloaded residents no longer appear completely frozen while the player is away.
The existing unloaded-survival ledger now tracks a claimed base duty. Guard and
patrol shifts accumulate bounded off-screen work time and complete through the
existing persisted task-board path. Physical jobs such as farming, repairs,
construction, hauling, and barricading remain claimed but are deliberately not
marked complete away from the loaded world; they resume with their native engine
actions when the resident returns.

Verification:

- `tools/test-base-duty-simulation.lua` covers shift accumulation, completion,
  queued-task rejection, and protection of physical jobs.
- Full Lua suite: 74 focused scripts pass; all 80 current Lua files pass syntax
  checks.
- `:java:build` and all existing Java verifiers pass.

Status: implemented and internally verified; save/reload and multi-hour live
materialization remain pending. No launcher patch is required.

## Persistence normalization hardening (offline verification, live pending)

The persistence root now normalizes the accumulated scheduling fields when an
older save is opened: task priority baselines, retry/failure counters, recent
claim timestamps, off-screen watch time, survivor duty defaults, and existing
unloaded-life values are sanitized in place. Missing unloaded-life state is not
invented, so legacy records still wait for a real capture before physiology is
applied. This keeps old saves compatible without replacing identities or
rewriting valid state.

Verification:

- Legacy world-presence and event-readiness regression tests pass.
- Full Lua suite: 74 focused scripts pass; all 80 current Lua files pass syntax
  checks.
- `:java:build` and all existing Java verifiers pass.

Status: implemented and internally verified; migration against a real legacy
save remains pending. No launcher patch is required.

## Base-task ownership restoration (offline verification, live pending)

Persistent claimed work is now explicitly restored before a reconstructed base
resident may select another task. The persistence boundary enforces one claimed
task per survivor, keeps the highest-priority deterministic claim, requeues any
duplicates, and releases claims owned by missing, dead, reassigned, or
event-borrowed survivors. Schema-wide repair runs once per schema version;
controller restoration performs only the relevant base scan.

This closes the previous state where a controller could forget its in-memory
`baseTask` after unloading while the task board still retained the durable claim,
allowing the resident to select additional work.

Verification:

- `tools/test-companion-base-domain.lua` covers authoritative claim recovery,
  duplicate-claim repair, orphan cleanup, and preservation of relocation rules.
- Full Lua suite: 74 focused scripts pass; all 80 current Lua files pass syntax
  checks.
- `:java:build`, all Java verifiers, and `git diff --check` pass.

Status: implemented and internally verified; unload/materialize continuation
remains pending live evidence. No launcher patch is required.

## Companion patrol orders (offline verification, live pending)

Individual companions and the full party can now receive a persistent
`patrol_area` directive through the existing context menus. The route uses four
inset points inside the selected area, advances from the nearest reached point,
and varies equal-distance starting choices by survivor identity so a party does
not deliberately stack. Patrol pauses are bounded, combat/self-care retain the
underlying directive, and three invalid-route attempts release the temporary
order cleanly. No formation or alternate movement system was introduced.

The world-population materializer also recognizes the new `base_working`
off-screen activity, preventing an unloaded working resident from restoring at
an obsolete pre-work record location.

Verification:

- `tools/test-companion-patrol.lua` covers inset route generation, waypoint
  advancement, and invalid-input safety.
- `tools/test-companion-commands.lua` covers persisted patrol directives.
- Full Lua suite: 75 focused scripts pass; all 81 current Lua files pass syntax
  checks.
- `:java:build`, all Java verifiers, and `git diff --check` pass.

Status: implemented and internally verified; visible patrol pacing, traversal,
and interruption/resume remain pending live evidence. No launcher patch is
required.

## Guard-post and base-patrol coherence (offline verification, live pending)

Guard and Patrol now have separate, consistent meanings across companion and
base behavior. A guard moves to one deterministic post within the assigned area
and holds it. A patrol follows a persisted multi-stop route through the area,
pauses briefly at each stop, and completes only after visiting the full route.
Faction bases place their default entry-watch zone at a valid nearby outdoor
square when one is loaded instead of blindly using the building center.

Base-patrol progress is stored on the existing task record. Combat, unload, or
another bounded failure may block and later reopen that same task without
losing the next route stop. Save normalization clamps malformed progress, small
areas collapse duplicate points safely, and no second movement or job owner was
introduced.

Verification:

- `tools/test-companion-patrol.lua` covers companion- and base-shaped bounds,
  distinct route stops, deterministic guard posts, persisted cycle progress,
  tiny-area deduplication, and controller wiring.
- `tools/test-base-jobs.lua` covers stable guard-post resolution and consecutive
  base-patrol destinations.
- `tools/test-companion-base-domain.lua` covers patrol progress surviving a
  blocked/requeued task and later reclaim.
- Full Lua suite: 75 focused scripts pass; all 80 current Lua files pass syntax
  checks.
- `:java:build`, all Java verifiers, and Workshop staging pass.

Status: implemented and internally verified. Live evidence is still required
for visible multi-stop pacing, obstacle traversal between stops, combat resume,
and save/reload midway through a patrol. No launcher patch is required because
this pass changes only staged mod Lua and documentation.

## Unified order vocabulary and safe resume command (offline verification, live pending)

The player-facing command surface now has a small Knox-owned order catalogue
shared by the companion service and both party/individual context menus. It
provides one stable label source for primary orders, temporary directives, and
base preferences without creating a second planner or task manager. A new
Resume Normal Duty action clears only the temporary companion directive through
the existing persistence and controller interruption boundary; Follow, Hold,
Relax, base duty, affiliation, and survivor identity remain untouched. The
party version applies the same operation to every owned companion and disables
it when no temporary directive exists.

Verification:

- `tools/test-order-catalog.lua` covers shared labels, directive classification,
  and unknown-order safety.
- Full focused Lua suite: 76 scripts pass; all current Lua test surfaces pass.
- `git diff --check` reports no whitespace errors.

Status: implemented and internally verified; live menu routing, interrupted
combat/self-care resume, and save/reload behavior remain pending. No launcher
patch is required because this pass changes only staged mod Lua and docs.

The catalogue is now also the source for party, individual, base-preference,
and survivor-card labels. Status text keeps its established readable wording
while menu wording remains concise, so this consolidation does not alter saved
directive data or controller behavior.

## Base resident rest preference (offline verification, live pending)

Base residents can now be assigned **Rest / Recover** through the existing job
preference menu. The preference is persisted on the resident's normal duty
record, prevents automatic task claiming while active, and lets the existing
base idle/ambient recovery path run. Returning to Automatic or another work
preference resumes the existing scheduler; no parallel task manager or abstract
rest state was introduced.

Verification: order catalogue, base-job, companion-command, and base-ambient
tests pass; Workshop staging passes. Live confirmation of visible sitting,
needs recovery, and preference persistence remains pending. No launcher patch
is required because this pass changes only staged Lua and documentation.

## Settlement job-type balancing (offline verification, live pending)

Automatic task selection now applies a small bounded penalty when a task type
already has active claims. Priority, skill/material eligibility, explicit role
preference, and recent-claim fairness remain authoritative; the penalty only
breaks near-equal ties between useful work types. This keeps a base from sending
every available resident to the same guard, farming, or hauling category while
still allowing that category when it is the only eligible work.

Verification: `tools/test-base-jobs.lua` now covers active work-type
distribution alongside existing preference, priority, and fallback checks;
order, ambient-life, diff, and Workshop staging checks pass. Live multi-resident
job distribution remains pending. No launcher patch is required.

## Base rest handoff and claim release (offline verification, live pending)

Selecting **Rest / Recover** now also releases any currently claimed base task
back to the existing task board before the resident enters ambient recovery.
This closes the boundary where a resident could be told to rest but continue a
previous work claim after the next controller refresh. The durable preference,
task requeue, native-action interruption, and later return to Automatic remain
on the existing persistence/controller paths.

Verification: base-job, ambient-life, companion-command, order-catalogue, diff,
and Workshop staging checks pass. Live confirmation of an in-progress job being
released and a resident visibly recovering remains pending. No launcher patch is
required.

The shared catalogue also now fails closed when a stripped test harness or
optional load path does not provide the module, keeping context-menu tests and
older initialization paths from throwing while the normal game load still uses
the full Knox labels.

Final offline verification for this pass: all 76 Lua tests pass, Java build and
verifiers pass, Workshop staging passes, and `git diff --check` reports no
content errors. Live settlement behavior remains pending.

## Player-base work-area defaults (superseded 2026-09-05)

Live usability review rejected automatic player-base work areas. Player areas
and storage policies are now explicit Notebook choices; automatic planning is
reserved for autonomous NPC faction bases. Existing player-created areas remain
valid and are not deleted. Repair continues to scan owned territory without a
dedicated overlay. The sandbox option is now labelled **Automatic NPC Base Work
Areas** to describe its actual scope.

## Settlement work feedback (offline verification, live pending)

Base work completion now reports the actual completed duty instead of using a
generic patrol message for every task. Guard, patrol, defense, repairs,
storage, corpse handling, animal care, farming, and wood work each have a short
contextual line through the existing activity-feed/native speech path. This is
presentation-only and does not add another dialogue or job system.

Verification: all 76 Lua tests pass; Java build/verifiers, Workshop staging, and
`git diff --check` pass. Live confirmation of the lines during real native job
completion remains pending. No launcher patch is required.

## Group-to-group human encounters (offline verification, live pending)

Encounter coordination now allows leaders of two different established travel
groups to notice and resolve a bounded human interaction. A `join` result is
deliberately narrowed to a greeting for group-to-group contact; only a lone
survivor can use the existing join-group path. The pending encounter records
both original group IDs, so membership changes abort safely while an unchanged
pair completes without merging or corrupting either group. Existing cooldowns,
hostility, and controller ownership remain authoritative.

Verification: the human-encounter regression now covers two established group
leaders meeting without an invalid join pair or group merge. All 76 Lua tests,
Java build/verifiers, Workshop staging, and `git diff --check` pass. Live
verification of group leaders meeting in-world remains pending. No launcher
patch is required.

## Faction identity collision handling (offline verification, live pending)

Generated NPC faction names now remain readable while avoiding duplicate names
when two groups happen to produce the same leader-based name. Existing names,
player faction names, and explicitly named event factions are preserved. A new
generated collision receives a stable numeric suffix before it reaches the
notebook, activity feed, or safehouse title.

Verification: faction persistence, human encounter, full Lua suite, Java
build/verifiers, Workshop staging, and `git diff --check` pass. Live formation
of multiple same-name factions remains pending. No launcher patch is required.

Faction-owned engine safehouses now also upgrade an old generated title such as
`Knox faction faction-1` to the persisted faction display name, while leaving
player-customized titles untouched. Newly created safehouses use the same
readable faction name from the start.

Verification: faction persistence, full Lua suite, Java build/verifiers,
Workshop staging, and `git diff --check` pass. Live safehouse-title migration
remains pending. No launcher patch is required.

## Faction base identity (offline verification, live pending)

When an NPC faction claims a permanent base, the base now adopts the persisted
faction name with a `Base` suffix when it still has the generic `Survivor Camp`
name. Customized base names are preserved. This keeps the faction, notebook,
activity feed, and settlement property visibly connected without adding another
name or ownership system.

Verification: full Lua suite, Java build/verifiers, Workshop staging, and
`git diff --check` pass. Live confirmation of faction-base naming remains
pending. No launcher patch is required.

Faction-formation activity-feed messages now use the persisted faction display
name instead of a generic announcement, keeping the player-facing settlement
loop tied to the same identity shown in the notebook and safehouse UI.

## Settlement security coverage (offline verification, live pending)

When a base has more than one resident and no guard or patrol task is active,
the existing task selector gives the first eligible security task a bounded
coverage bonus. Once security is covered, ordinary priorities, skills,
preferences, and fairness resume. This prevents a populated base from sending
everyone into production work while leaving its perimeter unwatched, without
adding another scheduler or overriding explicit jobs.

Verification: base-job regression coverage includes establishing and yielding
security coverage; all 76 Lua tests, Java build/verifiers, Workshop staging,
and `git diff --check` pass. Live multi-resident guard rotation remains
pending. No launcher patch is required.

## Scaled settlement watch (offline verification, live pending)

Security coverage now scales modestly with the resident roster: a small base
targets one active guard or patrol, while a base with four or more residents
can keep a second relief watch active. Guard and patrol are balanced when both
are available, and the existing repeat/recency penalties still prevent one
resident from owning every watch shift. This remains a soft selection bonus;
explicit duties, capabilities, task priority, and native action eligibility
still win.

Verification: base-job regression coverage now includes the larger-base relief
watch case; full Lua and Java verification remains required. Live watch
rotation and behavior around a real perimeter are still pending. No launcher
patch is required because this is Lua-only.

## Unified base-task presentation (offline verification, live pending)

The notebook Work tab and cancel/resume activity messages now resolve persisted
base task IDs through `KnoxOrderCatalog`. Residents therefore appear as
"Water Crops", "Build Defenses", "Move Corpses", and similar readable duties
instead of leaking internal names such as `farm_water`. Unknown or mod-added
task types still fall back safely to their raw identifier.

Verification: order-catalog regression coverage, full Lua suite, Java build and
verifiers, Workshop staging, and diff validation pass. Live UI scaling and task
feedback remain pending. No launcher patch is required.

The same catalogue now owns the visible `Return to Base` and `Resume Normal
Duty` labels in the companion context menu, removing the last duplicate strings
from the primary order path. This is presentation-only and does not alter
directive persistence or execution.

## Faction shelter rejection recovery (offline verification, live pending)

If a faction reaches a recorded shelter candidate but final confirmation fails,
the candidate is now written through the existing bounded rejection memory before
the scouting state is cleared. This prevents an ownership conflict, stale
building, or newly claimed safehouse from causing the faction to select the same
unusable building on every scouting cycle.

Verification: faction-persistence rejection coverage, full Lua suite, Java build
and verifiers, Workshop staging, and diff validation pass. Live faction scouting
through a failed candidate remains pending. No launcher patch is required.

## Deterministic faction shelter selection (offline verification, live pending)

Faction shelter scouting now breaks equal-score ties by nearest approach and
then stable building ID instead of relying on streamed map iteration order. A
faction therefore keeps a consistent candidate when several buildings are
equally suitable, while the existing score and rejection rules remain in force.

Verification: full Lua suite, Java build/verifiers, Workshop staging, and diff
validation pass. Live multi-building scouting remains pending. No launcher patch
is required.

## Outdoor temporary faction camps (offline verification, live pending)

Faction leaders can now establish a bounded temporary camp outdoors when they
form before locating a valid building. The camp uses the existing radius-based
occupancy and return behavior; permanent building/safehouse scouting remains a
separate later step. Incomplete streamed building metadata is treated safely
instead of causing a camp-location error.

Verification: camp-living regression coverage now includes an outdoor leader,
full Lua suite, Java build/verifiers, and Workshop staging pass. Live outdoor
camp formation and later conversion to a permanent base remain pending. No
launcher patch is required.

## Temporary camp/base territory boundary (offline verification, live pending)

Temporary faction camps now consult persisted base territories as well as loaded
safehouse objects and other camps. This closes the streaming gap where an
outdoor camp could be created inside an established player or faction base
before that base's engine safehouse was loaded.

Verification: faction-camp regression coverage includes persisted-base overlap,
full Lua suite, Java build/verifiers, and Workshop staging pass. Live competing
camp placement remains pending. No launcher patch is required.

## Temporary camp ownership safety (offline verification, live pending)

Temporary camp creation now checks existing camps across factions. A building
already claimed by another faction, or an outdoor camp patch within the bounded
radius, is rejected through the persistence layer. This keeps faction shelters
from overlapping while preserving same-faction reuse and later camp-to-base
conversion.

Verification: faction-camp regression coverage, full Lua suite, Java
build/verifiers, and Workshop staging pass. Live competing-faction camp
placement remains pending. No launcher patch is required.

## Unified order/work-duty mapping (offline verification, live pending)

The shared `KnoxOrderCatalog` now owns the preference-to-task-group mapping
used by automatic base-duty selection. Farming, woodwork/defense, hauling,
animal care, security, and repair preferences resolve through the same metadata
used by player-facing labels and task presentation. This removes the previous
duplicate matching table in `KS_BaseJobs` while leaving task creation, claims,
eligibility, and native execution in their existing owners.

Verification: order-catalog preference regressions, full Lua suite (76 tests),
Java build/verifiers, and Workshop staging pass. A live check that player
preferences and automatic resident assignment stay aligned remains pending.
No launcher patch is required because this is Lua-only.

## Ownership-aware survivor activation (offline verification, live pending)

Loaded-body activation now applies a deterministic ownership priority within
the existing active-body budget: player companions first, player-base
residents next, NPC-base residents, grouped survivors, then independent
survivors. Distance and restore-before-first-materialization ordering remain
the tie-breakers. This keeps established player relationships available when
the loaded band contains more durable survivors than the active-body budget,
without increasing population or changing origin allocation.

Verification: world-population regression coverage now asserts the priority
metadata; full Lua suite (77 tests), Java build/verifiers, Workshop staging,
and diff validation pass. Live streaming with a full active budget remains
pending. No launcher patch is required.

The settlement shortage boundary was tightened in the same pass: priority
bonuses now require at least one assigned storage policy to be loaded and
inspected. Streamed-out or unavailable storage no longer produces invented
shortage urgency; the task remains governed by its persisted priority until
real storage is available.

Verification: `tools/test-base-needs.lua` covers the zero-loaded-policy case;
the full 76-test Lua sweep and diff validation pass. Live storage streaming
behavior remains pending. No launcher patch is required.

The task-board convenience API now accepts the same optional resident preference
used by the autonomy controller. It performs a preferred pass, then falls back
to any eligible queued work, so callers outside the main controller cannot
silently ignore a persisted job preference.

Verification: `tools/test-base-task-board.lua` covers preferred selection and
fallback; the full Lua suite now contains 77 passing tests. Java build,
verifiers, Workshop staging, and diff validation pass. Live multi-resident duty
selection remains pending. No launcher patch is required.

## Faction settlement lifecycle guard (offline verification, live pending)

Faction-base reconciliation now refuses to convert dead, event-managed,
departing, or away-team survivors into residents. The same lifecycle boundary
also prevents those identities from being added back to an NPC faction. This
keeps durable death, event departure, and mission ownership authoritative when
a base is created or restored.

Verification: faction-persistence regression coverage exercises durable death
against faction membership and resident conversion; the full Lua suite and
diff validation pass. Java build/verifiers and Workshop staging were not
changed by this Lua-only guard. Live faction restoration remains pending. No
launcher patch is required.

## Settlement supply-search coordination (offline verification, live pending)

Base residents now share short-lived persisted claims for food, water, and
medical supply searches. When a base is short on one category, only one resident
claims that search at a time; the lease expires on failure, unload, death, or
after a bounded interval. Healthy storage releases the claim immediately. This
keeps the settlement loop from sending every resident on the same scavenging
trip while preserving real-world item search and existing base duty ownership.

Verification: roaming-controller source regressions cover the shared claim
table, bounded lease, and duplicate suppression; the full Lua suite, Java
build/verifiers, Workshop staging, and diff validation pass. Live multi-resident
supply distribution remains pending. No launcher patch is required.

## Faction-base duty handoff (offline verification, live pending)

When an NPC faction claims a permanent base, active members now receive the
normal runtime duty-change notification as each resident assignment is written.
This prevents an already-loaded leader or member from continuing stale roaming
or base-scouting behavior until an unrelated controller refresh occurs. The
persisted duty remains the source of truth; the notification only wakes the
existing controller boundary.

Verification: base-management UI/source regression coverage protects the duty
handoff hook; the full Lua suite, Java build/verifiers, Workshop staging, and
diff validation pass. Live faction conversion and resident-work startup remain
pending. No launcher patch is required.

## Base idle-life staggering (offline verification, live pending)

Idle residents now use a deterministic per-survivor phase for short movement,
rest, and wait decisions instead of independent same-tick random rolls. This
reduces synchronized pacing and resting while keeping the existing native
furniture/ground recovery actions and bounded base decision cadence intact.

Verification: autonomy source regressions cover deterministic per-survivor
jitter and bounded phase changes; the full Lua suite, Java build/verifiers,
Workshop staging, and diff validation pass. Live base ambience remains pending.
No launcher patch is required.

## Base supply-trip return handoff (offline verification, live pending)

Resident shortage searches now carry a temporary supply-trip marker. After the
native search/transfer completes, the marker is cleared and the existing base
duty decision boundary immediately routes the resident home if they are outside
the territory. Interruptions still clear only the temporary marker, allowing
combat or self-care to preempt safely without creating a second order.

Verification: roaming-controller source regressions cover marker creation and
return handoff; the full Lua suite, Java build/verifiers, Workshop staging, and
diff validation pass. Live supply collection and return remain pending. No
launcher patch is required.
### Human encounter availability for NPC faction residents (2026-09-04)

- **Defect:** the encounter coordinator excluded every survivor with `duty.mode == "base"`, which meant residents of an established NPC faction could never notice or meet nearby independent survivors. This blocked the intended path for faction groups to grow without weakening player companion/base ownership.
- **Fix:** social availability now receives the live controller and permits only NPC faction residents in `BASE_IDLE` or `BASE_AMBIENT_REST` to participate. Active base work/security, player-owned companions, and player-owned base residents remain protected. The controller meeting-interrupt boundary now recognizes those two idle base states, so the existing bounded approach/greeting flow can actually start.
- **Verification:** `tools/test-human-encounters.lua` now covers idle faction residents participating and active base work being excluded; full Lua suite and Java build/staging checks pass.
- **Status:** implemented; live in-game encounter verification pending.
### Unified order catalogue routing (2026-09-04)

- **Defect:** player-facing order validation and base-preference menu ordering were duplicated in service/UI code, allowing the visible vocabulary to drift from the command boundary and permitting malformed directives to reach persistence.
- **Fix:** `KnoxOrderCatalog` now owns primary-order/base-preference classification and the stable base-preference menu sequence. Companion commands validate against that catalogue, directive submission rejects unknown/non-table directives before persistence, and the context menu consumes the canonical preference order.
- **Verification:** order-catalogue regression checks cover primary/directive/preference classification and unknown safety; full Lua suite, Java build, staging, and `git diff --check` pass.
- **Status:** implemented; live command-menu verification pending.
### Unified companion order dispatch (2026-09-04)

- **Defect:** context-menu handlers each called persistence/directive methods directly, so player-facing orders had no single validation/routing boundary.
- **Fix:** added `KnoxCompanionService.issueOrder`, which validates against `KnoxOrderCatalog` and routes primary orders, return-to-base, resume, and existing directives to their current owners. Loot, survival, move, guard, and patrol menu actions now use that dispatcher; malformed/unsupported requests fail closed.
- **Verification:** companion command and order-catalogue checks pass, along with the full Lua suite, Java build/staging, and whitespace validation.
- **Status:** implemented; live menu interaction remains pending.
### Base-duty preferences on the shared order boundary (2026-09-04)

- **Defect:** base-resident job preferences still bypassed the shared player-facing order route, leaving the catalogue incomplete for settlement commands.
- **Fix:** the same dispatcher now routes catalogue base preferences (`auto`, guard/patrol, farming, woodwork, hauling, animal care, repair, rest) to the existing persisted base-preference service. No second task manager or job executor was introduced.
- **Verification:** companion command source checks, order-catalogue checks, full Lua suite, Java build/staging, and whitespace validation pass.
- **Status:** implemented; live base-menu verification pending.
### Base-resident player controls (2026-09-04)

- **Defect:** the base-resident context menu exposed a misleading `Follow` label and did not provide the native inventory access already available for companions.
- **Fix:** the entry is now explicitly `Bring Along` (using the existing base-to-companion transition), and base residents receive the same distance-gated inventory menu. Job preferences continue through the unified order dispatcher.
- **Verification:** base UI and companion command checks pass; full Lua/Java verification remains green from this pass.
- **Status:** implemented; live context-menu and activation verification pending.
### Persistence-safe catalogue validation (2026-09-04)

- **Defect:** making persistence load the UI catalogue directly broke standalone/test and early-load paths where the catalogue is intentionally unavailable.
- **Fix:** persistence now consults the catalogue when it is already loaded, with the existing allow-list as a compatibility fallback. This keeps save/load independent of UI load order while still converging on one canonical vocabulary at runtime.
- **Verification:** full Lua suite (`lua_failures=0`), Java build/staging, and diff validation pass.
- **Status:** implemented; live save/load remains pending.
### Dead resident task-claim guard (2026-09-04)

- **Defect:** the persistent task-board claim boundary checked record/duty ownership but did not explicitly reject an identity already marked dead.
- **Fix:** `claimBaseTask` now fails with `survivor_dead` before changing task state. Existing cleanup/requeue logic remains responsible for releasing any prior claim.
- **Verification:** full Lua suite, Java build/staging, and diff validation pass.
- **Status:** implemented; live death/base-job interaction remains pending.
### Single active base-task ownership (2026-09-04)

- **Defect:** task-level uniqueness did not prevent one resident from holding multiple claimed base tasks during same-tick controller/UI retries.
- **Fix:** `claimBaseTask` now checks the resident's existing claims and fails closed with `already_claimed_task` before changing another task. Native task execution and normal requeue paths remain unchanged.
- **Verification:** base task-board regression check, full Lua suite, Java build/staging, and diff validation pass.
- **Status:** implemented; live same-tick retry behavior remains pending.
### Base preference lifecycle guard (2026-09-04)

- **Defect:** persisted base-job preferences could still be edited on a dead or event-bound player-owned resident, leaving a stale duty mutation even though work execution was unavailable.
- **Fix:** `setBaseJobPreference` now rejects dead and event-owned residents before changing the durable duty record. Task claiming already rejects the same states, keeping preference and execution boundaries consistent.
- **Verification:** full Lua suite (`lua_failures=0`), Java build/staging, and diff validation pass.
- **Status:** implemented; live UI lifecycle verification remains pending.
### Base-duty acknowledgement feedback (2026-09-04)

- **Improvement:** changing a resident's persisted base-job preference gave no direct confirmation from the survivor.
- **Fix:** the existing companion service now emits one short role-specific acknowledgement through `KnoxActivityFeed` after a successful change. No new dialogue/UI surface was added and task ownership remains unchanged.
- **Verification:** full Lua suite (`lua_failures=0`), Java build/staging, and diff validation pass.
- **Status:** implemented; live feedback presentation remains pending.
### Catalogue-owned directive construction (2026-09-04)

- **Defect:** directive payloads were being assembled ad hoc at the companion-service boundary, allowing player-facing callers to bypass the catalogue's canonical directive vocabulary or omit a normalized `kind`.
- **Fix:** `KnoxOrderCatalog.makeDirective` now validates the directive kind, copies the payload, and stamps the canonical kind before persistence/execution. `issueOrder` uses this single constructor and fails closed for unsupported directives.
- **Verification:** focused order-catalogue and companion-command checks, full Lua suite, Java build/staging, and whitespace validation.
- **Status:** implemented; live directive execution remains pending.
### Unified settlement task selection (2026-09-04)

- **Defect:** `KS_BaseTaskBoard.claimBest` kept a second preference/fairness selector, so callers could receive different assignments from the newer settlement planner.
- **Fix:** when the base-job layer is loaded, the task board now delegates selection to `KnoxBaseJobs.selectEligibleTask` and retains atomic claiming in persistence. Early-load callers keep the compatibility selector until the job layer exists.
- **Verification:** base task-board regression, full Lua suite, Java build/staging, and whitespace validation.
- **Status:** implemented; live multi-resident duty distribution remains pending.
### Settlement shortage recovery expansion (2026-09-04)

- **Gap:** base supply recovery considered food, water, and medical stock but ignored a settlement with no weapons or basic tools, leaving residents to idle or roam without a concrete reason.
- **Fix:** the existing one-worker shortage lease now also selects `find_weapon` and `find_tools` after essential food, water, and medical checks. It reuses the normal ranked world search, real item transfer, and return-to-base path; no abstract stockpile or mission system was added.
- **Verification:** base-needs regression, full Lua suite, Java build/staging, and whitespace validation.
- **Status:** implemented; live shortage trip and return remain pending.
### Faction-to-settlement boundary review (2026-09-04)

- **Confirmed:** stable three-person groups can promote through the existing relationship gate, receive a persisted faction name, choose an unclaimed shelter, create a safehouse/base record, generate guard/patrol/maintenance/work coverage, and convert members into base residents without duplicate ownership.
- **Deliberately not duplicated:** faction membership, base ownership, and task assignment remain owned by `KS_Persistence`, `KS_FactionCamps`, `KS_BaseManager`, and the shared task board. No second faction scheduler was introduced.
- **Remaining gap:** a faction whose leader and members are outside loaded cells cannot yet perform a useful unloaded shelter/resource search; it waits for a loaded boundary before choosing a real building or gathering real supplies. This is the next faction progression pass.
- **Verification:** source inspection plus the existing faction, camp, population, task-board, full Lua, Java build/staging, and whitespace checks.
- **Status:** core loaded transition confirmed by focused checks; unloaded faction scouting/resource growth remains incomplete and live behavior is pending.
### Unloaded faction scouting handoff (2026-09-04)

- **Gap:** a fully stored NPC faction could advance ordinary group travel, but had no durable reason to stop at a plausible area for its leader to inspect a real shelter when the world cell was unloaded.
- **Fix:** stored faction cohorts now choose a different same-floor real origin from the cached population catalogue, persist an `investigate_building` objective, move as one cohort, and pause at that anchor. Once the leader materializes, the existing loaded `KS_FactionBaseScouting` path resumes and evaluates actual buildings; no building, supplies, or base is invented off-screen.
- **Verification:** population-origin and unloaded-group regression checks, full Lua suite, Java build/staging, and whitespace validation.
- **Status:** implemented; live unloaded-faction materialization and shelter selection remain pending.

### Faction growth and settlement admission (2026-09-04)

**Status:** implemented; live faction recruitment and post-admission settlement behavior remain pending.

The existing encounter path could add an independent survivor to an established faction,
but it had no faction-size boundary. A join rejected by the persistence layer could also
still be presented as an accepted join and mark the pair allied. That was an integration
defect at the relationship-to-faction boundary, not a reason to add another faction manager.

The fix adds the `NPCFactionMaxMembers` sandbox setting (default 8, bounded 3--24) and
enforces it transactionally in `KnoxPersistence.addTravelGroupMember`. Existing members
are never removed when the setting is lowered. `KS_SurvivorRelationships` now treats a
rejected faction admission as a short neutral cooldown, resumes both controllers, and
does not claim an alliance or group transition occurred.

Focused checks cover the default and clamped sandbox values, faction admission at the
configured limit, and persistence compatibility with later faction/base tests. The full
Lua suite and Java build remain the verification gate; live encounter, recruitment, and
settlement observation are still required. This is Lua/persistence-only, so no launcher
patch is required.
- **Regression coverage:** `test-unloaded-groups.lua` now creates a stored NPC faction, verifies the persisted shelter-scout objective, and confirms the shared cohort stops at its real origin anchor.

## Persistent workforce rotation (2026-09-04)

- **Defect:** automatic settlement selection already balanced active task types,
  but a resident's own previous duty was not remembered. A worker could be
  handed the same recurring job whenever it reopened, making a base look like
  one person had been assigned permanently to one station.
- **Fix:** a successful persistent task claim now records `lastJobType` and
  `lastJobAtHours` on the resident's existing duty record. Automatic selection
  applies a small, bounded penalty to that same task type. Explicit player
  preferences, eligibility, security coverage, and materially higher priority
  still win; no second scheduler or abstract job state was introduced.
- **Verification:** base-job regressions cover rotation to a near-equal task,
  explicit-preference precedence, and missing-duty safety. Focused base-job and
  task-board tests pass. Full Lua syntax/tests, Java build/staging, and diff
  validation remain the verification gate for this pass.
- **Status:** implemented; live multi-resident work rotation and save/reload
  behavior remain pending. Lua/persistence-only change; no launcher patch is
  required.

## Bounded human encounter lead-in (2026-09-04)

- **Gap:** human encounters were gated to a 24-tile awareness and 16-tile
  approach window. That was safe but too short for two roaming survivors to
  consistently notice and converge before passing each other.
- **Fix:** the existing same-floor and native line-of-sight gate now uses a
  bounded 32-tile awareness radius and 20-tile cautious approach radius. The
  change affects only contact lead time; it does not grant wall, floor, or
  map-wide awareness and does not alter relationship outcomes or cooldowns.
- **Verification:** encounter regressions cover blocked LOS, different floors,
  the expanded same-floor contact range, single-owner meetings, cooldowns,
  group protection, and idle faction-resident eligibility. Live encounter
  frequency remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Patrol preference/directive collision (2026-09-04)

- **Defect:** `patrol` is both a canonical player-base preference and a legacy
  shorthand for a companion patrol area. Applying the alias before dispatch
  classification could misroute payload-less resident or party Patrol orders
  as empty location directives.
- **Fix:** the catalogue keeps payload-less `patrol` canonical as the base
  preference. Payload-bearing shorthand is promoted to `patrol_area` only at
  directive construction/dispatch; payload-less party Patrol fans out through
  the existing per-companion bounded patrol directive.
- **Verification:** order-catalogue and order-routing regressions pass; the
  catalogue and companion service pass Lua 5.1 syntax validation and
  `git diff --check`. Live menu execution remains pending.
- **Status:** implemented; Lua-only order-boundary correction, so no launcher
  patch is required.

### Human combat player-safety correction — 2026-09-05

- Inspected installed Build 42.20.4 `zombie.CombatManager.checkPVP` bytecode.
  Instructions 64–67 skip multiplayer faction handling in single-player;
  205–222 require `IsoPlayer.getCoopPVP()`. Setting `factionPvp` cannot
  enable single-player human damage.
- Removed combat startup's unconditional `setFactionPvp(true)` calls on both
  participants. The old code altered the real player's setting without restoring
  it. No global PvP switch, artificial damage, or broad engine bypass was added.
- Added a source regression prohibiting player/global PvP-setting mutation in
  the combat controller. Renamed the existing source-only human-combat test
  result to `human_target_dispatch`, since it does not verify native damage.
- Native hostile-human damage with coop PvP disabled remains **incomplete**.
  A future bridge must authorize specific hostile pairs, preserve godmode,
  exclude friendlies, and leave unrelated player/multiplayer checks native.
  Player-initiated aggression must also be evaluated before hit acceptance;
  the post-hit relationship event alone cannot bypass a rejected first hit.
- Verification: player-facing source regression, all Java checks/runtime and
  transformer verifiers, Java build, checksum generation and Workshop staging
  pass. No launcher protocol/API change; no launcher release was created.
  No live test was run for this correction.

### Scoped native human eligibility — 2026-09-05

**Follow-up: player-first attack eligibility implemented, live-unverified.** Native
OnWeaponSwing/OnWeaponSwingHitPoint now rebuild directional permissions over active
survivors, using existing affiliation/faction/trust state. Owned companions/settlers,
allied factions and friendly personal relations are protected; neutral/hostile
survivors can be eligible when the combat setting permits. Hit-point refresh revokes
windup grants after recruitment. No hostility is created on a miss: the existing
native post-hit event remains authoritative. One-second expiry and world teardown
clear temporary player permissions. No player/global PvP setting is changed.

Verification: 86 Lua regressions, all 84 mod Lua syntax checks, Java checks/build,
transformer/runtime checks and Workshop staging pass. Java 25 verification now also
resolves the actual cached native API without initializing a game world. Regressions
cover neutral eligibility, friendly/companion protection, faction relations,
recruitment during windup, disabled settings, NPC exclusion, older bridge fallback,
directionality, lease expiry and world cleanup. No launcher code change is needed;
the matching Lua, agent JAR and checksum are staged together for a later upload.
No release or Workshop upload performed. Below describes the preceding boundary.

- Added exact-descriptor/offset redirects for the three installed 42.20.4
  CombatManager checkPVP callers. Mismatched call shapes fail closed. The native
  checkPVP implementation remains available for unrelated objects and multiplayer.
- Existing accepted live human combat registers a short-lived exact body pair;
  reverse direction allows self-defense, not damage to unrelated bystanders.
  Reset/replacement/failed startup revoke ownership. Lease expiry provides a
  fallback if ordinary cleanup is missed. Godmode/dead/unloaded victims are
  rejected. No synthetic damage or global player-setting changes.
- Lua disengagement now rejects former hostile humans before stale target intent
  can retain combat; ordinary local players are also classified as humans rather
  than accidentally evaluated as zombies after hostility clears.
- Verification: all 85 Lua tests, affected Lua syntax, all Java checks, exact
  transformer shape checks, Java 25 transformed-class verification, build,
  checksum generation and Workshop staging pass. Regressions cover pair scope,
  reversal, replacement, cleanup, expiry, godmode/death/unload and multiplayer
  exclusion, plus newly friendly target disengagement.
- **Implemented, live-unverified:** NPC-initiated human combat and self-defense.
  Test hostile NPC/player and NPC/NPC with coop PvP off; verify native damage,
  protected friendly bystanders, godmode and post-fight movement.
  Player-first aggression on neutral NPCs remains incomplete; no claim of full
  human combat parity. No save schema or launcher protocol change. Updated agent
  is staged locally; no launcher release or Workshop publication was performed.

### Unarmed combat rejection recovery (2026-09-05)

- Follow-up menu inspection: party/survivor/trade construction passes explicit
  callable-callback assertions in the executable UI regressions. This does not
  identify the two historical numeric callbacks. Removed two unreferenced local
  base-menu builders duplicating Notebook work-area controls; public handlers
  and saved zone types remain intact. All 83 Lua regressions, affected syntax,
  and Workshop staging pass after cleanup. No Java or launcher change.

- Latest run `20260905-005316` repeatedly rejected attacks for `ks-world-4`
  with `NO_EQUIPPED_WEAPON`, reaching failure counts of 70 and above.
  The controller retried every threat scan even when its held item was unchanged.
- Added a 900-tick rejection cooldown across targets. Changing the held item
  immediately permits reevaluation and releases the related target suppression.
  Existing threat awareness, orders, and configured retreat policy remain active.
- All 83 Lua regressions, affected syntax, Java checks/build and Workshop staging
  pass. Live behavior remains pending. No launcher change is required.
- That run also contains context-menu numeric callback errors and two native
  ThumpState null-target exceptions; their exact initiating actions remain
  unproven and require further tracing. Its farming `select()` exception is
  already covered by the current Kahlua-compatible requirement builder/test.

### Legacy Patrol preference migration (2026-09-04)

- **Gap:** older resident records could retain `patrol_area` in
  `duty.jobPreference`, which is a directive spelling rather than the
  scheduler's canonical `patrol` role. Those residents could lose their
  intended recurring patrol preference after reload.
- **Fix:** `KnoxOrderCatalog.normalizeBasePreference` maps only the base
  preference boundary from `patrol_area` to `patrol`. Persistence migration,
  base-job selection, party display, and preference updates now use that helper;
  explicit companion patrol directives remain `patrol_area`.
- **Verification:** order-catalogue and order-routing regressions pass; affected
  Lua files pass syntax validation. Live migrated-save scheduling remains
  pending.
- **Status:** implemented; Lua/persistence-only change, so no launcher patch is
  required.

### Final player-facing command bypasses removed (2026-09-04)

- **Gap:** The medical-check helper and Notebook resident recall still called
  the lower-level command/base service directly.
- **Fix:** Both now use the canonical `issueOrder` boundary (`hold` and
  `return_to_base`), while their existing medical and resident behavior remains
  unchanged.
- **Verification:** Order-routing and full Lua regressions pass; syntax,
  Java/staging, and whitespace checks remain green. Live medical-check and
  Notebook recall clicks remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Useful-building roaming score (2026-09-04)

- **Gap:** independent roaming selected the nearest reachable building almost
  entirely by distance, so survivors could repeatedly choose low-value structures
  even when a larger residential or supplied building was nearby.
- **Fix:** the existing bounded roam scan now adds a small defensive usefulness
  score for rooms, building area, residential status, and available water. The
  score is only a tie-break against distance and danger; short-term destination
  memory, native movement, and the existing planner remain unchanged.
- **Verification:** roaming-autonomy regression, Lua syntax scan, and diff
  validation pass. Live multi-hour destination behavior remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Concrete base-task order handoff (2026-09-04)

- **Gap:** the task board already provided an ownership-checked `claimSpecific`
  operation, but the canonical player-order dispatcher could not reach it.
  Player-facing callers therefore needed a separate service path for a concrete
  resident task.
- **Fix:** added the `assign_base_task` catalogue action and routed it through
  `CompanionService.issueOrder` with an explicit `{ baseId, taskId }` payload.
  Existing task-board ownership, resident, eligibility, and atomic-claim checks
  remain authoritative; malformed requests fail closed.
- **Verification:** order-catalogue and order-routing regressions pass, Lua
  syntax checks pass, and `git diff --check` passes. Live assignment remains
  pending the settlement acceptance run.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Loaded away-team mission handoff (2026-09-04)

**Status: Implemented, focused verification passes, live mission verification pending.**

Resource teams can now cross from persisted `awaiting_collection` into one loaded-world executor.
The normal population reconciler still excludes away members; an explicit mission-only exception
restores a member at the loaded destination or durable return point and binds its controller to the
persisted away duty. The controller reuses the existing exploration and native inventory-transfer
path. Collection is acknowledged only after the action completes, and the executor records item
types only when the exact item is present in the survivor's real inventory. Empty valid searches
also acknowledge a member. A complete team enters the persisted returning phase, travels to its
return point, and restores previous duties only through the existing completion transition.

Mission members receive deterministic nearby offsets where practical, while unavailable cells and
failed returns remain bounded retries and cannot fall through into roaming, companion, or base work.

Focused verification:

- `tools/test-away-team-executor.lua` covers bounded destination directives, real transfer proof,
  collection acknowledgement, and return gating;
- `tools/test-away-teams.lua` covers the explicit population exception and controller binding;
- `tools/test-world-population.lua` covers existing away exclusion and population behavior;
- all mod Lua files parse with Lua 5.1 and the focused tests pass.

No launcher patch is required because this is Lua/persistence-only integration. Live verification
still needs a real resource team near a loaded destination, collection from a vanilla container,
return to its owner/base, and save/reload during each phase.

### Patrol progress migration without fixed route geometry (2026-09-04)

- **Defect:** save migration reduced every patrol's persisted step and completed
  stop count against a hard-coded four-point route. That could skip or reset
  progress when a saved work area produced a different number of distinct
  runtime waypoints.
- **Fix:** migration now keeps both counters finite and bounded, while
  `KnoxCompanionPatrol` remains the only owner that folds progress against the
  actual waypoint list when the patrol is resumed. No new scheduler or route
  representation was introduced.
- **Verification:** base-duty simulation regression, full Lua suite, Lua 5.1
  syntax scan, Java checks, Workshop staging, and whitespace validation pass.
  Live reload of a custom-sized patrol area remains pending.
- **Status:** implemented; Lua/persistence-only change, so no launcher patch is
  required.

### Resident work status projection (2026-09-04)

- **Defect:** a delayed controller refresh could leave a stale companion
  directive on a resident duty record. The Notebook/Card therefore reported the
  old companion activity instead of the resident's claimed base task.
- **Fix:** `KS_SurvivorViewModel` now treats base ownership as authoritative,
  projects the currently claimed task through the shared order catalogue, and
  falls back to the last normalized duty only when no task is active. The
  projection is read-only and does not add another command owner.
- **Verification:** survivor view-model and base-duty regressions, full Lua
  suite, Lua 5.1 syntax scan, Java checks, Workshop staging, and whitespace
  validation pass. Live Notebook refresh after a duty handoff remains pending.
- **Status:** implemented; Lua/UI-only change, so no launcher patch is
  required.

### Away-team multi-member collection gate (2026-09-04)

- **Defect:** a resource team's persistence boundary could transition from
  `collecting` to `returning` after only one member had reported supplies.
  Remaining members would still be assigned away duty while the team had
  already become eligible for completion.
- **Fix:** each member now records an explicit collection acknowledgement,
  including a valid empty search. `beginAwayTeamReturn` is accepted only when
  every listed member has acknowledged collection; item ledgers still contain
  only real executor-reported item types.
- **Verification:** away-team regression covers partial collection, empty-member
  completion, normal return, timeouts, and death races; full Lua/syntax, Java,
  Workshop staging, and whitespace checks pass. Loaded destination collection and
  physical return remain pending integration/live verification.
- **Status:** implemented; Lua/persistence-only change, so no launcher patch is
  required.

### Offline patrol phase rotation (2026-09-04)

- **Defect:** long unloaded patrol intervals advanced the next waypoint but left
  `patrolStopsCompleted` at its pre-interval value. The next loaded arrival could
  therefore reset the route at an inconsistent stop.
- **Fix:** off-screen patrol advancement now wraps both waypoint and stop phase
  against the actual runtime waypoint count. Guard relief behavior is unchanged.
- **Verification:** base-duty simulation regression covers three- and four-point
  routes, full Lua/syntax, Java, Workshop staging, and whitespace checks pass.
  Live unload/reload patrol continuity remains pending.
- **Status:** implemented; Lua-only duty simulation change, so no launcher patch
  is required.

### Durable away-team return point (2026-09-04)

- **Gap:** resource away teams persisted their destination but not the real
  dispatch-side return point. A loaded mission executor would have had to infer
  whether a team belonged back at a player position, base, or another owner.
- **Fix:** away-team creation now accepts and validates an optional return
  destination, persists it as integer XYZ data, and exposes a read-only lookup.
  The player-base scout handoff records the player's dispatch square; a base
  resident dispatch derives the center of its persisted territory when no
  explicit point is supplied. Older missions without either source remain
  valid and return `nil` until a caller can provide a point.
- **Verification:** away-team regression, full Lua/syntax checks, Java checks,
  Workshop staging, and whitespace validation pass. Loaded collection and
  physical return remain pending.
- **Status:** implemented; Lua/persistence-only change, so no launcher patch is
  required.

### Off-screen security shift rotation (2026-09-04)

- **Gap:** unloaded guard and patrol duties accumulated watch time but did not
  retain any rotation result, and elapsed periods longer than one shift silently
  discarded the additional watch time.
- **Fix:** the existing `KS_BaseDutySimulation` now preserves the fractional
  remainder, records every completed four-hour watch shift, counts guard relief,
  and advances a patrol task's next waypoint once per completed shift. No
  movement, loot, or resource state is fabricated off-screen; loaded patrols
  still use the native controller path.
- **Verification:** focused base-duty regression, full standalone Lua suite,
  `luac` syntax validation, and whitespace validation pass. Long-session
  save/load and live unloaded patrol rotation remain pending.
- **Status:** implemented; Lua-only settlement simulation change, so no launcher
  patch is required.

The same persistence boundary now clamps `offscreenShiftsCompleted` and
`guardReliefCount` when older or damaged task records are loaded, preventing
invalid counters from affecting later duty rotation.

### Expanded legacy order compatibility (2026-09-04)

- **Gap:** familiar labels such as `loot_dead_bodies`, `get_food`, `get_meds`,
  `guard_area`, `patrol`, and `cancel` were not consistently normalized at the
  shared order boundary.
- **Fix:** `KS_OrderCatalog` and the early persistence fallback now converge
  those labels to the current Knox directives and primary orders. Existing
  executors and the task board remain the only runtime owners.
- **Verification:** order-catalogue regression, full standalone Lua suite,
  `luac` syntax validation, and whitespace validation pass. Live context-menu
  use of every new compatibility label remains pending.
- **Status:** implemented; Lua-only vocabulary change, so no launcher patch is
  required.

### Persisted companion-order normalization (2026-09-04)

- **Defect:** a duty or directive written by an older menu could retain labels
  such as `explore`, `stand_ground`, or `go_find_food`. If the catalogue was
  not loaded yet during save restoration, the controller could receive an
  unknown order and leave the survivor without a valid persistent owner.
- **Fix:** the persistence normalization boundary now applies the same Knox
  order aliases used by the live catalogue, limits companion duties to the
  supported primary orders (falling back to Follow), forces base residents to
  `available`, and validates canonicalized directives before they reach the
  runtime controller. Invalid directives are discarded rather than restored as
  stale work.
- **Verification:** order-catalogue regression, full Lua suite, Lua syntax
  checks, Java build/verifiers, Workshop staging, and whitespace validation
  pass. Live migration from an older save remains pending.
- **Status:** implemented; Lua-only persistence compatibility change, so no
  launcher patch is required.

### Player-directed settlement task assignment (2026-09-04)

- **Gap:** The unified order catalogue exposed base job preferences, but the
  Notebook could not assign a specific queued work item to a chosen resident.
  Players therefore had to rely entirely on automatic selection, leaving the
  Superb-style direct-work command surface incomplete.
- **Fix:** The Work tab now lists the real residents of the player's base and
  provides a guarded `Assign` action for the selected queued task. Assignment
  enters through `KnoxCompanionService.assignBaseTask` and then routes through
  `KS_BaseTaskBoard.claimSpecific`, which verifies player-base
  ownership, queued state, resident eligibility, skill requirements, and the
  existing one-active-task invariant before calling atomic persistence claiming.
  The active runtime is notified after a successful claim; no second task
  manager or alternate execution path was introduced.
- **Verification:** Base-task-board and Notebook source regressions cover the
  guarded assignment boundary; full Lua tests, Lua syntax checks, Java
  build/staging, and whitespace validation remain the pass gate. Live task
  assignment and interruption/resume behavior remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Manual settlement work with automatic jobs disabled (2026-09-04)

- **Defect:** `beginBaseTask` rejected the entire base-work path when automatic
  jobs were disabled. A player-assigned queued task could therefore be claimed
  and persisted but never restored or executed.
- **Fix:** The controller now restores and runs an existing claimed task before
  checking the automatic-jobs setting. The setting gates only new automatic
  task selection; it no longer overrides an explicit player assignment.
- **Verification:** Source regression protects the ordering boundary; full Lua
  tests, syntax checks, Java build/staging, and diff validation pass. Live
  execution with automatic jobs disabled remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Explicit work versus Rest preference (2026-09-04)

- **Defect:** A resident's Rest preference could supersede a task explicitly
  assigned moments earlier, causing the task to be requeued before execution.
- **Fix:** Player-directed claims are marked `manual` at the task boundary. The
  controller restores those claims before evaluating Rest and honors them; Rest
  continues to release automatic claims as intended. The distinction is stored
  on the existing task record and does not add another scheduler or duty model.
- **Verification:** Base-task-board/controller regression coverage, full Lua
  tests, Lua syntax checks, Java build/staging, and diff validation pass. Live
  manual-task-versus-Rest behavior remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Manual assignment marker atomicity (2026-09-04)

- **Defect:** The manual-assignment marker was written before the persistence
  claim returned. A rejected or concurrent claim could leave a queued task
  mislabeled as explicit work.
- **Fix:** `KS_BaseTaskBoard.claimSpecific` now writes `manual=true` and clears
  the automatic marker only after the atomic claim succeeds. Failed claims leave
  the task unchanged.
- **Verification:** Task-board regression covers the post-claim write ordering;
  full Lua tests, syntax checks, Java staging, and diff validation pass.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Larger-settlement security coverage (2026-09-04)

- **Gap:** A growing settlement could expose only one guard post, leaving all
  security duty concentrated at the same entrance while residents rotated.
- **Fix:** Bases with four or more residents now receive a second ordinary
  `guard` zone at a separate deterministic outdoor post. It uses the existing
  task board, native movement, guard executor, and fairness rotation; no
  parallel security system or teleporting was added. Smaller bases keep the
  original single-post behavior.
- **Verification:** Base-management regression protects the resident threshold,
  duplicate guard-zone guard, and `Outer Watch` marker. Full Lua tests, syntax
  checks, Java staging, and diff validation pass. Live multi-post coverage and
  save/reload remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Established-settlement patrol coverage (2026-09-04)

- **Gap:** A large resident roster still shared one recurring patrol route,
  limiting perimeter coverage even when multiple residents were available.
- **Fix:** Bases with six or more residents now receive a second ordinary
  `patrol` zone (`Outer Patrol`) at a separate deterministic position. It uses
  the existing patrol waypoint, claim, rotation, and native movement paths;
  no new formation or scheduler was introduced.
- **Verification:** Base-management regression protects the six-resident
  threshold, duplicate-route guard, and patrol marker. Lua tests, syntax checks,
  Java staging, and diff validation pass. Live large-roster patrol coverage and
  save/reload remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Capability-aware resident duty selection (2026-09-04)

- **Gap:** Residents were rejected when they lacked a required skill, but two
  equally valid tasks otherwise competed only by queue priority and history.
  A capable worker could therefore be assigned an unrelated duty while a
  matching resident remained idle.
- **Fix:** `KS_BaseJobs.selectEligibleTask` now adds a small capped affinity
  bonus for the resident's persisted Build 42 skill profile. The bonus is only
  a tie-breaker: explicit preferences, shortage priority, security coverage,
  eligibility gates, and atomic claims remain authoritative. Unknown skills or
  profiles safely contribute zero.
- **Verification:** Base-job regression covers equal-priority security skill
  preference; full Lua tests, syntax checks, Java staging, and diff validation
  pass. Live multi-resident role distribution remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

Legacy task labels are normalized before the affinity lookup as well, so older
saved `woodcutting`, `farming`, or maintenance records receive the same skill
hint without changing their persisted identity or executor path.

### Base security summary feedback (2026-09-04)

- **Gap:** The unified Base tab reported residents, zones, and queued work but
  did not show whether the settlement had guard or patrol coverage.
- **Fix:** The existing Base header now includes enabled guard-post and patrol-
  route counts. It is derived directly from persisted zones, clipped through
  the existing viewport-safe label helper, and does not add a second status or
  security model.
- **Verification:** Base-management UI regression, Lua syntax, diff checks,
  Java staging, and Workshop staging pass. Live rendering at alternate
  resolutions remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Resident active-duty feedback (2026-09-04)

- **Gap:** The Residents tab showed a base role and profession but not the
  concrete task currently claimed by that resident, making settlement work
  difficult to follow from the player-facing screen.
- **Fix:** Resident rows now derive the claimed task from the persisted base
  task board and render its canonical Knox label, falling back to `Idle` when
  no task is active. This is read-only presentation; task ownership and
  execution remain unchanged.
- **Verification:** Base-management UI regression, Lua syntax, diff checks,
  Java staging, and Workshop staging pass. Live refresh timing remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

The Base header now reports staffed security as `active/available` for guard
posts and patrol routes, making an understaffed settlement visible without
changing the scheduler or creating a second security state.

### Legacy settlement task normalization (2026-09-04)

- **Gap:** Persisted or manually-created work records could retain older task names
  such as `woodcutting`, `corpse_cleanup`, or `storage_sorting`, while current Knox
  executors expect canonical task types. Those records could survive but be skipped by
  the modern scheduler.
- **Fix:** Added a bounded task-type compatibility map to `KS_OrderCatalog`, applied it
  when queuing new work and while normalizing persisted tasks. Migrated signatures retain
  their target portion, preventing duplicate work records. No old executor code was copied.
- **Verification:** Order-routing and base-task-board regressions pass, the full Lua suite
  passes with zero failures, all Lua files parse with Lua 5.1, Workshop staging succeeds,
  and `git diff --check` is clean. Live migration and resident execution remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Unified player-facing order catalogue (2026-09-04)

- **Gap:** Companion and party dispatch already shared `KS_OrderCatalog`, but several
  party, vehicle, traversal, recruitment, and base-management labels were still hardcoded
  in individual menus. That made the visible command vocabulary drift from the canonical
  order boundary.
- **Fix:** Added presentation-only action entries to `KS_OrderCatalog` and routed the
  affected menus through `KnoxOrderCatalog.label`. Existing handlers, persistence, and
  executors remain unchanged; no second task manager or dispatch path was introduced.
- **Verification:** Order-routing and vehicle regressions pass, the full Lua suite passes
  with zero failures, all Lua files parse with Lua 5.1, and `git diff --check` is clean.
  Live menu rendering remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Canonical task-label collision guard (2026-09-04)

- **Gap:** `barricade` is both a concrete task name and a legacy alias for the
  broader woodwork preference. Alias-first lookup could show the wrong label in
  a player menu even though dispatch remained valid.
- **Fix:** Catalogue lookup now prefers exact canonical entries, then applies
  compatibility aliases only when no exact entry exists. Task dispatch continues
  to use the dedicated task-type normalizer.
- **Verification:** Order-catalogue and full Lua tests pass, all Lua files parse,
  Workshop staging succeeds, and diff validation is clean. Live menu rendering
  remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Automatic settlement task admission (2026-09-04)

- **Gap:** the automatic-duty allow-list lagged behind the settlement
  executors already present. Newer wood processing, corpse hauling, animal
  care, repair, and defense-construction tasks could be queued without being
  admitted through the same automatic zone boundary.
- **Fix:** `KS_BaseJobs.AUTOMATIC_TYPES` now includes those supported task
  types. Task creation, requirements, atomic claims, and native actions remain
  owned by the existing systems; no second scheduler or abstract resource
  simulation was introduced.
- **Verification:** the base-jobs regression now asserts admission for every
  supported task type. Full Lua tests, syntax validation, Java build/staging,
  and whitespace checks are run for this pass. Live multi-resident duty
  rotation and save/reload continuity remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Party menu settlement-order convergence (2026-09-04)

- **Gap:** the party context menu exposed companion orders but did not provide
  a direct, catalogue-backed way to set the player base residents' shared work
  preference.
- **Fix:** added a `Base Work Orders` submenu that iterates the canonical
  `KnoxOrderCatalog.basePreferenceOrder` and dispatches through
  `KnoxCompanionService.issueOrderAll`. Existing resident ownership checks and
  preference persistence remain authoritative.
- **Verification:** order-routing regression, full Lua suite, syntax scan,
  Java build/verifiers, Workshop staging, and diff validation pass. Live menu
  selection and resident duty rotation remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Settlement access without an active companion (2026-09-04)

- **Gap:** the party context entry was hidden when a player had no current
  followers, even when that player already owned a base with resident
  survivors. This made the new base-work order surface inaccessible to a
  legitimate settlement-only roster.
- **Fix:** the existing context-menu gate now permits the party/settlement
  entry when at least one player-base resident exists, while preserving the
  original companion requirement for players without either roster.
- **Verification:** order-routing regression, full Lua suite, syntax check,
  Workshop staging, and diff validation pass. Live context-menu visibility and
  base-resident order selection remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Shared settlement preference feedback (2026-09-04)

- **Gap:** the party-level base-work menu could issue a preference but did not
  show which persisted preference the resident roster currently shared.
- **Fix:** menu entries now derive the common normalized preference from the
  authoritative resident duty records and mark that entry selected when the
  roster agrees. Mixed rosters intentionally show no selection.
- **Verification:** order-routing regression, full Lua suite, syntax checks,
  Workshop staging, and diff validation pass. Live visual confirmation remains
  pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Bounded resource-mission expiry (2026-09-04)

- **Gap:** a resource away team with no loaded destination executor could remain
  in `awaiting_collection` forever, retaining away ownership and making its
  members unavailable for normal settlement life.
- **Fix:** after 72 in-game hours in that state, persistence moves the team to a
  durable `blocked` result, records `collection_timeout`, preserves any already
  recorded resource ledger, and restores each member's previous duty. No loot
  is generated and no collection is treated as successful.
- **Verification:** away-team regression, full Lua suite, syntax scan,
  Workshop staging, and diff validation pass. Live timeout/recovery behavior
  remains pending; the real loaded collection executor is still a separate
  milestone.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Rest preference releases persisted settlement claims (2026-09-04)

- **Defect:** changing a resident to the Rest preference while a previously claimed
  base task was only present in the persisted task board could drop the controller's
  pointer without releasing the durable claim. The task then remained owned by a
  resting survivor and could not rotate to another worker.
- **Fix:** the existing autonomy boundary now requeues all claims for that survivor
  through `KnoxPersistence.requeueBaseTasksForSurvivor` before entering ambient base
  recovery. Task identity, requirements, and retry metadata remain owned by the
  existing task board; no second scheduler was added.
- **Verification:** focused base-needs regression, full Lua tests, Lua syntax checks,
  and `git diff --check` pass. Live menu-to-rest and multi-resident rotation remain
  pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Notebook base-duty dispatch convergence (2026-09-04)

- **Gap:** the Residents tab wrote base-job preferences directly to persistence,
  bypassing the canonical companion/order service used by the context menu and
  party controls. The preference saved, but loaded controllers did not receive
  the same duty-change notification or acknowledgement path.
- **Fix:** the notebook now sends the selected preference through
  `KnoxCompanionService.issueOrder`. The service remains responsible for
  ownership validation, persistence, resident requeue behavior, feedback, and
  runtime notification; no second task manager or order state was introduced.
- **Verification:** base-setup UI regression, full Lua tests, Lua syntax checks,
  Java build/staging, and diff validation pass. Live notebook interaction remains
  pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Persisted active-duty coverage in task selection (2026-09-04)

- **Gap:** automatic selection normally receives only queued tasks, so its
  security and work-type balancing could not see already-claimed duties from
  the persisted base. A resident could therefore be assigned another guard
  post even when coverage already existed, or the settlement could repeatedly
  favor one work type.
- **Fix:** `KS_BaseJobs.selectEligibleTask` now supplements the queued snapshot
  with claimed records from the authoritative persisted base, de-duplicated by
  task ID. Claimed work affects only coverage/fairness scoring; only queued
  records remain eligible for a new atomic claim.
- **Verification:** base-job regression now covers an active persisted watch
  omitted from the queued snapshot; full Lua tests, syntax checks, Java
  build/staging, and diff validation pass. Live multi-resident balancing remains
  pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Legacy order labels at the task boundary (2026-09-04)

- **Gap:** direct task-board callers could pass older player-facing labels such
  as `barricade`, while the canonical scheduler expected `woodwork`. This could
  silently skip a resident's intended preferred work even though the order
  catalogue already knew the alias.
- **Fix:** `KS_BaseJobs.selectEligibleTask` normalizes the preference before
  calculating preferred passes and task-group matches. Execution and persistence
  ownership remain unchanged.
- **Verification:** base-job regression covers legacy-label selection; full Lua
  tests, syntax checks, Java build/staging, and diff validation pass. Live menu
  selection remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Player-base defense work-area default (2026-09-04)

- **Gap:** the automatic default-zone pass gave player bases farming, wood,
  repair, guard, patrol, and corpse areas, but no construction perimeter. A
  recruited resident therefore had no default place to perform the existing
  native defense-construction executor unless the player created a zone by hand.
- **Fix:** `KS_BaseManager.ensureFactionZones` now adds one guarded
  `construction` area around the saved territory when neither construction nor
  defense is already configured. Faction-specific perimeter records and manual
  zones remain authoritative; no structures or materials are created.
- **Verification:** base-setup regression, full Lua tests, syntax checks, Java
  build/staging, and diff validation pass. Live construction task discovery and
  native building remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Trough-aware animal-care area default (2026-09-04)

- **Gap:** the real animal-care executor could already water or feed a vanilla
  trough, but automatic base setup never created an animal-care area. Animal
  settlements therefore required manual zone configuration even when a trough
  was inside the claimed territory.
- **Fix:** default-zone setup now scans the saved base bounds for an actual
  `IsoFeedingTrough` and adds a small guarded care area around it. Bases without
  a trough receive no animal zone, and existing/manual zones remain untouched.
- **Verification:** base-setup regression, full Lua tests, syntax checks, Java
  build/staging, and diff validation pass. Live trough watering/feeding remains
  pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Claimed-task selector safety (2026-09-04)

- **Defect:** a scheduler snapshot containing a stale `claimed` record could
  still score that task as a new candidate, allowing a second resident to be
  offered work already owned by someone else.
- **Fix:** `KnoxBaseJobs.selectEligibleTask` now counts claimed work for coverage
  and fairness but only considers queued (or legacy state-less) records for new
  selection. Atomic persistence claiming remains the final ownership guard.
- **Verification:** base-job regression covers claimed-task exclusion; full Lua
  suite, Lua syntax, Java build/verifiers, Workshop staging, and diff validation
  pass. Live concurrent resident scheduling remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Canonical labels in individual companion menu (2026-09-04)

- **Gap:** the party menu used catalogue labels, but the individual context
  menu still hard-coded several primary and movement order names.
- **Fix:** Follow, Hold, Relax, Move, Guard, and Patrol now read their labels
  from `KS_OrderCatalog`, keeping both player-facing surfaces on the same Knox
  vocabulary while preserving their existing callbacks and order semantics.
- **Verification:** full Lua regression suite and Lua syntax checks pass;
  Java build/verifiers and Workshop staging pass. Live menu presentation remains
  pending. No launcher patch is required.
- **Status:** implemented.

### Expanded familiar order aliases (2026-09-04)

- **Improvement:** common player terms such as Search, Loot, Escort, and Defend
  now resolve to the existing Knox Explore, Follow, Hold, or Guard behaviors.
- **Boundary:** these remain vocabulary aliases only; they do not add a second
  task system or alter execution ownership.
- **Verification:** order-catalogue regression, Lua syntax check, Java build,
  runtime verifiers, Workshop staging, and diff validation pass. No launcher
  patch is required.

### Persisted duty canonicalization (2026-09-04)

- **Defect:** callers outside the companion UI could write a legacy base-role
  label directly, leaving a save with a preference that was readable but not
  canonical.
- **Fix:** persistence now normalizes valid base preferences both when saving a
  new role and while normalizing an existing survivor record. The task board,
  profession hinting, and fairness selector therefore see the same role value
  regardless of which UI or migration path produced it.
- **Verification:** full Lua suite, Lua syntax checks, Java build/verifiers,
  Workshop staging, and diff validation pass. Live save migration remains
  pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

## Superb-style order vocabulary convergence (2026-09-04)

- **Gap:** the rebuilt companion layer had the execution pieces for familiar
  survivor activities, but callers using names such as `explore`, `go_find_food`,
  or `stand_ground` could be rejected or routed inconsistently.
- **Fix:** added a small Knox-owned alias vocabulary in `KS_OrderCatalog`. Aliases
  normalize to the existing canonical orders (`loot_area`, `find_food`, `hold`,
  `woodwork`, `farming`, `hauling`, and so on) before validation, persistence,
  or directive creation. Individual
  and party dispatch now normalize at the same boundary, so old menu wording and
  future notebook controls converge without importing the legacy task system.
  Base-job preference aliases are canonicalized before persistence as well, so a
  legacy label cannot leave a resident with a second, non-matching duty value.
- **Verification:** alias, directive-normalization, companion-dispatch, and
  party-order regressions pass; all Lua tests pass with zero failures; all mod
  Lua files pass `luac -p`; Java build, runtime verifiers, and Workshop staging
  pass. Live menu execution remains pending.
- **Status:** implemented; Lua-only compatibility work, so no launcher patch is
  required. The old Superb source was not modified or copied.

### Settlement duty migration normalization (2026-09-04)

- **Defect:** a migrated resident could retain a familiar legacy role label in
  its duty record. Although task matching understood some aliases, the
  scheduler could still make a role decision from the non-canonical value.
- **Fix:** `KnoxBaseJobs.effectivePreference` now normalizes valid legacy labels
  before applying profession hints, preference matching, fairness, and fallback
  selection. Persistence remains the single owner of the duty record.
- **Verification:** base-job and order-catalogue regressions, full Lua suite,
  Lua syntax checks, Java build/verifiers, Workshop staging, and diff validation
  pass. Live resident rotation and save/reload migration remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.
## Settlement candidate recovery and ownership safety (2026-09-04)

- **Defect:** faction base scouting could retain one stale candidate indefinitely, and could select a building whose footprint overlapped an existing persisted Knox base.
- **Fix:** candidate leads now expire after a bounded 72 in-game hours so the leader can rescan; scouting rejects buildings overlapping any persisted base territory/home before scoring them. Existing safehouse and candidate-rejection rules remain authoritative.
- **Verification:** faction persistence/camp tests pass; full Lua syntax, Lua regression suite, and Java packaging checks pending in this pass.
- **Status:** implemented; live in-game scouting and base conversion remain pending verification.

## Off-screen faction shelter handoff timeout (2026-09-04)

- **Defect:** an unloaded faction stopped at its cached shelter-scoping anchor and could remain there indefinitely if the cell never streamed in, freezing its off-screen progression.
- **Fix:** the existing shared cohort now keeps the shelter handoff for 48 in-game hours, then releases it and selects another cached origin while preserving the faction and group records. No building or resources are fabricated off-screen.
- **Verification:** unloaded-group regression covers the pause and bounded release; affected Lua tests and syntax checks pass. Live materialization remains pending.
- **Status:** implemented; no launcher patch is required.

## Initial population group distribution (2026-09-04)

- **Gap:** opening groups were formed only from the identities allocated in the player's nearest start region. Compact spawn clusters in other regions always began as isolated survivors even when they were close enough to travel together.
- **Fix:** the existing bounded group-forming pass now considers every identity allocated during initial population. It still uses the configured chance, maximum size, compact-distance check, and group-count cap, so this increases social clustering without increasing the population or creating an army.
- **Verification:** world-population regression, full Lua suite, syntax checks, and whitespace validation pass. Live distribution across a fresh world remains pending.
- **Status:** implemented; Lua-only, no launcher patch required.

## Faction base ownership reconciliation (2026-09-04)

- **Defect:** a stale `homeBaseId` could resolve to a real base record owned by a player or another faction. The resident handoff would then fail closed, but the faction could remain attached to the wrong base record.
- **Fix:** `ensureFactionBase` now validates owner kind and owner id before using an existing record. Mismatches clear only the stale faction pointer and rebuild the faction-owned base from its persisted home definition.
- **Verification:** base-management source regression covers the stale-owner guard; faction persistence/camp tests, full Lua suite, Lua syntax, Java build/staging, and whitespace validation pass.
- **Status:** implemented; live restore from a deliberately stale save remains pending.

Save normalization now clears invalid faction `homeBaseId` links while preserving
the durable home definition for `KS_BaseManager` to rebuild on startup.

## Faction storage category completion (2026-09-04)

- **Defect:** automatic faction storage stopped as soon as any storage policy existed, so a partially configured or migrated base could never receive missing depot, tools, weapons, medical, building, farming, or clothing categories.
- **Fix:** storage initialization now preserves every existing policy and fills only uncovered categories from additional real containers in the territory. It still never creates containers or supplies and remains bounded to the existing scan.
- **Verification:** base-management source regression and Lua syntax checks pass; full Lua suite remains green. Live storage assignment remains pending.
- **Status:** implemented; Lua-only, no launcher patch required.

The fallback sequence also covers food and water when a base has ordinary
containers but no fridge, freezer, or dedicated water container.
Rain collectors and other water-named containers are now classified as water
storage automatically as well.

## Unified party order dispatch (2026-09-04)

- **Defect:** individual companion orders were validated through
  `KnoxOrderCatalog`, but party-wide context-menu actions still called several
  lower-level helpers directly. This left the group command surface with a
  second routing path and made future order additions easy to wire only for one
  companion or one menu.
- **Fix:** `KnoxCompanionService.issueOrderAll` now validates the same canonical
  catalogue and routes primary orders, return-to-base, resume, directives, and
  player-base job preferences through their existing owners. `KS_PartyCommands`
  uses that boundary for follow, hold, relax, return, directive, and resume
  actions. No new task manager, order state, or execution system was added.
- **Verification:** companion-command and order-catalogue regressions pass;
  the complete Lua test suite passes with zero failures and `git diff --check`
  is clean. Live party-menu execution and multi-resident preference changes
  remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Log-processing work-area integration (2026-09-04)

- **Gap:** Base Setup exposed a `log_processing` work area, but the automatic
  wood/log finder only searched `woodcutting` zones. A saved saw area could
  therefore exist without producing a resident task.
- **Fix:** `KS_BaseWoodcutting` now includes both existing zone types in the
  same native log/saw path while keeping their intent distinct: woodcutting
  searches trees, and log processing searches the saw recipe (with a woodlot
  fallback for older bases that have no dedicated saw area). Recipe validation,
  real log consumption, timed crafting, and task ownership remain unchanged;
  no second scheduler was added.
- **Verification:** Base-job regression now covers a `log_processing` zone;
  full Lua tests, Lua syntax checks, Java build/staging, and diff validation
  are the pass gate. Live saw-bench execution remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

The automatic base-area defaults now also create a small dedicated Log Processing
area beside the Wood Lot for new player and faction bases. Existing manually
configured areas are preserved.

### Base-supply return and storage handoff (2026-09-04)

- **Gap:** When a base resident left to recover food, water, or medical supplies,
  the real item stayed in personal inventory after the resident returned. The
  shortage loop could therefore send another resident out even though the first
  run had succeeded.
- **Fix:** A successful base-supply search now records the recovered real item,
  returns through the normal base duty, and queues one native inventory transfer
  into the nearest assigned category/depot container. The marker survives
  temporary combat or action interruption, persists the item type through the
  existing life-intent record for save/reload recovery, clears only after the
  destination contains the item, and fails cleanly when the item is gone.
  Missing storage remains a bounded retry rather than an invented stockpile;
  ordinary personal cleanup remains separate.
- **Verification:** The base-needs regression covers the explicit return-deposit
  boundary; the full Lua test suite and Lua syntax checks pass. Live shortage,
  return, and save/reload behavior remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Staged faction shelter scouting (2026-09-04)

- **Gap:** Loaded faction scouting searched only a 30-tile square. A group could
  abandon settlement selection even when a suitable nearby building was just
  outside that first block.
- **Fix:** `KS_FactionBaseScouting` now searches staged outer rings of 30, 60,
  and 90 tiles, stopping after the first ring that yields a valid candidate.
  The wider rings do not rescan the inner area and retain the existing room,
  accessibility, vanilla safehouse, persisted-base overlap, rejection-memory,
  and nearest-exterior-square checks.
- **Verification:** Added a focused staged-radius/ownership-safety regression;
  full Lua tests, syntax checks, Java build/staging, and whitespace validation
  are the remaining pass gate. Live multi-ring scouting is still pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Settlement shortage priority handoff (2026-09-04)

- **Gap:** A base resident with no active task could claim ordinary guard or
  production work before checking whether the settlement had a real food, water,
  medical, weapon, or tool shortage.
- **Fix:** The existing shortage lease is now considered before selecting a new
  base task. A successful search still uses the normal loaded-world loot,
  return, and native storage-deposit path. A task already claimed by a resident
  is never interrupted; this only changes the next-duty decision boundary.
- **Verification:** Base-needs regression now protects the ordering boundary;
  full Lua tests, syntax checks, Java build/staging, and whitespace validation
  pass. Live shortage-versus-duty behavior remains pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Settlement task ownership release (2026-09-04)

- **Defect:** completed or reassigned tasks could retain `claimedBy` and the
  `manual` marker after the resident stopped owning them. This made finished
  work appear assigned and could prevent clean automatic rotation.
- **Fix:** task completion now releases claimant ownership while retaining only
  `lastClaimedBy` for fairness. Duty changes requeue the task and clear both
  manual and automatic ownership markers before another resident can claim it.
- **Verification:** base-task-board regression, full Lua suite, Lua syntax
  checks, Java build/verifiers, Workshop staging, and whitespace validation
  pass. Live multi-resident rotation remains pending.
- **Status:** implemented; Lua-only settlement lifecycle change, so no launcher
  patch is required.

### Unified resident work-status projection (2026-09-04)

- **Gap:** the Notebook could only find a loaded claimed task directly in the
  base task table. Residents working through the unloaded-duty path appeared
  as `Idle`, hiding real guard/patrol progress from the player.
- **Fix:** persistence now exposes a read-only resident work-status projection
  from the existing claimed task and last-job fields. The Residents tab uses it
  for both loaded and off-screen members, showing the canonical work label and
  an explicit off-screen marker without creating another scheduler or status
  store.
- **Verification:** base-task-board and Notebook source regressions, full Lua
  tests, Lua syntax checks, Java build/verifiers, Workshop staging, and
  whitespace validation pass. Live off-screen status refresh remains pending.
- **Status:** implemented; Lua-only presentation integration, so no launcher
  patch is required.

### Animal-care task admission boundary (2026-09-04)

- **Defect:** an enabled `animal_care` work area could fall through the generic
  automatic-zone loop and create a plain `animal_care` task. The controller only
  executes the concrete `animal_water` and `animal_feed` actions produced after
  a real trough/item check, so the generic record was unsupported and could be
  claimed and blocked repeatedly.
- **Fix:** automatic zone admission now excludes `animal_care` from the generic
  queue. The existing animal-care finder remains responsible for emitting only
  concrete water/feed tasks when a loaded trough genuinely needs service. No
  second scheduler or simulated animal stock was added.
- **Verification:** full 79-test Lua suite passes; all mod Lua files pass Lua 5.1
  syntax validation; `gradlew.bat stageWorkshop` succeeds; `git diff --check`
  reports no errors. The old Superb reference tree remains untouched. Live trough
  servicing and multi-resident rotation remain pending.
- **Status:** implemented; Lua-only settlement change, so no launcher patch is
  required.

### Legacy animal-care task migration (2026-09-04)

- **Defect:** saves created before the animal-care admission guard could still
  contain a generic `animal_care` task. Scheduler filtering alone did not repair
  that persisted record, leaving a stale task available to later controllers.
- **Fix:** save normalization now converts a legacy record when its target carries
  the concrete `animal_water` or `animal_feed` action. A record without that
  information is retired as `cancelled`, releases any claimant, and is never
  reopened as executable work. The existing native trough finder remains the
  only creator of new animal tasks.
- **Verification:** full 79-test Lua suite passes; all mod Lua files pass Lua 5.1
  syntax validation; `gradlew.bat stageWorkshop` succeeds; `git diff --check`
  reports no errors. Live migration and trough servicing remain pending.
- **Status:** implemented; Lua-only persistence hardening, so no launcher patch is
  required.

### Persistence-side task vocabulary guard (2026-09-04)

- **Gap:** normal task-board calls already normalized legacy names, but direct
  persistence callers could bypass that boundary and save `haul`, `construction`,
  or another historical label as a new task.
- **Fix:** `KnoxPersistence.queueBaseTask` now canonicalizes the task type before
  signature creation and storage. The task board remains the ordinary routing
  surface, while persistence now guarantees that alternate callers cannot create
  a second executable vocabulary.
- **Verification:** full 79-test Lua suite passes; all mod Lua files pass Lua 5.1
  syntax validation; `gradlew.bat stageWorkshop` succeeds; `git diff --check`
  reports no errors. Live task creation through the in-game UI remains pending.
- **Status:** implemented; Lua-only order/work integration, so no launcher patch is
  required.

### Canonical settlement fairness accounting (2026-09-04)

- **Defect:** task preference matching already normalized legacy task names, but
  active-work counts, security coverage, previous-duty rotation, skill hints, and
  repeat penalties still compared raw `task.type` values. A migrated `haul` or
  `storage_sorting` record could therefore evade fairness accounting and make a
  resident receive duplicate work or hide an existing watch post.
- **Fix:** `KS_BaseJobs.selectEligibleTask` now canonicalizes task types at every
  scheduler comparison while leaving the persisted record and executor boundary
  unchanged. Legacy labels share the same active counts, security coverage, skill
  affinity, last-duty rotation, and repeat penalties as current task names.
- **Verification:** `tools/test-base-jobs.lua` passes, including a regression with
  active legacy storage work and queued legacy/current equivalents. Full Lua suite,
  Lua syntax, Java/staging, and whitespace checks remain the pass gate. Live
  multi-resident rotation and save/reload behavior remain pending.
- **Status:** implemented; Lua-only settlement scheduling change, so no launcher
  patch is required.

### Loaded/unloaded duty vocabulary parity (2026-09-04)

- **Gap:** loaded resident scheduling normalized legacy task labels, but the
  off-screen duty simulator still checked raw names when deciding whether a
  completed watch task should be requeued. A migrated `patrol_area`/legacy
  equivalent could finish off-screen without returning to the recurring duty
  queue.
- **Fix:** `KS_UnloadedSurvival` now uses the same `KnoxOrderCatalog` task-type
  normalization before applying guard/patrol requeue behavior. The existing
  persistence and duty-simulation owners remain unchanged.
- **Verification:** unloaded-survival regression, full Lua suite, and Lua 5.1
  syntax checks pass. Java/staging and whitespace checks are the remaining pass
  gate; live unloaded watch rotation remains pending.
- **Status:** implemented; Lua-only settlement parity change, so no launcher
  patch is required.

### Order-catalogue legacy boundary (2026-09-04)

- **Gap:** internal scheduler callers normalized legacy task names, but the
  public order catalogue did not. Direct UI or compatibility callers passing
  `storage_sorting`, `haul`, or another historical label could receive no base
  preference even though the same task was executable.
- **Fix:** `KS_OrderCatalog.preferenceForTask` and
  `preferenceMatchesTask` now normalize task types at their public boundary.
  All order, scheduler, and compatibility callers therefore resolve the same
  hauling/farming/woodwork/security preference without adding another dispatch
  path.
- **Verification:** order-catalogue regression and the full Lua suite pass;
  Lua 5.1 syntax, Java verification, Workshop staging, and whitespace checks
  pass. Live menu execution remains pending.
- **Status:** implemented; Lua-only order compatibility change, so no launcher
  patch is required.

### Canonical shortage prioritization (2026-09-04)

- **Gap:** settlement shortage bonuses compared raw task names. A migrated
  `farming` or `maintenance` task could therefore miss the food, water, or
  building-material urgency adjustment even though the executor vocabulary had
  already been normalized elsewhere.
- **Fix:** `KS_BaseNeeds.priorityBonus` now canonicalizes task types through the
  shared order catalogue before applying shortage priorities. It changes only
  scoring; real storage inspection, task claims, and native work execution stay
  owned by their existing systems.
- **Verification:** base-needs regression now covers a legacy farming task;
  full Lua suite and Lua 5.1 syntax checks pass. Java/staging and whitespace
  checks remain the pass gate; live shortage-driven resident assignment is
  pending.
- **Status:** implemented; Lua-only settlement scheduling change, so no
  launcher patch is required.

### Fresh physical-task lease on claim (2026-09-04)

- **Defect:** an automatic physical task released after an unloaded wait could
  retain its previous `offscreenWaitHours`. When reclaimed, it could therefore
  be released again almost immediately before the resident had a chance to
  execute the native world action.
- **Fix:** `KnoxPersistence.claimBaseTask` resets the off-screen wait lease at
  the atomic claim boundary and records the canonical task type as the
  resident's rotation hint. Manual assignments and native execution remain
  unchanged.
- **Verification:** base-task-board regression, full Lua suite, Lua 5.1 syntax,
  Java verification, Workshop staging, and whitespace checks pass. Live unload,
  reclaim, and physical task execution remain pending.
- **Status:** implemented; Lua-only persistence/task-boundary change, so no
  launcher patch is required.

### Action-field fallback for shortage scoring (2026-09-04)

- **Gap:** a small set of early persisted task records can lack `type` while
  retaining the concrete executor action in `target.action`. Those tasks could
  be selected, but would miss the existing food/water/building shortage bonus.
- **Fix:** `KS_BaseNeeds.priorityBonus` now uses `target.action` only when the
  task type is absent, then applies the normal shared task normalization. It
  does not create a new task record or change executor ownership.
- **Verification:** base-needs regression covers a missing-type farming record;
  full Lua suite, Lua 5.1 syntax, Java verification, Workshop staging, and
  whitespace checks pass. Live legacy-save scheduling remains pending.
- **Status:** implemented; Lua-only compatibility change, so no launcher patch
  is required.

### Persistence-first legacy order fallback (2026-09-04)

- **Gap:** persistence can initialize before `KS_OrderCatalog.lua`. In that
  load order, older `return_home`, `go_home`, `rest`, and `recover` orders,
  plus `patrol_area` task records, could bypass the catalogue and remain
  non-canonical until a later controller refresh.
- **Fix:** the persistence-local fallback maps now cover those legacy order
  labels and converge `patrol_area` to the existing recurring `patrol`
  executor. The catalogue remains authoritative when loaded; this only makes
  early-save migration deterministic and does not add a scheduler or task
  implementation.
- **Verification:** order-catalogue regression, full Lua suite, Lua 5.1
  syntax checks, Java verification, Workshop staging, and whitespace checks
  pass. Live migrated-save restoration remains pending.
- **Status:** implemented; Lua-only persistence compatibility change, so no
  launcher patch is required.

The fallback now also covers the remaining search, inventory, barricade,
farming, woodwork, hauling, and corpse-cleanup labels used by early menus.
The full Lua suite and whitespace validation were rerun after that alignment;
live migrated-save restoration remains the only pending evidence for this
boundary.

### Off-screen physical-task lease reachability (2026-09-04)

- **Defect:** the unloaded-survival loop had a dead branch for physical base
  work. Its claim-release code referenced per-survivor task, duty, state, and
  elapsed values outside their scope, and the generic stored-survivor branch
  matched first. Automatic physical claims could therefore remain reserved
  indefinitely while their world square was unloaded.
- **Fix:** `KS_UnloadedSurvival.advanceAll` now resolves each survivor's base
  duty, stored state, and claimed task inside the per-survivor loop, sends
  ordinary stored survivors through physiology only when no physical claim is
  present, and applies the existing bounded twelve-hour automatic release to
  the resolved claim. Manual assignments remain preserved.
- **Verification:** unloaded-survival regression, full Lua suite, Lua 5.1
  syntax checks, Java verification, Workshop staging, and whitespace checks
  pass. Live unload/reload claim handoff remains pending.
- **Status:** implemented; Lua-only unloaded-settlement fix, so no launcher
  patch is required.

The same boundary now persists the resident's `base_working`/`base_life`
activity after each off-screen lease update, keeping Notebook and activity
views consistent with the durable claim. Focused unloaded-survival coverage,
the full Lua suite, and diff validation pass; live unloaded UI confirmation
remains pending.

The lease calculation was then tightened to treat `advanceAll`'s argument as
absolute world age, matching the existing physiology and origin-travel APIs.
Each physical claim keeps its own `offscreenLastHours`, so only newly elapsed
time contributes to the twelve-hour handoff and normal hibernated survivors
continue advancing to the requested world-age target.

The unloaded-survival regression now exercises this branch with a claimed
physical task and verifies the release context, blocked transition, persisted
`base_life` activity, and timestamp update rather than relying only on source
inspection.

The atomic claim boundary also resets `offscreenLastHours`, preventing a
reclaimed task from inheriting timing from a previous unloaded attempt.

### Shared settlement security accounting (2026-09-04)

- **Gap:** the work scheduler normalized legacy guard/patrol labels, but the
  Notebook calculated zone and staffed-post counts independently. A migrated
  `patrol_area` record could therefore display an unstaffed or overstaffed
  settlement even when the task board had the correct ownership.
- **Fix:** `KS_BaseJobs.securityCoverage` now owns the small guard/patrol
  accounting boundary. It normalizes legacy zone/task labels, counts enabled
  posts and routes, and returns staffed/available totals. The Notebook consumes
  that result; task selection and native executors remain unchanged.
- The same helper now ignores duplicate persisted task IDs, matching the
  scheduler's existing duplicate guard when recovering damaged or migrated
  settlement records.
- **Verification:** base-job coverage regression, full Lua suite, Lua 5.1
  syntax checks, Java verification, Workshop staging, and whitespace checks
  pass. Live migrated-base Notebook rendering remains pending.
- **Status:** implemented; Lua-only settlement presentation alignment, so no
  launcher patch is required.

Security coverage also now reports the resident-count-based required watch
level and understaffed count. The Notebook shows this as a compact staffed
summary while preserving the separate guard-post and patrol-route totals.

### Explicit resource-mission return handoff (2026-09-04)

- **Gap:** resource away teams could be completed directly from `collecting`,
  leaving no durable boundary between destination work and the native return
  trip. That made the team state ambiguous for the Notebook and loaded
  movement executor.
- **Fix:** `KnoxPersistence.beginAwayTeamReturn` now transitions a collecting
  team to `returning` only after a real collection ledger exists. Member
  completion accepts that existing state and still restores prior duties only
  after every member has returned. No movement or supplies are simulated.
- **Verification:** away-team lifecycle regression, full Lua suite, Lua 5.1
  syntax checks, Java verification, Workshop staging, and whitespace checks
  pass. Native destination search, return travel, and deposit remain live
  integration work.
- The read-only progress snapshot now also reports collected item count,
  participating members, total members, and collection progress without
  mutating the mission.
- **Status:** implemented; Lua-only persistence boundary, so no launcher patch
  is required.

The next resource-mission step is deliberately still unimplemented: there is
currently no loaded-world materialization owner that can safely reconstruct an
away member at the destination, run the existing native loot/transfer action,
and hand the member back to the persisted return state. Adding a second
executor here would risk duplicate bodies or fabricated resources, so this
boundary remains an explicit implementation gate rather than a speculative
patch.

The runtime review confirms that gate is architectural: away members are
excluded from normal population activation, and the loaded autonomy controller
has no resource-mission duty mode. The next implementation must therefore add
one coordinated materialization/restore boundary that reuses the existing
controller and native transfer actions; a standalone collector would violate
the current shell-ownership rules.

### Shared settlement shortage selection (2026-09-04)

- **Gap:** the loaded autonomy controller contained the only shortage-priority
  decision, so future settlement and away-team callers could drift into a
  different food/water/medical/tool order.
- **Fix:** `KS_BaseSupplyPlanner.chooseShortage` now owns that pure priority
  decision. The controller delegates to it; claims, movement, native transfers,
  and real inventory remain unchanged.
- **Verification:** base-supply-planner regression, full Lua suite, Lua 5.1
  syntax checks, Java verification, Workshop staging, and whitespace checks
  pass. Live multi-resident shortage rotation remains pending.
- **Status:** implemented; Lua-only planner refactor, so no launcher patch is
  required.

### Unified search-order defaults (2026-09-04)

- **Gap:** direct Notebook, party, or future API callers that issued a search
  order without a selected ground area were rejected at the companion service
  boundary, even though the order itself was valid.
- **Fix:** `KS_CompanionService` now creates a bounded twelve-tile search
  directive around the survivor (falling back to the player square when the
  body is unavailable) for loot, supply-finding, and inventory-cleanup orders.
  Party calls resolve this per companion so separated members do not converge
  on one stale player-centered target. Destination-sensitive orders still
  require an explicit payload.
- **Verification:** order-routing and catalogue regressions, full Lua suite,
  Lua 5.1 syntax checks, and whitespace validation pass. Live Notebook/party
  use of payload-less search orders remains pending.
- **Status:** implemented; Lua-only service change, so no launcher patch is
  required.

### Temporary threat interruption preserves base work (2026-09-04)

- **Gap:** entering combat or a survival-flee state called the normal base-task
  abandonment path. That marked the resident's claimed job blocked, so a
  routine attack could silently remove legitimate settlement work.
- **Fix:** threat preemption now uses `Controller:suspendBaseTaskForThreat`.
  It clears only transient native-action/transfer state and keeps the existing
  claimed task attached to the resident. The normal restore path can resume it
  after combat; explicit cancellation, invalid targets, shutdown, and genuine
  action failures still finish or block tasks through the original boundary.
- **Verification:** full Lua suite, Lua 5.1 syntax checks, order/base regressions,
  and whitespace validation pass. Live combat-to-base-work resume remains
  pending.
- **Status:** implemented; Lua-only controller change, so no launcher patch is
  required.
### Payload-less companion Guard/Patrol routing (2026-09-04)

- **Gap:** the shared order service treated a payload-less `Guard` or `Patrol`
  command as a base-job preference. A travelling companion therefore could not
  accept the familiar order unless the player first selected a ground area.
- **Fix:** companion-owned survivors now receive a bounded native directive at
  their current position: a small guard post or an eight-tile patrol area.
  Payload-less party Guard/Patrol commands fan out through that same per-
  companion path. Payload-bearing commands and base residents keep their
  existing routing and persistence boundaries; no second scheduler or
  formation system was added.
- **Verification:** order-routing regression, full Lua suite, Java checks,
  Workshop staging, and whitespace validation pass. Live context-menu execution
  remains pending.
- **Status:** implemented; Lua-only service integration, so no launcher patch
  is required.

### Base preference duty handoff (2026-09-04)

- **Gap:** changing a player-base resident's job preference updated the durable
  preference but could leave an already-claimed automatic task running under
  the old role until completion. That delayed player-facing orders and could
  keep routine work assigned to the wrong resident.
- **Fix:** `KnoxPersistence.requeueAutomaticBaseTasksForSurvivor` now releases
  only non-manual claims, preserving task identity, last claimant, and the
  existing queue/eligibility boundary. `KnoxCompanionService.setBaseJobPreference`
  invokes it only when the preference actually changes; Rest keeps its existing
  explicit-assignment protection.
- **Verification:** companion-command regression covers automatic release and
  manual preservation; all 79 focused Lua tests, all 81 Lua syntax checks,
  Java checks, Workshop staging, and whitespace validation pass. Live menu and
  resident handoff behavior remain pending.
- **Status:** implemented; Lua/persistence-only change, so no launcher patch is
  required.

The same handoff now notifies the loaded autonomy controller immediately. If the
persisted automatic claim has already been requeued, its stale runtime pointer
and transient supply/action state are released in the same tick; explicit manual
work remains attached until its normal completion boundary. This closes the
loaded-controller/task-board split without adding another order owner.

Leaving base duty is a separate ownership boundary: even a previously manual
base task is cleared from the loaded controller when the survivor becomes a
companion or independent survivor, preventing a stale settlement job from
following them into another mode.

- **Verification:** companion-command regression covers stale automatic-pointer
  cleanup, manual-pointer preservation, and base-exit cleanup; the full Lua, syntax, Java, staging,
  and whitespace checks remain green. Live preference changes are still pending.

Rest now uses the same automatic-only release boundary. Selecting Rest no longer
cancels an explicit Notebook assignment; the controller can remain on that manual
task, while routine automatic work is released for another resident.
Automatic handoff also clears off-screen lease timestamps so a new claimant gets
a fresh physical-work window.

- **Verification:** companion-command regression/source guard, full Lua suite,
  syntax scan, Java checks, Workshop staging, and whitespace validation pass.
  Live Rest behavior remains pending.

### Away-team return ownership gate (2026-09-04)

- **Defect:** `completeAwayTeamMember` accepted calls while a resource team was
  still in `collecting`. A destination-side caller could therefore restore a
  member's previous base/companion duty before the member had entered the
  explicit return phase.
- **Fix:** member completion now requires the persisted `returning` state. Item
  collection remains owned by `recordAwayTeamCollection`; duty restoration and
  final mission completion can only occur after `beginAwayTeamReturn` succeeds.
- **Verification:** the away-team regression now rejects premature completion,
  confirms the member remains on away duty, and still passes the normal
  collecting → returning → complete path. Full Lua/syntax, Java, staging, and
  whitespace checks remain required; live destination collection is pending.
- **Status:** implemented; Lua-only persistence change, so no launcher patch is
  required.

### Rest preference and manual base work (2026-09-04)

- **Defect:** the loaded autonomy controller still used the broad base-task
  requeue path when it observed `Rest`, so a delayed preference refresh could
  release a manual Notebook assignment.
- **Fix:** the controller now calls the automatic-only requeue boundary used by
  the companion service. Explicit manual tasks remain attached until their
  normal completion or cancellation path.
- **Verification:** the companion-command regression checks the controller
  source guard; live preference switching remains pending.
- **Status:** implemented; Lua-only controller change, so no launcher patch is
  required.

### Away-team return timeout (2026-09-04)

- **Defect:** a resource team that entered `returning` could retain away duty
  indefinitely when a member never acknowledged the final handoff.
- **Fix:** returning teams now use a bounded 72-hour timeout. Missing members
  receive an explicit `return_timeout` failure, any real collection ledger is
  preserved, the team becomes `blocked`, and previous duties are restored once.
- **Verification:** the away-team regression covers the timeout and confirms
  the member is released without fabricated resources; full Lua/syntax, Java,
  staging, and whitespace checks remain required. Live return behavior remains
  pending.
- **Status:** implemented; Lua-only persistence change, so no launcher patch is
  required.

The same release path now treats a death racing timeout as authoritative: dead
members retain a `deceased` duty while living members recover their prior duty.
This prevents mission cleanup from reattaching a corpse to a settlement or
companion roster.

### Canonical order resolver (2026-09-04)

- **Gap:** the order catalogue was authoritative, but callers repeated alias
  normalization and category checks. A future command could therefore be
  accepted by one player-facing path and rejected or misrouted by another.
- **Fix:** `KS_OrderCatalog.resolve` now classifies one normalized request as a
  primary order, directive, base preference, task preference, or presentation
  action. Individual and party companion dispatch use this resolver before
  entering the existing command/directive/task owners. No new executor or task
  manager was added.
- **Verification:** order-catalogue and order-routing regressions pass, Lua
  syntax checks pass, and `git diff --check` passes. Live menu behavior remains
  pending the settlement acceptance run.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Catalogue-owned player actions (2026-09-04)

- **Gap:** the canonical order catalogue listed recruit, dismiss, needs,
  vehicle, and climbing actions, but the individual order dispatcher stopped
  after directives and settlement work. Those actions could work only through
  separate menu-specific callers, allowing player-facing paths to drift.
- **Fix:** `KS_CompanionService.issueOrder` now delegates those actions to the
  existing recruitment, dismissal, needs, vehicle, and climbing owners. The
  party dispatcher delegates safe per-party actions (needs, vehicle, and
  climbing); recruit and dismiss remain individual-only to prevent accidental
  mass ownership changes. No new executor or state store was added.
- **Verification:** order-routing and order-catalogue regressions pass; every
  mod Lua file passes Lua 5.1 syntax validation; `git diff --check` passes.
  Live context-menu execution remains pending.
- **Status:** implemented; Lua-only service integration, so no launcher patch
  is required.

### Player menus converge on order dispatch (2026-09-04)

- **Gap:** the party and survivor context menus still called the needs,
  vehicle, and climbing helpers directly, leaving a second player-facing
  routing path beside `issueOrder`/`issueOrderAll`.
- **Fix:** those callbacks now submit the canonical action names through the
  shared dispatcher. Existing service methods remain the execution owners;
  no behavior or persistence model changed.
- **Verification:** order-routing regression, full Lua suite, Lua 5.1 syntax
  validation, and `git diff --check` pass. Live menu clicks remain pending.
- **Status:** implemented; Lua-only UI/service convergence, so no launcher
  patch is required.

### Settlement definition reconciliation after population changes (2026-09-04)

- **Gap:** faction and player-base defaults were guaranteed at game start only.
  A later resident admission or return could leave a valid settlement without
  its normal guard, patrol, work-area, or storage defaults.
- **Fix:** `KS_SurvivorAutonomy` now calls the existing idempotent
  `KnoxBaseManager.ensureFactionBases` and `ensurePlayerBases` on the existing
  population-reconciliation cadence. Ownership, task selection, and storage
  remain owned by their existing managers; no second scheduler was introduced.
- **Verification:** settlement-reconciliation regression, all 81 Lua tests,
  Lua 5.1 syntax validation, Workshop staging, and `git diff --check` pass.
  Live resident-admission and post-reload zone creation remain pending.
- **Status:** implemented; Lua-only settlement integration, so no launcher patch
  is required.

### Player command adapters completed (2026-09-04)

- **Gap:** A few individual and party menu callbacks still called companion,
  vehicle, stance, or weapon services directly, leaving multiple player-facing
  dispatch paths.
- **Fix:** Context and party commands now submit recruit, follow, hold, relax,
  return, dismiss, vehicle, combat-stance, and weapon-preference actions through
  `KnoxCompanionService.issueOrder` / `issueOrderAll`. These remain thin adapters
  to the existing service owners; no second task manager or state store was added.
  Base-resident activation remains explicit because it changes ownership first.
- **Verification:** Order-routing, order-catalogue, and all 81 Lua regressions
  pass; Lua syntax, Java checks/verifiers, staging, and whitespace checks pass.
  Live menu clicks and save/reload remain pending.
- **Status:** implemented; Lua-only change, so no launcher patch is required.

### Legacy Patrol preference presentation and matching (2026-09-04)

- **Defect:** older resident records can still contain `patrol_area` as a
  recurring base preference. The scheduler had a migration guard, but direct
  preference matching and player-facing resident/card views could still show
  the legacy directive spelling or fail to match a canonical Patrol task.
- **Fix:** the shared preference-matching helper now uses the same
  `normalizeBasePreference` boundary as scheduling and persistence. ViewModel,
  Notebook, and Survivor Card output also normalize and label the preference
  through `KS_OrderCatalog`, keeping old saves and current menus consistent.
- **Verification:** order-catalogue regression now covers legacy preference
  matching; Lua syntax and the full suite remain required. Live migrated-save
  menu rendering is still pending.
- **Status:** implemented; Lua/UI-only change, so no launcher patch is required.

### Runtime settlement claim reconciliation (2026-09-04)

- **Defect:** atomic task claiming prevented normal duplicate assignments, but
  stale claims could still survive an unload, death, ownership change, or
  interrupted save until a later per-survivor restore noticed them. That could
  make a valid resident appear busy or leave queued work under an invalid owner.
- **Fix:** `KnoxPersistence.reconcileBaseTaskClaims` now runs at the existing
  automatic-duty selection boundary. It requeues claims whose owner is no
  longer a living resident of that base and repairs duplicate claims by keeping
  the higher-priority deterministic winner. Task history and retry ownership
  remain on the existing board; no second scheduler was introduced.
- **Verification:** base-task-board regression now protects the reconciliation
  boundary and stale/duplicate reasons; full Lua, syntax, Java, and staging
  checks remain required. Live unload/death/ownership transitions are still
  pending.
- **Status:** implemented; Lua/persistence-only change, so no launcher patch is
  required.

The same repair now runs across every persisted base on the existing settlement
reconciliation cadence, so a base with only resting or manually assigned
residents cannot indefinitely retain an invalid automatic claim.
### Read-only settlement workforce projection (2026-09-04)

- **Defect:** the task board held authoritative claims, but the base-facing layer
  had no single derived view of working, resting, idle, manual, and automatic
  residents. Different screens could therefore summarize the same settlement
  inconsistently.
- **Fix:** added `KnoxBaseJobs.workforceSummary(base)`, a read-only projection
  built from persisted resident duties and task claims. The Notebook Base and
  Work views now include the workforce counts beside the existing task and
  security summaries. It does not claim, release, or mutate tasks and does not
  introduce another scheduler.
- **Workforce handoff:** settlement claim reconciliation is now coalesced for an
  unchanged base for a short world-time window, while world-backed job discovery
  still runs each request so new corpses, crops, repairs, or supply transfers are
  not missed.
- **Accounting guard:** claims held by former or invalid residents are excluded
  from working, manual, and automatic counts; persistence repair remains the
  owner of the actual cleanup.
- **Verification:** base-job regression, full Lua regression suite, Lua syntax
  scan, `git diff --check`, and `:java:check stageWorkshop` passed. Live
  multi-resident settlement execution remains pending.
- **Status:** implemented; Lua/UI-only change, so no launcher patch is required.

### Faction threshold consistency (2026-09-04)

- **Defect:** the developer faction/faction-base scenario always allocated three
  survivors, while normal promotion read the sandbox minimum (four by default).
  The autonomy scenario path also omitted the configured minimum and therefore
  used persistence's fallback of three. This made identical groups behave
  differently depending on how they were created.
- **Fix:** developer scenario allocation and autonomy-triggered promotion now
  both use `KnoxSettings.npcFactionMinimumMembers()`, with the existing
  persistence floor of three preserved. No relationship or faction state model
  was added.
- **Verification:** the faction-persistence regression now guards both source
  boundaries; focused Lua checks, syntax validation, Java checks, and Workshop
  staging remain required. Live developer-scenario promotion is still pending.
- **Status:** implemented; Lua-only consistency fix, so no launcher patch is
  required.

### Security coverage claimant validation (2026-09-04)

- **Defect:** `BaseJobs.securityCoverage` counted every claimed guard/patrol task,
  including claims left by a dead, unloaded, or former resident. The Notebook
  could therefore report a staffed perimeter when no current resident owned the
  post.
- **Fix:** coverage now validates each claimant against the persisted base
  resident roster and, when available, the authoritative living-state check.
  Early-load callers without a roster retain their compatibility accounting;
  live settlement state uses the strict resident boundary.
- **Verification:** `tools/test-base-jobs.lua` covers stale-claim exclusion;
  all 81 Lua regressions and all 82 Lua syntax checks pass. Live death/unload
  rotation remains pending. No launcher patch is required.
- **Status:** implemented; settlement accounting fix only.
## Player-order label normalization (2026-09-04)

- **Gap:** the unified order catalogue accepted Knox's internal keys and a
  limited alias set, but title-cased labels from familiar menus or migrated
  callers could fall through as unknown orders. This made the same order behave
  differently depending on which entry point supplied it.
- **Fix:** `KS_OrderCatalog` now normalizes whitespace, hyphens, case, aliases,
  and catalogue labels before routing. Task labels use the same boundary, while
  execution and persistence remain owned by the existing companion service and
  base task board.
- **Verification:** order-catalogue regression, all 81 Lua regressions, all 83
  Lua syntax checks, and `git diff --check` pass. No launcher patch is required
  because this is a Lua-only routing change. Live menu/save migration remains
  pending.
- **Status:** implemented; live player-order and resident-duty integration still
  require the planned in-game acceptance pass.
## Settlement supply-claim ownership (2026-09-04)

- **Defect:** short-lived base food/water/medical search leases were checked for
  expiry and life status, but not for current base membership. A resident moved
  to another base or released from settlement duty could temporarily block the
  correct workforce from answering a shortage.
- **Fix:** `KS_SurvivorAutonomyController:baseSupplyNeed` now validates each
  claimant's persisted duty mode and base ID, along with the existing living
  check, before retaining the lease. Invalid claims are released at the normal
  supply-search boundary; no new scheduler or stockpile was introduced.
- **Verification:** base-needs regression, all 81 Lua regressions, all 83 Lua
  syntax checks, and `git diff --check` pass. No launcher patch is required;
  live multi-resident supply rotation remains pending.
- **Status:** implemented, offline verified, live settlement execution pending.

## Explicit base supply-run orders (2026-09-04)

- **Gap:** base residents could answer automatic shortages, but the shared
  Superb-style `Find Food/Water/Medical/Weapon/Tools` orders were routed as
  companion directives. A player could not persistently ask a resident to make
  one bounded supply run without changing that resident's ownership mode.
- **Fix:** added an ownership-checked `baseSupplyOrder` field and setter/clearer
  to `KnoxPersistence`. The shared companion dispatcher now routes those labels
  to base residents without creating a second task manager; the base controller
  executes the existing real-item world search, returns recovered items through
  the existing base deposit path, expires failed requests after three attempts,
  and clears the request on completion. The base context menu exposes the same
  five orders under `Supply Run`; party search orders include eligible base
  residents while companions retain their local directive behavior.
- **Verification:** all 81 Lua regressions pass, including order-routing and
  base-needs coverage; all 82 Lua files pass syntax validation. No Java or
  launcher change was needed because this is Lua/persistence-only. Live menu,
  search, deposit, and save/reload behavior remain pending.
- **Status:** implemented; live settlement execution and persistence acceptance
  remain pending.

### Base supply-run restore, cancellation, and status (2026-09-04)

- **Defect:** the controller could persist a `base_supply_deposit` handoff in
  name only: the life-intent validator omitted the tools and deposit kinds,
  omitted the returning phase, and rejected every base-duty intent. A restored
  controller also did not initially copy its resident supply order. Empty
  searches cleared an explicit request after one container rather than using
  the intended bounded retry policy.
- **Fix:** base supply search/return intents are now valid only for base-duty
  survivors and the existing supported supply kinds. Controller/base sync
  restores the request, persistent attempt count, and bounded three-search
  failure state. Successful collection clears the request before the existing
  real-item return/deposit path; empty searches retain it until the bounded
  limit. Replacing or cancelling a request releases transient movement/action
  ownership. `Resume Normal Duty` now cancels supply runs for individual or
  party-controlled base residents, and the Notebook reports an active supply
  run instead of showing that resident as idle.
- **Verification:** companion/base-domain, base-needs, order-routing, companion-
  command, and base-UI regressions pass; the full 81-test Lua suite passes.
  Live save-during-search, save-during-return, cancellation, and deposit remain
  pending.
- **Status:** implemented and offline verified. Lua/persistence/UI only; no
  launcher patch is required.

### Fair and durable settlement supply rotation (2026-09-04)

- **Defects:** shortage leases prevented several residents from searching for
  the same resource simultaneously, but stable controller iteration allowed the
  same resident to win every later lease. Supply movement also had no durable
  in-flight duty owner, so reconstruction during a search could retain a vague
  life intent while the base controller immediately chose ordinary return-home
  behavior.
- **Fix:** `KS_BaseSupplyPlanner` now selects the oldest eligible loaded worker,
  excludes resting, task-owned, unloaded, and explicitly ordered residents, and
  uses last resource kind plus stable ID only as deterministic tie-breakers.
  Selection and terminal outcomes are stored in the existing resident duty.
  One `activeSupplyRun` record now survives controller reconstruction while all
  native movement, item lookup, transfer, and deposit state remains transient.
  Successful, empty, unavailable, cancelled, dead, or reassigned paths release
  the existing shortage claim and durable run before ordinary work resumes.
  Automatic runs are now visible through the shared workforce and Notebook
  status projection rather than being reported as idle.
- **Verification:** planner coverage proves oldest-worker rotation, same-kind
  avoidance, stable ties, and busy/resting/order exclusion. Persistence coverage
  proves start, completion, cancellation, history, and roster projection. All
  81 Lua regressions pass and all 82 mod Lua files pass Lua 5.1 syntax checking.
  `:java:check`, `:java:build`, and `stageWorkshop` pass, including the movement,
  combat, corpse, inventory, traversal, shell, and visibility verifiers.
  `git diff --check` reports no whitespace errors; the staged Workshop payload
  contains the same rotation and durable-run boundaries.
- **Status:** implemented and offline verified. Live three-resident rotation,
  interruption/reconstruction, real collection, and return/deposit remain the
  acceptance gate. This is Lua/persistence/UI work; no launcher patch is
  required.

### Exact blocked-job resupply and minimum security coverage (2026-09-04)

- **Defect:** a resident searching outside the base for a blocked job matched
  every declared requirement, including tools and materials already carried.
  A worker who had a hammer but needed planks could consume all three bounded
  attempts collecting more hammers and incorrectly block the task. Automatic
  task scoring also gave understaffed Guard/Patrol work only a small bonus, so
  sufficiently high routine priorities could leave an established settlement
  with no watcher.
- **Fix:** `KS_BaseSupplyPlanner` now derives the outstanding count for each
  declared item from the worker's real recursive inventory and the loaded
  controller searches only for those missing full types. Inventory API failure
  remains fail-safe and never manufactures stock. Automatic/flexible workers
  now fill the existing one-or-two-person minimum watch before routine work;
  explicit non-security roles remain authoritative, and a resident who just
  worked a recurring watch yields the post for relief when another resident is
  available. Task creation and atomic ownership remain in the existing base
  task board.
- **Coordination:** shortage planning now exposes the complete ordered set of
  current shortages. Once one resident owns the food lease, another eligible
  resident may answer water, medical, weapon, or tool shortages instead of all
  controllers stopping at food. Existing per-kind leases still prevent two
  residents from leaving for the same resource, and a resident retains its own
  in-flight highest-priority claim through reconstruction.
- **Persistence boundary:** loaded supply leases no longer live on the durable
  base record. Controller-only lease state is rebuilt from the resident's
  persisted `activeSupplyRun` during reconstruction, while migration removes
  development-era `supplySearchClaims` tables from existing base ModData.
- **Verification:** focused planner coverage checks complete, partial, unknown,
  and unrelated inventory states plus distinct concurrent shortages and
  reconstruction ownership. Base-job coverage checks minimum-watch priority,
  explicit-role precedence, and existing relief rotation. All 81 Lua
  regressions and all 82 Lua syntax checks pass. Java checks/build, every
  transformer/runtime verifier, Workshop staging, and `git diff --check` pass.
  Live settlement verification remains required.
- **Status:** implemented; live collection of the correct missing material,
  guard relief, and multi-resident settlement behavior remain pending. This is
  Lua-only settlement logic and does not require a launcher patch.

### Unloaded resident work continuity (2026-09-04)

- **Defects:** `UnloadedSurvival.advanceAll` sent only residents without a
  claimed task through normal stored-survivor advancement. A resident holding
  physical work therefore stopped accumulating hunger, thirst, fatigue, and
  endurance while unloaded, and guard/patrol claims never reached the existing
  abstract watch-shift boundary. The separate claim-timeout branch also lacked
  an active-body exclusion, so a loaded worker could accumulate off-screen wait
  time. A record with a missing survival ledger could retain an automatic claim
  indefinitely because that branch required the ledger to exist.
- **Fix:** every inactive, non-cohort survivor with a real record now advances
  through the one existing unloaded-survival path whether or not it owns a base
  task. Guard/patrol alone may complete their existing abstract four-hour watch
  shift; physical work remains native loaded-world work. Only inactive task
  owners enter the physical-claim wait policy, and a missing survival ledger
  still releases an automatic claim after the same bounded twelve-hour wait.
  Manual Notebook assignments remain protected.
- **Verification:** focused coverage proves physical-task physiology, bounded
  automatic release, missing-ledger release, active-worker exclusion, and one
  recurring guard shift through the canonical task owner. All 81 Lua
  regressions and all 82 mod Lua syntax checks pass. `:java:check`,
  `:java:build`, every runtime/transformer verifier, and `stageWorkshop` pass;
  the staged Workshop copy contains the new inactive-resident ownership gate.
  `git diff --check` reports line-ending warnings only and no whitespace error.
- **Status:** implemented and offline verified. Live verification remains a
  multi-resident unload/revisit test covering physical-work handoff, guard
  relief, real needs progression, and save/reload. This is Lua/persistence
  integration only and does not require a launcher patch.

### Faction shelter-purpose completion (2026-09-04)

- **Defect:** home confirmation committed the faction shelter and removed its
  temporary camp, but left both the leader's durable shelter-scout life intent
  and the travel group's shared objective in persistence until a later runtime
  synchronization. Saving, unloading, or interrupting during that window could
  restore a group still pursuing a shelter objective it had already completed.
- **Fix:** `confirmFactionHomeBase` now retires the leader intent and matching
  faction travel-group objective in the same persistence transaction as the
  home claim. The existing loaded scouting controller, safehouse reconciler,
  base manager, and group movement owners remain unchanged.
- **Verification:** faction persistence now exercises a real leader intent and
  group objective before home confirmation and proves both are absent after
  the claim. Faction scouting, unloaded-group travel, settlement reconciliation,
  and human-encounter focused checks pass. All 81 Lua regressions and all 82
  mod Lua syntax checks pass.
- **Status:** implemented and offline verified. The staged shelter approach,
  loaded candidate selection, safehouse/base creation, resident conversion, and
  save/reload still require the existing live faction acceptance run. This is a
  Lua persistence correction and does not require a launcher patch.

### Settlement status convergence (2026-09-04)

- **Gap:** automatic settlement decisions already used real loaded storage,
  resident-scaled reserve thresholds, task failure reasons, retry times,
  workforce ownership, and security coverage, but Base Management exposed only
  nonzero stock plus queued/active totals. A functioning base could therefore
  look empty, and blocked work gave the player no useful explanation.
- **Fix:** `KS_BaseSupplyPlanner.reserveStatus` is now the single read-only
  reserve definition used by both shortage selection and presentation.
  `KS_BaseJobs.settlementSummary` combines that result with the existing real
  storage snapshot, task board, workforce, and security projections without
  claiming work or inventing unloaded stock. The existing vanilla-style Work
  tab now shows covered/missing reserves, blocked work reasons, retry delay,
  and the assigned resident for active work. Resident rows now distinguish a
  genuinely off-screen claim from a fresh loaded claim, present an in-flight
  supply run ahead of its retained request, and show the Rest preference as
  resting instead of stale idle work.
- **Verification:** focused supply-planner, base-job, and Base Management UI
  regressions cover shared thresholds, exact shortage amounts, loaded-storage
  honesty, task-state counts, blocked retry state, and UI routing. All 81 Lua
  regressions and all 82 mod Lua files pass Lua 5.1 syntax checking. Java
  checks/build, every transformer/runtime verifier, and Workshop staging pass;
  the staged Work tab contains the same status projection. `git diff --check`
  reports line-ending warnings only and no whitespace errors.
- **Status:** implemented and offline verified. Live Base Management rendering
  with loaded and streamed-out storage remains pending. Lua/UI only, so no
  launcher patch is required.

### Fresh-world population initialization hang (2026-09-04)

- **Evidence:** three launches under Project Zomboid 42.20.4 ended without a
  Java fatal-error file or Lua exception. Windows recorded `java.exe` as an
  application hang, and the final game-thread message in the complete log was
  the Knox population catalogue (`89` player starts, `1914` building origins,
  `11` regions). The bridge and all three Java transformers had already
  reported PASS. The next synchronous operation attempted to allocate the
  entire configured 48-person durable population in one tick.
- **Fix:** initial identity allocation now yields after six records and resumes
  on later population maintenance passes. It does not change the configured
  target, origin balancing, rarity, group policy, refill timing, active-body
  limit, or survivor identity format. Opening groups are formed only after the
  initial target is reached and use all identities from every batch.
- **Verification:** the world-population regression now forces a two-record
  budget and proves `initializing` across multiple passes, durable accumulation,
  final target completion, and group creation after the final batch. Focused
  world-population, unloaded-survival, unloaded-group, and sandbox-setting tests
  pass. All 81 standalone Lua tests and all 83 mod Lua files pass Lua 5.1
  syntax checking. `:java:check :java:build stageWorkshop` passes against the
  currently installed 42.20.4 game files, including every transformer, shell,
  movement, combat, traversal, inventory, and corpse verifier.
- **Status:** implemented; pending one fresh-world live confirmation. Lua-only,
  so the existing launcher remains compatible and no launcher patch is needed.

### Persistent-world hot-path freeze (2026-09-05)

- **Evidence:** after batched fresh-world allocation reached playable runtime,
  the latest live log spawned `ks-dev-1`, equipped its bat, and entered native
  combat twice before Windows recorded another `java.exe` application hang.
  There was no Lua exception, movement-failure storm, transformer failure, or
  JVM fatal-error file. Inspection found that nearly every persistence getter
  called `root()`, and `root()` re-normalized every survivor, relationship,
  travel group, faction, camp, base, and task on every call. Hot autonomy and
  combat paths invoke several such getters per survivor per game tick.
- **Fix:** completed persistence normalization is now cached for the exact
  authoritative ModData graph. Replacing any major domain table invalidates the
  cache; `OnGameStart` explicitly invalidates it and performs one full loaded-save
  repair. Scheduler scalar validation, faction event-identity validation, and
  travel-group leader/objective cleanup now occur at their narrow owning
  boundaries rather than depending on unrelated global read-side repair.
- **Verification:** `tools/test-persistence-hot-path.lua` performs 1,000 hot
  accessor reads without a base-domain scan, then proves an authoritative graph
  replacement triggers exactly one new normalization. Event scheduler, event
  faction, and relationship-coherence regressions protect the moved repair
  boundaries. All 82 standalone Lua tests pass. Live FPS and long-session
  responsiveness remain unverified.
- **Status:** implemented and offline verified; pending a normal live session
  with one or more active survivors. Lua-only, so the launcher does not need a
  patch for this optimization.

### Live inventory, corpse, base-area, and companion-need corrections (2026-09-05)

#### Follow-up order, rest and identity corrections

- Corrected the resident job-menu callback argument order responsible for the
  numeric `onSelect` exception. Added executable menu dispatch regression.
- Guard-zone placement uses one click and stores a 1x1 post. Area jobs retain
  two-corner selection. This input change does not yet prove guard-duty retention.
- Party vehicle exit remains available after the leader leaves the vehicle.
  Resident work labels now expose barricading/corpse cleanup more clearly.
  Notebook's existing mission display is titled Away; stored trips remain intact.
- Relax no longer stands/restarts every periodic recheck. Real actionable needs
  and replacement orders still interrupt it; combat remains checked first.
  Ambient base rest lasts longer, and awake furniture selection prefers usable
  sofas/couches and chairs over beds. Sleeping retains bed-quality selection.
- A shared presentation name resolver uses saved names/native descriptors and
  avoids internal placeholder labels. Loaded death announcement follows the
  persisted alive-to-dead transition, so corpse cleanup retries do not repeat it.
- Native human PvP investigation found the single-player `CombatManager.checkPVP`
  gate still depends on coop PvP. Existing faction-PvP flags do not bypass that
  gate. A narrow relationship-aware integration remains pending; human combat
  with ordinary PvP disabled must not be claimed complete.
- Pending: live traversal/circling, tall fences/windows, room-wide scavenging,
  guard retention, hostile human combat, and shared base-storage redesign.
  No infinite storage or new request/reward simulation was introduced.

- **Evidence:** the latest short live run produced three off-slot inventory
  exceptions at vanilla `ISEquipWeaponAction.complete`: the real action tried
  to call `refreshBackpacks` on a local-player inventory page that does not
  exist for a Knox shell. The survivor card also reached a hidden vanilla hair
  callback and attempted to hide a missing local context menu. Player feedback
  confirmed that taking equipped clothing moved the item but left its source
  survivor worn/hand references intact.
- **Fix:** native equip, wear, and unequip actions receive a no-op inventory
  page only for their invalid off-slot UI refresh; real item/equipment mutation
  remains vanilla. A survivor-source loot transfer detaches the item from that
  survivor after confirmed native transfer and refreshes clothing/model
  state. The read-only survivor card hard-disables hair, beard, and literature
  callbacks. Corpse hauling retains vanilla `ISUnequipAction` and
  `ISGrabCorpseAction`, so the shared unequip boundary is corrected without
  replacing corpse behavior.
- **Player-facing policy:** player base establishment/relocation no longer
  creates work areas. Repair and General Work overlays were removed from the
  picker; repair remains a territory-scoped job. Only autonomous NPC faction
  bases generate practical zones/storage. Missing food, water, or medical
  supplies no longer make an unordered companion abandon Follow/Hold; carried
  self-care and explicit Find orders remain available. Optional speech now
  enters Build 42's native overhead `ChatElement` directly.
- **Human combat:** survivor-survivor hostility and hostile survivor-player
  targeting already converge on the one Java combat owner, which accepts
  `IsoPlayer` targets and native BodyDamage. A real player hit records durable
  hostility only after `OnWeaponHitCharacter`. No simulated damage was added;
  both directions remain pending live acceptance.
- **Transfer outcome verification:** equipment now detaches only when an item
  was present before and absent after the native transfer. Rejected transfers
  preserve worn/hand state. If a later native callback throws after moving the
  item, equipment still reconciles before the original error propagates.
  Executable checks cover rejection, early error, success and late error.
- **Corpse destination/retry follow-up:** native pickup retries reject removed
  bodies. Drop selection remains inside the designated zone and rejects removed,
  disabled, or blocked zones rather than using stale coordinates. Discovery
  computes one drop destination per zone instead of repeating that search for
  every body. Regression checks cover these boundaries; all 83 Lua tests,
  affected syntax, Java checks/build and Workshop staging pass. The reported
  corpse-swinging animation still requires live reproduction/confirmation.
- **Connected combat defect:** the same live run repeatedly logged firearm
  close-range fallback followed by immediate firearm reselection. A weak-key,
  target-specific 900-tick cooldown now preserves melee fallback across threat
  scans. It uses the controller's current tick and expires normally; it does not
  suppress the target or prevent self-defense. Executable regression coverage
  verifies both fallback retention and firearm reevaluation after expiry.
- **Verification:** focused companion-inventory, base-setup, corpse-handling,
  companion-command, player-facing-human, encounter, and sandbox regressions
  pass. All 83 standalone Lua tests and all 83 mod Lua syntax checks pass.
  `:java:check`, `:java:build`, every runtime/transformer verifier, and
  `stageWorkshop` pass against installed Build 42.20.4. The staged Workshop
  copy contains the same inventory, companion, base, and speech corrections.
- **Status:** implemented and offline verified where noted. Inventory visual
  detach, corpse pickup, overhead bubbles, companion need containment, and both
  directions of human combat require the next live run. Lua/UI only; no launcher
  patch is required.

### Persistent companion Hold/Guard state — 2026-09-05

- Hold and Guard no longer fall back to `IDLE` every 90 ticks. They retain their
  authoritative directive and refresh only their observation deadline until a
  command explicitly replaces/releases it. Combat and immediate-threat preemption
  remains ahead of this state and returns to the same directive afterward.
- This removes planner churn and prevents guards from wandering simply because a
  refresh timer elapsed. Focused controller regressions cover both directives;
  Lua syntax and the full Java verification suite remain clean. Live combat,
  guard positioning and save/reload acceptance remain pending. No launcher change.

### Native corpse pickup load-order hardening — 2026-09-05

- `KS_BaseCorpseHandling` now explicitly loads Build 42's `ISGrabCorpseAction`
  before queueing a haul. This closes a load-order path where a corpse job could
  reach its transition without the native grab constructor and fall back into
  unrelated character input. The native grab/drop actions and real corpse state
  remain authoritative; no simulated carrying was added.
- Regression verifies the explicit import and existing async grab/drop, removed
  body, reach, and retry checks. Lua syntax and full Java checks were previously
  clean; Workshop staging will be refreshed with this Lua-only change. Live
  corpse pickup animation and persistence remain pending. No launcher patch.

### Nameplate PvP side-effect removal — 2026-09-05

- Removed the nameplate refresh's `setFactionPvp` mutation. Name rendering is a
  presentation concern and must not alter native combat policy each visibility
  tick. Relationship-aware human eligibility now lives only in the combat gate.
- Player-facing regression and Lua syntax pass; Workshop staging includes the
  correction. No launcher change. Live nameplate and human-combat verification
  remain pending.
### Launcher JVM option preservation — 2026-09-05

The launcher previously replaced the inherited `JAVA_TOOL_OPTIONS` value with only the Knox
agent. That could hide compatible options such as ZombieBuddy's `-agentlib:zbNative` and other
user/Steam JVM flags. `GameLauncher.MergeJavaToolOptions` now preserves the inherited value and
adds Knox once, leaving the normal batch/json launch configuration untouched. The launcher
verifier now covers preservation of an existing agent and memory option. Launcher build and
verifier pass locally; a real ZombieBuddy + Knox launch remains live-only verification.
### Survivor-card off-slot UI error hardening — 2026-09-05

The latest console log contained two UI exceptions from the survivor card: the inventory
shortcut referenced an unbound local module table, and the read-only health panel opened
Build 42's local-player body-part context menu with an invalid off-slot player index. The card
now binds the table returned by `require`, fails safely if it is unavailable, and suppresses
the vanilla health context-menu path for this read-only view. The card and inventory regression
tests, all 86 Lua tests, and Lua syntax checks pass. A live card click remains pending.
### Survivor-card health child-menu guard — 2026-09-05

The off-slot health panel's child list/body-part controls could still forward right-clicks into
Build 42's local-player context-menu path even after the parent callback was disabled. Both child
callbacks are now suppressed for the read-only survivor card. The UI regression test, full Lua
suite (86 tests), and syntax scan pass; confirmation in a fresh game session remains pending.

The ignored Windows launcher archive was rebuilt locally with `tools/build-launcher.ps1` after
the JVM-option compatibility change. The repeatable build/verify step produces the release
archive without committing machine-specific binaries.

### Companion synchronization hot-path cache — 2026-09-05

`syncController` was reapplying weapon, party visibility, formation, order, stance, policy, and
directive setters for every active survivor on every tick. It now fingerprints the authoritative
duty/policy/roster state and skips unchanged synchronization while still invalidating when a
controller, order, roster, stance, policy, or directive changes. The new source guard plus all 87
Lua tests and syntax checks pass; live frame pacing remains pending.

### Awareness hot-path batching — 2026-09-05

Zombie awareness was resolving every active controller, square, death state, and native attack
eligibility flag once per zombie during each scheduled pass. It now snapshots the active NPC set
once per pass and reuses those entries for LOS/target selection, preserving the existing 15-tick
cadence and close-combat refresh behavior while removing redundant hot-path calls. The dedicated
awareness regression, all 86 Lua tests, and syntax checks pass; multi-NPC frame pacing remains a
live performance verification item.
