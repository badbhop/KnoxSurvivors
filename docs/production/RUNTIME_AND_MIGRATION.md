<!-- modforge-doc
authority: canonical
load: on-demand
purpose: supported Java runtime paths, player migration and ZombieBuddy trust/signing
-->

# Knox Survivors — runtime, migration and signing

Updated: 2026-09-26

## Supported runtime paths

Knox Survivors currently supports two alternative Java bootstrap paths:

1. **ZombieBuddy Patch API path — recommended**
2. **Knox Launcher / retained legacy Java-agent path — fallback**

Use exactly one path per launch. Do not intentionally stack ZombieBuddy and the Knox legacy `-javaagent` path.

Both paths load the Knox Java runtime/bridge used by the current NPC implementation. The integration changes bootstrap behavior; it does not intentionally change the Knox survivor save schema.

## ZombieBuddy path

- Install/configure ZombieBuddy using its official instructions.
- Enable Knox Survivors and ZombieBuddy for this path.
- Remove obsolete Knox-only startup entries such as `-javaagent:...knox-agent.jar=pz-game` and `knox-steam-launch.cmd`.
- Launch through the ZombieBuddy-configured game startup.
- If ZombieBuddy asks permission to load Knox's Java JAR, approve it only when the build is trusted.

Expected fresh log evidence:

`runtime start PASS source=zombie-buddy-patch-api`

Knox uses ZombieBuddy's supported Patch API. Knox should not depend on ZombieBuddy's private instrumentation state.

## Knox Launcher / legacy path

- Enable Knox Survivors.
- Do not use ZombieBuddy for that launch. If it is installed but inactive, the
  Knox Launcher ignores it; if its startup configuration is active, the launcher
  blocks before game startup rather than composing the two runtimes.
- Start through the Knox Launcher / retained Knox Java-agent setup.

Expected fresh log evidence:

`runtime start PASS source=legacy-javaagent`

The retained `premain` path exists as a supported fallback/rollback path while the Java runtime remains required.

## Player migration rules

- ZombieBuddy is optional and should not be made a hard Workshop Required Item while the legacy path remains supported.
- Existing ZombieBuddy users should remove the old Knox-only `-javaagent`/wrapper startup path.
- Knox Launcher users may continue using the launcher without ZombieBuddy.
- Use one startup method per game launch.
- Back up saves that matter and use a fresh save for release-candidate acceptance.
- Bootstrap migration does not by itself prove compatibility with every Project Zomboid update or Java mod.

## Live verification

After reaching the Project Zomboid menu, inspect:

`Documents\Zomboid\KnoxIsoPlayer.log`

The selected runtime path must produce a fresh matching PASS line. Static package/build checks cannot replace a real Build 42.20.4 startup and gameplay acceptance.

Version-sensitive Knox Java edits currently include narrow behavior around:

- `CombatManager`;
- `SwipeStatePlayer`;
- `IsoZombie`.

A Project Zomboid update or another Java mod modifying the same methods may require renewed compatibility work.

## ZombieBuddy author/trust signing

Project Zomboid `mod.info` already identifies the author as `.exe`, but ZombieBuddy's cryptographic trust identity is separate.

A signed release should place these together:

- `knox-agent.jar`
- `knox-agent.jar.zbs`

The `.zbs` sidecar must be generated from the project owner's private Ed25519 key and SteamID64.

Rules:

- never commit or share the private signing key;
- regenerate the `.zbs` sidecar whenever the JAR changes;
- publish the corresponding public key in the supported ZombieBuddy trust mechanism;
- never package a fake or generic signature.

ZombieBuddy signing reference:
https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/ModSigning.md

## Long-term launcher-free direction

The long-term Workshop-native direction remains documented in `docs/LAUNCHER_FREE_MIGRATION.md`. It is a migration design, not proof that current Java runtime dependencies can be removed today.

Do not retire the current runtime path until the replacement passes its documented lifecycle, save compatibility, combat, movement, inventory, vehicle and release acceptance gates.
