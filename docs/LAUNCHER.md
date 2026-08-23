# Launcher

The player launcher is deliberately limited to one job: verify the subscribed Knox
Survivors files and start Project Zomboid with the required Java runtime enabled for that
one game process.

## Player setup

1. Install Project Zomboid through Steam.
2. Subscribe to Workshop item `3749727604` and wait for Steam to finish downloading it.
3. Download `KnoxSurvivorsLauncher-win-x64.zip` from the official GitHub release.
4. Extract and run `KnoxSurvivorsLauncher.exe`.
5. Enable Knox Survivors on the intended save the first time that save is used.

After that, Steam updates the Lua mod and Java-agent file together through the Workshop.
The launcher discovers Steam libraries automatically and needs no settings screen.

The launcher does not subscribe to Workshop items or alter save-specific mod selections.
Those are explicit Steam and Project Zomboid user choices.

## Safety boundary

The launcher:

- reads the Steam installation path from the normal Windows registry entry;
- reads Steam's `libraryfolders.vdf` to support additional library drives;
- requires Project Zomboid app `108600`, Workshop item `3749727604`, and Mod ID
  `KnoxSurvivors`;
- verifies both Build 42 `mod.info` files;
- verifies the Java-agent manifest and its published SHA-256 sidecar;
- passes `-javaagent` through a child-process-only `JAVA_TOOL_OPTIONS` value;
- starts the normal, unmodified `ProjectZomboid64.bat`.

It does not copy files into the game, patch the game launcher, create services, request
administrator access, edit the registry, or set permanent environment variables.

## Paths and private machine configuration

Production discovery contains no usernames or absolute personal paths. Development paths
remain in the repository's ignored `local.properties` file. That file is not committed,
included in Workshop staging, or packaged with the launcher.

## Building a launcher release

Run:

```powershell
.\tools\build-launcher.ps1
```

The script builds the .NET Framework 4.8 Windows executable, runs the standalone locator
and validation verifier, and writes the release ZIP plus its SHA-256 file under the
ignored `launcher/artifacts` directory.

The executable is framework-dependent on Windows' .NET Framework 4.8 and does not bundle
a separate runtime. Code signing should be added before broad public distribution so
Windows can identify the publisher; until then, an unsigned release may trigger a
SmartScreen reputation warning.

## Publishing Workshop runtime updates

`gradlew.bat clean build stageWorkshop` creates the Workshop layout. The staged Java JAR
and its generated `.sha256` sidecar must be uploaded together with `Contents/mods`.
Steam then keeps Lua and Java runtime versions in the same subscribed item. The launcher
itself only needs a new GitHub release when launcher discovery or validation code changes.
