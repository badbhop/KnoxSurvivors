<!-- modforge-doc
authority: canonical
load: on-demand
purpose: canonical community support triage process
-->

# Knox Survivors — community support and issue triage

Updated: 2026-09-26

Knox Survivors is now operating at a scale where support reports, compatibility questions, translation offers, and collaborator requests need a repeatable intake path instead of living only in chat history. The project owner reports the mod is approaching **26,000 active users** as of 2026-09-26; treat that figure as owner-reported operational context, not an independently verified analytics record.

## Goals

- Keep player reports from turning directly into speculative code changes.
- Separate support questions, confirmed bugs, compatibility problems, feature requests, and collaboration offers.
- Preserve enough evidence that Codex/OpenCode can reproduce a problem without rereading entire Discord/Steam threads.
- Make public commitments only after the project owner approves them.
- Keep credits, translator status, permissions, and external-author work traceable.

## Intake classes

### Support question
A player needs setup/runtime/save/feature guidance and there is no confirmed defect yet.

Record:
- game build;
- Knox version;
- runtime path (ZombieBuddy or Knox launcher/legacy path);
- whether this is a new or existing save;
- relevant settings/mod list when compatibility may matter;
- concise symptom and logs/screenshots when available.

Do **not** create a bug merely because a player is confused or a setup step was missed.

### Bug candidate
A repeatable symptom, error, broken behavior, or source-confirmed failure exists.

Flow:
1. capture reproduction/evidence;
2. Grunt/Researcher removes irrelevant noise and checks duplicates;
3. Planner identifies the first likely boundary and acceptance criteria;
4. create/update `BUGS.md` only when the report is concrete enough to track;
5. route narrow fixes to OpenCode and architecture/cross-system failures to Codex;
6. QA Reviewer checks regression evidence and required live verification.

### Compatibility report
A problem depends on another mod, runtime, Project Zomboid update, or environment.

Record the exact versions and relationship in `RESEARCH_AND_COMPATIBILITY.md`. If another author is actively coordinating with Knox, also record the relationship in `COLLABORATION.md`.

### Feature request
Do not put community requests directly into the active roadmap. Capture the request, expected player value, likely scope, and conflicts with current project principles. The Boss may prepare it for owner review; only approved work enters `WORK_QUEUE.md` / `ROADMAP.md`.

### Translation / external contribution
Use `COLLABORATION.md` first. Record contributor identity, language/project, scope, permission/ownership boundaries, maintenance expectations, and preferred public credit wording. Promote only confirmed entries to `CREDITS.md`.

## Severity guide

- **Critical** — save corruption/loss, widespread startup failure on a supported path, severe identity/persistence corruption, or release-blocking regression.
- **High** — major promised gameplay system unusable or repeatably broken for a meaningful population.
- **Medium** — real defect with workaround or limited scope.
- **Low** — minor UI/quality issue, edge-case annoyance, or non-blocking polish.

Popularity alone does not change severity; reproducibility, impact, and release risk do.

## Duplicate handling

Keep one canonical bug/task per underlying failure. Add new evidence, affected versions, and reproduction variants to that record rather than creating parallel fixes. If two symptoms prove to have different failing boundaries, split them deliberately and link the relationship in the task text.

## Public response discipline

- Do not promise dates or features that are not approved.
- Do not call a compatibility issue fixed until the relevant evidence passes.
- Do not expose private collaborator contact details in public credits.
- Do not present a community fork/reupload as an official contribution without confirmed permission/status.
- For active incidents, give players the safest known workaround and state what is still being investigated.

## ModForge usage

ModForge should import this document as project support policy and use the `support_triage` workflow from `.modforge/workflows.json`.

Normal support loop:

**report → classify → deduplicate → gather evidence → bug/task if warranted → implementation handoff → validation → update docs/public response**

Routine support triage should use local/free/cheap models when possible. Escalate to Codex only when the report crosses architecture/ownership/persistence boundaries or needs broad implementation work.
