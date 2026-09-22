local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["KS_Persistence"] = true
package.loaded["KS_Settings"] = true
package.loaded["KS_SurvivorNeeds"] = true
package.loaded["KS_SurvivorInventoryActions"] = true
package.loaded["Util/AdjacentFreeTileFinder"] = true
KnoxSurvivorNeeds = {
    isSafeFood = function(item) return item:getFullType() == "Base.TinnedSoup" end,
    isWaterItem = function(item) return item:getFullType() == "Base.WaterBottleFull" end,
}
KnoxInventoryActions = { queueTransfer = function() return {}, "queued" end }
KnoxSettings = { ignoreJobResourceRequirements = function() return true end }

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function item(full, extra)
    local value = { full = full }
    function value:getFullType() return self.full end
    function value:IsWeapon() return false end
    function value:IsClothing() return false end
    function value:IsInventoryContainer() return false end
    function value:isCanBandage() return false end
    function value:isBroken() return false end
    if extra ~= nil then for k, v in pairs(extra) do value[k] = v end end
    return value
end

local function container(kind, values)
    local result = { values = values or {} }
    function result:getItems() return list(self.values) end
    function result:isExistYet() return true end
    function result:getType() return kind end
    function result:getParent() return nil end
    function result:hasRoomFor() return not self.full end
    function result:isItemAllowed() return true end
    return result
end

-- Assigned storage holds the hammer; the worker's pockets are empty.
local stored = { item("Base.Hammer"), item("Base.Plank"), item("Base.Nails"), item("Base.Nails") }
local depot = container("crate", stored)
local depotObject = {}
function depotObject:getObjectIndex() return 1 end
function depotObject:getContainerByIndex(index) return index == 0 and depot or nil end
function depotObject:getContainerCount() return 1 end
function depotObject:getModData() return {} end
local function square(x, y, z, object)
    local result = { x = x, y = y, z = z, object = object }
    function result:getX() return self.x end
    function result:getY() return self.y end
    function result:getZ() return self.z end
    function result:getObjects() return list({ self.object }) end
    function result:canStand() return true end
    function result:isSomethingTo() return false end
    return result
end
local squares = { ["10:20:0"] = square(10, 20, 0, depotObject) }
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        return squares[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)]
    end }
end
AdjacentFreeTileFinder = { Find = function(sq) return sq end }

local carried = {}
local workerInventory = container("inventory", carried)
function workerInventory:getItemCount(full)
    local count = 0
    for _, value in ipairs(carried) do
        if value:getFullType() == full then count = count + 1 end
    end
    return count
end
local origin = square(11, 20, 0, {})
local worker = { getCurrentSquare = function() return origin end,
    getInventory = function() return workerInventory end }

local base = { id = "base-fetch", storage = {
    tools = { key = "tools", x = 10, y = 20, z = 0, objectIndex = 1,
        containerIndex = 0, containerType = "crate", category = "tools",
        storageRole = "tools", toolCupboard = false },
} }

local storage = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseStorage.lua")

-- Ignore mode gates open, but the fetch path must still find real stored items.
local gated = storage.findRequiredTransfer(base, worker,
    { items = { ["Base.Hammer"] = 1 } })
assert(gated == nil, "ignore mode bypasses requirement gating")
local fetch = assert(storage.findFetchTransfer(base, worker,
    { items = { ["Base.Hammer"] = 1 } }), "fetch must find the stored hammer")
assert(fetch.item:getFullType() == "Base.Hammer")

-- Nothing stored anywhere: fetch reports ready so the worker walks over and
-- the native action fails closed instead of looping supply trips.
stored = {}
depot.values = stored
local empty = storage.findFetchTransfer(base, worker, { items = { ["Base.Hammer"] = 1 } })
assert(empty == nil, "empty storage has nothing to fetch")

print("Ignore-mode supply fetch PASS gate_bypassed=true real_fetch=true empty_ready=true")
