# Launcher

> **Retired for the current KnoxBridge candidate.** This page is historical
> launcher documentation and is not a supported installation or startup path.
> Use [`docs/production/RUNTIME_AND_MIGRATION.md`](production/RUNTIME_AND_MIGRATION.md)
> and the player instructions in `README.md`. Do not stack the old launcher or
> direct agent with KnoxBridge. The separate launcher repository is retained
> only for migration/archive purposes pending owner handling of existing users.

> Release prerequisite: verify the downloaded Workshop item contains the tested IsoPlayer
> build and matching Java checksum before advertising either launch method. Local staging
> alone does not establish the current public payload.

The cross-platform player launcher is deliberately limited to one job: verify the subscribed Knox
Survivors files and start Project Zomboid with the required Java runtime enabled for that
one game process.

Windows players can instead use the one-time Steam launch option in [README.md](../README.md#launching-knox-survivors).
The launcher remains an optional install-verification and discovery path. Remove the
Steam Knox agent option before switching to the launcher, so it is loaded only once.

## Optional launcher setup

1. Install Project Zomboid through Steam.
2. Subscribe to Workshop item `3749727604` and wait for Steam to finish downloading it.
3. Download the Windows, Linux, or macOS archive from the official launcher release.
4. Extract the entire archive, then open `Launch Knox Survivors.cmd` on Windows or
   `Launch Knox Survivors.command` on macOS. Linux users run
   `scripts/launch-knox-survivors.sh`.
5. Enable Knox Survivors on the intended save the first time that save is used.

After that, Steam updates the Lua mod and Java-agent file together through the Workshop.
The launcher discovers Steam libraries automatically.

The launcher does not subscribe to Workshop items or alter save-specific mod selections.
Those are explicit Steam and Project Zomboid user choices.

## Safety boundary

The launcher:

- uses normal Steam locations on Windows, Linux, Flatpak Linux, and macOS;
- reads Steam's `libraryfolders.vdf` and permits the game and Workshop item to be in
  different libraries;
- requires Project Zomboid app `108600`, Workshop item `3749727604`, and Mod ID
  `KnoxSurvivors`;
- verifies both Build 42 `mod.info` files;
- verifies the Java-agent manifest and its published SHA-256 sidecar;
- passes Knox's `-javaagent` through a child-process-only `JAVA_TOOL_OPTIONS` value;
- rejects an active ZombieBuddy configuration before launch instead of composing
  ZombieBuddy and Knox instrumentation in one game process;
- starts the normal, unmodified platform game launcher.

It does not copy files into the game, patch the game launcher, create services, request
administrator access, edit the registry, or set permanent environment variables.

## Paths and private machine configuration

Production discovery contains no usernames or absolute personal paths. Development paths
remain in the repository's ignored `local.properties` file. That file is not committed,
included in Workshop staging, or packaged with the launcher.

## Building a launcher release

The launcher has its own public release repository. Its Windows and Unix build scripts compile
the shared Java 17 source, run the standalone locator/validation verifier, and create separate
Windows, Linux, and macOS archives. GitHub verifies the source on all three operating systems;
tagged packaging runs on Linux so executable bits are retained in the macOS/Linux ZIP files.

The launcher runs on Project Zomboid's bundled Java runtime; players do not install a
separate Java 17 package.

For local development, run:

```powershell
.\scripts\build.ps1
```

from the separate launcher checkout. Tagged builds prepare draft Windows, Linux, and macOS ZIPs
with a `SHA256SUMS.txt` file. The public Workshop package must contain the matching
`knox-runtime.properties`, agent JAR, and checksum before a launcher release is advertised.

## Publishing Workshop runtime updates

`gradlew.bat clean build stageWorkshop` synchronizes the generated Workshop mod payload.
The Java JAR and its generated `.sha256` sidecar live inside
`Contents/mods/KnoxSurvivors/java/`. Steam uploads only `Contents/`, so placing them
beside that folder does not deliver them to subscribers. Upload metadata and preview
are not generated or overwritten by this task.
Steam then keeps Lua and Java runtime versions in the same subscribed item. The launcher
itself only needs a new GitHub release when launcher discovery or validation code changes.

All launcher source, verification, and packaging changes belong in the separate launcher
repository. This mod repository intentionally contains no launcher project or launcher artifact
build path; publish launcher archives only through the separate launcher release workflow.

The mod source repository can remain private: neither discovery nor launch downloads
anything from it. Linux/macOS builds and command fixtures are automated checks, not
proof that a real game installation has launched on those platforms.

See [WORKSHOP_RELEASE.md](WORKSHOP_RELEASE.md) for the ordered Workshop and launcher
preview-release checklist.
