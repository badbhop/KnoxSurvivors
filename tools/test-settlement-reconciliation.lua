local rootPath = arg[1] or "."
local file = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomy.lua", "r"))
local source = file:read("*a")
file:close()

assert(source:find('require "KS_BaseManager"', 1, true),
    "autonomy must load the existing base manager before reconciliation")
assert(source:find("local function reconcileSettlementDefinitions()", 1, true),
    "settlement reconciliation must have one explicit cadence helper")
assert(source:find("manager.ensureFactionBases", 1, true)
    and source:find("manager.ensurePlayerBases", 1, true),
    "reconciliation must use both existing settlement owners")
assert(source:find("KnoxPersistence.reconcileAllBaseTaskClaims", 1, true),
    "settlement cadence must repair stale task claims even without an automatic worker")
assert(source:find("reconcileWorldPopulation(bridge)\n        reconcileSettlementDefinitions()", 1, true),
    "settlement reconciliation must share the population cadence")
print("Settlement reconciliation PASS shared_cadence=true idempotent_owner=true")
