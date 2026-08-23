# Development testing

The local development build automatically runs the Knox Test Lab when a single-player
save starts. It does not read, modify, or override Project Zomboid sandbox settings.

The active scenario is configured in `KS_DevTestConfig.lua`. Only `movement` is active
until locomotion passes in game. Equipment, combat, loot, health, medical treatment, and
persistence are registered as later gates and are activated one at a time as their real
gameplay implementations are added.

The movement scenario automatically:

1. finds a loaded visible square near the player;
2. spawns the single test survivor;
3. chooses a reachable destination;
4. drives and observes movement;
5. prints one machine-readable `RESULT` line with `PASS` or `FAIL`.

`Run Knox Survivors Dev.bat` starts a diagnostic session. While the game runs,
`dev-runs/<run>/live-test-status.txt` contains the latest result. After the game closes,
the collector writes `test-results.txt`, includes test counts in `summary.txt`, and treats
a failed scenario as a possible issue.

These tools are development-only scaffolding. They must stay separate from normal
survivor spawning and will be disabled before a playable Workshop release.
