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
assert(storage.matchesCategory(depotItem, "building"), "planks should route to building storage")
local transfer, transferResult = storage.findTransfer(base)
assert(transfer ~= nil and transferResult == "found")
assert(transfer.item == depotItem and transfer.destinationPolicy.key == "building")
local target = assert(storage.transferTarget(transfer))
assert(target.sourceKey == "depot" and target.destinationKey == "building")
local resolved, resolvedResult = storage.resolveTransfer(base, target)
assert(resolved ~= nil and resolvedResult == "resolved")
assert(resolved.item == depotItem and resolved.source.container == depot)
destination.full = true
assert(storage.findTransfer(base) == nil, "full destination is rejected before queuing transfer")
destination.full = false

local summary = storage.summarize(base)
assert(summary.loadedPolicies == 2 and summary.unavailablePolicies == 0,
    "summary should only count resolved assigned containers")
assert(summary.totals.building == 1 and summary.totals.food == 1,
    "depot contents should be classified into real resource categories")

destination.values[#destination.values + 1] = misplacedItem
summary = storage.summarize(base)
assert(summary.misplacedItems == 1 and summary.totals.tools == 0,
    "misplaced assigned-container items must not inflate available resource totals")

local worker = {
    getInventory = function()
        return { getItemCount = function() return 0 end }
    end,
}
local origin = square(11, 20, 0, {})
function origin:isSomethingTo() return self.blocked == true end
function worker:getCurrentSquare() return origin end
local nearby = assert(storage.findNearbyDeposit(base, worker, depotItem))
assert(nearby.policy.key == "building", "matching assigned storage beats a generic depot")
origin.blocked = true
assert(not storage.findNearbyDeposit(base, worker, depotItem), "cleanup cannot deposit through a wall")
origin.blocked = false
assert(not storage.findNearbyDeposit(nil, worker, depotItem), "no base means no arbitrary nearby storage")
destination.full = true
nearby = assert(storage.findNearbyDeposit(base, worker, depotItem))
assert(nearby.policy.key == "depot", "full categorized storage falls back to assigned depot")
destination.full = false
local tripApproach = square(11, 20, 0, {})
function tripApproach:isSomethingTo() return self.blocked == true end
AdjacentFreeTileFinder = { Find = function() return tripApproach end }
origin.x = 50
assert(not storage.findNearbyDeposit(base, worker, depotItem), "distant containers cannot transfer immediately")
local trip = assert(storage.findDepositTrip(base, worker, depotItem, {}, 100))
assert(trip.policy.key == "building" and trip.approach == tripApproach, "trip uses native interaction-side target")
trip = assert(storage.findDepositTrip(base, worker, depotItem, { building = 200 }, 100))
assert(trip.policy.key == "depot", "failed storage cools down while alternatives remain available")
assert(storage.findDepositTrip(base, worker, depotItem, { building = 200 }, 201).policy.key == "building",
    "failure memory expires")
assert(not storage.findDepositTrip(base, worker, depotItem, { building = 200, depot = 200 }, 100))
tripApproach.blocked = true
assert(not storage.findDepositTrip(base, worker, depotItem), "blocked interaction side is not a trip target")
tripApproach.blocked = false
origin.x = 200
assert(not storage.findDepositTrip(base, worker, depotItem), "low-value storage trip has bounded distance")
origin.x, origin.z = 50, 1
assert(not storage.findDepositTrip(base, worker, depotItem), "this local deposit selector does not invent another-floor access")
origin.x, origin.z = 11, 0
assert(storage.findNearbyDeposit(base, worker, depotItem, "depot").policy.key == "depot",
    "arrival revalidates the selected policy instead of silently substituting another container")
assert(not storage.findNearbyDeposit(base, worker, depotItem, "removed-policy"))
local requiredTransfer, requiredResult = storage.findRequiredTransfer(
    base, worker, { items = { ["Base.Plank"] = 1 } }
)
assert(requiredTransfer ~= nil and requiredResult == "found"
    and requiredTransfer.sourcePolicy.key == "depot",
    "a base task should retrieve exact required items only from assigned storage")
assert(storage.requirementsAvailable(base, worker, { items = { ["Base.Plank"] = 1 } }),
    "assigned base supplies should make a task eligible before pickup")
local available, reason = storage.requirementsAvailable(
    base, worker, { items = { ["Base.Nails"] = 1 } }
)
assert(not available and reason == "missing_assigned_item=Base.Nails",
    "missing storage supplies must not be treated as an abstract stockpile")

local controllerSource = assert(io.open(rootPath
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r")):read("*a")
assert(controllerSource:find("Base job blocked:", 1, true),
    "blocked base supply requirements must give the player a visible reason")

print("Base storage PASS policy_resolution=true category_routing=true transfer_target=true resource_summary=true task_supply=true feedback=true")
