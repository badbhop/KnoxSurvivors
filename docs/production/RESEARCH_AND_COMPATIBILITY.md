<!-- modforge-doc
authority: canonical
load: on-demand
purpose: canonical research and compatibility index
-->

# Knox Survivors — research and compatibility index

Updated: 2026-09-28

## Target environment

- Project Zomboid Build 42.
- Current repository target: **stable `42.20.4`**.
- Project Zomboid `42.21` was released to the **Unstable** branch on 2026-09-23; this does not silently change Knox's production target.
- Single-player is the current supported focus.
- Windows is the primary documented test platform.

Retargeting Knox to a newer unstable/stable build requires an explicit compatibility work item and renewed engine-sensitive verification.

## Runtime compatibility

Two alternative Java runtime paths are currently documented:

1. ZombieBuddy Patch API path (recommended).
2. Knox launcher / retained legacy Java-agent path.

Use one path per launch. See `RUNTIME_AND_MIGRATION.md`.

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
- `../LAUNCHER.md` — retained launcher details.
- `../LAUNCHER_FREE_MIGRATION.md` — long-term launcher-free design.
- `../WORKSHOP_RELEASE.md` — Workshop/runtime release checks.
- `../design/NPC_SYSTEM_INSPIRATION.md` — NPC-system research/design direction.
