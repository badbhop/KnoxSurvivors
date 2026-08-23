# Development testing

Knox Survivors currently runs one automatic test at a time. These tests do not change
Project Zomboid sandbox settings and are not part of the eventual release gameplay.

## Active test: appearance and persistence

Use a disposable or backed-up single-player Build 42.20 save.

### First load

1. Start the game with `Run Knox Survivors Dev.bat`.
2. Enable Knox Survivors on the save and load it.
3. Wait about ten seconds without leaving the area.
4. A green-outlined test survivor should appear a few tiles away.
5. Check their skin, hair, clothes, and bag. The current gate forces one starter bag so
   its back slot is tested on every run.
6. They should equip a baseball bat. Their body is then rebuilt automatically.
7. Confirm they remain clothed and visually unchanged.
8. Quit normally to the main menu so the save is written.

### Second load

1. Launch the development shortcut again and load the same save.
2. Wait about ten seconds.
3. The same survivor should return on the same tile.
4. Check that their skin, hair, clothes, clothing colors, bag, inventory, and baseball bat
   match the first load.
5. Quit normally when finished so the diagnostic collector can finish.

The useful result lines in `console.txt` begin with:

```text
[KnoxSurvivors][EquipmentTest] RESULT
```

The first load should report `reason=new_record_created`. The second should report
`reason=disk_record_restored`. A PASS confirms the recorded values matched; visual
inspection still matters because rendering problems may not produce a data mismatch.

`dev-runs/<run>/live-test-status.txt` shows the latest result while the game is running.
After the game closes, `test-results.txt` and `summary.txt` contain the collected result.

## Known limits

- Only one survivor is active.
- Combat and autonomous looting are not enabled.
- Nested bag contents, health, injuries, food age, and several detailed item properties
  are not fully persistent yet.
- If the survivor's recorded cell is not loaded, the test leaves them stored instead of
  teleporting them to the player.
- The Java agent requires the development launcher. Steam may replace a modified
  `ProjectZomboid64.bat` during an update or file verification.
