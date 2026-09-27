<!-- modforge-doc
authority: canonical
load: on-demand
purpose: canonical private collaboration ledger
-->

# Knox Survivors — collaboration and external-work ledger

Updated: 2026-09-26

This is the private production ledger for translators, compatibility partners, external mod authors, donated assets/work, permissions, and joint work. Public credits should be derived from confirmed records here, not from memory or an old chat.

## Rules

- Record the person's/project's preferred public name exactly.
- Record what they contributed and whether it is code, translation, testing, compatibility help, art/audio, research, or advice.
- Record permission/license boundaries when files or code are exchanged.
- Never imply contributor status merely because another project was used as a reference or compatibility target.
- Keep unauthorized forks/reuploads separate from collaboration records.
- Translation ownership/maintenance should identify language, current maintainer, source, and whether it is official or community-maintained.
- Before a public release, reconcile this file with player-facing credits/Workshop text.

## Confirmed project ownership

| Name | Role | Scope | Public credit status |
|---|---|---|---|
| .exe | Creator / project owner | Original Knox Survivors code, framework, direction and release ownership | Confirmed |

## Runtime / dependency relationships

| Project | Relationship | Notes | Contribution claim |
|---|---|---|---|
| Project Zomboid / The Indie Stone | Base game / engine | Knox targets Project Zomboid Build 42 and uses native game systems/assets under the game's normal modding context | Not a Knox contributor |
| ZombieBuddy | Optional Java runtime integration | Knox supports a ZombieBuddy Patch API path plus its retained legacy runtime path | Integration/dependency relationship; do not imply authorship of Knox |
| Superb Survivors | Concept inspiration | README explicitly identifies inspiration for the survivor-mod concept, not a source-code dependency | Inspiration only |

## Translators

_No repository-backed translator identity is confirmed in the retained documents yet._

Add confirmed translators here:

| Language | Contributor / team | Source / fork | Official or community | Permission / notes | Public credit |
|---|---|---|---|---|---|

## Mod-author collaboration

_No repository-backed external co-author/contributor record is confirmed in the retained documents yet._

| Author / project | Collaboration | Files/systems affected | Permission | Status | Public credit |
|---|---|---|---|---|---|

## Compatibility work

| Project / mod | What was tested | Evidence | Status | Owner |
|---|---|---|---|---|
| ZombieBuddy | Knox Java runtime bootstrap / Patch API path | `docs/production/RUNTIME_AND_MIGRATION.md`, `README.md`, runtime logs/tests | Supported path; live release compatibility still follows release gates | Knox project |

## Support-scale coordination

The owner reports Knox Survivors is approaching 26,000 active users. At that scale, translation offers, compatibility help, donated work, and external-author coordination should be recorded here before implementation so permissions and public credit do not get lost in support traffic. Player reports that are not collaboration belong in `SUPPORT_AND_TRIAGE.md`.

## Incoming collaboration workflow

1. Capture request/offer in ModForge Inbox.
2. Record author/project identity and contact reference.
3. Define exact scope and permission boundary.
4. Create task(s) with owner and acceptance criteria.
5. Keep exchanged code/assets traceable to source and permission.
6. Review integration and compatibility evidence.
7. Update this ledger and `CREDITS.md` before release.
