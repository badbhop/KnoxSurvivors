<!-- modforge-doc
authority: canonical
load: always
purpose: canonical confirmed bug and blocker ledger
-->

# Knox Survivors — confirmed bugs and blockers

Updated: 2026-09-27

## Rule

Only put a bug here when there is a concrete symptom, reproduction/log evidence, or a source-confirmed failure. “Needs live testing” is not itself a bug.

The 2026-09-21 release-readiness audit reported no source-confirmed release blocker at that snapshot. Later worktree changes mean the current candidate must be revalidated, but they do not automatically constitute bugs.

## Current confirmed blockers

## BUG-KS-001 — Unloaded raids manufacture terminal outcomes and world damage
Status: in_progress
Priority: high
Owner: Codex
Type: bug

### Symptom
An entirely unloaded faction raid can be declared repelled or breached without
loaded arrival or native combat. A breach can later create blood and smash real
windows when the player enters the area.

### Reproduction
On candidate `163b789`, schedule an eligible faction raid against an established
base, keep every raider and the target more than 300 tiles from the player, and
allow the event runtime to update. Return to the target after the event reaches a
terminal phase.

### Evidence
The current working diff removes `KS_EventRuntime.resolveUnloadedRaid` and
`KnoxEvents.resolveAbstractRaid`, including the path that released event duties,
recorded terminal outcomes/history, and created fight/breach traces from roster
counts. The runtime now permits stored travel/arrival, then leaves an unloaded
raid at the active/objective boundary until a raider body is loaded for native
combat/looting. While that body is absent, objective review does not time out
into a result; event duties remain owned. Updated event-runtime coverage checks
that this path creates no raid history or traces and that loading a raider
resumes the objective. Six focused event/trace tests passed. The full
`tools/verify.ps1 -SkipJava` run checked 112 Lua sources and ran 174 scripts
(286 checks, 0 failed). These are offline checks and do not verify native combat
or world effects.

### Expected
Unloaded travel may preserve/advance event intent, but only real loaded
arrival/combat/objective evidence may establish a raid outcome or mutate world
geometry.

### Acceptance
No unloaded-only update declares raid victory/defeat, releases a deployed roster
as if combat completed, creates blood, or smashes windows.

### Validation
Offline verification on 2026-09-27: six focused event/trace tests passed; full
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 174 scripts (286
checks, 0 failed). Still required: live Build 42 loaded-to-unloaded-to-loaded
raid replay with native combat evidence. Offline fixtures do not prove native
combat, blood placement, window damage, pathing, or persistence behavior.

## BUG-KS-002 — Failed world-trace materialization is marked complete
Status: in_progress
Priority: high
Owner: Codex
Type: bug

### Symptom
A trace site is permanently marked visited even when blood/window
materialization throws or returns false, so the visible trace is silently lost
instead of retried.

### Reproduction
Present an unvisited nearby trace whose loaded square exists but whose native
materialization call fails or cannot place any effect, then run
`KnoxWorldTraces.update()`.

### Evidence
The bounded fix in `mod/42/media/lua/client/KS_WorldTraces.lua` now calls
`markTraceVisited(site.id)` only when materialization returns success. Breach
materialization reports success only when the blood-placement helper succeeds
or at least one window smash succeeds; this is a code-level success signal, not
live confirmation of the native visual effect. `tools/test-world-traces.lua`
now checks a failed materialization remains unvisited, a later successful retry
is consumed once, and a throwing breach path remains retryable. The same
throwing breach site is now also retried after restoring working cells and
verified consumed exactly once with a bounded real effect
(`breach-retry=true`), with no production-code change.

### Expected
Only successful materialization consumes the persisted trace; transient native
failure remains bounded and retryable.

### Acceptance
Failure/false-result coverage proves the site remains unvisited and can later
materialize exactly once.

### Validation
Offline verification on 2026-09-27: `test-world-traces.lua` passed, including
the same-site throwing-breach retry consumed exactly once;
`test-event-runtime.lua` and `test-knox-events.lua` passed; full Lua regression
suite passed 174/174. This verifies the bounded retry logic under test doubles
only. Still required: live Build 42 trace replay on a temporarily unavailable
or invalid target, confirming the native blood/window effect before the trace
is consumed.

## BUG-KS-003 — Embedded launcher is a conflicting runtime owner
Status: closed by retirement of the unsupported launcher path (2026-09-29)
Priority: high
Owner: Codex / OpenCode
Type: bug

### Symptom
The main mod repository contained a second, stale C# launcher that preserved
ZombieBuddy's `-agentlib:zbNative` while adding Knox's legacy `-javaagent`,
contrary to the exactly-one-runtime-path contract. Its embedded source and
build path were retired. The separate Knox Survivors Launcher is now
deprecated and unsupported by owner direction; KnoxBridge is the sole
supported public Knox runtime path. Its GitHub privacy change was requested but
is still pending, so do not claim the repository is private yet.

### Reproduction
Historical reproduction: in the embedded launcher verifier, inherit
`JAVA_TOOL_OPTIONS=-agentlib:zbNative -Xmx2G` and create a launch plan. The
verifier required both the ZombieBuddy option and Knox `=pz-game` agent to be
present, and `tools/build-launcher.ps1` packaged that implementation. Those
embedded files are no longer present in the main repository.

### Evidence
The main repository diff retires all 12 tracked embedded launcher project/source
files and `tools/build-launcher.ps1`; `docs/LAUNCHER.md` now names the separate
launcher repository as the sole source, verification, and packaging owner and
rejects active ZombieBuddy composition. In the sibling
`KnoxSurvivorsLauncher` checkout, `scripts/build.ps1` passed launch-option
security/native-argument verification, updater metadata/version/checksum
verification, launcher verification with Knox and ZombieBuddy runtimes
isolated, and Windows bootstrap verification. The main repository structural
retirement check passed (13 tracked embedded files deleted),
`tools/verify.ps1` passed with 112 Lua sources, 174 Lua regression scripts,
Java checks/build included, 287 checks and 0 failures, and `git diff --check`
passed. These checks establish offline retirement and verifier behavior only;
they do not establish a live game launch.

### Expected
No supported Knox launcher path can package or run a competing instrumentation
runtime. Players use KnoxBridge through normal Steam startup.

### Acceptance
The stale embedded launcher build path is retired, the standalone launcher is
deprecated, and current-facing instructions direct users to KnoxBridge only.
No live acceptance is required for the retired launcher path. KnoxBridge live
startup and gameplay remain tracked separately under `KS-PROD-010` and
`KS-PROD-005`.

### Validation
Offline verification on 2026-09-27: sibling launcher `scripts/build.ps1` passed
the historical launcher/bootstrap checks; the main repository retirement
check and `tools/verify.ps1` passed (287 checks, 0 failed). On 2026-09-29,
current-facing Knox instructions were aligned to KnoxBridge and the separate
launcher was marked deprecated. The requested GitHub visibility change remains
unconfirmed. This does not establish current KnoxBridge live behavior or
release readiness.

## BUG-KS-008 — Detached companions can remain in a stale-shell limbo
Status: in_progress
Priority: high
Owner: Codex
Type: bug
Related: KS-PROD-008

### Symptom
An alive companion with a non-null shell but no current square can remain in
the active survivor registry while being skipped by off-screen simulation.
Without lifecycle classification, it can also accept order writes while it
cannot be normally simulated or re-materialized.

### Evidence
The bounded lifecycle correction classifies vehicle occupancy and recognized
native climb, vault, window, fence, and sheet-rope traversal as legitimate
temporary detached states that remain registered. An unexplained nil-square
companion shell receives ten hibernation checks of grace. During that grace,
new native companion order writes are rejected without changing the persisted
prior order. If detachment persists, the lifecycle uses the existing
transactional capture → native removal → `markStored` → unregister path, keeping
survivor identity and persistence ownership. Dismissal remains allowed as a
persistence ownership change. Recovery restores active order acceptance.

Focused offline coverage passed: `test-survivor-lifecycle-policy.lua`,
`test-detached-companion-lifecycle.lua`, `test-companion-commands.lua`,
`test-order-routing.lua`, `test-unloaded-survival.lua`,
`test-world-presence.lua`, `test-persistence-recovery.lua`,
`test-persistence-hot-path.lua`, `test-unloaded-base-return.lua`, and
`test-virtual-base-return-transaction.lua`. Full
`tools/verify.ps1 -SkipJava` passed: 112 Lua syntax files, 175 regression
scripts, 287 checks, 0 failed. `git diff --check` passed. These are offline
fixtures and do not prove native engine movement, streaming, or save behavior.

### Expected
No companion remains indefinitely registered without either valid simulation
or an intentional, recoverable lifecycle state. Temporary native detachments
remain registered, while a persistent unexplained detach is safely hibernated
with identity, order, inventory, and persistence state preserved.

### Acceptance
Focused tests cover detached classification; order acceptance/rejection;
active registry and off-screen behavior; safe return/rematerialization;
dead/nil-shell cleanup; and identity/persistence preservation. No duplicate
survivor body or lost survivor is introduced.

### Validation
Offline coverage listed above passes. Still required in live Build 42:
vault/climb transitions, cell-edge and streaming gaps, vehicle occupancy,
prolonged unexplained detachment, dismissal, save/reload, and subsequent
rematerialization. BUG-KS-008 and KS-PROD-008 remain open; no native behavior or
release readiness is established by offline tests.

## BUG-KS-009 — Off-slot survivor visibility writes throw Build 42 lighting exceptions
Status: in_progress
Priority: high
Owner: Terra
Type: bug
Related: KS-PROD-008

### Symptom
During a live controlled survivor combat observation, Knox repeatedly called
`IsoGridSquare:setCouldSee` for an off-slot survivor shell. Build 42's lighting
JNI rejected that call with `java.lang.IllegalStateException` from
`LightingJNI$JNILighting.bCouldSee`, producing repeated errors while the
survivor was in combat.

### Evidence
On 2026-09-27, disposable Build 42.20.4 save `KS-QA-Vertical-1` recorded 76
occurrences between 04:58:02 and 05:02:50 in
`<Zomboid-Logs>\2026-09-27_04-42_DebugLog.txt`. The Knox stack
is `KS_ZombieAwareness.setSquareBit` → `ensureVisibilityBit` → `update` →
`KS_SurvivorAutonomy`; the fixture was `ks-dev-1` in `COMBAT`. This confirms an
unsafe Knox lighting-state write, not native combat success or failure.

### Current correction
`KS_ZombieAwareness` no longer writes or clears native `setCouldSee` bits for
off-slot survivor shells. It retains native target selection and reports the
disabled unsafe assist once. The focused zombie-awareness regression verifies
that no lighting bit is written while native targeting remains available.

### Validation
Offline after the correction: `tools/test-zombie-awareness.lua`,
`tools/test-automated-qa.lua`, and `tools/verify.ps1 -SkipJava` passed (112 Lua
syntax checks, 175 scripts, 287 checks, 0 failed); `git diff --check` passed.
Still required: rerun one controlled Build 42 zombie encounter and confirm no
`LightingJNI.bCouldSee` exception while recording the native combat result.
Multi-zombie threat selection, native damage, and retreat behavior remain
unverified.

Additional Build 42.20.4 diagnostic evidence collected 2026-09-28 in
`dev-runs/20260928-021135`: the Knox log contains the one-time
`visibility_bit_disabled` marker and the console extract contains no
`LightingJNI`, `bCouldSee`, or `setCouldSee` failure. This supports that the
unsafe call is no longer being attempted in this run, but is not a standalone
focused replay or proof of all combat outcomes. The same session includes
native zombie attacks that reached `AttackDidDamage=true` and reduced survivor
health (for example, 100 to 96.96 and then 92.40), so the off-slot boundary is
not a blanket failure to damage survivors.

The controlled `combat_group_horde` scenario in that run ended `PARTIAL`:
15 survivor hits, zero zombie damage, and no kills. This mixed encounter does
not change the offline base-danger arbitration coverage or identify a new
source defect. Do not repeat that source audit without new evidence. Keep the
one-zombie and small-group native combat replay in Slice D live acceptance.

## BUG-KS-010 — Speech indicator overlay renders as a dark or malformed layer
Status: in_progress
Priority: medium
Owner: Codex
Type: bug
Related: KS-PROD-008

### Symptom
The owner observed the survivor communication arrow appearing black/ugly and
normal right-click interaction appearing unavailable while it was visible.

### Evidence
`KS_SpeechIndicators` created a full-viewport `ISPanel` without disabling
`ISPanel`'s default half-black background. The shaft also drew a same-width
near-black line at the exact coordinates of its coloured line. The overlay did
call `setWantMouseEvents(false)`, so source inspection does not establish that
it intentionally consumed input; the Activity Feed remains a separate normal
interactive window above world input.

### Current correction
The render-only overlay explicitly disables its background, retains
`setWantMouseEvents(false)`, uses one high-contrast coloured arrow, rejects
missing/stale coordinates, removes expired entries, and resets its owned panels
and marks at game start. It remains Knox-owned and imports no foraging code or
assets.

### Validation
`tools/test-speech-indicators.lua` passes range, compass, transparent style,
mouse-pass-through configuration, expiry, and stale-coordinate checks. Lua
syntax and related UI/order regressions pass. Still required in Build 42:
visually confirm the indicator colour/projection and open an ordinary world
right-click menu both outside and over the Activity Feed while the arrow is
visible.

## BUG-KS-011 — Formation cadence delays follow resumption after fence landing
Status: in_progress
Priority: medium
Owner: Codex
Type: bug
Related: KS-PROD-008

### Symptom
The owner observed a survivor stand for several seconds after completing a
fence traversal before resuming follow behavior.

### Evidence
`refreshFormationFollow` returned on its existing refresh deadline before it
checked native traversal state. A climb that began between refreshes, or a
landing before the deadline, could therefore hide the busy-to-landed transition
behind the old cadence even though native traversal had finished.

### Current correction
Formation follow now observes native traversal before applying its ordinary
refresh cadence, leaves the native climb/vault action untouched, and immediately
reevaluates on the first landed update. With developer diagnostics enabled it
emits bounded `traversal_started` and `traversal_completed` movement entries.

### Validation
`tools/test-autonomy-formation.lua` verifies that active fence traversal keeps
native ownership and that the first landed update clears the traversal latch
without waiting for the old deadline. Related combat, command, order, social,
and QA regressions pass. Live Build 42 fence replay remains required to confirm
animation completion, natural timing, and absence of duplicate route requests.

## BUG-KS-012 — Survivors have no active retreat policy for overwhelming fights
Status: in_progress
Priority: high
Owner: Codex
Type: bug
Related: KS-PROD-008

### Symptom
The owner observed survivors entering multi-zombie fights that appeared
overwhelming instead of reconsidering or withdrawing.

### Evidence
The pre-correction controller gathered nearby zombies, humans, health,
endurance, allies, and escape-lane inputs, but `fleeAssessment`,
`findFleeTarget`, and `beginFlee` were explicitly short-circuited as
`flee_retired`. Loaded survivors could therefore select and retarget threats
but had no active risk-based retreat handoff. This source boundary is
consistent with the visible report; it did not establish balance thresholds or
prove any native escape route.

### Current correction
The dormant native-movement retreat path now has a bounded admission policy. A
retreat needs a real open escape lane plus visible or actively targeting danger;
healthy, equipped survivors hold against a one-on-one or small non-targeting
encounter. Overwhelming immediate pressure, critical health, injury, or severe
exhaustion can admit a retreat. Existing route safety, retry/recovery, two-safe-
scan completion, order preservation, and native movement ownership remain in
place. Direct player companions and base residents retain their existing guard
against autonomous retreat until those ownership rules are separately designed.

`test-combat-intelligence.lua` and `test-autonomy-formation.lua` now cover
one-on-one/small encounters, crowd pressure, injury, exhaustion, equipment,
nearby allies, escape lanes, blocked lanes, and native-request admission. The
focused companion/order/conversation checks and `tools/verify.ps1 -SkipJava`
passed: 112 Lua syntax checks, 175 scripts, 287 checks, 0 failures; `git diff
--check` passed.

### Remaining live verification
Build 42 must still compare a healthy equipped survivor against one zombie and
a small group, then an overwhelming group with a real viable escape lane. Record
whether native movement begins once, reaches a safer tile, re-evaluates danger,
and resumes without a run-stop-return loop or fabricated combat result.

The retreat admission regression was re-run during the 2026-09-27 fallback
review. `test-combat-intelligence.lua`, `test-autonomy-formation.lua`, and
`test-threat-classifier.lua` passed; no new offline regression was found. Live
Build 42 combat and escape-route verification remains outstanding.

## Community-reported backlog — unverified until reproduced

The following reports were copied from the Discord bug tracker on 2026-09-27.
They are intentionally recorded as `reported` rather than confirmed bugs. Some
may already be fixed, may be design requests rather than defects, or may have
come from a different mod/version/setup. The external reference path supplied
by the owner is held in a local owner-only bug inbox; inspect it only
when the related item is actively investigated. Do not treat those files as
authoritative without matching the Build 42 version, Knox revision, save, and
runtime setup.

Priority is provisional and reflects player impact plus dependency order. These
items should be deduplicated against existing systems before implementation.

## BUG-KS-013 — Survivors can idle indefinitely at bases
Status: in_progress
Priority: high
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Survivors sometimes stand around the base doing nothing instead of resting,
using furniture, reading, sleeping, moving naturally, or choosing useful idle
life behavior.

### Verification needed
Offline source review found an existing base-life decision path for needs,
explicit orders, settlement shortages, eligible tasks, hygiene, scheduled rest,
ambient movement, snacks, socializing, television, and storage organizing. The
focused offline checks `test-base-ambient-life.lua`, `test-duty-schedule.lua`,
`test-roaming-autonomy.lua`, `test-base-jobs.lua`, `test-base-needs.lua`,
`test-base-duty-controller.lua`, and `test-base-duty-simulation.lua` pass. They
do not prove native Build 42 actions start or that residents visibly behave
naturally, so this report remains open pending live reproduction.

A narrow offline ownership defect was confirmed and corrected: `onDutyChanged`
interrupted pending recreation but omitted pending organizing. Leaving base
duty, changing bases, or turning hauling off could therefore retain the
organizer action, route, and item/container claims. It now uses the existing
directive-interruption path. `test-companion-commands.lua` dynamically covers
unchanged valid duty, leaving base duty, hauling disabled, and base reassignment,
asserting one action/route cancellation and released item/container claims.
The focused base-life set (`test-companion-commands.lua`,
`test-base-organize-wiring.lua`, `test-base-recreation.lua`,
`test-base-ambient-life.lua`, `test-base-needs.lua`,
`test-base-duty-controller.lua`, `test-base-duty-simulation.lua`, and
`test-base-task-board.lua`) passed 8/8; `tools/verify.ps1 -SkipJava` passed 112
Lua sources, 176 scripts, 288 checks, and 0 failures. This is offline evidence
only: native timed actions, real item transfer, and base-duty/UI behavior still
need Build 42 validation and do not establish that the reported visible idling
is solved.

The latest diagnostic run records the surrounding symptom: in
`dev-runs/20260928-021135/console-since-launch.txt`, line 2441 reports
`base_movement:FailedStuck` before line 2483 shows the resident back at
`BASE_IDLE`; lines 3794 and 3830 record a failed rest route and the resident
in `BASE_AMBIENT_REST`. These are explicit movement failures that reach existing
recovery, not evidence that the watchdog timeout itself occurred.

An additional offline watchdog gap is now corrected at the same controller
owner: `MOVING_TO_REST` that exceeded its movement deadline previously fell
through generic abandonment instead of taking the existing real ground-rest
fallback, and timed-out `BASE_PATROL`/`BASE_RETURN` skipped
`handleBaseMovementFailure`, leaking the selected ambient-square reservation
and bounded failure record. Both timeout paths now use their existing recovery
owners. The extended dynamic `test-base-leisure-routing.lua` exercises actual
`tick` watchdog dispatch for patrol, return and rest, including route
cancellation, reservation release, backoff and the native rest-action fixture.
This script is local under ignored `tools/`; it is not a tracked Git change.
The focused base-life recovery set passed 7/7 and the full offline gate passed
112 Lua files, 177 scripts, 289 checks, 0 failures. Explicit native movement-
failure logs already show rest/patrol falling back correctly; no hung watchdog
route was observed live. Keep the reported visible base-idle behavior open
until a Build 42 full-day replay covers a never-resolving chair approach and a
stalled base patrol/return, verifies another resident can claim the released
square, and confirms the resident can resume an ordinary real-resource job.

Source review for the public food-availability report found a separate current-
development handoff gap inside this broader base-life report. `Needs.decide()`
already selects real safe food and the existing action path verifies hunger
reduction, but ordinary active base-task states returned from `tick()` without
rechecking needs. A resident could therefore remain committed to work, a task
action, or a supply transfer after hunger became urgent. The controller now
checks these ordinary task states on a bounded cadence and yields actionable
self-care through the existing task suspension owner. The claim remains held;
native transfer leases are released through their current owner, and normal
task restoration remains responsible for resumption. Focused claim-suspension,
needs, task validation/arrival, base action/cooking/security/recovery checks
passed; the exact-worktree offline gate passed 112 Lua sources, 177 regression
scripts, 289 checks, 0 failures. Test scripts remain local under ignored
`tools/` policy. This confirms an offline arbitration gap, not the specific
September 23 Steam report or native food access. Keep that report open pending
the live replay below.

Live replay: with one resident assigned ordinary non-guard work and another
case in a real supply transfer, make the resident hungry while safe edible food
is in an accessible assigned fridge/pantry. Verify ordinary work yields,
actual food access and Build 42 eating reduce hunger, the exact task claim is
retained without duplication, and useful work resumes. Repeat with food only
inside a nested container and with unavailable/unsafe food to confirm truthful
failure/retry rather than fabricated relief. Include save/reload while the task
is suspended if the task claim persists across that state.

For that replay, use a disposable save with a safe, loaded base and two or more
base residents. Keep player orders, urgent needs, active threats, and in-flight
jobs out of the baseline; give the base usable chairs/beds and ordinary
recreation objects. Enable existing autonomy diagnostics. Observe across one
full in-game day, recording each resident's identity, duty/schedule, visible
behavior, and periodic **Write Survivor Status to Log** output. Then run one
controlled useful-work case with the required real items available and one
resource-missing case. In the latter, confirm no work is fabricated and record
any visible/logged blocked reason or complaint. If a resident appears stuck,
capture repeated status lines with `state`, `decision`, `destination`,
`lastFailure`, `failureTick`, and `retryAt`, plus the matching short DebugLog
slice. Classify standing during a valid wait/retry separately from a resident
that remains stationary after its decision or native action has failed.

## BUG-KS-014 — No reliable base cleanup order
Status: in_progress
Priority: medium
Owner: Codex / OpenCode
Type: behavior/design
Related: KS-PROD-008

### Report
There is no dependable way to direct survivors to collect loose ground items
and place them into appropriate storage.

### Verification needed
Compare existing hauling, storage claims, and job/task-board behavior before
adding a new cleanup job. Do not duplicate the existing hauling/organize path.

Offline source review distinguishes two existing paths from the reported need:
carried-inventory cleanup/deposit and a claimed corpse-hauling task. No general
base job was found that collects arbitrary loose ground items and routes them to
typed storage. The bounded ground-item cleanup/storage concept is already a
future design candidate in `docs/production/ROADMAP.md`; no new cleanup system
or ground stockpile was added in this pass.

## BUG-KS-015 — Loot deposit and resupply are unreliable
Status: reported
Priority: high
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Loot, food, tools, materials, medicine, and ammunition do not always flow
reliably between survivors, jobs, needs, and designated base storage.

### Verification needed
Trace one real loot → storage → need/job resupply loop and identify the first
failed transfer, claim, reservation, or ownership boundary.

Offline audit found no additional confirmed defect beyond the corrected
BUG-KS-016 category wiring. The existing path connects loot selection and
carried-item protection (`KS_SurvivorLooting`), controller-owned deposit trips
and retries, typed/capacity-aware destinations (`KS_BaseStorage`), native
inventory-transfer actions, shortage/task supply planning, and persistent duty
ownership. Focused storage, organizer, supply, needs, cleanup, job, inventory,
and persistence tests passed in the 2026-09-27 review. These fixtures cannot
prove native movement, reachability, container mutation, or save/reload. Keep
this report open for one disposable live loop: real loot → assigned typed
storage (then General fallback) → need/job withdrawal, checking item identity
and counts before/after and after reload.

## BUG-KS-016 — Storage category routing is incomplete
Status: in_progress
Priority: high
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Survivors sometimes use containers that do not match their assigned category.
The reports also request multiple storage areas of one type, a General Storage
fallback, and a Log & Firewood Storage area.

### Confirmed offline boundary
`KS_BaseContextMenu` exposed “Use for Logs & Lumber” and
`KS_BaseStorage` already classified logs, tree branches, twigs, and firewood
under the `logs` role. `KS_BaseManager.STORAGE_CATEGORIES` did not admit
`logs`, however, so selecting that visible option failed with
`unknown_storage_category` before any persistent assignment or native transfer
could occur.

### Current correction
The manager, player menu, and persistence validator now accept the existing
`logs` role. The same assignment path now exposes and persists the already
implemented `general` role, whose matcher and deposit fallback accept otherwise
unclassified real items. The storage label follows each assigned role. Focused
coverage selects/removes both policies, checks persistence validation, verifies
General Storage fallback, and checks Log, TreeBranch, Twigs, and Firewood
classification. No new transfer, claim, or resupply owner was added.

### Validation and remaining scope
On 2026-09-27, `test-base-storage-menu.lua`, `test-base-storage.lua`,
`test-base-organize-wiring.lua`, `test-base-supply-routing.lua`,
`test-base-supply-planner.lua`, `test-base-jobs.lua`,
`test-base-task-board.lua`, `test-multi-base.lua`, `test-base-needs.lua`, and
`test-inventory-cleanup.lua` passed. `tools/verify.ps1 -SkipJava` passed: 112
Lua syntax checks, 175 scripts, 287 checks, 0 failures; `git diff --check`
passed.

Multiple same-category stores, typed overflow, and category selection have
offline coverage. Real loot → storage → need/job resupply behavior, physical
container transfer, and save/reload remain live-unverified. Loose ground-item
pickup is a separate future feature candidate, not implemented by this fix.

## BUG-KS-017 — Base boundaries are inaccurate or cannot join connected areas
Status: reported
Priority: high
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Large bases may calculate inaccurate boundaries, and players cannot reliably
attach additional connected buildings or areas to an existing base.

### Verification needed
Offline review found the boundary editor selects two world squares and commits
through `KS_BaseManager.setTerritory`; `KS_Persistence.normalizedBaseTerritory`
sorts both axes into canonical min/max coordinates before saving. Territory
ownership is one axis-aligned rectangle and applies to all floors. The existing
selector regression only checks cursor setup, modal invocation, and one save
call; it does not assert selected coordinates or persisted bounds. No offline
geometry defect is confirmed, and UI projection/hit-testing still requires a
live replay.

On a disposable copy of the affected save, record the Build 42 version, Knox
revision, runtime/mod path, save identity, and the existing base ID/bounds.
Using the current boundary editor, select the same large asymmetric area in
both corner orders. Record the two clicked world-square coordinates, draft
highlight, confirmation dimensions, saved min/max bounds, and reopened editor
state. Check all four boundary edges and immediately adjacent tiles against
base ownership, then save/reload and check the same values again. For a
connected building/area, record whether it lies inside the rectangle or
outside it; the current single-rectangle model cannot claim disjoint areas, so
do not interpret this as an existing polygon/union feature.

## BUG-KS-018 — Fort Waterfront boundary selection flips
Status: reported
Priority: high
Owner: Codex / OpenCode
Type: UI/behavior
Related: BUG-KS-017

### Report
Open Base Management → Edit Boundary can flip between the main fort and the
pasture/farm area while selecting the full Fort Waterfront location.

### Verification needed
Reproduce on the same disposable Fort Waterfront save referenced by BUG-KS-017.
Record the clicked world-square coordinates and screenshots of the live draft
highlight and confirmation size while selecting the main fort and pasture/farm
corners in both directions. Compare those values with the saved territory
bounds and the reopened boundary display before and after save/reload. If the
clicked squares themselves differ from the cursor target, investigate
Build 42 cursor/screen-to-iso hit-testing; if clicks are correct but the draft
or saved bounds differ, isolate rendering versus persistence next. Offline
normalization currently sorts reversed corners, so a live flip is not yet
explained by source inspection. Keep this report separate from the larger
connected-area feature request in BUG-KS-017.

## BUG-KS-019 — Survivors leave doors open after passing through
Status: reported
Priority: medium
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Survivors do not always close doors after traversal. Any automatic close policy
must respect permissions/settings and avoid open/close loops.

### Verification needed
Test normal passage, combat interruption, player-owned doors, locked/blocked
doors, and repeated pathing through the same doorway.

Offline source review confirmed a narrow failure in the supported `setOpen`
fallback: door cleanup requested `setOpen(true)`, so a door wrapper without a
toggle method could never be closed by that path. The fallback now receives
the requested open/closed state, with focused coverage in
`tools/test-door-discipline.lua`. This does not confirm the reported behavior
for native Build 42 doors; the live traversal scenarios above remain required.

## BUG-KS-020 — Barricade jobs stop before completing valid windows
Status: reported
Priority: medium
Owner: Codex / OpenCode
Type: job
Related: KS-PROD-008

### Report
Barricade work may stop after one window or one pass instead of processing all
valid windows. The report also requests configurable plank counts per side.

### Verification needed
Confirm whether the current job intentionally bounds work, loses its claim,
fails native actions, or exits after one target. Treat plank-count options as a
separate design request until the job failure is reproduced.

Offline review found the implementation intentionally creates one target task
at a time, excludes claimed targets, and rediscovers work through the recurring
job pass after completion/retry. Focused barricade, task-validation, job, and
task-board tests pass, but do not exercise a full native timed-action cycle
followed by discovery of a second opening. Keep this report unconfirmed; on a
disposable loaded base, observe two valid windows through completion of the
first native action and record task IDs, claims, material counts, action result,
and whether the second window is offered.

## BUG-KS-021 — Owned survivor map tracking is incomplete
Status: reported
Priority: medium
Owner: Codex / OpenCode
Type: UI/feature
Related: KS-PROD-008

### Report
Owned survivors should remain visible on the map while offscreen, with nearby
survivors optionally grouped into a marker.

### Verification needed
Check existing map marker ownership, unloaded identity records, privacy/performance
limits, and whether this is missing functionality rather than a regression.

Offline source review found an existing Knox-owned overlay in
`KS_MapOrders.ownedLocations`: it resolves owned living survivors from loaded,
persisted logical, then last-known coordinates, and renders durable death
evidence separately. `tools/test-map-owned-locations.lua` covers ownership
filtering, coordinate confidence, unloaded/deceased records, duplicate-free
identity enumeration, bounded refresh/cache behavior, and preservation of
native right-click handling. No stale-marker defect was reproduced offline.
Nearby-survivor grouping is not implemented, and Build 42 map projection,
save/reload, and streaming behavior remain live-unverified; keep this report
open as a feature/live-validation candidate rather than a confirmed defect.

## BUG-KS-022 — Faction base map markers are missing or stale
Status: reported
Priority: low
Owner: Codex / OpenCode
Type: UI/feature
Related: KS-PROD-008

### Report
Known faction bases should have map markers that update or disappear when a
faction moves, dies, or abandons the location.

### Verification needed
Wait until faction/base lifecycle is live-validated. Do not add marker state
that can become another stale ownership system.

Offline source inventory found durable faction-owned base records and existing
relocation/removal paths, but no faction-base map-marker consumer. This is a
missing map feature, not a stale-marker regression in the current implementation.
Any later implementation should derive presentation from current faction/base
records rather than adding a parallel marker ledger. Lifecycle and map behavior
still require live validation.

## BUG-KS-023 — Survivor work priorities need more player control
Status: reported
Priority: high
Owner: Codex / OpenCode
Type: feature request
Related: KS-PROD-008

### Report
Players need clearer control over work priorities such as hauling, cleaning,
farming, construction, guarding, medicine, cooking, and animal care.

### Verification needed
Compare the existing job/task-board and preference systems first. This is a
candidate expansion informed by RimWorld, not proof that the current system is
broken.

Offline audit classifies this as a feature/design candidate rather than a
confirmed defect. Existing controls include an explicit resident job
preference, Auto profession hint, persisted work-group priorities (Auto/1–4/
Never), duty schedules, and guarded assignment of a concrete queued task.
`KS_BaseJobs` applies preferences as a first-pass selection hint, then falls
back when matching work is unavailable; capability, real requirements, task
priority, security coverage, and fairness remain authoritative. Focused
`test-base-jobs.lua`, `test-base-task-board.lua`, `test-work-priorities.lua`,
`test-survivor-origins.lua`, and `test-contextual-origins.lua` passed. Broader
ranked multi-role profiles and work groups such as cleaning/medicine/animal
care are not established by this coverage and would need product scoping before
implementation. No full colony-style priority grid is implied.

## BUG-KS-024 — Offscreen survival behavior is incomplete
Status: in_progress
Priority: critical
Owner: Codex
Type: behavior/architecture
Related: KS-PROD-008, BUG-KS-001

### Report
Survivors should continue bounded travel, looting, eating, resting, combat,
injury, death, resource gathering, and return-to-base behavior while away from
the player.

### Verification needed
Reconcile this report with the existing unloaded-survival architecture and
BUG-KS-001. Never manufacture native combat, loot, death, or world damage from
an unloaded state without documented simulation authority.

### Evidence
Offline source review found `KS_UnloadedSurvival.advanceHibernated` applying a
daily deterministic "scuffle" to autonomous and supply-running survivors. It
could reduce persisted health, mark an unloaded survivor dead, and create a
`fight` trace at virtual coordinates; later restoration could apply the saved
health to the native body. That crossed the loaded/native-combat boundary.

The scuffle branch is removed. Unloaded survival still advances only its
persisted needs, real carried supply consumption, rest, and logical travel. It
does not create combat injury, death, blood, or fight traces. Focused unloaded
survival, group, world-trace, and event-runtime tests pass. `tools/verify.ps1
-SkipJava` then checked 112 Lua files and ran 175 regression scripts (287
checks, zero failures). Native materialization and real save/reload behavior
remain live-unverified.

The same transition review found automatic hibernation removed a native shell
before committing its `hibernated` ledger state. A failed final ledger write
could therefore unregister the controller after body removal, leaving no valid
active or unloaded owner. Hibernation now commits stored ownership first; a
failed commit retains the active shell, and removal succeeds only when the
bridge confirms that no shell remains. A failed removal re-captures the loaded
snapshot before its bounded retry. Focused lifecycle, virtual-base-return,
unloaded-survival/base-return, and away-team tests pass, followed by the same
full offline gate. Native removal acknowledgement and real save/reload remain
live-unverified.

Away-team dispatch had the same ownership mismatch across a multi-member
handoff. A failed pre-removal store/team commit could leave a live body with a
`hibernated` ledger; a middle/final native removal failure could restore normal
duties for members whose bodies were already gone. Dispatch now rolls stored
ledger ownership back to `loaded` for every still-live member on a pre-removal
abort. Members already confirmed removed remain hibernated and recoverable,
while the durable dispatch record is blocked rather than reported as outbound.
Focused coverage exercises valid, invalid, duplicate, dead, store/team failure,
first/middle/final removal failure, recovery and retry paths. It preserves the
same identity, inventory/equipment/needs ledger, orders and affiliation in
fixtures. The current `tools/verify.ps1 -SkipJava` run checked 112 Lua files
and ran 176 regression scripts (288 checks, zero failures). Live native
teardown, save/reload, rematerialization and duplicate-body evidence remain
required.

The blocked-dispatch recovery path is now also covered offline. Only members
whose removal was acknowledged retain the `away` duty beneath the blocked
ledger; members whose shell remains live recover their previous duty
immediately. The blocked ledger persists across a Lua persistence reload and
an acknowledged removed member can release its prior duty only after the
canonical record-restoration path has registered a body. Finalization failure
uses the same blocked ownership path. This does not prove native removal,
record reconstruction, inventory/equipment restoration, or duplicate-body
prevention in Build 42; those remain live acceptance requirements.

## BUG-KS-025 — Independent survivor/group/faction decision-making feels weak
Status: reported
Priority: high
Owner: Codex
Type: behavior/architecture
Related: KS-PROD-008

### Report
Independent survivors, groups, and factions can feel like random wandering or
looting instead of making decisions around supplies, danger, food, water,
healing, shelter, combat, and travel.

### Verification needed
Measure the existing decision chain and identify the first missing or failing
priority before adding new behavior or faction types.

Offline review did not identify a deterministic priority/ownership failure.
The existing single-survivor need evaluator gives active threats and medical,
water, food, recovery needs precedence; the controller then applies durable
orders, group-support/scavenge coordination, and ordinary autonomy through the
existing controller path. Focused needs, work-priority, anti-flap, group support,
group scavenging, and behavior-integration tests passed in the 2026-09-27
review. This does not establish that decisions look believable during native
gameplay. Keep the report open until a live observation identifies the first
undesired decision with survivor identity, state, need/threat snapshot, group
role, and selected action.

## BUG-KS-026 — World population ownership is not yet proven unified
Status: reported
Priority: high
Owner: Codex
Type: architecture/design
Related: KS-PROD-008

### Report
Solo survivors, groups, and factions should use one balanced population,
identity, origin, affiliation, and lifecycle system, with solos common, groups
less common, and factions rarer.

### Verification needed
Source review indicates a shared foundation, but live allocation, origin
uniqueness, event ownership, and performance remain to be demonstrated. Do not
tune population counts until a measured bottleneck exists.

The 2026-09-27 offline ownership review found no deterministic identity/origin
collision path: `KS_WorldPopulation` allocates through the persistence-owned
`allocateWorldSurvivor` boundary, which rejects reused population origin keys;
groups and factions attach to canonical survivor IDs, and event-entry creation
allocates those same identities before claiming event duty. Focused world-
population, contextual-origin, faction-development, event-entry, and named-event
runtime tests passed. These checks do not prove Build 42 spawn-catalog
completeness, live materialization/activation, concurrent streaming behavior,
or real-map performance. Keep population balance and unified ownership reported
until those are measured in-game.

## BUG-KS-027 — Custom survivor/group/faction creator is missing
Status: reported
Priority: low
Owner: Codex / OpenCode
Type: feature
Related: KS-PROD-008

### Report
The owner would like a creator for custom survivor, group, faction, and event
definitions including appearance, traits, skills, gear, relationships,
hostility, spawn rules, and locations.

### Verification needed
This is a future expansion, not a current bug. Defer until existing population,
identity, faction, persistence, and performance boundaries are stable.

## BUG-KS-028 — Group followers pause instead of fluidly following their leader
Status: in_progress
Priority: high
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Followers in NPC groups or factions may stop, think, and resume repeatedly
instead of following their leader fluidly. The problem appears more visible in
followers than leaders. Groups must still perform needs, jobs, combat,
traversal, and survival behavior without becoming permanently locked to
formation movement.

### Intended direction
Leaders should be able to issue group-level orders comparable to player group
orders. Followers should retain local autonomy for urgent needs, threats,
traversal, recovery, and valid individual tasks. Leader orders should be
explicit, interruptible, persisted where appropriate, and resumed after a
valid interruption instead of repeatedly resetting the follower brain.

### Verification needed
Reproduce with a leader and at least two followers across ordinary movement,
doors, fences, combat interruption, needs, distance changes, and save/reload.
Compare decision cadence, route ownership, formation refresh, order arbitration,
and native movement completion. Determine whether the pause is caused by
formation cadence, route requests, order arbitration, native movement timing,
or expected autonomy interruption.

Do not solve this by teleporting followers, ignoring threats/needs, or
reissuing native movement orders in a loop.

### Offline evidence
The `GROUP_FOLLOW` native-success branch was unconditionally entering a
45-tick `GROUP_WAIT`, even when the leader had already moved beyond the route's
completed formation slot. That source-level delay made a follower wait before
normal formation arbitration could consider the next bounded route. Successful
group routes now return to `IDLE` for the next controller tick without issuing
a movement request themselves. Existing route-commit, cadence, threat, need,
combat, traversal, and movement-failure owners remain authoritative.

`tools/test-autonomy-formation.lua` now covers native group-route success,
immediate re-arbitration, and no duplicate request from the success handler.
Focused formation, relationship, unloaded-group, order-routing/signals, and
behavior-integration checks passed. `tools/verify.ps1 -SkipJava` checked 112
Lua files, ran 176 regression scripts, and reported 288 checks with zero
failures. Build 42 still must verify actual leader-plus-multiple-follower
movement, doors/fences, combat/need interruptions, native route timing, and
save/reload continuity. The bounded leader-order slice below is now part of
the follow-up evidence path; it does not complete this bug.

### Leader-order slice
The first NPC leader-order slice adds one durable group directive owned by the
canonical travel-group leader: `follow` or explicit bounded `hold`. It is
distinct from the leader's read-only autonomous life-intent summary and does
not own native movement, combat, or timed actions. Successful ordinary roam
and regroup routes now call the existing follow wrapper; invalid, dead, or
detached leaders are rejected. Persistence validates stored issuer, group, and
faction leadership, ignores legacy unbounded records, defaults a new directive
to a 0.25-game-hour lease, and keeps an identical default reissue's deadline
and revision. There is no autonomous hold choice, order UI, destination command,
or group mission in this slice.

Relationship coordination delivers a changed directive to current loaded
followers as pending formation-only arbitration. Delivery itself does not
cancel or replan. The controller may apply a responsive hold only after its
danger scan and only when traversal or a timed action no longer owns the body;
needs, jobs, combat, recovery, and retry owners remain protected. Identical
follow delivery causes no cancellation or route churn; a native cancellation
must report `MOVE_CANCELLED`, and a failure retries no faster than 60 ticks.

Extended relationship-coherence, autonomy-formation, and roaming-autonomy
coverage exercises persistence, delivery, route-only issuance, expiry,
deduplication, safe cancellation/retry, and fixture-shaped interruption.
The focused relationship, formation, roaming, order-routing, faction,
human-encounter, unloaded-group, and priority suites passed; `tools/verify.ps1
-SkipJava` checked 112 Lua files, ran 176 regression scripts, and reported 288
checks with zero failures; `git diff --check` passed. Build 42 still must verify
a disposable leader-plus-two-follower ordinary travel/regroup replay, a
developer-assisted persistence-API hold during fence/door and need/combat cases,
cancellation, expiry/reload, and no duplicate route requests. Leader-selected
destination movement, complex missions, raids, and group-order UI remain future
bounded work.

## BUG-KS-029 — Firearm behavior needs a dedicated stabilization pass
Status: reported
Priority: high
Owner: Codex
Type: behavior
Related: KS-PROD-005, KS-PROD-008

### Report
Firearm use, aiming, reloads, target selection, ammunition handling, friendly
fire, and combat recovery need a complete reliable gameplay pass.

### Scope note
This is a future stabilization track, not incidental work in group movement.
Use real Project Zomboid weapons, ammunition, aiming, reload, damage, and
native action state. Live evidence is required for claims about actual shots,
hits, damage, and recovery.

### Offline review and live acceptance
The first bounded firearm review found no source-confirmed offline defect.
`KS_FirearmSupport.lua` selects only carried real weapons, delegates reload and
racking to native timed actions, and does not write ammunition, magazine,
chamber, projectile, hit, damage, or kill state. The developer-only
`firearm_duel` fixture may seed its own pistol, empty magazine, and loose rounds
but is not gameplay supply behavior. Existing focused firearm, empty-hand,
reload-yield, combat-scenario/intelligence, equipment-intelligence, and
weapon-preference tests cover readiness, native action deduplication, fallback,
policy persistence, and fixture boundaries.

Required Build 42 evidence is one hostile `firearm_duel` replay plus an
allied/neutral bystander check: record weapon, magazine, chamber and loose-round
state before/after reload and a shot; native aiming/reload/attack state; target
health; friendly-fire result; interruption/recovery; and save/reload after a
reload and a shot. Native hook invocation telemetry is not proof of a shot or
damage without corresponding native observation. Keep BUG-KS-030 vehicle work
deferred; no vehicle ownership defect was identified by this firearm pass.

## BUG-KS-030 — Driving and vehicle behavior needs a dedicated stabilization pass
Status: in_progress
Priority: high
Owner: Codex / OpenCode
Type: behavior/compatibility
Related: KS-PROD-005, KS-PROD-008

### Report
Vehicle boarding, seating, driving, navigation, passenger group behavior,
vehicle ownership, fuel, exits, and recovery need a complete reliable gameplay
pass when the existing vehicle system is ready for focused work.

### Scope note
Per D-019, driving joins the core-completion track: autonomous NPC driving,
group vehicle acquisition, and 2–3 car convoys with no hard count cap.
Use real Project Zomboid vehicle state and native actions; do not add a
parallel abstract driving simulation. Hotwiring/key acquisition, forced entry,
player-assigned vehicle work orders with HP thresholds, specialist workstations,
and any vehicle-work UI remain deferred future tracks plugging into the
existing job catalog and Materials routing.

### Offline evidence (admission seam)
`VehicleTravel.assessReadiness` (`KS_NpcVehicleTravel.lua`) is now the single
shared verdict for a parked vehicle: driver, engine, driveability, speed,
towing, fuel (`getRemainingFuelPercentage`, sub-1% reads unfueled), and locks
(`areAllDoorsLocked`) resolve to one `ok, reason` result reusing the drive-
admission vocabulary; missing native state fails closed as
`vehicle_state_unknown`; locked vehicles are rejected (forced entry stays
deferred). Discovery (`safeVehicle`) delegates its state portion; drive
admission (`startDrive`) consumes the shared verdict with an identical local
fallback for contexts that never load the travel module. No movement, routing,
formation, leader-order, away-team, lifecycle, or persistence owner changed.
Focused vehicle set (`test-npc-vehicle-travel.lua` with the new ready/low-fuel/
locked/unknown matrix, `test-vehicle-driver.lua` with the fallback matrix,
`test-companion-vehicles.lua`, `test-vehicle-ownership.lua`,
`test-vehicle-navigation.lua`, `test-vehicle-journeys.lua`) passed 6/6;
`tools/verify.ps1 -SkipJava` passed 112 Lua sources, 176 scripts, 288 checks,
0 failures; `git diff --check` passed. Native fuel/condition/lock semantics,
real transfer/boarding, convoy seating, and control release remain live-only.

Boarding is now transactional: group boarding commits an explicit per-member
roster (`{member, vehicle}`) attached to the driver run, and every abort or
arrival rolls it back at once — pending leases cancel immediately instead of
waiting out the action timeout, and seated passengers get the existing native
exit (which still refuses a moving vehicle itself). Overflow beyond free seats
stays unleased and unclaimed rather than silently skipped. The same pass closed
a latent traversal hazard: clearing an absent driver-run key during `pairs`
is undefined behavior, so `stopDriver` now only clears a present key.
Focused roster/rollback coverage plus the full gate above pass with no frozen-
boundary changes. Real multi-car driving (a driver run per car), native seat
animation, and convoy spacing remain live future gates.

Duty/order arbitration now reaches vehicle leases: `onDutyChanged` routes an
active boarding lease or live driver run through the existing directive-
interruption owner (lease-free survivors untouched), and every `cancel` settles
the attached roster — except player takeover (`stopDriving`), which preserves
passenger leases so riders stay with the new driver. The same pass hardened
`stopDriver` against clearing an absent run key mid-traversal. Organizer-begin
needed no change: the tick vehicle guard already blocks it while a lease is
active or the survivor rides. Covered by the duty-lease matrix in
`test-companion-commands.lua` and the cancel/takeover matrix in
`test-vehicle-driver.lua` within the same 112/176/288 green gate.

Boarding stays interruptible and abort-stranded riders recover: a busy
boarding lease now yields to retreat-worthy danger (`fleeAssessment`) or a
critical need (`Needs.decide`, same non-`roam` convention as organizer rounds)
through the existing lease owner, rearming threat/think scans for next-tick
arbitration instead of holding the survivor deaf up to the 45s timeout; checks
fail safe on lean native state. An abort-time exit refused by a moving vehicle
marks the rider for a bounded stationary retry in the vehicle tick sweep (new
ownership wins, attempts while moving do not count down, 20-try give-up), so
no passenger sits lease-free with no owner. Covered by the new
`test-vehicle-boarding-urgency.lua` (healthy boarding kept, exhausted boarding
released, rescans armed) and the stranded-recovery matrix in
`test-vehicle-driver.lua` (moving waits, stopped retries). Full gate now
112 Lua sources, 177 scripts, 289 checks, 0 failures; `git diff --check`
passed.

Arrival is deterministic and honest: each roster passenger exits exactly
once with no re-queue on later ticks, the driver stays seated with nothing
queued and no run beneath them, and the feed speaks arrival exactly once;
base-vs-wasteland recognition stays explicitly pending with no lookup
invented. An unrecoverable exit reports one restrained member line instead
of printing forever. Multi-driver orchestration is confirmed out of reach
offline (one driver run per car plus native physics) and stays a Codex+live
design slice.

### Remaining live verification
Disposable-save Build 42 replay over real parked vehicles: engine off/on,
empty fuel, damaged/non-driveable condition, locked driver door, blocked seat,
occupied/player-near vehicle, towing state, and one valid fueled vehicle —
recording native accessor values, admission reason, boarding, route start, and
no unintended control takeover. Autonomous movement quality, convoy behavior,
and native part consumption are separate future gates.

## BUG-KS-031 — Automatic base supply claims ended before storage receipt
Status: in_progress
Priority: high
Owner: Codex
Type: behavior
Related: KS-PROD-008, BUG-KS-015

### Confirmed offline defect and correction
An automatic loaded base supply run previously recorded `collected` as its
terminal outcome immediately after pickup. That cleared the durable
`activeSupplyRun` and transient shortage claim before the resident returned and
the assigned typed-storage container confirmed receipt. Another resident could
therefore be elected for the same still-unmet shortage while the first real
item was in transit.

The autonomy owner now records `collected_returning`, persists the
`base_supply_deposit` return intent, and retains the run/claim until the native
inventory cleanup path confirms the item left the resident and reached the
destination. Missing carried items terminate explicitly. Focused election and
inventory-cleanup regressions verify duplicate-run suppression and release
only after receipt. Offline fix verified; native transfer, save/reload, and
container capacity remain live-only under BUG-KS-015/Slice E.

### Validation
2026-09-28: `test-base-auto-scavenge.lua`, `test-base-needs.lua`,
`test-inventory-cleanup.lua`, and `tools/verify.ps1 -SkipJava` passed; 112 Lua
files, 177 regression scripts, 289 checks, 0 failures. `git diff --check`
passed.

## BUG-KS-032 — Gift and money social acts rewarded trust without transfer
Status: resolved_offline
Priority: high
Owner: Codex
Type: behavior
Related: KS-PROD-008, D-020

### Symptom
The survivor context menu exposed `Offer Gift` and `Give Money`. Both called
`socialAct`, which increased relationship trust, recorded a meeting, played a
thank-you response, and returned success without checking or transferring a
real player-owned item. Knox has no account/balance owner for abstract money.

### Reproduction
Call `KnoxCompanionService.socialAct(player, survivorId, "offer_gift")` or
`"give_money"` while the survivor is nearby. Before correction, the offline
social-act regression asserted the trust increase with no inventory fixture.

### Evidence and correction
The service's `SOCIAL_ACTS` definitions granted +8/+6 trust; the context menu
advertised each action; `KS_OrderSignals` also mapped both to a thank-you
gesture. Neither path touched inventory. Those social-act definitions and stale
gesture mappings were removed. A distinct `Give Item` entry now opens the
existing Trade UI in gift mode. It requires explicit selection of an eligible
real item, rechecks recipient survival/task reserves, then uses the existing
native transfer journal, capacity check, receipt verification, rollback, and
survivor capture. The existing `gift` contribution rule grants its modest trust
increase only after that transaction verifies. `Give Money` remains removed:
there is no abstract account balance, though real supported currency objects
can be selected as real items. Direct calls to the old social-act names return
`unknown_social_act` before relationship, meeting, speech, or gesture mutation.

### Acceptance
No social-only action may stand in for a gift or money transfer. Gift trust is
awarded only after the selected real item is received and captured. Abstract
money remains unsupported; tangible currency follows the same item receipt
path as any other supported gift.

### Validation
2026-09-28: local ignored `tools/test-social-acts.lua`,
`tools/test-trade-valuation.lua`, `tools/test-trade-action.lua`, and
`tools/test-trade-ui.lua` edits passed (these are not tracked Git evidence).
Coverage includes missing gift selection, same-instance successful delivery,
post-receipt contribution reward, rollback with no reward, and menu/UI routing.
The full `tools/verify.ps1 -SkipJava` gate checked 112 Lua sources and ran 177
regression scripts (289 checks, 0 failed). `git diff --check` passed. These are
offline checks; live Build 42 still needs to confirm native gift/barter transfers,
recipient capacity, action cancellation, and save/reload of the received item.

## BUG-KS-033 — Base-job supply pickup failed to recover entry traversal
Status: resolved_offline
Priority: medium
Owner: Codex
Type: traversal
Related: KS-PROD-008

### Confirmed offline defect and correction
After a resident claimed real tools/materials from assigned base storage, an
entry-related native movement failure in `BASE_TASK_SUPPLY_MOVE` immediately
failed the entire task. The same controller already provided bounded
alternate-window and permission-gated door-break recovery for ordinary base
work movement, but this earlier storage leg bypassed it. The route now uses the
existing alternate-entry machinery with the actual assigned container's room
and approach. Quiet entry retains the exact task/item/container lease; a
permitted door break retains that lease until success, then resumes the same
route. If no permitted entry works, the existing task failure path releases
the claim and exact storage reservations. No transfer or work completion is
inferred from traversal success.

### Validation
Local ignored `tools/test-base-task-supply-entry.lua` exercises locked-route
entry, lease-preserving quiet entry, same-route resumption, one real transfer
queue after arrival, permitted door-break resumption, and truthful failure with
reservation release. `test-entry-and-escort.lua`, base-action lifecycle, task
validation, supply arrival, claim suspension and inventory cleanup regressions
also pass. The 2026-09-28 offline gate checked 112 Lua sources and ran 178 Lua
regression scripts (290 checks, 0 failed); Java was skipped. The focused script
is local under ignored `tools/` policy, not tracked Git evidence.

This does not reproduce or resolve every public locked-door report. Build 42
must verify native door/window actions, route continuation to a real container,
item receipt, permission/protection behavior, interruption and save/reload.
Corpse/fence handling remains bounded by existing drop cooldown and task retry
owners in offline coverage, but the reported repeated physical fence behavior
remains live-only and unconfirmed for current development.

## BUG-KS-034 — Base-job completion was reported before task-board acceptance
Status: resolved_offline
Priority: high
Owner: Codex
Type: base_jobs
Related: KS-PROD-008

### Confirmed offline defect and correction
Native executors verify their world result before asking the existing task board
to finish the claimed task. If ownership had been revoked or reassigned in the
meantime, the board correctly rejected the stale completion, but the autonomy
controller had already emitted `task_finished_ok`, advanced automatic-work
pacing, and several executor callers announced the job as complete. The
controller now treats the board response as the authoritative task outcome:
only accepted finishes emit task-finished success/failure and update pacing;
rejections emit a distinct failure diagnostic/reason, apply bounded retry delay,
and clear only the stale controller's transient state/reservations. Completion
speech is gated on board acceptance. Already-applied native world effects are
not rolled back or misrepresented as undone, and persistence/task-board ownership
is unchanged.

### Validation
Local ignored `tools/test-base-task-validation.lua` covers accepted automatic
completion/pacing, rejected stale ownership, failure evidence, task and supply
lease cleanup, no false success diagnostic, and no completion announcement.
Connected base-action lifecycle, task-board/persistence ownership, supply,
corpse, repair, farming, woodcutting, and base-work regressions were run with
the full offline verifier. The 2026-09-28 exact-worktree results are recorded
in `WORK_QUEUE.md` and `CURRENT_STATE.md`. Tests are local under the existing
ignored `tools/` policy and are not tracked Git evidence.

Build 42 still needs a real base-job completion while its claim is revoked or
reassigned, including native action result, truthful resident feedback, next
activity arbitration, and save/reload. Ordinary accepted work also needs a live
replay to confirm the native result and task-board lifecycle align.

## BUG-KS-035 — Active base supply runs could outlive their shared claim
Status: resolved_offline
Priority: high
Owner: Codex
Type: base_work
Related: KS-PROD-008, BUG-KS-031

### Confirmed offline defect and correction
The shared loaded-world shortage lease expired after 1.5 in-game hours even
when the same resident's persisted `duty.activeSupplyRun` still owned an
unfinished search or return. A different resident could then be elected for
the same shortage, duplicating travel and resource acquisition. The existing
autonomy owner now rehydrates a transient claim from each same-base resident's
valid active run before shortage election, including when the resident is
unloaded or the old transient lease expired. The claim remains ephemeral; the
persisted duty run remains authoritative and clears only through existing
terminal supply-run cleanup. No persistence schema, storage owner, or mission
system changed.

### Validation
Local ignored `tools/test-base-auto-scavenge.lua` advances world time beyond
the lease expiry while the first resident still owns an active run, then proves
the helper cannot start a duplicate and the original durable run remains
unchanged. Connected supply-planner, inventory-cleanup, and base-needs tests
passed. `tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 178
regression scripts (290 checks, 0 failures); `git diff --check` passed. The
focused fixture remains local under the repository's ignored `tools/` policy.
Build 42 still needs a real long-running shortage trip past the lease window,
including unload/reload, native pickup, return, storage receipt and
reassessment.

## BUG-KS-036 — Finalized loaded encounters were absent from survivor memory
Status: resolved_offline
Priority: high
Owner: Codex
Type: social
Related: KS-PROD-008, D-021

### Confirmed offline defect and correction
The loaded encounter coordinator committed greetings, declines, hostile
disposition, and group membership, but none of those final outcomes were added
to the existing persistent survivor history. That history already feeds later
dialogue recounts and the Survivor Card, so loaded social life could be real in
relationships yet forgotten by the same survivors. `KS_OffscreenStories` now
appends a bounded `meet` fact to each participant's existing canonical ledger;
it fails closed if that ledger is missing, deduplicates the same participant,
outcome, and world-time entry, and retains the existing 12-entry cap. The
relationship owner records only finalized outcomes: hostile means persisted
hostile disposition (not a successful robbery/fight), joined means a real group
mutation, and incomplete/interrupted encounters are not recorded. Existing
dialogue recounts distinguish joining, parting, and hostility without claiming
an unverified fight.

### Validation
Focused `test-offscreen-stories.lua`, `test-offscreen-recount.lua`,
`test-human-encounters.lua`, `test-relationship-coherence.lua`, and
`test-survivor-view-model.lua` passed.
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 178 regression
scripts (290 checks, 0 failures); `git diff --check` passed. Focused test edits
remain local under ignored `tools/` policy. Build 42 still needs loaded greet,
decline, join/rejection, and hostile encounter replay, followed by save/reload
and later dialogue/Card inspection. No native robbery or combat result is
implied by this history entry.

When a live/offline failure is found, add it using this format so ModForge can import it automatically:

<!--
## Example template — not a bug record
Status: todo
Priority: critical
Owner: OpenCode
Type: bug

### Symptom
What visibly fails.

### Reproduction
Exact steps/build/save/setup.

### Evidence
Log line, failing test, screenshot reference, or source boundary.

### Expected
What should happen.

### Acceptance
Observable fix criteria.

### Validation
Focused regression plus required live test.
-->
