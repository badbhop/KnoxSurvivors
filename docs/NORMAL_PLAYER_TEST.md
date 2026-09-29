# Test the subscribed Knox Survivors release

Use a disposable single-player save. This checks the subscriber installation and
supported KnoxBridge startup path, not the local development copy or full gameplay
acceptance.

## Prepare

1. Subscribe to Knox Survivors and its required KnoxBridge Runtime Workshop item.
   Wait for Steam to finish both downloads.
2. Close Project Zomboid. Move any local `KnoxSurvivors` development folders out
   of `%USERPROFILE%\Zomboid\mods` into a backup folder outside Zomboid's mod
   locations. Do not delete them or disturb other mods.
3. Download the official KnoxBridge player setup from
   [GitHub Releases](https://github.com/exe-create/KnoxBridge/releases/latest).
   On Windows, run `KnoxBridgeSetup.exe` and choose install/update. The installer
   uses Project Zomboid's bundled Java.
4. Enable Knox Survivors in the PZ Mods menu. Start Project Zomboid normally
   through Steam; do not use the retired Knox Survivors Launcher or another Java
   instrumentation runtime.

## First startup and short gameplay check

1. In the updated KnoxBridge Workshop version, open **Review Java Mods** at the
   main menu. Confirm the Knox module is listed by exact JAR name/hash, keep
   unknown files denied, and allow only modules you trust. Choices apply after
   a full restart. The displayed author is unverified metadata. This UI is not
   in the currently published Bridge package and must not be claimed tested
   until a new disposable Build 42 replay passes. Never bypass an antivirus
   malware detection.
2. At the main menu, confirm the current run has a fresh KnoxBridge log and that
   Knox reports its bridge/module ready. Record the exact Project Zomboid build,
   Knox version, runtime, and save name.
3. Create a new disposable save. Check survivor visibility, travel a short route,
   interact and recruit if eligible, issue Follow/Hold, and observe one safe
   zombie encounter only if convenient. Do not treat a missing encounter as a
   population count.
4. Save, quit, and reload once. Record whether identity, equipment, relationship,
   and any companion order remain coherent. This is a test result, not a claim
   that all save migration or long-term persistence is supported.

If startup or gameplay fails, stop and preserve the smallest useful evidence:
the exact symptom, game/build, Knox version, runtime path, save type, and a log
excerpt from the reproduction time. Useful logs are `%USERPROFILE%\Zomboid\console.txt`
and `%USERPROFILE%\Zomboid\KnoxBridge\knoxbridge.log`.

## Boundaries

- KnoxBridge is the only supported Knox Java runtime path. The separate Knox
  Survivors Launcher is deprecated/private and must not be used.
- Linux/macOS setup is implemented but has not been live-verified; this checklist
  does not certify those platforms.
- Use a new save for testing and back up saves you care about. Migration from
  older Knox NPC data is not guaranteed.
- A successful startup does not prove native movement, combat, transfers,
  save/reload, or release readiness.
