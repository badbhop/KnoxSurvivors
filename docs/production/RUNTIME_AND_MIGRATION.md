<!-- modforge-doc
authority: canonical
load: on-demand
purpose: current supported KnoxBridge module runtime and migration boundary
-->

# Knox Survivors — KnoxBridge runtime and migration

Updated: 2026-09-28

## Active runtime

The Workshop candidate uses KnoxBridge as its only Java runtime bootstrap. KnoxBridge is a separate required runtime install; after setup, users enable Knox Survivors in the PZ Mods menu and launch normally through Steam. The Windows bootstrap is stored in Project Zomboid's own JSON VM arguments; the Linux/macOS helper edits the selected Steam account's launch option. Setup exposes exact-JAR SHA-256 ALLOW/DENY decisions. The Knox Workshop payload contains no ZombieBuddy dependency or startup path.

Knox declares `com.knoxsurvivors.knox-module` in `mod/42/knoxbridge.properties`. The Knox module reuses the existing Java bridge, NPC runtime, and direct transformers. Lua survivor simulation and save schema are unchanged. The module uses KnoxBridge's `system` class-loader policy because transformed PZ classes must resolve Knox's helper methods; this grants module code normal JVM permissions and is not a sandbox.

## Rollback boundary

The direct Knox `premain` entry and source remain in the repository as a rollback path while the KnoxBridge module is validated. They are not selected by Workshop metadata. Never run the legacy agent and KnoxBridge together in one PZ process.

## 42.21 verification

On normal Steam Play, the installed runtime reported PZ 42.21.0 / Java 25.0.1, discovered the actual enabled roots for the independent test module and Knox Survivors, blocked both unknown hashes, then loaded both after exact-hash approval and restart. The test entrypoint initialized and registered its harmless probe. Knox initialized through the `system` class-loader policy; required combat and visibility patches reported ready, `KnoxJavaBridge` was exposed, and combat-impact/human-pair gates reported PASS. Later in the same live game session, Knox logged a real NPC probe spawn, movement transitions, combat attacks, and zombie health reaching zero; one movement attempt reported `FailedStuck`. Save/reload was not tested. The game JSON comparison confirms all original settings match after removing only KnoxBridge-owned VM arguments. The full prior Workshop `Contents` tree was backed up before local staging replacement; no other mods, settings, or saves were targeted.

NPC creation, movement/order, zombie awareness/combat, save/reload, deny and changed-hash behavior, and live 42.20 remain open. The staged Workshop files are local and have not been uploaded. Knox's use of the system class loader grants normal JVM permissions and is not a sandbox.

The candidate metadata range is 42.20–42.21, with 42.21 labeled as testing. Offline transformer checks are not live gameplay proof.
