<!-- modforge-doc
authority: canonical
load: always
purpose: canonical settled decision ledger
-->

# Knox Survivors — active project decisions

Updated: 2026-09-28

These are settled operating/product decisions extracted from the current repository documentation. Agents should not reopen them without new evidence or owner direction.

## D-001 — Single-player is the current supported focus

Multiplayer NPC support is not a current release promise.

Source: `README.md`, `RELEASE_NOTES.md`.

## D-002 — Prefer native Project Zomboid systems where practical

Survivors use real items, actions, containers, combat, clothing, farming, and other vanilla systems instead of simulated success where practical.

Source: `README.md`, `docs/ARCHITECTURE.md`, `docs/production/PROJECT.md`.

## D-003 — Live engine behavior requires live evidence

Offline doubles/tests do not prove native animation, projectile damage, item transfer, pathing, UI behavior, or other engine-bound behavior.

Source: `docs/production/QA_RELEASE.md`, `docs/DEVELOPMENT_TESTING.md`.

## D-004 — Experimental systems remain experimental until accepted

Vehicle autonomy, automatic raids/large faction events, away-team dispatch, developer QA modes, and other explicitly experimental systems must not become release promises without their acceptance gate.

Source: `README.md`, `docs/production/QA_RELEASE.md`, `RELEASE_NOTES.md`.

## D-005 — KnoxBridge is the sole supported Knox Java runtime path

The current Knox candidate uses KnoxBridge. Do not advertise the standalone
Knox Launcher or a direct Knox Java-agent path as alternatives, and never stack
KnoxBridge with ZombieBuddy or another instrumentation runtime. Preserve the
old launcher/source only as a migration artifact until Bridge acceptance and
rollback gates are complete. Java modules must explicitly implement the
KnoxBridge contract; arbitrary or ZombieBuddy-specific JARs are not assumed
compatible.

Source: `README.md`, `docs/production/RUNTIME_AND_MIGRATION.md`,
`docs/production/RESEARCH_AND_COMPATIBILITY.md`.

## D-006 — Historical engineering evidence does not own current status

`docs/FEATURE_AUDIT.md` and Git history preserve deep implementation evidence. Current production truth is routed through `docs/production/` and must be reconciled against the current worktree.

Source: `docs/README.md`, `docs/production/SOURCE_REGISTRY.md`.

## D-007 — ModForge is optional coordination; Codex/OpenCode implement

ModForge owns organization, roadmap, documentation, low-cost planning/review,
bug/decision tracking, and handoffs when it is being used. Codex/OpenCode remain
the normal coding path and must be able to work directly from the repository
without ModForge installed, running, or synchronized.

Source: `docs/production/PROJECT.md`, `docs/production/AI_WORKFLOW.md` and owner direction.

## D-008 — Canonical repository records are the durable production truth

`docs/production/WORK_QUEUE.md` and `docs/production/BUGS.md` own repository-backed work state independently of ModForge. ModForge may edit those records through guarded write-through, but its local database and generated `.modforge/PROJECT_STATE.md` are coordination/cache layers rather than competing truth. External repository edits win on sync conflicts.

Source: owner direction and the production hardening workflow.

## D-009 — One implementation owner per work item

A single coding lane owns dependent implementation for a task. Planner, Grunt, Researcher, and QA agents may support or independently review it, but they must not make competing edits to the same dependent work. Adjacent discoveries are triaged separately unless the active task demonstrably requires them.

Source: owner direction and the production hardening workflow.

## D-010 — Codex/Astra and OpenCode own technical execution for assigned implementation

For an approved work item, Codex/Astra is the primary technical authority for heavy engineering and OpenCode is the technical authority for bounded budget/scoped engineering. ModForge, Boss, Planner, and cheap support agents own coordination, scope, priority, constraints, evidence, and routing; they do not compete with or repeatedly re-plan the active implementation unless project vision, architecture ownership, scope, evidence, or release safety is violated. The human owner remains final for product/reputation/release/public decisions.

Source: owner direction and the production hardening workflow.

## D-011 — Usage exhaustion and logs must fail safe

Running out of model allowance, rate limit, or credits must not silently enable paid usage, mark work complete, or alter release status. Preserve completed evidence/diffs, use only a deliberately configured safe free fallback when capable, otherwise pause the item for later resumption. Debug/console logs are on-demand diagnostic evidence only and must not be preloaded into routine project context; inspect the smallest relevant recent slice when the active runtime/test boundary requires it.

Source: owner direction and the ModForge 1.9 failover/diagnostics policy.


## D-012 — Knox NPCs remain Project Zomboid survivors, not colony pawns

Other games are mechanic references only. The NPC architecture should connect current Knox systems around one primary intention/job, bounded emergency reactions, real PZ resources, group/base needs, persistent relationships/history and loaded ↔ unloaded continuity.

Do not replace working Knox systems simply to imitate another game's architecture.

Source: owner 2026-09-26 research direction and `docs/design/NPC_SYSTEM_INSPIRATION.md`.

## D-013 — Standalone development remains supported

The minimum supported workflow is: read `AGENTS.md`, load the small canonical
production path, identify a task/bug or explicit owner request, inspect Git,
implement with the assigned coding tool, validate, and update the existing
canonical record. ModForge sync, generated state, Inbox, Change Ledger and
handoff UI are optional accelerators and must never be prerequisites for work.

Source: owner workflow direction and `AGENTS.md`.

## D-014 — Complete and connect existing systems before unrelated expansion

The next playable milestone prioritizes finishing, connecting and polishing the
systems already implemented: survivor loops/brains, movement/pathing, native
actions, combat/threat awareness, persistence/off-screen continuity,
storage/base/jobs, companion orders/UI, events/factions/world life, and the
launcher/runtime boundary where required. A new feature family stays deferred if
it has not meaningfully started or has no clear purpose in the core loop.

An implemented experimental system with a real player purpose should be brought
to a safe complete state rather than abandoned as a half-connected promise.

Source: owner milestone direction, 2026-09-26.

## D-015 — Balanced defaults with explicit player customization

Player-facing defaults should be conservative, believable and performance-aware.
Meaningful population, autonomy, event, difficulty and performance behavior
should be configurable where the existing architecture supports it. Settings do
not bypass ownership, native-world requirements, evidence gates or save safety.

Source: owner milestone direction, 2026-09-26.

## D-016 — Off-screen simulation is continuous, real, and cheaper — never faked

Unloaded survivors continue in real time: travel, needs, rest, intent, group membership, and history keep advancing through the persisted ledger at the same rates and triggers as loaded life. Performance savings come from cheaper computation (coarse travel, stepped needs, bounded storylets, no bodies/pathfinding/animation), not from inventing supplies, combat results, loot, injury/death, blood, smashed windows, robbery, or raid outcomes. Every abstract outcome reconciles idempotently onto the same identity through loaded native actions; failed materialization stays retryable.

Source: owner vision direction, 2026-09-28.

## D-017 — Rare-but-findable population, relations-driven hostility, deferred politics/creator/MP

Settled from owner concept answers, 2026-09-28:

- **Rarity:** survivors stay rare — never armies — but findable without hours of searching. The apocalypse feels empty yet encounters, fights, and immersive world activity happen through ordinary exploration. Everyone keeps moving, eating, and surviving off-screen. Defaults stay conservative; named modes/presets (e.g. Lonely / Balanced / Lively) should eventually let each player pick their preference without leaving anyone out.
- **Hostility:** encounters are relations-driven. A survivor may be hostile or not depending on history and current relations — never random aggression and never guaranteed peace.
- **Deferred:** full faction politics (alliances/wars/territory deals), the survivor/faction creator built on the vanilla character creator plus Knox additions, and multiplayer compatibility are future tracks. Single-player remains the supported focus (D-001); these tracks begin only after the core loop is live-verified, each with its own approved work item.

Source: owner concept direction, 2026-09-28.

## D-018 — Walking-Dead danger, universal living-world moments, keep-all-systems

Settled from owner concept answers, 2026-09-28:

- **First moments:** loading in feels like normal Zomboid — then the world proves alive. Stumble on a small group fighting another over food, materials, or past history. Find a lone scared survivor looking for shelter. Come across a faction base building up and farming. Meet police, military, or a solo survivor who wants conversation but not company. Universal and systemic, never scripted encounters — the same rules for groups, factions, and independents.
- **Danger:** unpredictable and human. Strangers may share, talk, rob, or attack depending on history and relations — humans scarier than zombies, and the greatest benefit comes from working together when it clicks. Think Walking Dead realism. This sharpens D-017: relations-driven, but wide-ranging rather than mostly-cautious.
- **Keep all:** every system on the roadmap stays — vehicles, cooking, trading, camps, raids — with more expansion later, not less. Nothing is cut.
- **Join-as-member (future):** asking to join or live at a faction base as a member rather than a leader is a future feature track with its own work item, after the core loop is live-verified. Today recruitment means survivors joining the player, not the reverse.
- **Preset naming:** future rarity presets get the best plain player-facing names; sandbox settings stay numerous and organized for exact customization. Placeholder names in current docs are not final.

Source: owner concept direction, 2026-09-28.

## D-019 — Driving joins the core-completion track; offline-first tempo

Settled from owner direction, 2026-09-28:

- **Driving scope:** autonomous NPC driving, group vehicle acquisition, and group/faction convoys move from experimental-gated (D-004) to the core-completion track. NPCs use vehicles on their own for a believable world; groups obtain and share cars; convoys run 2–3 carloads with no hard count cap — bounded only by real vehicle availability, condition, and fuel, plus documented performance budgets. Seating, entry/exit, control release, and persistence stay identity-safe under existing ownership.
- **Storage support:** heavy vehicle/base materials (logs, metal sheets, parts) route through the existing typed-storage policies; no second stockpile owner is created to serve vehicles.
- **Tempo:** live Build 42 testing is halted unless absolutely needed. Progress is proven offline with focused regressions plus `tools/verify.ps1 -SkipJava`; every live-only boundary is recorded as an open replay item with its exact scenario, not run. Evidence gates themselves do not move — deferred live items still block their release claims.

Source: owner direction, 2026-09-28.

## D-020 — Social transfer consequences require verified real transfer

Gift or money interactions may not award relationship trust, play a received-
gift response, or report success unless the existing physical item owner has
verified the corresponding transfer. `Give Item` therefore uses the existing
trade UI/action in explicit one-way gift mode, including real inventory
ownership, capacity, receipt, rollback, and capture checks. Its gift contribution
is awarded after the verified transfer only. Abstract currency balances are not
an owner; supported tangible currency items are transferred as real items.
Social-only actions must never stand in for a missing economy operation.

Source: source-confirmed `BUG-KS-032`, 2026-09-28.

## D-021 — Loaded social memory records finalized outcomes only

The loaded relationship coordinator owns encounter decisions and verified
social consequences; `KS_OffscreenStories` owns bounded personal history in
each survivor's existing persistent ledger. Record an event only after its
loaded outcome is committed (greeting, disposition, or real group membership).
Interrupted encounters are not memories. Hostility records a persisted hostile
encounter, never an assumed fight, robbery, or transfer. Fail closed when a
canonical survivor ledger is unavailable; do not create partial persistence
state for narrative convenience. Existing dialogue and presentation consume
that history.

Source: source-confirmed `BUG-KS-036`, 2026-09-28.
