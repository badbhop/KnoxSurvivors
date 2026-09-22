local root = arg[1] or "."
require = function() return true end
local scenarios = dofile(root .. "/mod/42/media/lua/client/KS_JobTestScenarios.lua")

local fed = {}
KnoxActivityFeed = { event = function(message) fed[#fed + 1] = message end }
getSpecificPlayer = function() return { id = "player" } end
local square = {
    getX = function() return 100 end, getY = function() return 100 end, getZ = function() return 0 end,
}
local worldObjects = {
    { getSquare = function() return square end, getContainerCount = function() return 2 end },
}
local base = { id = "base-1", tasks = {} }
KnoxCompanionService = {
    getPlayerId = function() return "player-1" end,
    setBaseJobPreference = function() return true, "farming" end,
    setBaseSupplyOrder = function() return true, "ordered" end,
}
KnoxBaseManager = {
    getForOwner = function() return base end,
    setStoragePolicy = function(_, _, role) return { storageRole = role } end,
}
KnoxPersistence = {
    getBaseResidentIds = function() return { "resident-1" } end,
    addBaseZone = function(_, kind, bounds, label) return { type = kind, label = label }, "created" end,
}
KnoxBaseStorage = { policies = function() return {} end }
KnoxJobTestSupplies = { ensure = function() return 5, "test_stock_ready" end }
local claimed = {}
KnoxBaseTaskBoard = {
    claimSpecific = function(_, taskId)
        claimed[#claimed + 1] = taskId
        return { id = taskId }, "claimed"
    end,
}
local ordered = 0
KnoxBaseContextMenu = {
    orderBarricadeHere = function() ordered = ordered + 1 end,
}

-- Catalogue shape for the dev menu.
local list = scenarios.list()
assert(#list == 11, "one scenario per job plus scavenge, got " .. #list)
local keys = {}
for _, entry in ipairs(list) do keys[entry.key] = entry.label end
assert(keys.barricade_here ~= nil and keys.scavenge_run ~= nil)

-- Barricade delegates to the real order path.
local ok = scenarios.run(0, "barricade_here", worldObjects)
assert(ok and ordered == 1, "barricade test must use the real order flow")

-- Farm stages zone, preference, and assigns the queued task.
base.tasks = { t1 = { id = "t1", type = "farm_plow", state = "queued", priority = 80 } }
ok = scenarios.run(0, "farm_here", worldObjects)
assert(ok and claimed[1] == "t1", "farm test must assign the queued plot task")

-- Empty states still guide instead of erroring.
base.tasks = {}
ok = scenarios.run(0, "haul_here", worldObjects)
assert(ok, "haul test without bodies must still mark the area and assign the hauler")

ok = scenarios.run(0, "scavenge_run", worldObjects)
assert(ok, "scavenge test must order an explicit supply run")

ok = scenarios.run(0, "nope", worldObjects)
assert(not ok, "unknown scenario keys must fail closed")

-- Missing base and missing resident explain the next step.
KnoxBaseManager.getForOwner = function() return nil end
ok = scenarios.run(0, "farm_here", worldObjects)
assert(not ok, "farm test without a base must explain setup")
KnoxBaseManager.getForOwner = function() return base end
KnoxPersistence.getBaseResidentIds = function() return {} end
ok = scenarios.run(0, "farm_here", worldObjects)
assert(not ok, "farm test without a resident must explain setup")

-- Every staged run must say whether materials exist: an unstocked cupboard
-- is the usual reason a resident walks but never acts.
KnoxPersistence.getBaseResidentIds = function() return { "resident-1" } end
local _, message = scenarios.run(0, "farm_here", worldObjects)
assert(string.find(message, "Test stock landed", 1, true) ~= nil,
    "scenario must report landed stock, got: " .. tostring(message))
KnoxJobTestSupplies.ensure = function() return 0, "disabled" end
_, message = scenarios.run(0, "farm_here", worldObjects)
assert(string.find(message, "Ignore Job Resource Requirements", 1, true) ~= nil,
    "scenario must explain disabled stock, got: " .. tostring(message))

print("Job test scenarios PASS catalogue=true staging=true guidance=true stock-honest=true")
