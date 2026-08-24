# Development testing

Knox Survivors now exposes its test harness through real Build 42 sandbox settings.
Developer tools are off by default. Enable them on a test save, then select one automatic
scenario or use the in-world right-click menu described in
[Sandbox Settings](SANDBOX_SETTINGS.md). The tools never rewrite vanilla sandbox values.

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

Do not call this gate complete until activation, hibernation, restoration, and one real zombie
attack have all been observed in game.

## Party commands, zombie parity, and base territory — live pass pending

The latest build adds occupation/trait persistence, recruitment, companion orders, the
right-side HUD, and the shared base domain. Compilation and standalone save tests pass;
the following behavior is not yet called live-verified:

1. Start with the normal three-survivor scenario and confirm the player stays visible.
2. Right-click a nearby survivor. `Talk` should work inside four tiles. Three successful
   conversations, separated by the half-hour in-game cooldown, should make `Recruit`
   available. Grouped or faction survivors must refuse recruitment.
3. Recruitment should create one companion HUD row. Confirm the portrait, name, activity,
   weapon, health, food, water, and rest bars update without stealing mouse input.
4. Test Follow and Hold from both the world menu and HUD right-click. Lead a zombie close;
   combat may interrupt the order, but the survivor should resume it afterward.
5. Return to the main menu and reload. The same person, occupation, traits, perk progress,
   ownership, command, and HUD row must return. No duplicate panels should appear.
6. Inside an unclaimed building, use `Knox Survivors > Establish Home Base`. Right-click
   a container inside it and set one storage category. Reload and confirm both remain.
7. Choose `Return to Base` while the home area is loaded. The survivor should move back,
   then alternate between short patrols and idle time around the home. They are not eligible
   for future jobs until physically inside the saved base bounds.
8. If possible, repeat recruitment/HUD ownership with a second split-screen player. Each
   viewport must show and command only its own companions.
9. Right-click the `SQUAD` header. Test whole-party Follow, Hold, and traversal policy.
   Right-click the world and issue Loot Nearby Area, Loot This Building, and Loot Dead
   Bodies. Critical needs and combat may interrupt, but survivors must resume and then
   return to their primary order when the directive finishes.
10. Close the activity feed with X, then reopen it through the `SQUAD` header menu. Speech
    must show the speaker name plus a stable party/group/faction label and color.
11. Use `Set Home Base Boundary`, choose two opposite corners around the house and yard,
    and confirm the territory persists. Residents must navigate every floor normally.
    Friendly survivors may open ordinary entries but must not smash player-base windows
    or attack its locked doors.
12. Open the Survivor Notebook from the party header and verify Party, Home Base,
    Survivors, and Factions show distinct, readable data.

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
    the leader rather than sharing one destination. Walk far enough to stretch the group.
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

## Already verified and hibernating

- one-survivor spawn, appearance, equipment, reconstruction, and save/reload;
- doors, windows, locked-window fallback, and low-fence traversal;
- melee approach, animation, damage, weapon use, and zombie death;
- container transfer and rummaging action;
- native injury reception, self-bandaging, and medical presentation persistence;
- native hunger/thirst consumption and physiology persistence;
- repeated autonomous roaming with independent completed movement requests.
- three simultaneous persistent survivor runtimes across save/reload remain the active gate.

## Known limits

- The active gate integrates already verified survival actions per survivor; it does not
  claim every action will naturally occur during one short run.
- Firearms/ammunition, cooking, lethal survivor PvP, job execution, work-zone drawing,
  and interactive Notebook management remain later gates. The current Notebook is the
  readable domain shell, not the finished base administration interface.
- If a recorded square is not loaded, the survivor remains stored instead of being
  teleported to the player.
- Room-wide alternate-entry planning, sleep furniture selection, death, and
  zombification remain unverified in game. The alternate-entry implementation is present
  in the active gate but still requires its first live end-to-end observation.
- Return to Base currently needs the destination cell loaded; unloaded-world travel is not
  implemented yet.
- The Java agent requires the development launcher.
