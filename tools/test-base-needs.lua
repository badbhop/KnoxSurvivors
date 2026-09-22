local root = arg[1] or "."
package.path = root .. "/mod/42/media/lua/client/?.lua;" .. package.path
require "KS_OrderCatalog"
local needs = dofile(root .. "/mod/42/media/lua/client/KS_BaseNeeds.lua")

local summary = {
    loadedPolicies = 1,
    totals = { food = 1, water = 0, building = 0 },
    misplacedItems = 2,
}
local task = { type = "farm_seed", priority = 60 }
local tasks = needs.apply({ task }, summary, 3)
assert(task.basePriority == 60, "original priority should be retained")
assert(task.priority == 80, "food shortage should raise farming priority")
assert(needs.priorityBonus({ type = "haul_corpse" }, summary, 3) == 24,
    "corpse cleanup should be urgent")
assert(needs.priorityBonus({ type = "sort_depot" }, summary, 3) == 18,
    "misplaced depot items should raise sorting priority")
assert(needs.priorityBonus({ type = "farming" }, summary, 3) == 20,
    "legacy farming task types should use shortage priorities")
assert(needs.priorityBonus({ target = { action = "farm_seed" } }, summary, 3) == 20,
    "task action should provide a safe fallback when type is absent")
assert(needs.priorityBonus({ type = "farm_seed" }, { totals = { food = 20 } }, 3) == 0,
    "adequate food should not raise farming priority")
local streamedTask = { type = "farm_seed", priority = 60 }
needs.apply({ streamedTask }, {
    loadedPolicies = 0,
    totals = { food = 0, water = 0, building = 0 },
}, 3)
assert(streamedTask.priority == 60,
    "streamed-out storage should not invent a shortage priority")
local controllerFile = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r"
))
local controllerText = controllerFile:read("*a")
controllerFile:close()
local plannerFile = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_BaseSupplyPlanner.lua", "r"
))
local plannerText = plannerFile:read("*a")
plannerFile:close()
assert(string.find(plannerText, '{ kind = "find_weapon", category = "weapons"', 1, true)
    and string.find(plannerText, '{ kind = "find_tools", category = "tools"', 1, true)
    and string.find(plannerText, 'Planner.reserveStatus(totals, residentCount)', 1, true),
    "base shortages should include weapon and tool recovery goals")
assert(string.find(plannerText, 'function Planner.chooseWorker', 1, true)
    and string.find(controllerText, 'KnoxBaseSupplyPlanner.chooseWorker', 1, true),
    "automatic supply work should use persisted resident rotation")
assert(string.find(plannerText, 'function Planner.chooseAvailableShortage', 1, true)
    and string.find(controllerText, 'chooseAvailableShortage', 1, true),
    "separate shortage types should be assignable without duplicating one kind")
assert(string.find(controllerText, 'function Controller:beginBaseSupplyDeposit', 1, true),
    "base supply runs must have an explicit return deposit handoff")
assert(string.find(controllerText, 'function Controller:beginBaseResourceRun', 1, true)
    and not string.find(controllerText, 'findSupply(self, "base_supply"', 1, true)
    and string.find(controllerText, 'self.state = "BASE_TASK_SUPPLY_WAIT"', 1, true),
    "blocked base jobs must wait for assigned storage instead of roaming for supplies")
assert(string.find(controllerText, 'self.pendingBaseSupplyDeposit = { item = recoveredBaseItem }', 1, true),
    "recovered base supplies must be retained until the resident returns home")
assert(string.find(controllerText, 'baseSupply = true', 1, true),
    "base-supply deposits must be distinguishable from ordinary cleanup")
assert(string.find(controllerText, 'self:setLifeIntent("base_supply_deposit"', 1, true),
    "base-supply handoff must persist across save and reload")
assert(string.find(controllerText, 'carriedItemByType(self.character', 1, true),
    "restored base-supply handoff must resolve against real carried inventory")
assert(string.find(controllerText, 'claimantDuty.mode == "base"', 1, true)
    and string.find(controllerText, 'claimantDuty.baseId', 1, true),
    "stale supply claims must be limited to current residents of the same base")
assert(string.find(controllerText, 'local baseSupplyClaimsByBase = {}', 1, true)
    and string.find(controllerText, 'restoreSupplyClaim(self.baseId, kind, self.id)', 1, true)
    and not string.find(controllerText, 'self.base.supplySearchClaims = claims', 1, true),
    "loaded supply leases must remain transient and rebuild from durable run ownership")
assert(not string.find(controllerText,
    'local supplyGoal = self:baseSupplyNeed(ticks)', 1, true),
    "base residents must not autonomously leave the base for shortages")
assert(string.find(controllerText,
    'Base residents stay on settlement duty', 1, true),
    "base shortage decisions must retain settlement duty")
assert(string.find(controllerText,
    'if self:beginWorldSearch(decision.kind, ticks) then return end', 1, true)
    and string.find(controllerText, 'self:clearLifeIntent()', 1, true)
    and string.find(controllerText,
        'autonomous neighborhood search. findSupply() fails closed', 1, true),
    "base residents may retrieve assigned storage but must not start a neighborhood search")
assert(string.find(controllerText,
    'KnoxPersistence.requeueBaseTasksForSurvivor', 1, true),
    "resting residents must release persisted task claims")
assert(string.find(controllerText,
    '"resident_requested_rest"', 1, true),
    "rest preference should use a stable requeue reason")
assert(string.find(controllerText, 'self.baseSupplyOrder = nil', 1, true)
    and string.find(controllerText, 'explicitKind', 1, true),
    "base residents should retain and execute explicit supply orders")
assert(string.find(controllerText, 'self.baseSupplyOrderAttempts < 3', 1, true),
    "failed explicit supply orders should stop after bounded retries")
local persistenceFile = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_Persistence.lua", "r"
))
local persistenceText = persistenceFile:read("*a")
persistenceFile:close()
assert(string.find(persistenceText, 'function KnoxPersistence.setBaseSupplyOrder', 1, true)
    and string.find(persistenceText, 'function KnoxPersistence.clearBaseSupplyOrder', 1, true)
    and string.find(persistenceText, 'function KnoxPersistence.recordBaseSupplyOrderAttempt', 1, true)
    and string.find(persistenceText, 'function KnoxPersistence.beginBaseSupplyRun', 1, true)
    and string.find(persistenceText, 'function KnoxPersistence.finishBaseSupplyRun', 1, true),
    "base supply orders need an ownership-checked persistence boundary")
assert(string.find(controllerText, 'self:syncBaseSupplyRun()', 1, true)
    and string.find(controllerText, 'self:finishBaseSupplyRun("empty")', 1, true)
    and string.find(controllerText, 'continuingSupplyOrder', 1, true),
    "in-flight supply ownership must restore and release at terminal outcomes")
assert(string.find(controllerText,
    'function Controller:beginImmediateNeedAction(kind, ticks)', 1, true)
    and string.find(controllerText, 'source=retrieved_supply', 1, true)
    and string.find(controllerText, 'need_supply_transfer_not_completed', 1, true),
    "retrieved food and water must verify transfer and chain native consumption")
assert(string.find(controllerText,
    'local function inspect(container, square, seen)', 1, true)
    and string.find(controllerText, 'local nestedSupply = inspect(inventory, square, seen)', 1, true),
    "assigned storage searches must inspect real nested containers")
local needsFile = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_SurvivorNeeds.lua", "r"
))
local needsText = needsFile:read("*a")
needsFile:close()
assert(string.find(needsText, 'function Needs.isNeedCurrent(character, kind)', 1, true)
    and string.find(controllerText, 'not needCalloutIsCurrent(self.character, decision)', 1, true),
    "need dialogue must use the live native stat boundary")
assert(string.find(persistenceText, 'base_supply_deposit = true', 1, true)
    and string.find(persistenceText, 'returning = true', 1, true),
    "base supply return intent must survive save and reload")
assert(string.find(persistenceText, 'base.supplySearchClaims = nil', 1, true),
    "legacy runtime supply leases must be removed from persisted base records")
local serviceFile = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_CompanionService.lua", "r"
))
local serviceText = serviceFile:read("*a")
serviceFile:close()
assert(string.find(serviceText, 'BASE_SUPPLY_ORDERS', 1, true)
    and string.find(serviceText, 'setBaseSupplyOrder', 1, true),
    "player-facing supply orders should route through the base boundary")
local contextFile = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_SurvivorContextMenu.lua", "r"
))
local contextText = contextFile:read("*a")
contextFile:close()
assert(string.find(contextText, 'local supply = ordersMenu:addOption("Survival Orders"', 1, true),
    "base residents need a visible supply-run menu")
print("base needs tests passed")
