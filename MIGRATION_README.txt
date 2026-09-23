KNOX SURVIVORS -> ZOMBIEBUDDY MIGRATION
========================================

WHAT THIS DOES
- Knox Survivors can be loaded by ZombieBuddy as a normal Java mod, or by the retained legacy Knox Java-agent/launcher path.
- ZombieBuddy users no longer need Knox's Steam -javaagent line or Knox launch wrapper; legacy launcher users may continue using that path.
- Existing Knox combat/visibility behavior and KnoxJavaBridge are retained.
- ZombieBuddy uses its supported Patch API; Knox does not access ZombieBuddy's private
  Instrumentation state.
- Legacy Knox premain remains temporarily for rollback/developer compatibility only.

FILES
ADD:
  java/src/main/java/com/knoxsurvivors/Main.java

REPLACE:
  java/src/main/java/com/knoxsurvivors/agent/KnoxAgent.java
  mod/42/mod.info
  mod/mod.info
  mod/42/media/lua/client/KS_JavaBridge.lua
  mod/42/knox-runtime.properties

WHY NO GRADLE CHANGE IS REQUIRED
The existing build already produces and stages java/knox-agent.jar. ZombieBuddy supports
JAR paths containing '..' (ZombieBuddy's own Build 42 mod.info uses this pattern), so
mod/42/mod.info points at ../java/knox-agent.jar. Java's normal source set automatically
compiles the new com.knoxsurvivors.Main class into the existing JAR.

FIRST TEST
1. Back up the repo / use a git branch.
2. Drop these files into the repository root, preserving paths.
3. Build/stage the mod exactly as you do now.
4. For the ZombieBuddy path, install/enable ZombieBuddy and Knox Survivors. For the legacy path, enable Knox Survivors and use the Knox Launcher.
5. REMOVE old Knox-specific Steam launch entries before launching:
     -javaagent:...knox-agent.jar=pz-game
   and any Knox knox-steam-launch.cmd wrapper.
6. On Windows, ZombieBuddy's installer can patch ProjectZomboid64.json so Steam's
   Launch Options box can remain empty.
7. Launch using exactly one runtime path. If ZombieBuddy asks whether Knox's Java JAR may load, approve it if you trust the build.
8. Check Documents/Zomboid/KnoxIsoPlayer.log for a fresh:
     runtime start PASS source=zombie-buddy-patch-api
   The ZombieBuddy patch readiness check and Lua bridge should also log PASS.
9. Test spawn, movement, zombie targeting, melee, human-vs-human combat and save/reload.

IMPORTANT
This package is source-level validated, but it cannot replace a real Project Zomboid
42.20.4 live test. Knox's CombatManager transformer contains version-specific bytecode
offsets, so a PZ update or another mod patching the same exact methods can still require
adjustment. ZombieBuddy core itself did not contain patches for Knox's three target
classes when this migration was prepared.

ROLLBACK
Restore these files from git and restore your previous Knox launch method. No save format
or survivor record format is changed by this migration.
