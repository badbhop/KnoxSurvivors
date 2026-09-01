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
| 10. Factions | **Partial / membership coherence implemented, live pass pending** | Persistent faction IDs, leaders, members, traits, relationships, home candidate/base IDs, safehouse ownership, and resident conversion exist. Save-start normalization prevents contradictory faction ownership, preserves player companions, repairs dead leaders, and synchronizes camp occupancy. Resource expeditions, diplomacy expansion, recruitment growth, and full faction progression remain incomplete. |
| 11. Base scouting/settlement | **Partial** | Loaded buildings are scored, safehouse conflicts are rejected, candidates persist, leaders travel to candidates, and faction bases/residents are created. Candidate breadth, repeated unloaded search, resource/water evaluation, and failure recovery need completion and live verification. |
| 12. Base domain | **Partial / relocation implemented, live pass pending** | Player and faction base records, home/territory separation, residents, zones, storage policies, tasks, ownership protection, and save migration exist. New player building claims receive a six-tile yard perimeter. Moving homes retains the stable base/resident ownership ID and leaves physical world items untouched while transactionally replacing the home/territory and clearing old location-bound zones, storage policies, and unclaimed work. A resident-owned task blocks relocation rather than being orphaned. NPC faction planning fills only missing zones, binds available real containers without creating supplies, and relies on priority ordering plus atomic task claims so residents distribute across available work. Off-base resource acquisition and end-to-end settlement life remain incomplete. |
| 13. Base Setup UI | **Partial / selector crash corrected, live pass pending** | Context menus can establish or confirmation-move a base, redraw territory, create zones, categorize containers, and safely remove inactive work areas. Build 42 modal callbacks now consume the real target/button signature, and both corner selectors use the native `skipWalk2` opt-out so selecting ground cannot queue player movement. A vanilla-style Base Setup window opens from party/world menus with Overview, Residents, Work Areas, Storage, and Tasks tabs plus boundary editing, work-area selection, party recall, persistent resident job preferences, and safe queued-task cancellation/resume. Cancellation cannot interrupt a claimed native action and preserves the task signature so automatic planning does not immediately recreate it. Zone resizing, exact task-to-resident assignment, and richer visual territory/zone management remain incomplete. |
| 14. Existing base jobs | **Implemented, unverified** | Guard, patrol, depot sorting, barricading, farming, tree cutting, log sawing, corpse hauling, trough water/feed, and structure repair have real executors and focused passing tests. When no ready task or patrol is selected, a resident can now make a bounded ambient rest decision that reuses normal furniture/ground sitting rather than standing motionless; it releases its seat/posture before the next decision. A claimed task collects missing exact requirements from currently loaded assigned storage through normal inventory transfers before work begins; it blocks safely when that storage is absent. Most lack live passes; task reservation across multiple residents and save/interruption still needs integration testing. |
| 15. Construction/defense planning | **Partial, static path verified** | Defense Construction Areas now plan a gate first, then wall frames and first-stage wooden walls using Build 42.20 entity recipes, native `ISBuildAction`, real materials, skill gates, XP, sounds, and world-object completion checks. Faction bases receive a conservative default perimeter. Live off-slot action, construction interruption, and multi-resident verification remain required; walls/gates beyond the first wooden stage are not yet implemented. |
| 16. Companions | **Partial / follow locomotion implemented, unverified** | Talk, trust, recruit, Follow, Hold, Return to Base, Dismiss, climbing policy, and area/building/corpse loot directives persist. Follow now uses distinct trailing slots, ignores insignificant leader motion, refreshes pace without replacing the route, catches up with bounded walk/run/sprint policy, resets recovery on arrival, and explicitly respects Hold. Return to Base hands a companion off transactionally to a persisted virtual route when the destination cell is unloaded. Party Go To and Guard persist and resume after ordinary interruptions. Combat stances and normalized duty data remain intact. Exact task assignment, finished base roster exchange, and live verification of follow transitions/order recovery remain incomplete. |
| 17. Companion HUD | **Partial** | Split-screen-isolated right-side HUD, portraits, needs, health, weapon, activity, individual menu, and party menu exist. It needs a complete live lifecycle pass, unloaded cleanup verification, urgency presentation, and final command coverage. |
| 18. Survivor Card | **Partial / lifecycle patch unverified live** | Identity, age, occupation, time alive/known, group/base/job/activity, conditions, weapon, faction, trust, persistent traits, and top learned skills are shown. The card now follows Build 42's `ISHealthPanel:initialise()` → `createChildren()` lifecycle and safely omits that optional tab if the engine rejects it. Its Knox tab has direct Inventory and Medical Check shortcuts, both delegated to the existing vanilla inventory bridge and medical timed action rather than duplicating those mechanics. Standalone UI coverage passes, but a new live opening/render/action test is still required. Detailed relationship history and richer equipment presentation remain incomplete. |
| 19. Survivors Notebook | **Partial** | A vanilla-styled window now has Base, Residents, Work, Missions, Survivors, and Factions tabs. It distinguishes loaded people from stored survivors, lists durable individual activity/role state, shows faction member counts, base/shelter status, and the current player-faction relation, and keeps mission progress separate from ordinary unloaded people. Portraits, richer selection/actions, resource status, and detailed base/faction views remain incomplete. |
| 20. Away teams/missions | **Partial** | Persistent teams now have an owner, members, mission type, destination, departure, ETA, state, result, and preserved prior duties. The unloaded simulation advances completed scout missions and restores every participant's prior duty; scouting deliberately returns no items. Away members remain excluded from proximity activation, while their persisted needs, rest, endurance, inventory consumption, and health continue advancing in the off-screen ledger. Both scout dispatchers validate owner, members, duty, and destination before taking a loaded shell down; the player command sends one available loaded resident at a time. Resource missions now reach a durable awaiting-collection state and have a per-member real-item ledger: a future live executor can record only item types actually moved from world containers, then restore duties only after every member returns. Destination materialization, the transfer/return executor, risk, mission-selection UI, and live verification remain incomplete. |
| 21. Unloaded-world simulation | **Partial, focused checks pass** | Hibernated survivors carry a persisted survival ledger: needs advance, rest/endurance recover, real stored food/water is consumed, and deprivation can cause durable death. Autonomous survivors, travel groups, away teams, and unloaded returning base residents make deterministic low-cost virtual progress; a base return starts at the freshly captured origin, travels at the normal virtual rate, then changes to base life only on arrival. Group members share a heading, base residents take deterministic ambient positions inside their own saved territory, companions preserve their reunion point, and away-team travel/result ownership remains separate from physiology. A hidden loaded square transactionally updates the Java record before rematerialization. Detailed offscreen pathing, injury treatment, encounters, supply gathering, faction growth, and a multi-day live return remain incomplete. |
| 22. Camps | **Partial / temporary living implemented, live pass pending** | Homeless NPC factions create one lightweight persistent shelter in an unclaimed loaded building. Durable faction membership restores camp linkage without duplication; loaded members take distinct reserved shelter positions, stagger bounded idle/rest/reposition behavior, use ordinary needs and real nearby containers, take short roaming/scavenging excursions, return through native movement, defend group members, and retain camp identity through interruption. Camp conversion clears stale ownership. Player camps, fortification, jobs, strategy management, and richer social behavior remain outside this slice. |
| 23. Vehicles | **Partial / passenger slice unverified** | Companion Orders now expose Enter My Vehicle and Exit Vehicle. The passenger-only implementation uses Build 42's native path-to-seat, enter, exit, and door-close timed actions, refuses occupied/locked/uninstalled/blocked seats, and never takes driver seat zero or changes keys/engine ownership. A seated shell is excluded from detached hibernation so its native seat relationship is not destroyed while the player drives. NPC driving, autonomous/group vehicle travel, vehicle-specific persistence/reconstruction, and live verification remain incomplete. |
| 24. Raids/faction conflict | **Experimental dispatch/travel, unverified** | Symmetric persisted faction relations and hostile base-protection rules exist. Knox Events proposes real minority parties and can dispatch ready loaded residents from explicitly scheduled plans. Temporary duty bindings, native travel, shared stored travel/rest, and return/casualty cleanup have focused checks. No random scheduler is enabled. Actual combat/loot objectives, dispatch of already-stored parties, event factions, and live verification remain incomplete. |
| 25. World population | **Implemented, unverified** | Region-balanced identities, persistent target, active-body limit, distant/hidden materialization, refill delay, origin reuse protection, hibernation candidates, and durable death records exist and pass standalone tests. Production-scale live streaming/refill is not proven. |
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

1. restore and prove local-player/global-instance ownership, fix the Survivor Card crash,
   and eliminate permanent `DETACHED` lifecycle states;
2. make loaded-world melee and zombie-to-survivor damage reliable in duel and horde tests;
3. reduce movement/action retry failures and prove group/companion travel recovery;
4. live-verify the existing base-job executors with multiple residents and save/reload;
5. add persistent replacement-door/basic-defense construction through real Build 42
   recipes, skills, tools, materials, placement, and actions;
6. finish player inventory/medical management and the Base Setup/Notebook management UIs;
7. live-verify the implemented native firearm reload/fire gate, then complete away-team
   materialization because both are required for production settlement supply loops;
8. add camps, vehicles, and raids only after ordinary survivor/faction life is stable.

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
- Withdrawal returns to the saved entry anchor, releases event duty, and retains living members as
  ordinary persistent world/faction identities. Non-persistent faction disposal is intentionally
  not faked by deleting survivors; that lifecycle policy remains future work.
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
