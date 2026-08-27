local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["KS_Persistence"] = true
package.loaded["KS_SurvivorNeeds"] = true
package.loaded["KS_SurvivorInventoryActions"] = true
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

local summary = storage.summarize(base)
assert(summary.loadedPolicies == 2 and summary.unavailablePolicies == 0,
    "summary should only count resolved assigned containers")
assert(summary.totals.building == 1 and summary.totals.food == 1,
    "depot contents should be classified into real resource categories")

destination.values[#destination.values + 1] = misplacedItem
summary = storage.summarize(base)
assert(summary.misplacedItems == 1 and summary.totals.tools == 0,
    "misplaced assigned-container items must not inflate available resource totals")

print("Base storage PASS policy_resolution=true category_routing=true transfer_target=true resource_summary=true")
