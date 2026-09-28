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
- Keep one person/project record per collaborator. Append conversation and work updates to that record instead of creating a new note for every message.
- Store only the contact reference needed to identify the collaboration. Do not copy private addresses, tokens, or unrelated personal information into the repository.
- A conversation is not an approval. Record proposed work, confirmed permission, delivered files, review state, and public-credit wording separately.

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

### Per-collaborator record template

Use this template inside the appropriate contributor section for each real collaborator. Keep the stable identity and the running work log together.

```markdown
### COLLAB-<short-id> — <preferred public name>

- Contact reference: <platform/profile or private reference; no secrets>
- Relationship: <translator / tester / compatibility author / contributor / researcher>
- Project or language: <scope>
- Started: YYYY-MM-DD
- Current status: proposed | active | awaiting handoff | review | integrated | paused | closed
- Official or community work: <which>
- Permission/license boundary: <confirmed wording or pending>
- Public credit wording: <exact approved wording or pending>
- Canonical tasks/bugs: <KS-PROD-###, BUG-KS-###, or none>
- Files/package location: <repository path, fork, PR, or external link>

#### Conversation and decision log

| Date | From/To | Topic | Decision or request | Follow-up | Evidence/link |
|---|---|---|---|---|---|
| YYYY-MM-DD | owner / collaborator | short topic | confirmed wording, proposal, or unanswered question | person responsible | file, PR, screenshot, or message reference |

#### Work log

| Date | Contributor work | Knox-side work | Result/evidence | Next action |
|---|---|---|---|---|
| YYYY-MM-DD | files, translation, test, or report | integration/review needed | exact evidence | owner |

#### Handoff checklist

- [ ] scope and files identified
- [ ] permission/license recorded
- [ ] build/version and compatibility context recorded
- [ ] delivered files preserved or linked
- [ ] review task/bug linked
- [ ] public credit wording confirmed
- [ ] integration/release status recorded
```

For the PT-BR translator, keep the standalone injector, pending hardcoded-string catalog, overflow report, screenshots/videos, and eventual native-string handoff in one `COLLAB-*` record. Do not treat the standalone addon as official integration until the files are reviewed and merged by the project owner.

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

## Conversation capture

When the owner pastes a collaborator conversation, the receiving agent should:

1. identify or create the single matching collaborator record;
2. summarize only decisions, requests, promises, delivered work, risks, and unanswered questions;
3. append dated entries to the conversation/work tables;
4. link any concrete issue to the existing `BUGS.md` or `WORK_QUEUE.md` item;
5. leave vague ideas or unconfirmed claims in the conversation log rather than promoting them to project truth;
6. return a short reply draft only when the owner asks for one.

Never rewrite the entire conversation into production documentation, and never expose private contact details in a public-facing file.
