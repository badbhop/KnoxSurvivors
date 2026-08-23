# Development testing

The local development build automatically runs the Knox Test Lab when a single-player
save starts. It does not read, modify, or override Project Zomboid sandbox settings.

The active scenario is configured in `KS_DevTestConfig.lua`. The current
`obstacle_suite` runs baseline movement plus controlled door, window, and fence
crossings. Equipment, combat, loot, health, medical treatment, and persistence are
registered as later gates and are activated one at a time as their real gameplay
implementations are added.

The obstacle suite automatically:

1. waits for the area around the player to load;
2. scans 12 tiles for a closed unlocked door, an unlocked closed window, a locked closed
   window, and a low fence with standable squares on both sides;
3. spawns a fresh test survivor beside each discovered fixture;
4. bypasses destination path selection for obstacle cases and commands the exact adjacent
   edge, preventing the engine from detouring through a different door or fence;
5. requires the expected traversal evidence and a completed controller route before the
   case can pass;
6. records each case once, removes the survivor, and advances to the next case without
   retrying a completed case during that suite run;
7. prints a machine-readable `RESULT` line with `PASS`, `FAIL`, or `SKIP` for every case,
   followed by one final `obstacle_suite` result.

`SKIP` means the required map fixture was not found near the player; it is not a code
failure. The locked-window case is intentionally destructive and is enabled only in the
development configuration: the NPC can permanently smash that window in the test save.
The suite does not create, delete, lock, close, or silently alter map fixtures. Locked
door alternate routing remains registered but inactive until its room-entry planner is
implemented.

Evidence requirements prevent arrival-only false positives: a door must record its open
transition, a window must record its open and climb transitions, a locked window must
also record its smash transition, and a fence must record its climb transition. The
movement controller must report `Succeeded`; merely reaching the midpoint of a climb is
not enough. Starting a new save load deliberately starts a fresh suite so new code can
be regression-tested.

## Running the obstacle test

1. Use a disposable or backed-up save because the locked-window case may break a window.
2. Before quitting the save, stand outside a normal house within 12 tiles of a closed
   door and several closed windows. Stand near a low fence as well if one is available.
3. Launch with `Run Knox Survivors Dev.bat` and load that save. Do not move or interact
   with the nearby fixtures while the suite runs.
4. Watch the survivor if visible. Allow roughly one minute; missing fixtures are skipped
   automatically rather than hanging the run.
5. Quit normally after the final `obstacle_suite` result appears. The diagnostic monitor
   collects the complete evidence automatically.

For the best single location, use a detached house with a closed front door, multiple
closed first-floor windows, and a short yard fence. A locked window is determined by the
save; if none is nearby, that case will simply show `SKIP`.

`Run Knox Survivors Dev.bat` starts a diagnostic session. While the game runs,
`dev-runs/<run>/live-test-status.txt` contains the latest result. After the game closes,
the collector writes `test-results.txt`, includes test counts in `summary.txt`, and treats
a failed scenario as a possible issue.

These tools are development-only scaffolding. They must stay separate from normal
survivor spawning and will be disabled before a playable Workshop release.
