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

## M2 — Stabilization gate

Status: planned

Run focused regression/build checks, fix confirmed failures, and leave no unexplained changed subsystem.

## M3 — Full offline release gate

Status: planned

Run the complete Lua/Java/build/package verification on the exact candidate revision and record the evidence.

## M4 — Live Build 42 acceptance

Status: planned

Complete the required disposable-save and normal-player acceptance scenarios on Project Zomboid 42.20.4.

## M5 — Release-ready decision

Status: planned

Reconcile canonical candidate evidence and public release notes, confirm no critical blocker remains, and prepare the supported Workshop/runtime release path for owner approval.
