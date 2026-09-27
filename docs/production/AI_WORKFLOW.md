<!-- modforge-doc
authority: canonical
load: always
purpose: canonical AI/tool routing workflow
-->

# Knox Survivors — AI development workflow

Updated: 2026-09-26

## Goal

Make one developer operate like a coherent small studio without turning Knox into disconnected AI-generated patches.

The production loop is:

**capture → establish current truth → scope → assign one owner → implement → independent review → validate → record evidence → sync state → choose next work**

## Non-negotiable coherence rules

1. **One active implementation owner per task/bug ID.** Subagents may research, plan, inspect, or review, but dependent edits should not be split across competing agents.
2. **One durable source for each fact.** Active work lives in `WORK_QUEUE.md`; confirmed defects in `BUGS.md`; settled decisions in `DECISIONS.md`. `.modforge/PROJECT_STATE.md` is generated.
3. **No opportunistic scope creep.** If an agent finds adjacent work that is not required to complete the current item, record/triage it instead of silently fixing it.
4. **Escalate by boundary, not by frustration.** Narrow reproducible bugs stay in the budget lane. Persistence/identity/lifecycle/architecture/cross-system work moves to Codex.
5. **Evidence changes status.** Code existing is not the same as offline verified, live verified, or release ready.
6. **No agent creates work merely to stay busy.** When there is no approved actionable item, return the uncertainty/priorities to the Boss/owner.

## ModForge — production desk

ModForge is the persistent coordination layer. It should automatically sync the repository on project open, on watched canonical-file changes, and on the configured fallback interval without spending model tokens just to detect changes.

ModForge owns:

- project overview/current state;
- roadmap and milestones;
- task/bug board synchronized with canonical repository sections;
- decision log and documentation authority index;
- collaboration/credits/support intake;
- evidence/completion state;
- cheap planning/research/review agents;
- workflow construction and tool routing;
- focused handoff packets for Codex, OpenCode, and ChatGPT Consultant use;
- Design Inbox/reference provenance before ideas become roadmap work;
- Model Center role profiles and explicit Free / Subscription Allowance / Paid usage lanes;
- source-write protection and Change Ledger notes when ModForge itself is deliberately allowed to edit repository files.

For imported production tasks/bugs, ModForge is a **view/editor of repository truth**, not an independent second task database. Safe UI changes should write through to the canonical section when there is no external-edit conflict.

## Implementation authority hierarchy

For an approved work item, authority is deliberately separated:

1. **Human owner:** final product, reputation, release, public claims, permissions, and save-breaking decisions.
2. **Codex / Astra:** primary technical implementation authority for heavy engineering assigned to Codex.
3. **OpenCode:** technical implementation authority for bounded budget/scoped engineering assigned to OpenCode.
4. **ModForge / Boss / Planner:** production coordination, scope, priority, constraints, evidence, and routing. They do not rewrite the active implementer's approach just to express a different preference.
5. **Cheap subagents:** research, scoping, cleanup, independent review, and evidence support only unless explicitly promoted.

If an implementation conflicts with recorded project vision, architecture ownership, task scope, or evidence requirements, ModForge/Boss can stop/escalate it. Otherwise the assigned coding tool gets room to work coherently like the project's engineering department.

## Codex / Astra — heavyweight engineering department

Use Codex for:

- architecture-sensitive changes;
- persistence, identity, lifecycle, ownership, reconstruction;
- cross-system expansion;
- difficult engine/debugging work;
- broad required refactors;
- large release-hardening/reconciliation passes;
- difficult regressions whose first failing boundary spans multiple systems.

Normal Codex startup:

`AGENTS.md` → current production docs → generated project state → smallest relevant technical authority → Git status/diff.

The main Codex session (normally Astra for the owner's heavy-engineering workflow, with Sol/other approved models when deliberately chosen) remains the implementation owner. It should use its own normal agent/subagent workflow rather than being reduced to a passive ModForge worker. Cheap subagents should handle planning, file scoping, lookups, and independent review where useful. Do not spend the strongest model on grunt work by default.

## OpenCode — budget implementation/support department

Use OpenCode for:

- confirmed narrow bug fixes;
- small/medium scoped implementation;
- support/triage follow-up;
- compatibility investigation;
- cleanup and mechanical maintenance;
- translation/collaboration support;
- narrow review/research using local/free/cheap models.

OpenCode must stop and escalate instead of stretching a cheap patch when the work crosses persistence, survivor identity, lifecycle ownership, save migration, core architecture, or several coupled systems.

Project subagents live under `.opencode/agents/`. Model/provider selection is intentionally flexible: prefer local/free/cheap routes, but the owner may deliberately use spare OpenCode subscription/provider allowance for stronger planning/research/support. ModForge must never assume an ambiguous OpenCode route is free; subscription-backed model IDs are explicitly marked in Model Center and require the Subscription Allowance toggle.

## ModForge team roles

### Boss
Owns priorities, dependencies, blockers, project health, assignment, and handoffs. Protects the project vision; does not become the default coder.

### Planner
Turns an approved goal/bug into a bounded plan with dependencies, acceptance, validation, and stop/escalation conditions. Does not code or make final product/architecture decisions.

### Grunt
Cheap operations worker for lookups, file/task/doc maintenance, evidence gathering, cleanup, and mechanical support. No architecture decisions and no coding by default.

### Researcher
Answers one narrow technical/compatibility question, records evidence/uncertainty, and returns it to the active owner.

### QA Reviewer
Independently checks the requested scope, diff, regressions, evidence level, and release claims. Does not approve engine behavior without the required live evidence.

## Routing matrix

| Situation | Default route |
|---|---|
| unclear request / missing acceptance | Planner |
| narrow technical unknown | Researcher |
| narrow reproduced bug | OpenCode |
| small/medium isolated implementation | OpenCode |
| persistence/identity/lifecycle/ownership | Codex |
| cross-system feature/major expansion | Codex |
| difficult release reconciliation/hardening | Codex |
| product/public/collaboration permission decision | Boss prepares; human decides |
| release claim | QA Reviewer + evidence + human approval |
| community report | `SUPPORT_AND_TRIAGE.md` before coding |

## Handoff contract

Every implementation handoff should carry:

- stable task/bug ID;
- why the work matters now;
- exact allowed scope and explicit out-of-scope items;
- relevant decisions/architecture boundaries;
- acceptance criteria;
- validation plan/evidence level required;
- likely files/systems when known;
- stop/escalation conditions;
- current Git/repository state warning;
- instruction to return exact changed files/checks/unverified risks.

A handoff is not permission to clean unrelated code.

## Completion loop

1. Implementation owner returns result/evidence.
2. QA Reviewer checks task contract and scope drift.
3. Required focused/full/live checks run.
4. Only then does task/bug status advance.
5. Canonical repository section is updated (directly or by ModForge write-through).
6. ModForge re-indexes and regenerates `.modforge/PROJECT_STATE.md`.
7. Boss chooses the next approved item from fresh state.

## Context rule

Do not dump the entire repository or `FEATURE_AUDIT.md` into routine model calls. Start with the short production path, then lazy-load only the technical/history material required for the current boundary.


## Usage exhaustion / model failure

AI usage limits must never change project truth by themselves. If Codex/OpenCode/a cloud model runs out of quota or becomes unavailable:

1. stop at the current recorded boundary;
2. do not mark the task done or advance release status;
3. preserve completed diffs/tests/evidence;
4. switch only to a deliberately configured free/local fallback when it is capable of the remaining work; otherwise leave the item open/paused;
5. never silently enable paid API usage or broaden permissions just to keep an agent running;
6. when the stronger implementation lane becomes available again, resume from the canonical task, Git diff, and recorded evidence rather than restarting from memory.

For heavy architecture work, a weak fallback should support research/scoping/review rather than taking over an implementation it cannot safely own.

## Debug / console evidence

Do **not** ingest logs during normal planning or every coding session. Logs are a diagnostic tool, not project memory.

Use them only when the active bug/test/runtime boundary calls for them or the owner says a log contains the symptom. Start with the smallest recent slice around the reproduction, extract the useful evidence into `BUGS.md` / the active task, then return to source/tests. Old bulk logs and `dev-runs` stay excluded from routine ModForge context.

## Model/usage lanes

ModForge separates model usage into three user-visible lanes:

1. **Free/local** — default and preferred for routine Boss/Planner/Grunt/Research/QA work.
2. **Subscription allowance** — optional; use spare included usage from Codex/ChatGPT-plan-backed routes or OpenCode models the owner explicitly marks as subscription-backed. This is for times when stronger planning/research is worth spending weekly/session allowance.
3. **Paid/metered API** — separate explicit opt-in. Never enabled automatically by quota failure.

Quota exhaustion stops cleanly or uses an explicitly configured safe free fallback. It never promotes a paid route or a weak model into risky architecture work without approval.

## Design Inbox → production work

Game inspiration, owner notes, community suggestions, PDFs/transcripts/screenshots, and mechanic comparisons start as **design/reference intake**, not implementation. Boss/Planner/Researcher may organize and analyze them, but only the owner can approve the resulting direction. Promoted material is written under `docs/design/` with provenance, then reconciled into decisions/roadmap before implementation work exists.

## ModForge file writes

Routine ModForge behavior should not edit Knox source. Managed production/design records may be updated; all other repository writes require explicit per-project owner approval. Every ModForge file write produces a local `.modforge/changes/CHANGE_LEDGER.md` entry so Codex/OpenCode can inspect the same rationale/task context before continuing. Git diff is the exact authority for what changed.
