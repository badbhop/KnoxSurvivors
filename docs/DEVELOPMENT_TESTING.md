# Development testing

Knox Survivors currently runs one automatic test at a time. These tests do not change
Project Zomboid sandbox settings and are not part of the eventual release gameplay.

## Active test: controlled melee combat

Use a disposable or backed-up single-player Build 42.20 save.

The appearance, equipment, and reconstruction probe is currently hibernating. Its code
and saved survivor record remain available, but it will not repeat while combat is active.

1. Start the game with `Run Knox Survivors Dev.bat`.
2. Enable Knox Survivors on the save and load it.
3. The saved survivor should appear immediately in their saved position with their bat.
4. The test removes ordinary zombies from the currently loaded area. It does not change
   sandbox settings or rewrite zombies stored in distant, unloaded map chunks.
5. One stationary test zombie appears three clear tiles from the survivor.
6. The survivor should approach, face it, swing the bat using normal player combat, and
   continue attacking until it dies.
7. Do not attack the test zombie yourself. Visual animation and sound confirmation matter.
8. Quit normally after PASS or FAIL so the diagnostic collector can finish.

After the first PASS, this save records the combat gate as complete and will not create
another combat target on later loads. The next planned gate is one-container looting.

The useful result lines in `console.txt` begin with:

```text
[KnoxSurvivors][TestLab] RESULT scenario=combat
```

A PASS requires observed zombie health loss followed by death. The result also records
the number of attack requests and the bat's condition before and after the encounter.

`dev-runs/<run>/live-test-status.txt` shows the latest result while the game is running.
After the game closes, `test-results.txt` and `summary.txt` contain the collected result.

## Known limits

- Only one survivor is active.
- Autonomous looting is not enabled.
- Nested bag contents, health, injuries, food age, and several detailed item properties
  are not fully persistent yet.
- If the survivor's recorded cell is not loaded, the test leaves them stored instead of
  teleporting them to the player.
- The Java agent requires the development launcher. Steam may replace a modified
  `ProjectZomboid64.bat` during an update or file verification.
