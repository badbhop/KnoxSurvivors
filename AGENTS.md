<!-- modforge-doc
authority: entrypoint
load: always
purpose: single repository-wide start point for coding agents
-->
# Knox Survivors — repository working instructions

This is the **only repository-wide coding-agent entry point** for Codex, OpenCode, and other implementation tools. Work from the repository root. Do **not** preload every historical document.

## Start every session here

Read these small current-state sources first:

1. `docs/production/PROJECT.md` — stable vision and product boundaries.
2. `docs/production/CURRENT_STATE.md` — current position and immediate objective.
3. `docs/production/WORK_QUEUE.md` — active work, with stable task IDs.
4. `docs/production/BUGS.md` — confirmed failures/blockers only.
5. `docs/production/DECISIONS.md` — settled decisions.
6. `.modforge/PROJECT_STATE.md` when present — generated coordination snapshot; never hand-edit.
7. `.modforge/changes/CHANGE_LEDGER.md` **only when relevant** — recent ModForge file-write notes; confirm exact changes with Git.

Then load only the authority relevant to the current work:

- gameplay scope → `docs/FEATURE_SPEC.md`
- architecture / ownership / persistence / identity → `docs/ARCHITECTURE.md`
- detailed testing / live acceptance → `docs/DEVELOPMENT_TESTING.md`
- candidate/release operations / save compatibility → `docs/production/QA_RELEASE.md` and `docs/production/RELEASE_OPERATIONS.md`
- collaboration / translations / external authors / permissions → `docs/production/COLLABORATION.md`
- NPC design/game-reference work → `docs/design/NPC_SYSTEM_INSPIRATION.md`, `docs/design/README.md`, and a specific `docs/design/INTAKE-*.md` item when relevant
- support/community report triage → `docs/production/SUPPORT_AND_TRIAGE.md`
- deep subsystem history → `docs/FEATURE_AUDIT.md` **only when the active question requires it**

`docs/production/README.md` defines the authority model for every retained document.

## Stay on task

Before changing code, identify the active task/bug ID or the explicit owner request. If there is no tracked item, do not invent a feature just to stay busy; either create/clarify a bounded work item or return the uncertainty to the owner/Boss.

- Preserve established architecture and ownership boundaries. Do not create a second owner for movement, combat, persistence, base work, survivor identity, or lifecycle state.
- Fix the first confirmed failing boundary. Avoid speculative patch stacking, patch chains, and unrelated refactors.
- Use real Project Zomboid systems/items/resources where practical. Never fabricate supplies, native success, damage, world state, or test evidence.
- Offline tests prove only what they exercise. Engine-bound behavior remains unverified until the required live Build 42 acceptance passes.
- Keep experimental systems experimental until their documented acceptance gate passes.
- Do not rewrite large working systems for style.
- Do not broaden scope without recording why the active task now requires it.

## Tool routing and authority

- **Codex / Astra — primary heavy-engineering authority:** hardest implementation, architecture-sensitive expansion, cross-system changes, difficult debugging, broad validation, persistence/identity work, and release hardening. Once assigned a heavy work item, the main Codex session owns the technical implementation approach inside the approved project/architecture boundaries and may use its normal Astra/Sol/subagent setup.
- **OpenCode — budget-engineering authority:** confirmed bug fixes, focused support work, small/medium implementation, cleanup, compatibility investigation, translation/collaboration support, and narrow review/research. Once assigned a bounded item, OpenCode owns that implementation until it either finishes with evidence or escalates the boundary to Codex.
- **ModForge — production/coordination authority:** current state, roadmap, tasks/bugs, documentation index, decisions, collaboration ledger, evidence, agent/workflow construction, routing, and focused handoffs. ModForge/Boss/Planner do not micromanage or compete with the active implementation owner; they intervene when scope, project vision, architecture, evidence, or release risk is violated.
- **Human owner — final product/reputation authority:** product direction, release approval, public claims, save-breaking decisions, permissions/credits, and any scope change with reputation/compatibility impact.

Use subagents for independent research/review/planning. Keep dependent implementation in one coherent owner so multiple agents do not fight over the same files.


## ModForge source-write boundary

ModForge is allowed to maintain its managed coordination/design records, but **project source is read-only by default**. A ModForge Studio agent cannot write outside the approved managed paths unless the owner explicitly enables source writes for this project in ModForge.

If ModForge does make an owner-approved repository change:

1. inspect `.modforge/changes/CHANGE_LEDGER.md`;
2. inspect `git diff` for the exact file change;
3. treat the edit as **unverified implementation** until the normal Codex/OpenCode/QA evidence path validates it;
4. continue from the same task/decision context rather than reinterpreting the project from scratch.

Codex/OpenCode remain the normal implementation authorities. This gate exists so ModForge can safely dogfood or perform explicitly authorized maintenance without ever silently becoming a second uncontrolled coder.

## Design/reference intake

Raw inspiration is not a task. When the owner provides ideas from other games, screenshots, notes, documents, transcripts, or mechanic descriptions, preserve the original intent/source first. ModForge should triage/research/plan it in Design Inbox. Only owner-approved-for-planning material is promoted into `docs/design/INTAKE-*.md`, and implementation still requires a separate approved work item.

## Usage exhaustion / interrupted coding sessions

A provider limit is **not** a reason to change project truth or force a weaker model through risky work. If Codex, OpenCode, or a cloud model runs out of allowance/credits/rate capacity mid-task:

- do not mark the item done, reviewed, tested, or release-ready because the model stopped;
- do not silently enable paid usage, broaden permissions, or swap a weak fallback into architecture-sensitive implementation;
- keep the existing Git working diff and any completed test/evidence output intact rather than blindly rolling it back;
- record/resume from the canonical work item, current Git diff, and evidence when an approved capable model becomes available;
- a safe free/local fallback may help with lookup, scoping, review, or bounded work only when it is actually capable of the remaining boundary.

This makes quota exhaustion a resumable interruption rather than a source of hidden partial-completion claims.

## Debug / console / log policy

Logs are **on-demand diagnostic evidence**, not normal startup context. Do not preload `console.txt`, debug logs, old `dev-runs`, or giant console dumps just because they exist.

Use logs when one of these is true:

- the owner reports a runtime symptom and points to console/debug output;
- a focused test/launcher/startup boundary failed and the log is the next evidence source;
- the task explicitly requires diagnosing an engine/API/runtime failure.

When logs are needed, inspect the **smallest recent/relevant slice first**, correlate it with reproduction time/task ID, and summarize the actual evidence into the canonical bug/task. Do not turn raw logs into permanent routine context.

## Engine investigation reminder

For engine-level behavior, use exact runtime evidence when available. Prefer: current symptom/log → exact engine/API boundary → working-vs-failing comparison → first concrete divergence → smallest safe fix. Do not stack speculative engine patches or treat offline mocks as proof of native animation, pathing, damage, item transfer or UI behavior.

## Before editing

1. Check `.modforge/PROJECT_STATE.md` if present.
2. Check `git status`/`git diff` and preserve unrelated local changes.
3. Identify the active `KS-PROD-*` or `BUG-KS-*` record, or the exact owner request.
4. Read the smallest technical authority that governs the subsystem.
5. Define acceptance and validation before making the change.
6. Escalate to Codex if a supposedly narrow task crosses persistence, identity, lifecycle, architecture ownership, or multiple coupled systems.

## After editing

- Run the cheapest focused verification first; broaden only when warranted.
- Report exact files changed, checks run, what remains unverified, and any live test still required.
- Update the canonical production record **only after the evidence supports the new state**.
- Do not create a new broad status/plan document. Update the existing canonical owner.
- Do not claim release readiness from implementation alone.
- When a tracked item changes state, update `docs/production/WORK_QUEUE.md` or `docs/production/BUGS.md`; ModForge will re-index and regenerate `.modforge/PROJECT_STATE.md`.
- `.modforge/PROJECT_STATE.md` is generated and never edited manually.

## Document authority

Current operational truth lives in `docs/production/`. Technical authorities govern subsystem rules. `docs/FEATURE_AUDIT.md` and Git history preserve deep past evidence but **cannot override current canonical state unless their findings are explicitly reconciled into the production layer**.
