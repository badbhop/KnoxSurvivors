# Knox Survivors — Codex Instructions

## Authoritative project documents

Use these documents instead of rediscovering project intent:

- `docs/FEATURE_SPEC.md` — required final gameplay scope.
- `docs/FEATURE_AUDIT.md` — current implementation status and next development priority.
- `docs/ARCHITECTURE.md` — authoritative architecture, engine research findings, ownership boundaries, persistence design, and implementation constraints.
- `docs/DEVELOPMENT_TESTING.md` — authoritative automated/live verification procedures.
- `docs/MILESTONES.md` — milestone context and implementation history.

`FEATURE_AUDIT.md` is the authoritative source for what is currently finished, unfinished, blocked, or awaiting verification.

Do not repeatedly perform a whole-repository feature audit unless the audit is clearly stale or the user explicitly asks.

## Development loop

For each milestone:

inspect relevant implementation
→ identify the actual missing/failing boundary
→ implement the smallest architecture-safe solution
→ run the cheapest useful focused tests
→ update `FEATURE_AUDIT.md`
→ continue to the next actionable unfinished dependency.

Preserve the architecture documented in `ARCHITECTURE.md`.

Do not redesign stable systems merely for style.

## Live-testing rule

Live Project Zomboid evidence is required where documented in `DEVELOPMENT_TESTING.md`, but lack of a new live run is not automatically a development blocker.

If the newest available live logs have already been inspected:

- do not search for them repeatedly;
- do not rerun unchanged log analysis;
- do not repeatedly announce that testing is required;
- mark the relevant work `Implemented, unverified` when appropriate;
- record the exact pending live verification in `FEATURE_AUDIT.md`;
- continue another independent productive feature.

Only wait for live testing when proceeding would risk save corruption, survivor identity loss/duplication, real-player/IsoPlayer ownership corruption, invalidate dependent architecture, or when no independent productive work remains.

## Engine work

For engine-level behavior use the exact Project Zomboid installation configured by
`local.properties` and record its build before drawing conclusions. The current
release candidate targets Build 42.20.4.

Do not guess engine behavior.

Use:

runtime evidence
→ exact engine inspection
→ working-vs-failing path comparison
→ first concrete divergence
→ smallest safe fix.

Do not stack speculative engine patches.

## Priority

Prioritize:

1. build/crash/save corruption;
2. real-player and IsoPlayer ownership;
3. identity/lifecycle/reconstruction;
4. fundamental movement/action ownership;
5. combat/damage;
6. dependencies required by other major systems;
7. unfinished gameplay features.

Defer non-blocking polish while major promised systems remain unfinished.
