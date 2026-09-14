# Development testing

## Repair supply replay - 2026-09-14

Damage a repairable door or structure while the worker has empty hands. Put the
required tools and parts in the assigned central storage and confirm the worker
collects them before native repair begins. Include an empty/depleted tool, a usable
duplicate, and optional repair parts; the usable combination should be selected.

Remove the target or make it structurally invalid during the supply trip. The
repair must stop safely. After delivery, verify native equipment, tool use, part
consumption and health change. A stored item must never be treated as already
carried, and a same-sprite object must never be substituted for a stale target.


## Structural crew replay - 2026-09-14

Give equipped repairers/builders several damaged structures, unfinished perimeter
edges and unbarricaded openings. Claim or block the first target and verify other
workers select another available site. Mix repair, construction and barricading
near one tile: only one structural task should occupy that tile at a time. Remove
a claimed repair object and leave another with the same sprite nearby/on the tile;
the old task must fail safely instead of repairing a substituted object.

Verify actual native repair health changes, barricade material consumption and
built perimeter stages. Cupboard-only repair startup is still unfinished; this
replay currently needs carried repair tools and parts. Live mixed-crew path/action
acceptance remains pending.


## Corpse and woodwork crew replay - 2026-09-14

Place two bodies on one tile and assign two haulers. Confirm they select different
bodies. Add a second corpse disposal area: bodies already inside either enabled
area must stay there. Designate a body's square as disposal while a worker is on
the way and confirm the old pickup stops. Disable that area and verify cleanup
can resume. Repeat with a blocked or claimed body and another available body.

Assign two woodworkers with multiple trees and log-processing areas. Confirm a
busy/retrying tree or processing area does not hide other available work, and
that native chopping/crafting still produces actual logs/planks. Watch for route
conflicts and inspect actual corpse grab/drag/drop animations in a disposable save.


## Multi-garden and animal work replay - 2026-09-14

Assign two farmers and two animal carers. Put empty plots in the first garden and
ripe/dry crops in later gardens; place feed needs before a separate thirsty trough
area. Verify maintenance wins over expansion, each resident selects a distinct
available target, and a failed/claimed target does not idle the rest of the crew.
After retry expiry, verify failed work is attempted again. Include a manually
prioritized task and confirm its priority is preserved.

Watch a crop through watering and rain: workers should refill to a safe reserve,
leave healthy crops alone and respect the native maximum where present. Give two
equally useful targets at different distances and check preference for nearby
same-floor work; blocked routes still use the ordinary job recovery. This replay
is pending and remains necessary despite passing offline selection checks.


## Base supplies and action ownership replay - 2026-09-13

Use an empty-handed resident with an animal-care area and real feed/water in
assigned storage. Confirm the worker collects the supply, reaches the trough and
changes its contents. Include an empty bottle of the same type alongside a full
one. Block every adjacent trough tile: the worker should defer rather than target
the occupied trough tile. Replace/remove a trough while a job is claimed and check
that the old job cannot act on a different object.

Put seeds, water and a digging tool in the worker's backpack. Confirm an unpack
precedes the native farm action. Include dead crops and two seed varieties: dead
crops must not receive watering jobs, and claimed planting must retain its selected
crop. Give a different order, introduce a threat, or unload/reload during a transfer,
turn-to-start, corpse pickup or work action. Old queued work must be cancelled;
temporary danger must retain the job claim for a fresh attempt afterward. These
are still live acceptance checks; mocked queues cannot prove native animations.


## Turn-aware driving replay - 2026-09-13

Enable experimental NPC driving in a disposable test save. From a passenger seat,
order a companion to drive to loaded open ground ahead, around a bend, behind the
car and around a parked obstruction. Confirm continuous steering, clearance for
the whole body, and braking near the destination. Repeat with a long vehicle and
one with offset body/collision parts. A destination without room for the nose must
be rejected or approached safely, never marked clear using only the centreline.

Block the route for about 14 seconds, then clear it: the same order should resume
without a no-progress cancellation. Cancel before the NPC reaches the driver seat:
the vehicle's controls must remain untouched. Cancel after driving, injure the NPC,
change driver, or attach a trailer: verify control release and player takeover.
Compare normal/poor tires and brakes, turns beside walls, downhill approaches and
newly moving pedestrians. Offline diagnostic journeys use simplified independent
dynamics and do not replace these native-physics checks.

### Base downtime replay - 2026-09-12

Use the matching updated agent. Leave several idle residents in a large base with
rooms, an upper floor and a yard. Confirm short walks, no immediate doorway ping-pong,
no pileups at occupied destinations, and indoor destinations after dark. A blocked
route should settle into an idle retry rather than escaping the base boundary.
Place a suitable book in assigned storage: watch collection, native reading and
return. Give Follow during the transfer/read/return, then restore base duty; the
physical book must remain accounted for. Turn off Base Reading during a read and
confirm the book is returned without starting another read. These checks also apply
to autonomous faction residents at their own base.

## Permanent guard/patrol replay - 2026-09-12

Use the matching newly staged mod and Java agent; this adds the area-routing bridge.

1. Give a companion Patrol Area, and assign a resident to a patrol work area. Watch
   several circuits: real stops and observation pauses should repeat without clearing
   the order. Include a narrow two-tile area and a larger irregular obstacle layout.
2. Block one corner, barricade a route, and stream out a destination. The survivor
   should try another in-area position or keep watch with a blocked-route status.
   Three failures must not erase Guard/Patrol. Clear the obstruction and verify retry.
3. Choose an area where the engine would prefer an outside shortcut or another
   floor. Verify that shortcut is rejected; the NPC must not tour the neighborhood
   to complete a patrol. Check both entry from outside and normal in-area movement.
4. Interrupt through thirst, hunger, combat and Follow. Needs/danger should preserve
   duties for resumption; Follow releases the companion order. Disable a base work
   area to release its resident, including while they are waiting on a blocked route.
5. Leave a guard and a partly completed patrol unloaded for more than four game
   hours, then return/save/reload. The original claims, last guard positions and real
   patrol progress should remain; needs and elapsed watch time still advance.
6. Shove/displace a guard outside the area. Verify movement stops safely, then a
   normal approach can bring them back. Test a new Move/Follow order to the same
   endpoint to catch a stale area restriction. Read the status log for failure and
   attempted destination when a route cannot resume.

Offline regressions use native API doubles and captured route data; they do not
prove game pathfinding or door/stair animation behavior in these layouts.

## Cooking and outdoor work replay - 2026-09-12

1. In a disposable powered base, assign Main Supplies and optionally a fridge as
   Food & Drink storage. Put raw fish or another nonmetal ingredient inside. The
   Developer Job Supplies option now includes raw fish. Keep a microwave empty.
2. Assign a resident **Cooking** or leave Automatic jobs enabled. Watch physical
   collection, native microwave operation/cooking, and delivery. Check real food
   state and inventories; only saying "Cooking" is not acceptance.
3. Test a hungry resident with raw ingredients and no ready meal. They should cook
   locally, then actually eat. Existing ready meals should take precedence.
4. Interrupt with Follow, thirst, danger and save/reload during cooking. Check the
   same ingredient remains and the microwave shuts off. Move the resident away:
   its native timer must expire within two game minutes without remote toggling.
5. Remove power, clear a storage assignment, fill the fridge/cupboard, take the
   ingredient yourself, or occupy the appliance before the cook arrives. Verify
   bounded failure/recovery, no duplicated food and no stolen player cooking.
6. Place a Cooking area outside the home and repeat. Also complete consecutive tree
   or crop jobs in an outside work area: residents should select the next job there.
   Disabling the area should remove that permission, without bypassing materials.

Ovens, BBQs, campfires and recipe preparation are not enabled by this executor.
`tools/test-base-cooking.lua` uses native API doubles, not simulated proof of actual
heat/animations. Long accelerated-time and real appliance acceptance remain pending.

## Faction development replay - 2026-09-12

Use a fresh disposable world with initial group maximum 4 and faction minimum 4.
Opening-group chance still applies; established saves keep existing cohorts. Observe
normal groups rather than the developer command that directly spawns a faction.
Let a cohesive group travel/shelter together for at least one game hour, including
an offscreen interval. Developer Tools > Faction & World Events > **Write Faction
Formation Status to Log** shows member count, required count and missing shared
survival evidence. Follow formation into camp/home selection and resume after
save/reload. Repeat with factions disabled and with members separated or partly
active. Offline formation tests pass; this live development loop remains pending.


## Travel, reading and driver replay - 2026-09-12

Pending live acceptance; automated doubles do not establish in-game physics or
animation quality. Use a disposable save with the matching freshly built agent.

1. Walk past one zombie, then a small crowd. Compare facing/behind, crouched/upright,
   blocked LOS and an actual pursuing attacker. Routine travel should not provoke
   a neighborhood hunt. Contact must remain dangerous. Repeat with cautious travel
   disabled, an aggressive companion and a crouching/running actual group leader.
2. Stock a suitable book in Main Supplies. An idle resident should collect, read
   and return it through visible native actions. Interrupt with thirst, an order
   and a threat; then repeat after save/load, after moving the book into a carried
   bag, and after removing the storage assignment. Confirm no lost/duplicated book.
3. Hold/Guard a hungry companion carrying safe food and water. They should consume
   supplies and resume the same order. Shove a guard away from the assigned post.
4. Enable Experimental NPC Driving on a quiet outdoor road. Start the engine, take
   a passenger seat, right-click the map 20–40 tiles ahead and select **Drive Here
   (Experimental) > [companion]**. Repeat with the NPC already a passenger and then
   already driving. Verify native entry/switch, correct heading and measured speed.
5. Place parked vehicles/walls beside the centreline, a bend, a pedestrian and a
   temporary obstruction. Check braking, waiting, detour and arrival. Use **Stop
   Driving** and take over the driver seat; NPC inputs must stop controlling the car.
   Test a different vehicle size, route failure and injury while driving.
6. Reject unloaded/distant destinations and a trailer clearly. Try map annotations
   and debug options. Current routes are limited to 160 tiles of loaded outdoor
   ground; this is not yet general long-distance road navigation.


## Base storage and permanent duty replay - 2026-09-09

Use a disposable save for **Developer Tools + Job Tests: Provide Tools and
Materials**. Normal play leaves this off. Right-click main supplies to manage
storage; Developer Tools > Base & Job Tests can stock real materials for testing.

1. Right-click a dry cupboard/crate inside your base > Knox Survivors > Set Storage
   > **Use as Main Supplies**. Right-click a fridge/pantry > **Use for Food & Drink**.
   A fridge/freezer object offers each compartment separately. Check the Work tab
   for assigned locations and the Base highlights for marked tiles.
2. Put edible food, raw meat, a water bottle and tools in the assigned stores.
   Empty one resident's carried food. They should collect a safe meal at home,
   eat it, and resume work. Repeat with the pantry upstairs. Spoiled/unsafe food
   must not be selected for eating. A full kitchen falls back to main supplies.
3. Send a resident to find base supplies. Existing assigned stock must not be
   taken and redeposited as a new find. Watch them return from an actual find,
   approach the assigned container, transfer the item and resume base life.
   Repeat for a faction resident and after streaming/reload.
4. Assign guard and patrol work. Guards hold their post until released; patrols
   walk successive points and repeat. Add hunger/thirst, then a nearby attack:
   duty should resume after the interruption. Remove the security area while
   staffed/moving and verify the resident stops that duty.
5. Set a corpse drop area and a hauler. Watch native pickup, continuous dragging,
   arrival and release. The temporary dragged-body proxy must not draw weapon
   swings or bite steering. Place a real attacking zombie nearby to check a
   genuine emergency still takes priority. Confirm the dropped body is in the area.
6. Issue Follow/Hold/Guard and watch gestures; busy actors must finish their native
   action. Disable order gestures and confirm player and NPC leaders both comply.

All six are pending live acceptance; Lua tests verify control flow and invariants,
not the visual animation, stairs, doors or driving behavior inside the game.

## Integrated settlement and encounter acceptance - 2026-09-09

These scenarios are pending live acceptance on the installed Build 42 runtime.
Use a disposable save and normal player commands; record the relevant survivor
IDs and base IDs so streaming/reload results refer to the same people.

1. Recruit a roaming survivor and Talk within four tiles in clear sight. They
   should stop briefly without losing their Follow order, then resume. Walk away,
   change floors, issue an order, or expose an attacker during attention: the new
   activity must win. An active worker must finish/release work before casual talk.
2. Give a base one central cupboard with seeds, crop water, axe, saw, hammer, logs,
   planks and nails. Keep builders'/farmers' inventories empty; create work areas,
   including an external wood lot. Watch native transfers before real planting,
   watering, chopping, sawing, barricading and construction. Add two hinges and a
   doorknob for a door; construction skill requirements still apply. No manual
   inventory injection should be necessary to get cupboard-backed discovery started.
3. Put a broken tool and empty bottle ahead of usable copies in storage, and put
   broken/empty duplicates on a worker. They must acquire usable instances, not
   repeatedly walk to work with invalid supplies. Remove real required stock:
   no task may succeed or create materials. Restore supplies and check recovery.
4. Complete a small rectangular construction area. Keep exactly the intended gate;
   the opposite wall must be filled and finished edges must not attract repeated
   frame-building attempts. Interrupt one worker during gathering and one during
   work; verify native cancellation, retained items and coherent task recovery.
5. Observe two independent survivors greeting. Introduce danger during approach
   and again during the greeting. The escaping survivor must keep escaping and
   the waiting partner must return to normal activity. A resting resident must
   get up before walking over, without leaving a stuck furniture reservation.
6. Test an injured/unarmed survivor against a visible hostile human. Verify an
   escape route, then recovery and return to duty when safe. Repeat with unseen
   people behind walls, established peace, and player combat disabled; those must
   not generate inappropriate retreat. Keep zombie/self-defense checks enabled.
7. Observe independent residents and a returning supply team across streaming and
   save/reload, using a base whose territory is larger than its home. Verify real
   stock, IDs, membership and claims persist; arrival/resident positions must use
   the actual territory rather than a single corner. Check clear activity labels
   while workers gather, wait, retreat, eat, deposit and return.

Record frame times at the configured population during ordinary play and crowded
job/combat situations. Offline regressions do not establish frame-time performance,
multiplayer support, native animation quality or multi-day survival balance.

## Repeatable offline verification

Run `./tools/verify.ps1` from PowerShell. It checks every mod Lua source with Lua 5.1,
runs every `tools/test-*.lua` script, then runs Java check/build. All checks run even
if an earlier test fails; the command exits nonzero on any failure. Per-check output
and `summary.json` are written to the ignored `build/verification` directory.
Use `-Lua` and `-Luac` for explicit interpreter paths, `-GameDirectory` when native
Lua fixtures need a non-default game installation, or `-SkipJava` for a focused Lua
pass (the summary records that omission). This does not stage, deploy or start a game.

The [replacement-quality delivery gates](RELEASE_QUALITY.md) define the integrated
acceptance order. For the current additions, check paired and single-file followers
at spacing 1 and 3 through doorways and turns; no movement to an unloaded/blocked
slot or leader tile should be issued. Verify injured companions show both current
activity and needs. Try boarding while native actions cannot start, then retry when
available: no phantom seat reservation or queued duplicate should remain. A save
with refill days 0 retains its initial people but never replaces routine population
losses; enabling refill later waits a full configured interval.

Java Gradle verifiers write diagnostics to `java/build/verification-logs/<task>/`
instead of the player's `Zomboid/KnoxIsoPlayer.log`. Synthetic failure cases are
expected there. Use game `console.txt` and the normal agent log for live evidence;
a verifier run should not update either gameplay log.

Knox Survivors now exposes its test harness through real Build 42 sandbox settings.
Developer tools are off by default. Enable them on a test save, then select one automatic
scenario or use the in-world right-click menu described in
[Sandbox Settings](SANDBOX_SETTINGS.md). The tools never rewrite vanilla sandbox values.

## One-click combat tests

### Human-combat eligibility regression (pending live)

Use a disposable test save with coop PvP off and Knox survivor/player combat on.
Attack an independent neutral survivor: verify a real native hit, health/injury
change, and hostility only after contact. Miss once and confirm no hostility from
the miss. Check a recruited companion and a friendly survivor remain protected.
Then test a hostile survivor attacking the player and another hostile survivor;
verify two-way native damage, godmode protection, death cleanup and movement resume.
Repeat the player swing with Knox survivor/player combat disabled. Do not enable
global PvP to make this test pass. Multiplayer combat is not covered by this adapter.

With developer tools enabled, right-click the ground and open
**Knox Survivors - Developer Tools > Run Combat Scenario**. The menu provides a one-on-one
fight, one survivor against a zombie group, a travel group fight, a faction fight, and a
larger stress test. Each preset creates its survivor population, spawns only its own tagged
zombies nearby, and watches for both survivor damage to zombies and native zombie damage to
survivors. It does not remove ordinary world zombies or alter sandbox population values.

The activity feed reports PASS, PARTIAL, FAIL, or BLOCKED. A PASS requires evidence of
two-way combat. **Write Combat Snapshot to Log** records every test survivor's controller and
Java combat state plus each test zombie's target, distance, target-seen timer, attack action,
attack outcome, collision-damage flag, and survivor health. **Cleanup Combat Test** removes
only zombies created by the selected preset; the deliberately spawned development survivors
remain persistent so save/reload can still be tested.

For the current native-bite gate, run **Survivor vs Zombie** and then **Survivor vs Crawler**.
Keep the player far enough away that the test remains uncontaminated, and wait for each automatic
result. The start line records `crawler=false` or `crawler=true crawlerConfigured=true`; if the
latter is not true, stop there and collect the logs. If either result is not PASS, write one
combat snapshot before cleanup, close the game normally, and use the collected run folder. That
single comparison distinguishes failure to acquire, approach, transition into the bite animation,
fire its collision event, or apply BodyDamage.

The 2026-08-25 duel and survivor-group runs reported PARTIAL: survivor approach, melee
animation, damage, kills, and moving-target re-approach worked, but zombie collision damage was
not consistently visible. Engine inspection isolated two lifecycle hazards: an off-slot zombie
could be re-entered from `hitreaction`, and a completed bite could be re-entered with stale
`ZombieBiteDone=true`. The current patch defers those transitions, clears the native terminal
flags before each new bite, and records the survivor's `AttackType`, hit-reaction action,
floor-aim state, and `attackedBy` result in the snapshot. It also gives the survivor a short
native-defense interval between swings, including stomp targeting for downed zombies. This is
ready for a fresh live confirmation; it is not marked verified until the run records a real
survivor reaction and health/injury change.

The current zombie handoff no longer forces either Build 42 combat state. Fresh engine evidence
showed that the old bridge was trying to write the unused off-slot lighting bit, which Build
42.20.3 does not create for a contained NPC. Crawlers can attack because their close-range branch
skips that standing-zombie visibility gate. Knox now adapts only the single
`IsoZombie.isTargetVisible()` lookup for a confirmed Knox shell; real players still use their
normal lighting data. The adapter does not change target selection, pathing, collision, attack
states, animation callbacks, hit rolls, or BodyDamage. The standing-zombie result is still
live-unverified until the next duel records the full native attack and injury sequence.

The shell's `isLocalPlayer()` override is also explicitly false. Local-player combat callbacks
needed by survivor melee remain covered by the existing three-call callback transformer; the
NPC itself no longer leaks into unrelated local input, music, or building-entry branches.

The awareness handoff now keeps a short native-target memory instead of reissuing the same
target every frame. Close-range perception refreshes are paced, and a zombie keeps its current
survivor target unless that target is lost or a clearly more urgent target appears. This is
intended to prevent attack-state churn while preserving normal zombie target selection and
collision rules. Movement also reports `FailedStuck` after a real no-displacement window, and
failed traversal edges receive a brief cooldown so a survivor can choose another route instead
of repeating the same locked door, fence, or window attempt.

Save capture attempts every active survivor independently. If one shell is unloading or
otherwise cannot be captured, successful records are still written and the save log reports
the failed IDs instead of aborting the entire capture pass.

## Production world population and hibernation — live retest required

The production population core now allocates survivors from the map's real Build 42 player
spawn definitions and materializes only nearby loaded identities. A first live run confirmed
that a 64-survivor test population initialized and that `ks-world-50` materialized when the
player entered its area. That run also exposed a streamed-out lifecycle bug: the shell lost
`getCurrentSquare()`, was labelled `STORED`, and repeatedly failed persistence capture.

The lifecycle fix changes that path in three ways: hibernation is checked every 30 ticks
instead of only during the slower population reconciliation pass; behavior controllers call
a missing-square body `DETACHED` rather than claiming it is already stored; and Java record
capture can fall back to the shell's last finite XYZ position when the engine has already
streamed its square out. Removal still happens only after capture succeeds.

For the next live pass:

1. Use a fresh or disposable save with a noticeable world population and developer diagnostics
   enabled. Travel through normal player-spawn neighborhoods until a survivor activates.
2. Confirm `population-activated id=... mode=... square=... playerDistance=...` appears and the
   survivor stays physically valid while you remain in the area.
3. Move away from the survivor. A normal distance hibernation should log
   `hibernate-attempt reason=distance` followed by `state=HIBERNATED` without any repeating
   `CAPTURE_FAILED` lines.
4. If the engine streams the square first, the Java log may report
   `NPC persistence capture fallback ... reason=no_current_square`; Lua should still complete
   one `state=HIBERNATED reason=detached` transition and remove the runtime cleanly.
5. Return to the saved area and confirm the same identity restores at the recorded square.
6. During the same run, watch for `MOVE_ALREADY_REQUESTED`, verify zombies actually complete
   attack animations against survivors, and confirm survivor health can fall below 100.
7. Recruit a companion or let a travelling group form, then lead it through a building exit,
   around a fence, and far enough to require running catch-up. A blocked formation route may
   log one `formation_movement:...` failure, but it must enter `GROUP_WAIT` or
   `COMPANION_WAIT` until the reported `retryAt` tick instead of issuing failures every frame.
   Put that group under pressure with three zombies per nearby survivor, or let one member
   fall to 25% health. The leader should choose one retreat direction and members should run
   or sprint toward nearby separate tiles, rather than each selecting an unrelated escape.
8. Change direction while a follower is catching up. The status line should show a bounded
   `formationFailures` streak; a successful catch-up must reset it to zero.
9. Separate one travelling-group member by more than the retrieve leash. The leader should
   wait or move back toward that member rather than continuing to widen the separation.

## Barter quotation / exchange / Trade window — live verification required

Run `tools/test-trade-valuation.lua` with the repository root argument. It executes the quote module
against real Knox persistence and native-shaped inventory objects: full-type ownership, known item
subtypes, quantity/condition, food/water safety, stock/urgency, offer order and food portion splitting,
whole-basket reserve protection, native ammo-key matching, nested bags, favorite/equipped items,
oversized/corrupt inventory, canonical base task demand, life/affiliation/hostility, player identity,
trust/reputation, reload stability and the nonzero spread. Quotes never change inventory or rewards.

`tools/test-trade-action.lua` additionally executes the installed 42.20.3 `ISTransferAction` and
base timed-action Lua with native-shaped containers and the real Knox controller/runtime/quote/
persistence domain. Its optional second argument is the game installation directory. Native Java
containers and record encoding remain mocked here. It covers exactly-once exchange, original item
identity/receipt, full-capacity root swaps, source/destination policy and ID rejection, cancellation,
queue failure, invalidated offers/relationships/life/reach, capture failures, transfer exceptions
before and after insertion, verified rollback, reputation error isolation, lease expiry, directive
changes, unload/detachment and retaining a recovery journal after an injected rollback failure.

`tools/test-trade-ui.lua` runs the actual UI/context callbacks and exchange/controller code with
native-shaped widget stubs. It checks single initialization, viewport/font layout, joypad focus,
fair-offer selection, completed exchange, close cancellation, two-minute expiry, danger, menu/death/
resolution cleanup, changed inventory, persistent capacity-error feedback and hostile/multiplayer
menu guards. It is not a rendered game UI test. Valuation checks also reject hidden items/hidden bag
contents and shared-inventory browsing; action checks cover browsing-to-exchange lease handoff.

Use an independent nearby NPC on a backed-up single-player save. Stand beside them with no blocked
edge and right-click Trade. Select items on both sides with double-click or Offer / Remove (joypad
A; left/right changes list). Y or Trade confirms an acceptable offer; B or Close cancels. Test a
low offer, then a fair one, and ensure the refusal/fair indication is readable. Try duplicate/stale
items, nearly equivalent goods, unsafe food, mismatched ammo, a whole reserve basket and a fair
useful exchange. Verify the real items change owners exactly once only for a valid accepted offer.
Repeat while moving away, entering danger, changing inventory after the quote and interrupting the
action; neither side may lose its payment or receive free items. Save/reload immediately afterward
and check both inventories and completion-only reputation. Also check nested bags, container
capacity, hostile/recruited targets and split-screen. While browsing, close the window, leave reach,
allow two minutes to pass, introduce a threat, or return to the menu: the survivor must be released
without losing its underlying activity. Opening/closing alone must never grant inventory access or
reputation. Verify both small/large fonts, list scrolling, long names, window close/minimize behavior
and controller focus. Reopen after completing one exchange to trade again. Real animation, native
container side effects, rendered layout and save/reload exchange integrity need live evidence.
`[Trade] RECOVERY_REQUIRED` is a hard test failure: stop further trading, retain the logs and do not
assume the before-record or inventory has safely recovered. Fault-recovery UX/durable recovery is
unfinished. Multiplayer trade is deliberately rejected rather than using fake player IDs.

## Wallet / currency gate — live verification required

Run `tools/test-wallet-currency.lua` with the repository root; optional second argument is the
42.20.3 installation. It checks the actual native wallet definition/UnbundleMoney recipe, executes
native wallet acceptance and wear completion Lua against native-shaped fixtures, then real Knox
equipment selection and barter using cash inside a worn wallet. Checks include missing/changed
script definitions, repeated setup, separate slot, unchanged non-wallet definitions, accepted and
rejected contents, supported/unknown currency, denomination ratio, stock saturation, trade receipt,
remaining coin ownership and no repeated equip. Native objects/registry initialization are mocked;
this does not prove the full game bootstrap. Inventory cleanup tests protect bundles/coins, and
the Java inventory snapshot verifier round-trips wallet cash/coins plus a separately worn backpack.

On a backed-up test save, obtain an existing Base wallet, cash, coins and a backpack. Use the normal
inventory Wear option for both wallet and backpack. Confirm a separate accessible wallet container;
drag bills/coins into it, confirm capacity/size limits still apply and a gold bar is rejected. A
MoneyBundle must be unpacked using the native recipe before its bills can enter the wallet. No
free wallet or cash should appear merely from loading the mod. Wear/unequip should keep contents.

Give a survivor a carried wallet and cash/coins, let existing equipment evaluation equip it, then
unload/restore and save/reload. Check the same types/counts and wallet/backpack worn state. Trade
with a neutral survivor using bills/coins from a worn wallet or a bundle from normal inventory.
Verify real payment, no duplicate currency, no emptied wallet lost or unequipped, preserved favorite
protection and clean action cancellation. Repeated equivalent trades must not manufacture value.
Check native menu labels/bag switching and console errors. This mod slot should be unequipped before
disabling/removing Knox. Broader currency/rarity balance and compatibility with other wallet mods
remain unverified. Then continue the reputation gate below.

## Player contribution / reputation gate — live retest required

On a disposable backed-up save, find a neutral survivor and kill a zombie actively targeting them
within eight tiles. Stay on the same floor and within twenty tiles of the survivor. Confirm a bounded
acknowledgement and trust increase in the existing survivor card; repeated rapid kills must not spam
credit. Repeat with a faction member and inspect the canonical faction relationship reputation.
Save/reload and confirm trust/reputation and reward cooldowns survive. Unrelated kills, another
floor, a zombie targeting the player, NPC-made kills and missing native target evidence earn nothing.
If the native death event has already cleared its target in a particular death path, record that
missing-evidence case; do not treat nearby kills as proof of defense.

With survivor/player combat enabled, hit a previously neutral survivor. Confirm Talk/Recruit become
unavailable with a hostile label, trust drops, and their NPC faction becomes hostile if applicable.
Continued combat must not repeatedly apply the first-aggression penalty. A hostile target cannot
be made recruitable just by talking/help credit. Test with both split-screen players if available:
only the actual player's relationship should change. No test grants items, cash, health or XP.
Trade credit is now wired only after a captured, verified exchange; gifts/medical/construction
rewards still lack completion adapters.

## Weapon preference gate — live retest required

Give a companion a usable bat, pistol, compatible magazine and real rounds. Under Orders →
Weapon Preference, choose Prefer Melee, Prefer Ranged and Survivor Choice in turn. Confirm only
the active option has the native checked marker and a newly opened menu reflects saved state.
Melee should keep the bat available; ranged should use the pistol only when native ammo/reload
allows it. Remove compatible ammo and verify melee fallback without reload spam. Survivor Choice
should usually keep a novice on melee; a survivor with native Aiming 4+ and room to aim may use a gun.

Change preference during a reload and during combat; check no simultaneous reload/fire/weapon-swap
loop, then confirm Follow/Hold/Guard remains intact. Set two companions to different preferences:
the party menu should show no single checked preference. Apply a party choice and confirm both
update. Save/reload, send a companion home/re-recruit, and verify the policy remains. Run the existing
Survivor Firearm Test: its test identity now explicitly prefers ranged to exercise real reload/fire.
Automated policy/menu/native-shaped fixtures cannot prove live timing, sound, ammo or animations.

## Carried cleanup / deposit gate — live retest required

On a backed-up disposable save, overload a survivor with a broken spare weapon, an inferior spare,
vanilla junk, extra food and planks. Also include equipped/attached gear, a favorite bag, ammo,
medical supplies and an accessory. Observe away from storage, then beside a categorized container
or depot assigned to their own base. Only eligible low-value items may be dropped; useful surplus
food/materials should be deposited rather than discarded. Confirm dropped objects remain lootable
and deposited items really exist in the destination. Required job supplies must remain carried.

Repeat with full storage, an intervening wall, a foreign/unassigned container, combat interruption
and replacement Hold/Follow. There should be one action at a time, no transfer spam, no command
loss and no item disappearance/duplication after save/reload. Unknown/favorite/valuable gear stays
protected. Also place an unassigned base resident 20–60 tiles from their own loaded assigned
storage with useful spare gear/materials. Confirm they walk to a valid interaction side, transfer
real items and return to normal behavior. Repeat with a blocked approach and then another eligible
container: failure must cool down rather than loop. During a trip change the base/storage, favorite
the selected item, issue Follow/Hold, trigger combat, or unload/save/reload. No old transfer may
survive invalid ownership and no duplicate/missing item may result. Travelling groups and active
companions must not abandon their roles for this detour. The local trip selector is same-floor and
128 tiles maximum; it does not claim cross-floor or unloaded-container logistics.
A protected-heavy inventory may remain overweight. Automated `test-inventory-cleanup.lua` and `test-base-storage.lua`
cover policy/action ownership and native-shaped fixtures, not in-game animation or world transfer.

## Unloaded survival ledger — live retest required

When a captured survivor is not active, Knox now advances a compact persisted survival
ledger rather than freezing their needs completely. It uses the portable inventory record:
if an unloaded survivor drinks or eats, real stored quantities are consumed before the need
is relieved. Partial food and reusable water bottles remain. Independent survivors distinguish
awake travel from endurance rest and sleep in the same ledger, then restore those needs when
the survivor materializes again. Fully stored travel groups share travel/rest decisions;
away-team missions retain their earlier policy.

1. Give a survivor at least one food item and one drink, then allow normal distance
   hibernation. Do not use a developer preset that gives the survivor endless supplies.
2. Advance enough game time while away for needs to matter, then return until the same ID
   restores. The survivor should retain its identity and have its restored needs applied.
3. Look for restrained `[KnoxSurvivors][Unloaded]` event lines only when a food/water item was
   consumed or an exceptional condition occurred. There should be no per-tick spam.
4. Save, quit, and reload while the survivor is hibernated; returning to the area must restore
   the same stored ledger and must not duplicate the consumed item.
5. Leave a faction resident at a settled base, travel away for at least one in-game day, then
   return. The resident should restore at a safe valid point inside its own base territory,
   not at the old hibernation tile or stacked with every other resident. This is ambient
   off-screen base life, not an away mission.

The focused `test-unloaded-survival.lua` check covers record-backed consumption, rest
recovery, and durable starvation/dehydration death. It does not prove live engine behavior.
`test-world-presence.lua` also exercises real Lua persistence and the production itinerary across
capture, travel, interrupted sleep, module reload and hidden-square activation. In a disposable
save, compare a rested independent survivor and an exhausted one after several unloaded hours;
the rested survivor should progress between nearby locations, and the tired one should pause,
recover and resume. Save/reload during the pause and confirm no snap back to the capture tile.
Send a companion to an unloaded base several hundred tiles away and verify gradual travel,
rest when needed and arrival at the current base. Reassign Follow during the trip and verify the
old return destination no longer controls movement. These pacing/restore checks remain live-only.

For stored groups, keep three members together, exhaust one, and leave their area. Advance time,
save/reload, then inspect the same identities: the group should rest together and later travel
with preserved spacing. Separating one before hibernation should make the others wait while that
member approaches, not teleport them together. Keep one member loaded in a repeat run: stored
members must not independently drift while the loaded controller owns the group. Verify native
regroup/activation after returning, member/leader death cleanup and retained inventory quantities.
`test-unloaded-groups.lua` covers the production Lua scheduler, shared itinerary, real persistence,
rest/reload, unequal clocks, separation, death and per-member supply transactions without a live
engine. Different-floor regrouping remains delegated to loaded navigation, not this simulation.

Do not call this gate complete until activation, hibernation, restoration, and one real zombie
attack have all been observed in game, and the collected log contains no formation retry storm.

## Party commands, zombie parity, and base territory — live pass pending

The latest build adds occupation/trait persistence, recruitment, companion orders, the
right-side HUD, and the shared base domain. Compilation and standalone save tests pass;
the following behavior is not yet called live-verified:

1. Start with the normal three-survivor scenario and confirm the player stays visible.
2. Right-click a nearby independent survivor. With the default **Require Trust to Recruit** setting
   off, `Recruit` should be immediately available inside four tiles. On a second disposable save,
   enable that setting: three successful `Talk` conversations separated by the half-hour in-game
   cooldown should raise trust enough to recruit. Hostile, grouped, or faction survivors must refuse
   recruitment under both policies.
3. Recruitment should create one companion HUD row. Confirm the portrait, name, activity,
   weapon, health, food, water, and rest bars update without stealing mouse input.
4. Test Follow and Hold from both the world menu and HUD right-click. Lead a zombie close;
   combat may interrupt the order, but the survivor should resume it afterward.
5. Stand within four tiles of a companion, right-click them, and choose `Medical Check`.
   The real player should walk into range, play the vanilla medical-check action, and open
   the regular body-part treatment window for that survivor. Treat a real minor wound with
   a carried bandage, then save/reload: the treatment and the consumed item must persist.
   Do not treat this as complete until it has been checked with an off-slot survivor body.
6. Return to the main menu and reload. The same person, occupation, traits, perk progress,
   ownership, command, and HUD row must return. No duplicate panels should appear.
7. Inside an unclaimed building, use `Knox Survivors > Establish Home Base`. Right-click
   a container inside it and set one storage category. Reload and confirm both remain.
8. Choose `Return to Base` while the home area is loaded. The survivor should move back,
   then alternate between short patrols and idle time around the home. They are not eligible
   for future jobs until physically inside the saved base bounds. Repeat while the home area
   is unloaded: the survivor should say they are heading back, disappear only after a normal
   capture/removal handoff, and later restore near the base with a `VIRTUAL_BASE_RETURN` log
   rather than reappearing at the old location. This unloaded route remains live-unverified.
9. If possible, repeat recruitment/HUD ownership with a second split-screen player. Each
   viewport must show and command only its own companions.
10. Right-click the `SQUAD` header. Test whole-party Follow, Hold, and traversal policy.
   Right-click the world and issue Loot Nearby Area, Loot This Building, and Loot Dead
   Bodies. Critical needs and combat may interrupt, but survivors must resume and then
   return to their primary order when the directive finishes.
11. From a world-square Party Orders menu, issue `Move Party Here`. Survivors should
    travel to the selected square, report arrival once, then return to their underlying
    Follow or Hold order. Issue `Guard This Location` and confirm they stay near the
    selected square, still defend themselves, and return there after a short fight.
    Save/load once while a guard order is active; its location and order must survive.
    Individual survivor menus also provide `Move to Me` and `Guard Here`; the HUD row
    should change from Follow/Hold to the current directive while either is active.
12. Close the activity feed with X, then reopen it through the `SQUAD` header menu. Speech
    must show the speaker name plus a stable party/group/faction label and color.
13. Use `Set Home Base Boundary`, choose two opposite corners around the house and yard,
    and confirm the territory persists. Residents must navigate every floor normally.
    Friendly survivors may open ordinary entries but must not smash player-base windows
    or attack its locked doors.
14. Open the Survivor Notebook from the party header and verify Party, Home Base,
    Survivors, and Factions show distinct, readable data.
15. From a player-owned base, use `Knox Survivors > Set Work Area`, choose Guard Area or
    Patrol Area, and select two opposite corners. The zone should appear in the Notebook's
    Home Base tab. A base resident should claim the recurring task, walk to a standable point,
    remain there briefly, and then record `completed_guard` or `completed_patrol` before the
    same zone becomes available again. Combat, a new companion order, leaving the base, or
    a save/reload must release the claim instead of leaving a permanently stuck task.
16. Set an Animal Care Area over one or more loaded feeding troughs. Give a base resident a
    container holding water and an animal-feed bag. A trough below half capacity should create
    one persisted refill task: water uses the normal pour animation and fluid transfer, while
    feed uses the normal inventory transfer and trough sound. The task should finish only when
    the real trough amount increases. Full troughs, missing supplies, a removed trough, or an
    incompatible fluid must be skipped or released for retry instead of claiming success.
17. To test depot sorting, mark one container `Depot` and another `Food`, `Building Materials`,
    or another supported category. Put one matching item in the depot, send a base resident
    home, and watch for one transfer with the normal rummage animation. The task should finish
    only after the item leaves the depot; an empty depot or unloaded destination must leave the
    task waiting/retryable rather than deleting the item or claiming success.
18. Give a base resident a hammer, a plank, and at least two nails, then leave an unbarricaded
    closed window inside the base boundary. The resident should walk to it, play the vanilla
    Build action, consume one plank and two nails, and complete only when the real barricade
    reports one additional plank. Fully barricaded windows should be skipped; missing tools or
    materials should leave no claimed task behind.
19. Set a farming work area over a loaded crop patch. With one ripe plant, the resident should
    queue the normal Harvest action and the plant should no longer report harvestable after
    completion. With a seeded plant below full water and a usable water item in inventory, the
    resident should queue the normal Water Plant action and the plant's water level should
    increase. Missing water, unloaded plants, and plants that no longer need work should be
    skipped and retried later rather than claimed indefinitely. With a usable digging tool and
    a matching carried seed, an empty suitable square should then be plowed and the resulting
    furrow seeded as two separate normal actions. No seed should mean no pointless plowing.
20. Set a Woodcutting Area over one or more loaded trees and give the resident a usable axe.
    The resident should equip the axe, play the normal Chop Tree action, and finish only when
    the tree object is gone. Missing axes, unloaded trees, or an already-chopped target should
    be released and retried rather than reported as success. If the resident carries a log and
    a usable saw, the next task should use the vanilla SawLogs recipe and consume the log for
    real planks; missing recipe, tool, or skill should leave it retryable.
21. Set a Corpse Drop Area on clear ground inside the base, then leave a human or zombie body
    elsewhere in the loaded base territory. The resident should walk adjacent to the body, put
    away held items, use the normal grab animation, drag the body to the drop-area center, and
    use the normal drop action. Bodies already in the drop area and animal bodies
    are deliberately excluded from this job. Starting combat, changing the resident's order,
    or failing the route while dragging must release the body and leave the task retryable.
22. Damage a player-built door, thumpable wall/fence, or barricade to between 20% and 95%
    health. Give a base resident the exact tools and materials shown by vanilla Repair mode.
    With no Repair Area the resident should maintain a loaded target anywhere in the base;
    drawing a Repair Area should restrict discovery to that zone. The normal repair animation,
    sound, material consumption, and skill-based chance should run. Knox must report success
    only if object health rises. Empty supplies, a barricaded door, a removed target, objects
    below 20% health, and a legitimate failed skill roll must remain failed/retryable rather
    than being silently restored or reported as repaired.
23. Draw a **Defense Construction Area** at least three tiles wide around a small outdoor
    perimeter, then give a base resident a hammer, planks, nails, hinges, a doorknob, and the
    required Carpentry level. The resident should build the planned access frame, then its
    door, before working through wall frames and first-stage walls. Each step must use vanilla
    Build actions, consume the actual recipe materials, and finish only when the expected
    Build 42 entity exists in the world. Remove a target or supplies mid-action to confirm the
    persistent task is released for retry rather than being marked complete.

Report the first exception or incorrect ownership transition rather than continuing on a
damaged test save. Live portrait framing, world-menu picking, distant-base return, and
split-screen isolation are the highest-risk checks in this gate.

## Active test: three independent survival controllers

Start a new Build 42.20 development save. The active scenario does not alter sandbox
settings, remove loaded zombies, freeze zombies, or make survivors immune. It uses the
save's normal zombie population. Three survivors are placed in a broad nearby test band
so social behavior can be observed without searching the map for hours; their survival
decisions and world interactions are otherwise live.

1. Fully close Project Zomboid so the new Java agent can load.
2. Start it with `Run Knox Survivors Dev.bat` and create/load the new save.
3. All three survivors should spawn or restore with their identities,
   health, needs, inventory, and equipment intact.
4. Each survivor now owns a separate decision controller. They can independently roam,
   detect and fight nearby zombies, satisfy carried food/medical/water needs, search for
   missing supplies, loot a reserved item, and re-evaluate their carried melee weapon.
5. Survivors should prefer reachable uninspected containers over random roaming. They
   visibly search, take up to two ranked need/upgrade items when present, and re-evaluate
   worn clothing and their carried melee weapon. They should not empty the container.
6. Survivors notice one another within 24 tiles. One approaches while the other safely
   waits, then they exchange short speech bubbles and matching lines in the small vanilla-
   styled Knox Survivors activity window. The encounter can join, decline, or become hostile.
   Afterwards group members follow their leader unless a need or zombie interrupts.
7. Let the test run until all three survivors complete at least two decisions. Their choices
   do not need to match.
8. Zombies can attack during this test. Do not intentionally lead a large group into the
   survivors while controller ownership is being checked.
9. Leave the game running for several minutes. The player and visible survivors must not
   fade permanently. Each periodic `render RENDER_DIAGNOSTICS` line should keep the local
   player at `alpha=1.0,targetAlpha=1.0`; NPC alpha may legitimately change with the real
   player's line of sight.
10. If a survivor encounters a locked door while pursuing optional loot, they may try a
    usable window but otherwise abandon and cool down that room. Only urgent food, water,
    or medical searches may attack a locked door, and only with sufficient endurance.
11. A survivor below the endurance threshold should choose the most comfortable free seat
    within eight tiles, walk to it, and sit while recovering. If no usable seat is reachable,
    the survivor sits on the ground. Look for `recovery-posture` and increasing
    `recovery-progress endurance=` values before the survivor stands and resumes autonomy.
12. After a group forms, followers should settle into separate staggered positions behind
    the leader rather than sharing one destination. Walk far enough to stretch the group. A gap
    of roughly five tiles should request running; a gap of twelve or more should request sprint
    catch-up when endurance and fatigue allow it. The live status line should expose
    `running=true`/`sprinting=true` and the route pace while the gap closes.
    The leader should wait around ten tiles of separation and move back toward a member who
    falls roughly fourteen tiles behind. After any zombie dies, every controller must leave
    combat and keep travelling; `releaseThreat` errors or `state=STOPPED` fail this gate.

Useful `console.txt` lines begin with:

```text
[KnoxSurvivors][Autonomy]
```

The expected result is:

```text
RESULT scenario=survival status=PASS reason=three_independent_autonomy_controllers
```

PASS proves all three stable identities made and completed decisions through separate runtime
controllers, then captures all three records. The controllers continue running after PASS so
longer observation can reveal combat, looting, needs, or navigation problems.

The development launcher monitors the run and collects its logs when the game closes.
`summary.txt` now counts both Test Lab and autonomy results, local-player alpha corruption,
alternate-entry events, and movement/combat failures. This keeps the next diagnosis
available without requiring the tester to copy console output manually.

The social result sequence is `meeting`, `greeting-approach`, `greeting-started`, then
`travel-group`. A two-person travelling group is not a faction. Adding a third consenting
survivor is the faction boundary once shared travel, loot, or combat has been recorded;
there is no minimum number of days together.

Persistent sociability and aggression influence three encounter outcomes. Joining creates
or expands a travelling group. Declining places that pair on a six-hour cooldown so they
carry on naturally. A hostile encounter currently robs up to two unequipped supplies using
normal timed inventory-transfer actions and records lasting hostility. Lethal survivor PvP
is not yet claimed because the verified melee bridge currently targets zombies only.

The faction/base sequence is `faction-formed`, `faction-base-candidate`,
`MOVING_TO_BASE_CANDIDATE`, then `faction-base-selected`. The final milestone evidence is:

```text
RESULT scenario=faction_base status=PASS
```

The candidate scorer currently requires a loaded building with at least two rooms and
30 tiles, favors residential buildings with water, rejects overlap with an existing
vanilla safehouse, and saves the building ID and bounds. Selection occurs only after the
leader reaches a standable exterior scouting point. It creates a vanilla safehouse boundary
and a stable faction-base record, then assigns faction members as residents. Residents
currently return, idle, and patrol; registered work tasks do not yet execute. The boundary
is restored on load and prevents the player from claiming an overlapping safehouse.

For the autonomy-cadence test, watch one survivor around several buildings for roughly
two minutes. After a useful loot visit or nearby rummage, the next normal decision must be
a roam leg rather than another container. An optional locked room should log
`blocked-area=optional_locked_entry` and be left behind. Urgent food, water, or medical
searches may still attempt one forced entry when endurance is at least 0.40.

For moving-target combat, let a zombie approach and then change distance during the fight.
The survivor may finish a swing already in progress, but must stop swinging at empty space,
move back into effective range, and resume. `knox-since-launch.log` records this correction
as `NPC combat REAPPROACH`.

Survivors immediately notice zombies within seven tiles, can notice visible zombies within
sixteen tiles, and prioritize zombies targeting a group member within twenty tiles. Combat
start lines record `awareness=immediate`, `visible`, `active_target`, or `group_target` so a
missed threat can be diagnosed without guessing from the screen.

Zombies should now discover a nearby survivor without first being attacked or led into the
survivor's swing range. Compare a survivor and the player standing at similar distance and
visibility. The result need not alternate perfectly, but survivors must be valid vanilla
targets and take normal attacks. Any `[ZombieAwareness] failed=` line fails this gate.

## Current foundation regression gate

This gate covers the 2026-08-26 constructor, Survivor Card, and detached-lifecycle fixes:

1. Launch through the development shortcut and load a backed-up save with at least two
   survivors active.
2. Open and close Survivor Card for two different survivors. Both cards must render without
   `ISUI3DModel.lua:110`, `setState of non-table: null`, player invisibility, or camera/input
   changes.
3. Leave the card closed and play normally for at least two status intervals. Every
   `RENDER_DIAGNOSTICS` survivor entry must report `instanceIsLocal0=true`.
4. With developer tools enabled, create a test survivor and travel far enough to stream its
   square out. A `detach-detected` transition may appear briefly, but it must be followed by
   one `hibernate-attempt` and `state=HIBERNATED` instead of repeating `state=DETACHED`.

The Java build and standalone policy checks prove the code path exists; only this live gate
proves Build 42 actually follows it.

## Already verified and hibernating

- one-survivor spawn, appearance, equipment, reconstruction, and save/reload;
- doors, windows, locked-window fallback, and low-fence traversal;
- melee approach, animation, damage, weapon use, and zombie death;
- container transfer and rummaging action;
- native injury reception, self-bandaging, and medical presentation persistence;
- native hunger/thirst consumption and physiology persistence;
- repeated autonomous roaming with independent completed movement requests.
- three simultaneous persistent survivor runtimes across save/reload remain the active gate.

For the firearm gate, use the developer **Survivor Firearm Test** once in a clear outdoor
area. The survivor should equip the seeded real pistol, queue a native reload when needed,
hold a visible stand-off distance, and fire through the normal aiming animation. Take a
combat snapshot after the first shot and confirm `firearm=` reports a real weapon with its
round count changing, while the Java status reports `ranged=true`. A reload or shot sound
must be audible/attract nearby zombies; a gun must not close to melee range or use the
floor-shove animation. This is a live gate: the standalone firearm test only proves that
Knox selects owned weapons and delegates reload to `ISReloadWeaponAction`.

For the passenger-vehicle gate, park a stopped vehicle with an empty installed passenger
seat, sit in the driver seat, then right-click a nearby companion and choose
**Orders → Enter My Vehicle**. The companion must path to an unlocked passenger door, use
the normal enter animation, occupy a passenger seat, and leave seat zero to the player.
Repeat with every passenger seat occupied: the companion must remain outside and say that
there are no more seats. Then use **Orders → Exit Vehicle** while stopped and confirm the
normal exit animation. Do not save/reload this slice as vehicle-seat restoration is not yet
implemented; no error, detached-shell hibernation, or change to vehicle keys/engine state is
acceptable while a companion is seated.

## Known limits

- The active gate integrates already verified survival actions per survivor; it does not
  claim every action will naturally occur during one short run.
- Firearm sound-attraction/targeting, cooking, lethal survivor PvP, deliberate construction, and
  interactive Notebook management remain later gates.
  Guard/patrol work-zone drawing, one-item depot sorting, one-plank barricading, crop work,
  wood processing, corpse hauling, trough feeding/watering, and structure repair now have
  initial executors.
  Passenger companions can use native entry/exit actions, but NPC driving, group vehicle travel,
  and vehicle-seat restoration after save/load remain later gates.
  The current Notebook is the readable domain shell, not the finished base administration
  interface; newer jobs still require live in-game confirmation.
- If a recorded square is not loaded, the survivor remains stored instead of being
  teleported to the player.
- Room-wide alternate-entry planning, sleep furniture selection, death, and
  zombification remain unverified in game. For the death gate, kill one infected survivor
  and one survivor who should not turn under the active sandbox rule. Both must leave a
  normal lootable corpse after save/reload; only the eligible corpse should later reanimate.
  The log must contain `CORPSE_CREATED` with `reanimationScheduled=true` for the former and
  `false` for the latter. The alternate-entry implementation is present in the active gate
  but still requires its first live end-to-end observation.
- Unloaded Return to Base now has a persisted virtual-route handoff, but it still needs its
  first live save/reload and rematerialization test.
- The Java agent requires the development launcher.

## Knox Events ledger / real-roster raid proposal checks

Run `lua tools/test-knox-events.lua .` from the repository root. This loads the real
persistence service over a fixture ModData store and checks additive schema migration,
hostility gating, five-member/two-raider selection, claimed-work exclusion, one active
party per faction, defensive snapshots, revision-checked phases, save-state reconstruction,
death/relocation/peace invalidation, home-defender loss, malformed record recovery, bounded
maintenance, history pruning, and cooldown retention across pruning/reload. It also checks
that survivor count, native record strings, and base/affiliation intent are not rewritten.

Run `lua tools/test-event-stored-readiness.lua .` to verify the inactive-party dispatch
boundary. It checks fresh persisted physiology and home position, read-only native equipped-
weapon readiness, active-body exclusion, atomic all-member qualification, bounded retry,
save reconstruction, and dispatch without materializing or manufacturing survivors/items.

Run `lua tools/test-event-automatic-scheduler.lua .` to verify automatic proposal policy:
world-age/settings gates, explicit hostility, persistent scan timing, real minority rosters,
one active automatic event, source/target distance, faction cooldown, reload, and poisoned-state
normalization. With Developer Tools and Allow Destructive Tests enabled, **Schedule Eligible
Faction Raid Now** invokes this same scheduler without waiting for the calendar gate; it still
requires two real hostile bases and an eligible five-member source faction.

Run `lua tools/test-event-factions.lua .` for the named-faction policy boundary. It verifies all
six stable definitions, defensive catalog copies, world-age/objective constraints, no artificial
combat multipliers, disabled Scavenger boss, future PMC contract role, canonical faction binding,
idempotency/rebind rejection, malformed-save cleanup and no survivor/inventory/duty creation.
This is policy/persistence coverage only; it does not prove a Police/Military/etc. encounter.

Run `lua tools/test-event-entry.lua .` for the named-party entry transaction. It checks bounded
cached-world origins, compact party placement, local-player separation, ordinary persistent
world identities, canonical group/faction ownership, no pre-body itinerary scattering, normal
activation eligibility, idempotent retry, injected mid-batch rollback, world-age policy, and
entry-wait cleanup after a real-state capture. It does not materialize an IsoPlayer or validate
the themed appearance/loadout that later event runtime work must request.

Run `lua tools/test-named-event-runtime.lua .` for the persisted named-event lifecycle. It covers
schedule-without-allocation, world-age/objective validation, due-time one-shot party creation,
atomic event duty, no duplicate retry, local-player entry separation, distinct approach points,
real-position arrival, the bounded common objective, entry-anchor withdrawal, identity/faction
retention, fully stored cohort travel and persisted retry cooldown when no safe origin exists. It
also covers the policy split after withdrawal: Police remains present, while Scientists retain
identity/native records but enter two-phase pending/complete departure, stop activation/offscreen
simulation and leave only a historical empty faction after every shell is retired.

Run `lua tools/test-survivor-capabilities.lua .`, `lua tools/test-survivor-starting-gear.lua .`
and `lua tools/test-event-entry.lua .` for Police first materialization. Together they verify the
canonical event-policy lookup, real `base:policeofficer` selection with balanced vanilla points,
native Police starter items, and protection against rewriting an existing persisted profile.

Run `lua tools/test-character-appearance.lua .`, `lua tools/test-survivor-capabilities.lua .`,
`lua tools/test-survivor-starting-gear.lua .`, `lua tools/test-event-factions.lua .` and
`lua tools/test-named-event-runtime.lua .` for Scientist first materialization. They verify the
real balanced `base:doctor` profession, native clothing application with the real lab coat item,
the ordinary clipboard/pen/scalpel field kit, canonical policy propagation and one-time event
identity. These checks do not claim research simulation or a completed Scientist feature.

The same focused set covers Military first materialization: real balanced `base:veteran`, four
real army clothing items, and a restrained M9 kit with one compatible `Base.9mmClip` and exactly
three native five-round `Base.Bullets9mm` stacks. For a live gate on a disposable day-14-or-later
save, choose **Schedule Military Exit Test Here**. Verify three entrants materialize with stable
identity/gear, use the existing native reload/firearm path rather than appearing with fabricated
loaded state, execute the bounded secure-area objective, and depart through the existing event-only
lifecycle. Save/reload must not duplicate clothing, firearms, magazines or ammunition.

For the Scavenger real-loot gate, use a disposable day-7-or-later save and choose **Schedule
Scavenger Search Here** on a loaded square near several ordinary world containers. Three persistent
Scavengers should enter, search only the bounded nearby area through existing looting behavior,
and withdraw after six completed transfers, three exhausted searches per member, or two in-game
hours. Inspect their real inventories: only items physically transferred from real containers may
be retained. Empty/no-op transfers, containers outside 18 tiles and other survivors' inventories
must not count. Save/reload during the objective and verify receipt/item identity is not duplicated.

Live named-entry gate: on a disposable day-one-or-later save, enable **Developer Tools** and
**Allow Destructive Tests**, then right-click a loaded ground square and choose **Schedule Police
Entry Here**. The feed should report one event ID. Confirm three Police identities enter from a
believable offscreen anchor rather than beside the player, approach distinct nearby positions,
remain ordinary neutral survivors during the initial bounded objective, withdraw toward that same
anchor, and keep one identity/faction record each after save/reload. Inspect
`[KnoxSurvivors][Events]` for `spawning`, `active`, and `completed`; no phase may create a second
party. On first appearance, Police members should use recognizable ordinary Build 42 Police
clothing, own/equip a nightstick and carry a Police walkie-talkie. Save/reload must preserve the
same profession, clothing and items without issuing a second kit. Automatic Police triggers,
disposition behavior and the `assist` objective are not part of this gate. For `secure_area`, place
a small number of zombies inside 18 tiles of the selected target. Police must remain on objective
while a living threat remains, fight only through common combat behavior, then withdraw after the
area stays clear for roughly three in-game minutes. Reload during that clear window and confirm the
event neither completes twice nor invents a cleared result.

Event-only departure live gate: on a disposable day-14-or-later save with **Developer Tools** and
**Allow Destructive Tests** enabled, right-click a loaded ground square and choose **Schedule
Scientists Exit Test Here**. Keep at least one member loaded through its return. A survivor must
not disappear before reaching the saved entry anchor. At the anchor, the
loaded shell must capture/remove once, the event must wait for every member, and no corpse may be
created. Save/reload afterward and revisit the area: departed identities must not materialize again
or count toward living world population. Repeat while killing one withdrawing member; that member
must use the ordinary death/corpse path while surviving members depart normally. Inspect autonomy
logs for one `state=DEPARTED` per surviving loaded member and no repeated removal, restore or event
completion loop. On first materialization, confirm the entrants retain the same medical profession,
lab coat and ordinary field items after save/reload without receiving duplicate equipment.

This is not an end-to-end raid scenario. The runtime can now dispatch explicitly scheduled
plans, but no random scheduler is enabled. Do not manually advance phases and describe
that as a successful live raid. `lua tools/test-event-runtime.lua .` additionally runs
the real persistence, event runtime, controller travel entry point, and unloaded cohort
scheduler over engine fixtures. It covers readiness rejection, all-member duty claims,
base-job exclusion, native movement requests, stable projection, combat interruption,
reload, actual-position arrival, loaded/stored return, cooldown retention, shared fatigue,
mixed-loaded waiting, casualties, malformed roster recovery, and lost-home cleanup.

Pending live dispatch gate: use five equipped residents of an established hostile faction
and an existing target base. Explicitly schedule its proposal through `KnoxEvents.scheduleRaid`
or the developer context command. Verify only the selected party leaves, native movement/obstacles
and group regrouping work, combat/self-care can interrupt it, the same IDs and gear persist
across hibernation/reload, and withdrawal returns/releases survivors without duplication.
Inspect `[KnoxSurvivors][Events]` transitions; timers must not claim combat victories.
Automatic scheduling and real supply objectives are implemented but not live-proven and must
not be presented as a release-ready raid feature. No substitute NPCs or free equipment are permitted.
