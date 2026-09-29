<!-- modforge-doc
authority: canonical
load: on-demand
purpose: canonical research and compatibility index
-->

# Knox Survivors — research and compatibility index

Updated: 2026-09-28

## Target environment

- Project Zomboid Build 42.
- Current compatibility-test target: **stable `42.21.0`**, following the owner's 2026-09-28 direction and The Indie Stone's [42.21 Stable release announcement](https://projectzomboid.com/blog/news/2026/09/42-21-stable-released/).
- The existing `KnoxSurvivors` mod ID and files now declare a `42.20`–`42.21` metadata range so the same mod can be tested on both builds. This does not claim Knox Survivors already works on 42.21.
- Single-player is the current supported focus.
- Windows is the primary documented test platform.

The current 42.21 compatibility work is tracked in `WORK_QUEUE.md` as KS-PROD-010. It requires renewed engine-sensitive verification before a new public Workshop upload.

## Runtime compatibility

The current Knox candidate uses KnoxBridge as its only supported Java runtime
path. ZombieBuddy is historical interoperability research, not the current
technical baseline or a supported Knox startup path. The separate Knox
Survivors Launcher is deprecated and unsupported; the owner has requested that
its repository become private, but the setting still needs to be changed and
verified. The direct Knox agent remains in source only as a rollback artifact
and must not be stacked with KnoxBridge. See `RUNTIME_AND_MIGRATION.md`.

KnoxBridge discovers only PZ-enabled mods with a valid `knoxbridge.properties`
descriptor and an entrypoint implementing the versioned KnoxBridge API. It does
not load arbitrary Java archives or ZombieBuddy-specific modules unchanged;
their authors must port or explicitly support KnoxBridge. Its Workshop item
contains the dependency marker, compile-time API, and guides; player runtime
setup is downloaded separately, and the
Linux/macOS path is implemented but lacks live OS acceptance.

Runtime PASS evidence and static packaging checks do not replace real gameplay/release acceptance.

## Engine-sensitive areas

The repository identifies narrow Java edits around `CombatManager`, `SwipeStatePlayer` and `IsoZombie` as version-sensitive. Project Zomboid updates or another Java mod patching the same methods may require renewed compatibility testing.

## Compatibility discipline

- Distinguish bootstrap compatibility from gameplay compatibility.
- Validate against actual installed versions when another runtime/mod is involved.
- Do not claim compatibility from filenames/dependency names/static inspection alone.
- Record exact runtime/build evidence for release claims.

## NPC design research

Current owner-approved NPC-system research is consolidated in:

`../design/NPC_SYSTEM_INSPIRATION.md`

That document uses Project Zomboid, RimWorld, Survivalist: Invisible Strain, State of Decay 2, Rebuild 3 and Dead State as bounded design references while keeping PZ as the foundation. As of 2026-09-28 it also contains the verified TIS vision synthesis (NPCs-as-players, abstract storylets, three manifest stages), the immersive/natural/smooth feel guide, per-system implementation dossiers with Knox owners and must-never rules, and the Codex execution map. Codex should read the dossier for the active subsystem plus `../ARCHITECTURE.md` and `../FEATURE_SPEC.md`; the dossier does not replace task/bug state in `WORK_QUEUE.md`/`BUGS.md`.

The current research is sufficient for the next architecture/design pass. Additional game research is optional and should enter through Design Inbox rather than becoming surprise implementation scope.

## Deep sources

- `../ARCHITECTURE.md` — engine and ownership design.
- `../DEVELOPMENT_TESTING.md` — verification procedures.
- `RUNTIME_AND_MIGRATION.md` — supported bootstrap, migration and signing.
- `../LAUNCHER.md` — retirement notice for the deprecated launcher.
- `../LAUNCHER_FREE_MIGRATION.md` — long-term launcher-free design.
- `../WORKSHOP_RELEASE.md` — Workshop/runtime release checks.
- `../design/NPC_SYSTEM_INSPIRATION.md` — NPC-system research/design direction.
