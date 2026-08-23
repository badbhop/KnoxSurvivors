# Development testing

Knox Survivors currently runs one automatic test at a time. These tests do not change
Project Zomboid sandbox settings and are not part of the eventual release gameplay.

## Active test: controlled container looting

Use a disposable or backed-up single-player Build 42.20 save.

The appearance, equipment, reconstruction, traversal, and combat probes are hibernating.
Their code and saved results remain available, but passed gates do not repeat.

1. Start the game with `Run Knox Survivors Dev.bat`.
2. Enable Knox Survivors on the save and load it.
3. The saved survivor should appear immediately in their saved position with their bat.
4. The test removes ordinary zombies from the currently loaded area. It does not change
   sandbox settings or rewrite zombies stored in distant, unloaded map chunks.
5. The test finds a nearby world-object container and adds one bandage to it as a
   deterministic test item.
6. The survivor should walk beside the container, turn toward it, play the looting
   action, and take the bandage into their real inventory.
7. Do not move items or control the survivor during the test. Animation and sound
   confirmation matter.
8. Quit normally after the result so the diagnostic collector can finish.

After the first PASS, this save records the loot gate as complete and will not repeat it
on later loads. The next planned gate is ordinary injury reception and health persistence.

The useful result lines in `console.txt` begin with:

```text
[KnoxSurvivors][TestLab] RESULT scenario=loot
```

A PASS requires the timed action to be observed, the exact item to leave the source
container, and that same item to appear in the survivor inventory. The updated persistent
record is captured before the gate is marked complete.

The previous combat run passed with real attack animation and measured zombie health
loss. Its controller now approaches inside the equipped weapon's usable range instead
of stopping at the general movement arrival boundary.

`dev-runs/<run>/live-test-status.txt` shows the latest result while the game is running.
After the game closes, `test-results.txt` and `summary.txt` contain the collected result.

## Known limits

- Only one survivor is active.
- Loot target scoring and the autonomous survival planner are not enabled; this gate
  proves one controlled world-container transfer first.
- Nested bag contents, health, injuries, food age, and several detailed item properties
  are not fully persistent yet.
- If the survivor's recorded cell is not loaded, the test leaves them stored instead of
  teleporting them to the player.
- The Java agent requires the development launcher. Steam may replace a modified
  `ProjectZomboid64.bat` during an update or file verification.
