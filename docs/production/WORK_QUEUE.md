<!-- modforge-doc
authority: canonical
load: always
purpose: canonical active work queue
-->

# Knox Survivors — active production work queue

Updated: 2026-09-26

The sections below are deliberately machine-friendly so ModForge can populate its task board automatically. Keep confirmed bugs in `BUGS.md` instead of hiding them here.

## KS-PROD-001 — Reconcile the current worktree with repository baseline
Status: done
Priority: critical
Owner: Codex
Type: release

### Goal
Identify the GitHub baseline and make the post-main worktree understandable to downstream verification.

### Result
- GitHub `main` verified at `7f56dcb846f107a4c226770b3ca72fe21232235b`.
- Local checkout verified as based on the same HEAD.
- Current source/test changes grouped by subsystem in `CURRENT_STATE.md`.
- Old overlapping plan/release documents consolidated so they no longer compete with current production truth.

### Validation
Repository status/diff, connected GitHub baseline, current source/test inventory and retained historical evidence.

### Definition of Done
Downstream QA can verify the exact current implementation without relying on a stale release snapshot.

## KS-PROD-002 — Run focused verification for all release-bound changed subsystems
Status: todo
Priority: critical
Owner: Codex / OpenCode
Type: qa

### Goal
Prove each changed subsystem passes its cheapest meaningful focused checks before the full gate.

### Scope
Use the tests/verifiers already associated with the changed files. OpenCode may handle narrow failures; Codex owns cross-system or architecture-sensitive failures.

### Acceptance
- Focused checks pass for every release-bound subsystem, or a confirmed failure is converted to a tracked bug.
- No failure is hidden by retries, fake fixtures, or wording changes.

### Validation
Record exact commands/checks and results.

### Definition of Done
All focused release-bound checks are green or represented by explicit blocker tasks.

## KS-PROD-003 — Run the full offline candidate gate
Status: todo
Priority: high
Owner: Codex
Type: release

### Goal
Run the complete syntax/regression/Java/build/package verification on the same candidate revision.

### Acceptance
- Full offline suite completes without unexplained failure.
- Exact check counts, revision/worktree state, and packaging result are recorded.

### Validation
Follow `docs/DEVELOPMENT_TESTING.md` and the supported build/release tooling.

### Definition of Done
A fresh offline evidence record exists for the exact candidate.

## KS-PROD-004 — Complete live UI acceptance on Build 42.20.4
Status: todo
Priority: high
Owner: Human + QA Reviewer
Type: live-test

### Goal
Verify the current Survivor Card and related character UI in the real engine.

### Acceptance
Inspect Skills, health, inventory, and medical views at small and large UI scales without repeated errors, unusable clipping, or stale unloaded-survivor assumptions.

### Validation
Disposable save, target Build 42.20.4, fresh logs.

### Definition of Done
Live UI evidence is recorded with any failure converted into `BUGS.md`.

## KS-PROD-005 — Complete core live gameplay acceptance
Status: todo
Priority: critical
Owner: Human + QA Reviewer
Type: live-test

### Goal
Validate engine-bound behavior that offline doubles cannot prove.

### Acceptance
Cover companion orders/interruption recovery, representative native base jobs, firearms/native damage/reload, save/reload, hibernation/rematerialization, real resource consumption, faction lifecycle/event behavior where enabled, and vehicle behavior where enabled.

### Validation
Use `docs/production/QA_RELEASE.md` and `docs/DEVELOPMENT_TESTING.md`.

### Definition of Done
Required live scenarios pass or produce reproducible tracked bugs.

## KS-PROD-006 — Verify supported Steam/runtime startup paths
Status: todo
Priority: high
Owner: OpenCode + Human
Type: compatibility

### Goal
Confirm the release candidate starts through the supported runtime path(s) from a real subscribed/published-style install.

### Acceptance
- ZombieBuddy path produces fresh expected runtime PASS evidence when used.
- Retained Knox launcher/legacy path works when used instead.
- Direct Steam `-javaagent` route is only called supported after an actual Steam startup acceptance.
- No test intentionally loads duplicate runtime paths.

### Validation
Follow `README.md`, `docs/production/RUNTIME_AND_MIGRATION.md`, and `docs/WORKSHOP_RELEASE.md`.

### Definition of Done
Runtime support claims match live evidence.

## KS-PROD-007 — Refresh candidate evidence and public-facing documentation
Status: todo
Priority: high
Owner: ModForge + Codex
Type: documentation

### Goal
Bring release documentation forward to the exact candidate after verification.

### Acceptance
- `CURRENT_STATE.md`, `QA_RELEASE.md`, `WORK_QUEUE.md` and `BUGS.md` reflect the exact candidate evidence.
- `RELEASE_NOTES.md` contains only supported player-facing claims.
- Generated ModForge state agrees with the canonical repository docs.

### Validation
Cross-check the exact candidate revision, test results, live acceptance, and open bugs.

### Definition of Done
One coherent release story exists across ModForge, production docs, and player-facing docs.
