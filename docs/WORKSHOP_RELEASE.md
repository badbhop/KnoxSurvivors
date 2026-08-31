# Workshop Preview Release

The Workshop mod must be published before the matching launcher release. The launcher rejects the legacy Workshop package by design.

## 1. Freeze and verify the mod build

1. Commit the exact mod revision intended for the preview.
2. Run `gradlew.bat clean :java:build stageWorkshop` from the repository root.
3. Confirm the staged package contains:
   - `Contents/mods/KnoxSurvivors/42/knox-runtime.properties`
   - exactly one `Contents/mods/KnoxSurvivors/java/knox-agent-*.jar`
   - its matching `.sha256` file in that same folder
4. Run one Windows smoke test from that exact staged package.

For the read-only native payload check, compile `tools/WorkshopPayloadVerifier.java`
with the development JDK (`javac --release 17 -d build/release-checks ...`), then run
`WorkshopPayloadVerifier` with the game's bundled Java 25 and a classpath containing
`build/release-checks` and the installed `projectzomboid.jar`. Pass the staging folder
as its single argument. This checks native mod/file acceptance, not preview metadata,
Steam publication, or gameplay. The bundled runtime does not contain javac.

From the launcher checkout, its built `LauncherVerifier` also accepts two optional
arguments: the installed game directory and this staging folder's `Contents` directory.
This verifies the actual published payload against launcher manifest/checksum rules.

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
8. Run the launcher against that downloaded copy. Do not rely only on the local staging folder.

## 4. Publish the matching launcher preview

The tagged workflow prepares a draft preview. Keep it a draft until the Workshop
download passes launcher verification:

1. In the launcher repository, tag the verified commit, for example `v0.2.0-preview.1`.
2. Push the tag to GitHub.
3. Wait for the Windows, Linux, and macOS GitHub checks to pass.
4. Confirm the release contains separate Windows, Linux, and macOS ZIP files plus `SHA256SUMS.txt`.
5. Publish the draft only after the downloaded Workshop copy launches on Windows.
6. Keep it marked as a pre-release until human Linux and macOS launch reports are received.

Players need only the public launcher release and subscribed Workshop item. Making
the main mod source repository private does not affect either dependency.

## 5. Rollback preparation

Keep a ZIP of the exact previous Workshop upload folder before updating. If the preview has a blocking issue, restore that folder through the same existing-item update flow; do not delete the Workshop page.
