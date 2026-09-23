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

The supported Windows Steam route uses the Workshop-shipped
`knox-steam-launch.cmd` bootstrap:

`"<actual subscribed path>\mods\KnoxSurvivors\knox-steam-launch.cmd" %command%`

The bootstrap keeps the normal Steam command, prepends the game's own
`jre64\bin` and `jre64\bin\server` to PATH for that process tree only,
preserves inherited `JAVA_TOOL_OPTIONS`, appends the Knox agent, and forwards all
existing Steam arguments. It does not edit global environment values, game JSON/BAT
files, saves or mod settings.

For support/development, the staged/subscribed
`get-steam-launch-options.ps1` discovers the subscribed agent, validates its checksum
and premain manifest, checks the bootstrap is present, and prints a merged Steam line.
Pass `-ExistingOptions` with the player's current Steam line. Plain launch arguments
are kept after an explicit `%command%`; a line that already contains exactly one
`%command%` is preserved behind the Knox bootstrap. Duplicate Knox entries and
multiple `%command%` placeholders are rejected.

Common Java mod options must survive unchanged. In particular, a Windows ZombieBuddy
line such as `-agentlib:zbNative --` becomes:

`"<actual subscribed path>\mods\KnoxSurvivors\knox-steam-launch.cmd" %command% -agentlib:zbNative --`

Before calling this route live-verified:

1. Confirm the subscribed package contains `knox-steam-launch.cmd`,
   `get-steam-launch-options.ps1`, the stable `java/knox-agent.jar`, and its matching
   checksum. Exclude local mods shadowing the subscription and remove any older Knox
   `-javaagent` Steam option.
2. Record the game JSON/BAT hashes, effective heap/options, other agents, game arguments
   and launch mode. Do not edit those files for this test.
3. Launch the normal Steam EXE from the actual subscribed copy. On a machine with an
   external Java (for example Zulu) on PATH, verify the game reaches the main menu and
   fresh Knox logs show `agent start arguments=pz-game`, transformer success and Lua
   bridge availability.
4. Verify loaded `java.dll`/JVM components come from Project Zomboid's bundled
   `jre64`, not the external Java installation.
5. Test one existing direct agent option (ZombieBuddy is the primary compatibility
   case) and one existing `%command%` wrapper. Confirm their original arguments remain
   present and Knox loads only once.
6. Check survivor spawn, movement, melee, firearms/reload and save/reload. Confirm one
   body per persisted identity and no player/camera/input ownership change.
7. Confirm JSON/BAT hashes, saves and global environment values are unchanged. Remove
   only the Knox bootstrap prefix and confirm the previous Steam line still launches.

Keep Steam/subscribed-install and gameplay gates open until those exact runs are
recorded. Offline payload checks are separate evidence. Linux/macOS and alternate BAT
startup need their own validation.

## Windows runtime isolation and other Java mods

An entry-point error naming an external Java installation (for example Zulu 17's
`java.dll`) is a native runtime selection problem. The Workshop bootstrap addresses
that by changing PATH only in the Project Zomboid process tree before the JVM loads;
it does not uninstall system Java or change the user's global PATH.

For a runtime-selection fix, require these additional checks:

- Reproduce the affected environment with external Java on PATH, then verify `java.dll`,
  `jli.dll`, `instrument.dll` and `jvm.dll` come from the same bundled runtime after the fix. An unrelated system
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
- Round-trip the generated wrapper through Windows `cmd`, comparing the exact child
  arguments, working directory, exit code, inherited agent variables and remaining PATH.
  Cover quoted spaces/parentheses and reject unsupported shell syntax rather than
  silently changing it. Verify parent-process and user/machine environment values stay
  unchanged. Simulating `%command%` is a parser test, not an actual Steam launch.
- Distinguish command preservation from gameplay compatibility. Require a real run
  with the installed ZombieBuddy/Project REM versions, fresh loading evidence, and
  representative gameplay before claiming that combination is supported. Arbitrary
  agents can still conflict when they patch the same game methods.
