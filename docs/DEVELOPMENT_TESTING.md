# Development testing

Knox Survivors runs one bounded automatic gate at a time. These tests do not rewrite
Project Zomboid sandbox settings and are not release gameplay.

## Active test: two independent survival controllers

Use the existing backed-up Build 42.20 development save.

1. Fully close Project Zomboid so the new Java agent can load.
2. Start it with `Run Knox Survivors Dev.bat` and load the same save.
3. Both saved survivors should restore in their recorded positions with their identities,
   health, needs, inventory, and equipment intact.
4. Each survivor now owns a separate decision controller. They can independently roam,
   detect and fight nearby zombies, satisfy carried food/medical/water needs, search for
   missing supplies, loot a reserved item, and re-evaluate their carried melee weapon.
5. Survivors should prefer reachable uninspected containers over random roaming. They
   visibly search, take up to three ranked need/upgrade items when present, and re-evaluate
   worn clothing and their carried melee weapon. They should not empty the container.
6. When two ungrouped survivors enter awareness range, they should stop safe travel,
   approach, face one another, exchange two short speech bubbles, and form a travelling
   group. Afterwards one leads while the other follows or waits nearby unless an urgent
   personal need or zombie interrupts them.
7. Let the test run until both survivors complete at least two decisions. Their choices
   do not need to match.
8. Zombies can attack during this test. Do not intentionally lead a large group into the
   survivors while controller ownership is being checked.
9. Leave the game running for several minutes. The player and visible survivors must not
   fade permanently. Each periodic `render RENDER_DIAGNOSTICS` line should keep the local
   player at `alpha=1.0,targetAlpha=1.0`; NPC alpha may legitimately change with the real
   player's line of sight.
10. If a survivor encounters a locked door while pursuing a container, it first routes
    to the nearest usable window of that room, attempts to open it, smashes it if needed,
    climbs through, and resumes the original goal. If the room has no usable window, the
    survivor attacks the locked door with the equipped melee weapon.

Useful `console.txt` lines begin with:

```text
[KnoxSurvivors][Autonomy]
```

The expected result is:

```text
RESULT scenario=survival status=PASS reason=two_independent_autonomy_controllers
```

PASS proves both stable identities made and completed decisions through separate runtime
controllers, then captures both records. The controllers continue running after PASS so
longer observation can reveal combat, looting, needs, or navigation problems.

The social result sequence is `meeting`, `greeting-approach`, `greeting-started`, then
`travel-group`. A two-person travelling group is not a faction. Adding a third consenting
survivor is the faction boundary.

## Already verified and hibernating

- one-survivor spawn, appearance, equipment, reconstruction, and save/reload;
- doors, windows, locked-window fallback, and low-fence traversal;
- melee approach, animation, damage, weapon use, and zombie death;
- container transfer and rummaging action;
- native injury reception, self-bandaging, and medical presentation persistence;
- native hunger/thirst consumption and physiology persistence;
- repeated autonomous roaming with independent completed movement requests.
- two simultaneous persistent survivor runtimes across save/reload.

## Known limits

- The active gate integrates already verified survival actions per survivor; it does not
  claim every action will naturally occur during one short run.
- Firearms/ammunition, cooking, sleep furniture, hostility/personality-based refusal,
  third-member recruitment, faction bases, and safehouse ownership remain later gates.
- If a recorded square is not loaded, the survivor remains stored instead of being
  teleported to the player.
- Room-wide alternate-entry planning, sleep furniture selection, death, and
  zombification remain unverified in game. The alternate-entry implementation is present
  in the active gate but still requires its first live end-to-end observation.
- The Java agent requires the development launcher.
