<!-- modforge-doc
authority: canonical
load: on-demand
purpose: release, save compatibility, packaging, hotfix and rollback policy
-->
# Knox Survivors — release operations and save-compatibility policy

Updated: 2026-09-26

This document governs how a candidate becomes a public build. It does not declare the current candidate ready; `CURRENT_STATE.md`, `BUGS.md`, and `QA_RELEASE.md` own that state/evidence.

## Save compatibility policy

- Preserve survivor identity, ownership, persistence schema expectations, inventory/resources, orders, bases/camps, relationships, and lifecycle state across supported save/load boundaries.
- Any deliberate persistent-data shape change must have an explicit migration/default path before publication.
- Never silently reinterpret an existing durable field in a way that can duplicate, orphan, reset, or corrupt survivor/world state.
- A change touching persistence/identity/lifecycle is release-sensitive even if its offline tests pass; use the live acceptance requirements in `QA_RELEASE.md`.
- If save compatibility cannot be maintained, the owner must explicitly approve the break and the player-facing migration note must say exactly what is affected. AI agents may not make this call implicitly.

## Candidate freeze

Before final release validation:

1. Define the exact candidate scope/revision/worktree state.
2. Stop unrelated feature expansion.
3. Convert every known candidate failure into `BUGS.md` with evidence.
4. Run focused verification for each changed subsystem.
5. Run the full offline gate on the same candidate.
6. Run required live Build 42 acceptance on the same candidate.
7. Refresh `docs/production/QA_RELEASE.md` and player-facing release notes from that exact evidence.

Any release-bound source change after the full gate invalidates the affected evidence and requires the appropriate verification to be rerun.

## Workshop/runtime packaging

- Follow `docs/WORKSHOP_RELEASE.md` for packaging mechanics.
- Preserve the Workshop-required `mod/poster.png` and `mod/icon.png` assets and their Build 42 counterparts while those files are referenced by `mod.info`/the build.
- Use exactly one supported Java runtime path per launch; do not intentionally stack alternative bootstrap paths. See `RUNTIME_AND_MIGRATION.md`.
- Validate the actual staged/subscribed payload, not only a source-tree layout.
- Do not publish generated build caches, temporary logs, IDE indexes, local machine properties, or development artifacts.

## Hotfix policy

A hotfix is appropriate for a narrow confirmed regression affecting the public release when the smallest safe correction can be isolated and verified without pulling unrelated unfinished work.

Hotfix flow:

**capture reproduction → confirm first failing boundary → isolate fix → focused regression → required live check → package verification → owner approval → public note**

If the fix crosses persistence, identity, architecture ownership, or multiple coupled systems, route it through the normal Codex/release-hardening path instead of treating it as a cheap patch.

## Rollback / hold conditions

Hold publication or roll back the candidate when evidence indicates any of the following without an accepted mitigation:

- save corruption or survivor identity loss/duplication;
- real-player/IsoPlayer ownership corruption;
- crash/startup failure on the supported runtime path;
- repeatable native combat/resource/action failures that invalidate a release promise;
- a critical confirmed blocker in `BUGS.md`;
- candidate/source drift that makes the recorded verification refer to a different revision.

## Public release authority

Only the project owner approves publication, compatibility-breaking changes, contributor/credit wording, and public promises. ModForge/Codex/OpenCode may prepare evidence and release material but must not silently publish or broaden claims.
