# Development testing

Knox Survivors runs one bounded automatic gate at a time. These tests do not rewrite
Project Zomboid sandbox settings and are not release gameplay.

## Active test: two persistent survivor runtimes

Use the existing backed-up Build 42.20 development save.

1. Fully close Project Zomboid so the new Java agent can load.
2. Start it with `Run Knox Survivors Dev.bat` and load the same save.
3. The existing survivor should restore at their saved position.
4. A second survivor should restore or be created on a loaded standable square with a
   randomized human appearance, starter equipment, and a separate stable ID.
5. Both survivors should roam independently. This gate temporarily prevents zombies
   from targeting them so combat cannot hide movement ownership failures.
6. A PASS requires each survivor to finish three routes and both records to save.
7. Return to the main menu and reload once. Both survivors must restore and independently
   complete the gate again to verify disk continuity.

Useful `console.txt` lines begin with:

```text
[KnoxSurvivors][Population]
```

The expected result is:

```text
RESULT scenario=population status=PASS reason=two_independent_survivors
```

The first PASS proves two live runtimes and captures both records. A PASS after reload
also reports `reloadVerified=true`.

## Already verified and hibernating

- one-survivor spawn, appearance, equipment, reconstruction, and save/reload;
- doors, windows, locked-window fallback, and low-fence traversal;
- melee approach, animation, damage, weapon use, and zombie death;
- container transfer and rummaging action;
- native injury reception, self-bandaging, and medical presentation persistence;
- native hunger/thirst consumption and physiology persistence;
- repeated autonomous roaming with independent completed movement requests.

## Known limits

- The two-survivor gate proves runtime and persistence ownership, not full per-survivor
  needs, combat, looting, relationships, dialogue, or factions.
- Zombies are temporarily prevented from attacking both survivors during this gate.
- If a recorded square is not loaded, the survivor remains stored instead of being
  teleported to the player.
- Room-wide alternate-entry planning, sleep furniture selection, death, and
  zombification remain unverified.
- The Java agent requires the development launcher.
