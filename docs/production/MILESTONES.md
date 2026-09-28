<!-- modforge-doc
authority: canonical
load: on-demand
purpose: release gates and milestone state
-->

# Milestones

## M1 — Current candidate reconciliation

Status: done
Target: 2026-09-26

GitHub `main` and the uploaded local HEAD were reconciled, post-main source/test work was grouped by subsystem, and overlapping documentation was consolidated. Focused behavioral verification remains M2 work.

## M2 — Core completion and stabilization gate

Status: in_progress

Complete and connect the existing survivor systems in dependency order: identity/
persistence/lifecycle, brains/autonomy, movement/pathing, combat/threat,
storage/base/jobs, companions/orders/UI, purposeful implemented events/factions,
launcher/runtime compatibility, then performance/default/customization review.
Run focused regression/build checks as each boundary changes and fix confirmed
failures without creating overlapping owners.

## M3 — Full offline release gate

Status: planned

Run the complete Lua/Java/build/package verification on the exact candidate revision and record the evidence.

## M4 — Live Build 42 acceptance

Status: planned

Complete the required disposable-save and normal-player acceptance scenarios on Project Zomboid 42.20.4.

## M5 — Release-ready decision

Status: planned

Reconcile canonical candidate evidence and public release notes, confirm no critical blocker remains, and prepare the supported Workshop/runtime release path for owner approval.
