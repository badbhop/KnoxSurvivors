# Workshop Preview Release

Prefer publishing and verifying the Workshop mod before advertising a matching launcher
release. The launcher rejects the legacy Workshop package by design.

The owner requested public preview availability on 2026-08-31:
[v0.2.0-preview.1](https://github.com/exe-create/KnoxSurvivorsLauncher/releases/tag/v0.2.0-preview.1)
is now downloadable. Its real Windows package passes validation against the refreshed
staging files; Steam upload/download and gameplay still need the steps below. Availability
of the launcher alone does not confirm that Steam has delivered the rebuild.

## 1. Freeze and verify the mod build

1. Commit the exact mod revision intended for the preview.
2. Run `gradlew.bat :java:build prepareWorkshopUpload` from the repository root.
   Unlike ordinary staging, this explicit release task replaces `workshop.txt` from
   `workshop/description.bbcode` and copies the existing poster to `preview.png`.
3. Confirm the staged package contains:
   - `Contents/mods/KnoxSurvivors/42/knox-runtime.properties`
   - exactly one `Contents/mods/KnoxSurvivors/java/knox-agent.jar`
     (version-stable filename, so Steam launch options survive updates; no retired versioned JARs)
   - its matching `.sha256` file in that same folder
4. Run one Windows smoke test from that exact staged package.

For the read-only native payload check, compile `tools/WorkshopPayloadVerifier.java`
with the development JDK (`javac --release 17 -d build/release-checks ...`), then run
`WorkshopPayloadVerifier` with the game's bundled Java 25 and a classpath containing
`build/release-checks` and the installed `projectzomboid.jar`. Pass the staging folder
as its single argument. The verifier supports an isolated staging folder under
`build/` using a process-local native filesystem context. It checks mod/file
acceptance, exactly one agent, the matching SHA-256 sidecar and agent premain entry.
When `workshop.txt` is present it also checks the existing item ID, description and
preview. This does not publish or verify gameplay. The bundled runtime does not
contain javac.

From the launcher checkout, its built `LauncherVerifier` also accepts two optional
arguments: the installed game directory and this staging folder's `Contents` directory.
This verifies the supplied payload against launcher manifest/checksum rules; a staging
path is not evidence of a successful Steam publication/download.

## 2. Prepare Project Zomboid's Workshop folder

The `KnoxSurvivors` folder under Project Zomboid's `Workshop` directory must contain:

- `Contents/`
- `preview.png`
- `workshop.txt`

Because this updates the existing item, `workshop.txt` must contain `id=3749727604`. Review its title, description, tags, and `visibility=public` before uploading. Do not create a second Workshop item.

Build 42.20.3 uploads the contents of `Contents/`, not its parent folder. The Java
runtime belongs inside `Contents/mods/KnoxSurvivors/java/`. A root-level `java/`
folder is not published. `stageWorkshop` synchronizes the generated mod folder so
removed Lua files and old runtime versions are not accidentally shipped; it leaves
`workshop.txt` and `preview.png` alone. Back up any manual staging edits before building.

## 3. Upload the existing Workshop item

1. Start Project Zomboid normally through Steam.
2. Open **Workshop**, then **Create and update items**.
3. Select the Knox Survivors entry tied to Workshop item `3749727604`.
4. Review the preview, title, description, Build 42 tag, and public visibility.
5. Choose **Update** and wait for the upload to finish.
6. Open the public Workshop page and confirm its updated time and description.
7. Let Steam download the published build to a normal subscribed installation.
8. Run the launcher against that downloaded copy, or boot once through the
   documented Steam launch option. Do not rely only on the local staging folder.

## 4. Publish the matching launcher preview

The tagged workflow prepares a draft preview. Keep it a draft until the Workshop
download passes launcher verification:

1. In the launcher repository, tag the verified commit, for example `v0.2.0-preview.1`.
2. Push the tag to GitHub.
3. Wait for the Windows, Linux, and macOS GitHub checks to pass.
4. Confirm the release contains separate Windows, Linux, and macOS ZIP files plus `SHA256SUMS.txt`.
5. Publish the draft only after the downloaded Workshop copy launches on Windows.
6. Keep it marked as a pre-release until human Linux and macOS launch reports are received.

Windows players can use the subscribed Workshop item and the one-time Steam launch
option in `README.md`; the launcher is optional. Making the main mod source repository
private does not affect either launch method.

## 5. Rollback preparation

Keep a ZIP of the exact previous Workshop upload folder before updating. If the preview has a blocking issue, restore that folder through the same existing-item update flow; do not delete the Workshop page.

The recovered subscribed copy labelled `1.0.237-beta-active-contained-path-driver` is
also backed up, but has not been confirmed as the latest public Workshop revision.
Do not label it an exact latest-release rollback without checking the actual upload.

See [NORMAL_PLAYER_TEST.md](NORMAL_PLAYER_TEST.md) before testing from this development PC:
local copies with the same Mod ID can shadow the subscribed files.

## Steam launch-option acceptance

The direct Windows recipe is `-javaagent:"<actual subscribed path>\mods\KnoxSurvivors\java\knox-agent.jar"=pz-game --`.
Use the normal Steam EXE launch mode. Preserve existing JVM options before the single
`--` and existing game arguments after it. Do not replace inherited `JAVA_TOOL_OPTIONS`
or use the retired `cmd /c set JAVA_TOOL_OPTIONS=...` recipe.

For support/development, `tools/get-steam-launch-options.ps1` discovers the subscribed
agent and prints the option after validating its checksum and manifest. It does not
edit Steam or game settings and is not required each time the player launches. Pass
`-ExistingOptions` to preserve an existing ordinary options line; ambiguous wrappers
or duplicate Knox options are rejected for manual review. `-SteamRoot` and `-AgentJar`
provide explicit discovery overrides. A generated line is not live launch evidence.
For a Windows Java DLL collision, `-IsolateBundledRuntime -GameDirectory <installed game>`
generates a Steam command wrapper that prepends the bundled runtime directories to the
child process PATH. Retain the generated `%command%` placeholder and pass existing
ordinary options through `-ExistingOptions`; do not paste an existing wrapper into it.
Keep the original Steam line for rollback. This mode preserves the rest of PATH and
does not clear `JAVA_TOOL_OPTIONS`, change global environment values or rewrite game
configuration. A command window may appear; this mode is not the direct EXE-only recipe.

Before calling this route live-verified:

1. Confirm the subscribed JAR and checksum match the intended release; exclude local
   mods shadowing the subscription and any second Knox agent injection.
2. Record the game JSON/BAT hashes, effective JVM options/heap, existing agents, game
   arguments and launch mode. Start with the existing settings, without editing game files.
3. Launch from Steam using the actual subscribed path, including a path with spaces.
   Require fresh agent and transformer success logs and the Lua bridge in a loaded world.
   A `java -version` probe or direct EXE boot does not prove the Steam/subscription route.
4. Check survivor spawn, movement, melee, zombie damage, firearms/reload and save/reload.
   Confirm one body per persisted identity and no player/camera/input ownership change.
5. Compare the same save, agent, settings and survivor count with the existing launch
   path: startup time, frame-time spikes, memory/GC and NPC update cost. Startup packaging
   is not evidence of a gameplay performance improvement.
6. Confirm JSON/BAT hashes and effective settings are unchanged. Test an additional
   game argument and compatible agent without duplicate injection or lost options.
7. Remove the Knox launch option and confirm normal game startup. Restore it for Knox
   testing. Document removal before unsubscribing and path repair after moving libraries.

Keep the Steam/subscribed-install and gameplay gates open until those exact runs are
recorded. Offline command parsing, payload validation and agent startup checks are
separate evidence. Linux/macOS and alternate BAT startup need their own validation.

## Windows runtime isolation and other Java mods

An entry-point error naming an external Java installation (for example Zulu 17's
`java.dll`) is evidence of a native runtime loading failure, not proof that a Knox
class or another mod is incompatible. Diagnose the selected JVM and loaded DLL paths
before changing Java agents. Windows can resolve a dependent DLL by its module name
even when its parent was loaded using a full path; see Microsoft's
[DLL search-order documentation](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-search-order).

For a runtime-selection fix, require these additional checks:

- Reproduce the affected environment with external Java on PATH, then verify `java.dll`
  and `jvm.dll` come from the same bundled runtime after the fix. An unrelated system
  `java -version` result does not prove which DLLs the game EXE loaded.
- Keep the normal game EXE, working directory, launch configuration and heap selection.
  Confine any environment adjustment to the game process; preserve other PATH entries
  and agent options. Do not uninstall system Java or rewrite global environment values.
- Preserve `-javaagent`, `-agentlib` and `-agentpath` options and their order, including
  ZombieBuddy's actual installed configuration. Check Project REM's installed hooks
  rather than assuming that preserving a name or dependency proves compatibility.
- Validate paths with spaces and separate Steam libraries, existing game arguments,
  and operation both with and without an external Java installation. Any one-time
  integration must have a clear removal path and must not leave stale absolute paths
  after moving or unsubscribing from the Workshop item.
- Distinguish command preservation from gameplay compatibility. Require a real run
  with the installed ZombieBuddy/Project REM versions, fresh loading evidence, and
  representative gameplay before claiming that combination is supported. Arbitrary
  agents can still conflict when they patch the same game methods.
