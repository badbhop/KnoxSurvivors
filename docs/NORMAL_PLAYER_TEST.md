# Test the Workshop download, not the development copy

The upload package is prepared for existing Workshop item **3749727604**. The source
repository stays private. This procedure does not require any source files to run the mod.

## Before uploading

1. Close Project Zomboid completely. Keep Steam running.
2. Keep the backup of the old downloaded mod and use a fresh test save. That recovered
   old copy is not confirmed to be the latest public release.
3. Move the two development copies out of `%USERPROFILE%\Zomboid\mods` into a backup
   folder outside Zomboid's mod locations:
   - `KnoxSurvivors`
   - `KnoxSurvivors-pre-rebuild-20260822`
   Both currently declare `id=KnoxSurvivors`, regardless of their folder names.
   Do not delete them or change unrelated mods. Do not run the development launcher
   afterward: its deployment step would put a local copy back.

## Upload the prepared item

1. Start Project Zomboid through Steam for the uploader only.
2. Open Workshop and the create/update screen.
3. Select the prepared `KnoxSurvivors` folder. Confirm existing item **3749727604**,
   the early-rebuild title, original artwork, description, and public visibility.
4. Update the existing item, not a new item. Wait for upload success, then quit the game.
5. Let Steam download the update through the existing subscription.

The folder to upload is `%USERPROFILE%\Zomboid\Workshop\KnoxSurvivors`.
Do not manually copy its files into `steamapps/workshop/content`: that would bypass
the download we need to verify.

## Launch as a subscriber

1. Download `KnoxSurvivorsLauncher-windows.zip` from the public
   [launcher preview](https://github.com/exe-create/KnoxSurvivorsLauncher/releases/tag/v0.2.0-preview.1).
   Anonymous download/checksum verification is complete; this gameplay smoke test is
   still needed after Steam supplies the updated mod.
2. Extract the full ZIP into a new folder, for example Desktop/Knox Survivors Player Test.
3. Open `Launch Knox Survivors.cmd`. Wait for READY, then press PLAY KNOX SURVIVORS.
4. Enable Knox Survivors in Mods and for a **new** single-player test save on 42.20.3.
   Do not use an old Knox save to test migration; that is a separate unverified issue.
5. Check spawn/visibility, short travel, one zombie encounter, recruitment/Follow/Hold,
   inventory interaction, then quit and reload to check identity and equipment.

If READY fails or an error repeats, stop and capture the message. Do not verify against
the local staging folder as a substitute. The launcher log must show the subscribed
Workshop location ending in `steamapps/workshop/content/108600/3749727604`; game logs
must confirm the Knox Java bridge and Lua mod loaded from that installation.

Support logs: `%USERPROFILE%\KnoxSurvivors\launcher.log` and
`%USERPROFILE%\Zomboid\console.txt`, plus the current Knox runtime log when present.

## Release boundary

The launcher preview is public and updated upload files are prepared; that does not
publish the Steam item or prove gameplay. Windows/Linux/macOS CI passes are build/startup-fixture
checks, not real Linux/macOS game runs. Keep the release marked early/preview and
gather those live reports separately.
