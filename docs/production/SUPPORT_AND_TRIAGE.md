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

### Tester and player report intake

The owner may paste a tester's or player's complete report directly into the next
available intake block below. The report can be informal; the triage agent must
extract the useful facts without inventing missing details. Keep the original
wording or a link outside the repository when permission/privacy requires it.

```markdown
### REPORT-<date>-<short-id> — <short symptom>

- Reporter: <preferred name or anonymous>
- Contact reference: <platform/profile; no private secrets>
- Report date: YYYY-MM-DD
- Game/build: <exact Build 42 version if known>
- Knox version/commit: <version, workshop revision, or unknown>
- Runtime path: <KnoxBridge / normal Steam without Knox runtime / ZombieBuddy / deprecated Knox Launcher / unknown>
- Save: <new / existing / disposable / unknown>
- Mods/setup: <relevant list or unknown>
- Exact symptom: <what the player saw>
- Reproduction steps: <numbered steps or unknown>
- Expected result: <what should happen>
- Actual result: <what happened instead>
- Evidence: <console slice, screenshot, video, save, file, or none>
- Frequency: always | often | once | unknown
- Severity guess: critical | high | medium | low | unknown
- Privacy/permission limits: <what may not be copied or shared>
- Triage status: new | needs-info | support | compatibility | bug-candidate | duplicate | feature | resolved
- Linked record: <BUG-KS-### / KS-PROD-### / none>

#### Triage notes

- Confirmed facts:
- Missing information:
- Duplicate check:
- First likely boundary:
- Safe workaround, if known:
- Next owner/action:
```

For a batch of reports from one tester, use one report block per distinct symptom
and add the tester's stable identity to a collaborator/tester record in
`COLLABORATION.md`. Do not create a bug for every message: deduplicate by the
underlying failing boundary.

### Tester work record

When a tester is repeatedly helping, add a compact record to the collaboration
ledger rather than turning their reports into a public credit automatically:

```markdown
### TESTER-<short-id> — <preferred name>

- Contact reference: <platform/profile>
- Scope: <systems, build, language, or save type>
- Status: active | occasional | paused
- Permission to use reports/media: confirmed | pending | not granted
- Linked reports: REPORT-..., BUG-KS-..., KS-PROD-...
- Public credit: pending | approved wording | not requested

#### Testing log
| Date | Scenario/build/save | Result | Evidence | Follow-up |
|---|---|---|---|---|
| YYYY-MM-DD | short scenario | pass/fail/partial | link or file | owner/action |
```

### Support question
A player needs setup/runtime/save/feature guidance and there is no confirmed defect yet.

Record:
- game build;
- Knox version;
- runtime path (KnoxBridge, normal Steam without a Knox runtime, ZombieBuddy,
  deprecated Knox Launcher, or unknown);
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

Promotion rule: a pasted report stays in intake until it has a concrete symptom
and enough reproduction/evidence to distinguish a bug candidate from support or
compatibility help. Once confirmed, add or update one canonical `BUG-KS-*` entry
and link the report identifier there. Do not delete the original report context;
compress it into the canonical record and retain the source reference when allowed.

#### Report-to-bug promotion map

When a report is promoted to `BUGS.md`, carry fields across as follows so no
evidence is lost in the rename:

| REPORT-* field | BUG-KS-* destination |
|---|---|
| Exact symptom + Actual result | `### Symptom` (observed behavior first, then what was desired) |
| Reproduction steps | `### Reproduction` |
| Expected result | `### Expected` |
| Evidence + Triage notes (confirmed facts, duplicate check, first likely boundary) | `### Evidence` |
| Game/build, Knox version/commit, Launcher/runtime, Save, Mods/setup, Frequency | `### Evidence` (environment block at the top) |
| Reporter, Contact reference, Report date | `### Evidence` (source line) plus the `Linked record` back-pointer; never paste private secrets |
| Privacy/permission limits, Safe workaround, Missing information | `### Evidence` (limits/workaround notes) or `### Validation` (missing-info live steps) |

`### Acceptance` and `### Validation` never come from the report verbatim: the
Planner drafts them from the first likely boundary, and the `Status/Priority/Owner/Type`
header is assigned at promotion time (`Severity guess` informs priority but does
not set it). After promotion, set the report's `Triage status` and `Linked record`
and add the report ID to the bug's evidence section.

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

When deduplicating tester reports, record the report IDs, affected builds, and
different reproduction conditions in the existing bug's evidence section. A
report that cannot yet be reproduced remains linked intake evidence, not a
second bug.

## Public response discipline

- Do not promise dates or features that are not approved.
- Do not call a compatibility issue fixed until the relevant evidence passes.
- Do not expose private collaborator contact details in public credits.
- Do not present a community fork/reupload as an official contribution without confirmed permission/status.
- For active incidents, give players the safest known workaround and state what is still being investigated.

## ModForge usage

When ModForge is available, it may import this document as project support
policy and use the `support_triage` workflow from `.modforge/workflows.json`.
ModForge is not required: Codex/OpenCode or the owner may follow the same loop
directly from this document, `BUGS.md`, `WORK_QUEUE.md`, and Git.

Normal support loop:

**report → classify → deduplicate → gather evidence → bug/task if warranted → implementation handoff → validation → update docs/public response**

The normal support loop updates the existing canonical record in place. It must not create a parallel support plan, bug ledger, or status document. A vague report remains triage context only; a confirmed report updates or creates the smallest appropriate `BUG-KS-*` entry in `BUGS.md` and then routes implementation to OpenCode or Codex. If ModForge is active, it re-indexes the edited record; it does not become a second authority.

Routine support triage should use local/free/cheap models when possible. Escalate to Codex only when the report crosses architecture/ownership/persistence boundaries or needs broad implementation work.
