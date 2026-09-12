local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["KS_Persistence"] = true
package.loaded["KS_SurvivorNeeds"] = true
package.loaded["KS_SurvivorInventoryActions"] = true
package.loaded["Util/AdjacentFreeTileFinder"] = true
KnoxSurvivorNeeds = {
    isSafeFood = function(item) return item:getFullType() == "Base.TinnedSoup" end,
    isWaterItem = function(item) return item:getFullType() == "Base.WaterBottleFull" end,
}
KnoxInventoryActions = {
    queueTransfer = function() return {}, "queued" end,
}

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function item(full)
    return {
        getFullType = function() return full end,
        IsWeapon = function() return false end,
        IsClothing = function() return false end,
        IsInventoryContainer = function() return false end,
        isCanBandage = function() return false end,
    }
end

local function container(kind, values)
    local result = { values = values or {} }
    function result:getItems() return list(self.values) end
    function result:isExistYet() return true end
    function result:getType() return kind end
    function result:getParent() return nil end
    function result:hasRoomFor(character, candidate)
        assert(candidate ~= nil, "native capacity check requires character plus item")
        return not self.full
    end
    function result:isItemAllowed() return true end
    function result:contains(target)
        for _, value in ipairs(self.values) do
            if value == target then return true end
        end
        return false
    end
    return result
end

local function square(x, y, z, object)
    local result = { x = x, y = y, z = z, object = object }
    function result:getX() return self.x end
    function result:getY() return self.y end
    function result:getZ() return self.z end
    function result:getObjects() return list({ self.object }) end
    return result
end

local depotItem = item("Base.Plank")
local foodItem = item("Base.TinnedSoup")
local misplacedItem = item("Base.HandAxe")
local depot = container("crate", { depotItem, foodItem })
local destination = container("crate", {})
local depotObject = {}
function depotObject:getObjectIndex() return 1 end
function depotObject:getContainerByIndex(index) return index == 0 and depot or nil end
function depotObject:getContainerCount() return 1 end
local destinationObject = {}
function destinationObject:getObjectIndex() return 2 end
function destinationObject:getContainerByIndex(index) return index == 0 and destination or nil end
function destinationObject:getContainerCount() return 1 end
local squares = {
    ["10:20:0"] = square(10, 20, 0, depotObject),
    ["12:20:0"] = square(12, 20, 0, destinationObject),
}
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            return squares[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)]
        end,
    }
end

local base = {
    id = "base-storage",
    storage = {
        depot = {
            key = "depot",
            x = 10, y = 20, z = 0, objectIndex = 1, containerIndex = 0,
            containerType = "crate", category = "depot", depot = true,
        },
        building = {
            key = "building",
            x = 12, y = 20, z = 0, objectIndex = 2, containerIndex = 0,
            containerType = "crate", category = "building", depot = false,
        },
    },
}

local storage = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseStorage.lua")
local policies = storage.policies(base)
assert(#policies == 1 and policies[1].key == "depot" and base.toolCupboardKey == "depot")
assert(base.storage.building == nil and #depot.values == 2 and #destination.values == 0,
    "legacy migration retires assignments without moving or deleting real items")
assert(storage.findTransfer(base) == nil, "central storage has no sorting job")
local summary = storage.summarize(base)
assert(summary.loadedPolicies == 1 and summary.totals.building == 1 and summary.totals.food == 1)
local origin = square(11, 20, 0, {})
function origin:isSomethingTo() return self.blocked == true end
local worker = { getCurrentSquare = function() return origin end,
    getInventory = function() return container("inventory", {}) end }
local nearby = assert(storage.findNearbyDeposit(base, worker, depotItem))
assert(nearby.policy.key == "depot")
origin.blocked = true
assert(not storage.findNearbyDeposit(base, worker, depotItem), "no transfer through walls")
origin.blocked = false
depot.full = true
assert(not storage.findNearbyDeposit(base, worker, depotItem), "full cupboard cannot fall back to former storage")
depot.full = false
local approach = square(11, 20, 0, {})
function approach:isSomethingTo() return self.blocked == true end
AdjacentFreeTileFinder = { Find = function() return approach end }
origin.x = 50
assert(not storage.findNearbyDeposit(base, worker, depotItem))
assert(storage.findDepositTrip(base, worker, depotItem, {}, 100).policy.key == "depot")
assert(not storage.findDepositTrip(base, worker, depotItem, { depot = 200 }, 100))
assert(storage.findDepositTrip(base, worker, depotItem, { depot = 200 }, 201))
approach.blocked = true
assert(not storage.findDepositTrip(base, worker, depotItem))
approach.blocked = false
origin.x = 200
assert(not storage.findDepositTrip(base, worker, depotItem))
origin.x, origin.z = 50, 1
assert(storage.findDepositTrip(base, worker, depotItem), "native deposit routes can reach another loaded floor")
assert(not storage.findNearbyDeposit(base, worker, depotItem), "cross-floor transfers require walking first")
origin.z = 3
assert(not storage.findDepositTrip(base, worker, depotItem), "cross-floor search remains bounded")
origin.x, origin.z = 11, 0
assert(not storage.findNearbyDeposit(base, worker, depotItem, "building"), "retired policy cannot be selected")
local required = assert(storage.findRequiredTransfer(base, worker, { items = { ["Base.Plank"] = 1 } }))
assert(required.sourcePolicy.key == "depot")
assert(storage.requirementsAvailable(base, worker, { items = { ["Base.Plank"] = 1 } }))
assert(not storage.requirementsAvailable(base, worker, { items = { ["Base.Nails"] = 1 } }))
local stableKey = "base:container:10:20:0:1:0"
local stablePolicy = { key = stableKey, x = 10, y = 20, z = 0, objectIndex = 99,
    containerIndex = 0, containerType = "crate" }
depotObject.getModData = function() return { KnoxSurvivors = { storageIds = { original = stableKey } } } end
assert(storage.resolvePolicy(stablePolicy).container == depot,
    "stable identity survives tile object reordering")
depotObject.getModData = function() return {} end
stablePolicy.objectIndex = 1
assert(storage.resolvePolicy(stablePolicy) == nil, "replacement object cannot inherit assignment")
base.toolCupboardKey = "missing"
assert(#storage.policies(base) == 0, "missing cupboard never silently selects another container")
local coldOnly = { storage = { fridge = { key = "fridge", containerType = "fridge" } } }
assert(#storage.policies(coldOnly) == 0, "legacy fridge is not silently enlarged into a dry cupboard")
assert(coldOnly.storage.fridge ~= nil, "migration preserves old physical-container references when no dry storage exists")
print("Central storage PASS migration=true single=true capacity=true route=true reserves=true identity=true")

-- Readiness, cupboard withdrawal and local supply searches must agree on usable stock.
base.toolCupboardKey = "depot"
local brokenAxe, goodAxe = item("Base.HandAxe"), item("Base.HandAxe")
brokenAxe.isBroken = function() return true end
goodAxe.isBroken = function() return false end
local emptyWater, fullWater = item("Base.WaterBottle"), item("Base.WaterBottle")
emptyWater.uses, fullWater.uses = 0, 4
ISFarmingMenu = { getWaterUsesInteger = function(candidate) return candidate.uses or 0 end }
local carried = container("inventory", {brokenAxe, emptyWater})
carried.getItemCount = function(_, fullType)
    return (fullType == "Base.HandAxe" or fullType == "Base.WaterBottle") and 1 or 0
end
worker.getInventory = function() return carried end
local axeRequirement = { items = { ["Base.HandAxe"] = 1 },
    itemRules = { ["Base.HandAxe"] = { usable = true } } }
local waterRequirement = { items = { ["Base.WaterBottle"] = 1 },
    itemRules = { ["Base.WaterBottle"] = { water = true } } }
depot.values = {brokenAxe, emptyWater}
assert(not storage.requirementsAvailable(base, worker, axeRequirement),
    "broken carried and stored tools cannot make a job ready")
assert(not storage.requirementsAvailable(base, worker, waterRequirement),
    "empty bottles cannot make watering ready")
depot.values = {brokenAxe, emptyWater, goodAxe, fullWater}
assert(storage.requirementsAvailable(base, worker, axeRequirement))
assert(storage.findRequiredTransfer(base, worker, axeRequirement).item == goodAxe,
    "worker replaces a broken tool with the usable stored instance")
assert(storage.findRequiredTransfer(base, worker, waterRequirement).item == fullWater,
    "worker skips empty bottles when gathering crop water")
local planner = KnoxBaseSupplyPlanner
assert(not planner.matchesMissingRequirement(brokenAxe, axeRequirement, carried)
    and planner.matchesMissingRequirement(goodAxe, axeRequirement, carried),
    "world resupply uses the same usable-tool requirement")
assert(not planner.matchesMissingRequirement(emptyWater, waterRequirement, carried)
    and planner.matchesMissingRequirement(fullWater, waterRequirement, carried),
    "world resupply uses the same nonempty-water requirement")
local bag = item("Base.Bag")
bag.IsInventoryContainer = function() return true end
bag.getInventory = function() return container("bag", {goodAxe, fullWater}) end
carried.values = {brokenAxe, emptyWater, bag}
local transfer, status = storage.findRequiredTransfer(base, worker, axeRequirement)
assert(transfer == nil and status == "requirements_ready", "usable nested tools prevent duplicate withdrawals")
transfer, status = storage.findRequiredTransfer(base, worker, waterRequirement)
assert(transfer == nil and status == "requirements_ready", "usable nested water prevents duplicate withdrawals")
print("Job supply usability PASS broken_tools=true empty_water=true nested=true world_search=true")

-- Kitchen assignments preserve raw ingredients and prefer food deposits, without
-- making unsafe food edible or changing native refrigerator capacity.
local rawFood = item("Base.RawChicken")
rawFood.IsFood = function() return true end
foodItem.IsFood = function() return true end
local waterItem = item("Base.WaterBottleFull")
local pantry = {key="pantry", x=12,y=20,z=0,objectIndex=2,containerIndex=0,
    containerType="crate",category="food",storageRole="food"}
base.storage.pantry = pantry
origin.x,origin.y,origin.z=11,20,0
carried.values = {}
depot.values, destination.values = {}, {foodItem,rawFood,waterItem,goodAxe}
assert(#storage.policies(base)==2 and base.storage.pantry==pantry)
assert(storage.findNearbyDeposit(base,worker,rawFood).policy.key=="pantry", "raw food belongs in kitchen storage")
assert(storage.findNearbyDeposit(base,worker,foodItem).policy.key=="pantry")
assert(storage.findNearbyDeposit(base,worker,waterItem).policy.key=="pantry")
assert(storage.findNearbyDeposit(base,worker,depotItem).policy.key=="depot", "building supplies stay out of food storage")
destination.full=true
assert(storage.findNearbyDeposit(base,worker,foodItem).policy.key=="depot", "full kitchen falls back to main supplies")
destination.full=false
summary=storage.summarize(base)
assert(summary.loadedPolicies==2 and summary.totals.food==1 and summary.totals.water==1
    and summary.totals.other==1 and summary.misplacedItems==1, "raw food is stored but not counted as ready-to-eat meals")
assert(storage.requirementsAvailable(base,worker,axeRequirement)
    and storage.findRequiredTransfer(base,worker,axeRequirement).item==goodAxe,
    "actual supplies can be recovered even if the player puts a tool in food storage")
local foodOnly={storage={pantry=pantry}}
assert(#storage.policies(foodOnly)==1 and storage.mainPolicy(foodOnly)==nil and not pantry.toolCupboard,
    "food-only bases never silently enlarge a pantry")
local capacityChanges=0
local originalApply=KnoxToolCupboard.apply
KnoxToolCupboard.apply=function() capacityChanges=capacityChanges+1;return true end
storage.resolvePolicy(pantry)
assert(capacityChanges==0, "food storage never reapplies an old cupboard capacity marker")
KnoxToolCupboard.apply=originalApply
print("Kitchen storage PASS persistence=true food=true raw_ingredients=true fallback=true capacity=true withdrawal=true")
