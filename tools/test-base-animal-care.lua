local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["TimedActions/ISAddFluidFromItemAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
package.loaded["Util/AdjacentFreeTileFinder"] = true
package.loaded["KS_SurvivorInventoryActions"] = true

local queued = {}
ISTimedActionQueue = {
    add = function(action) queued[#queued + 1] = action end,
}
ISAddFluidFromItemAction = {
    new = function(_, character, item, trough)
        return { kind = "water", character = character, item = item, trough = trough }
    end,
}
KnoxInventoryActions = {
    queueTransfer = function(character, item, source, destination)
        local action = { kind = "feed", character = character, item = item,
            source = source, destination = destination }
        queued[#queued + 1] = action
        return action, "queued"
    end,
}
AdjacentFreeTileFinder = {
    Find = function(square) return square.approach end,
}
instanceof = function(object, className)
    return object ~= nil and object.className == className
end

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local mainInventory = { values = {} }
function mainInventory:getItems() return list(self.values) end

local function fluid(amount)
    local value = { amount = amount }
    function value:getAmount() return self.amount end
    return value
end

local function item(fullType, id, kind)
    local value = {
        fullType = fullType,
        id = id,
        kind = kind,
        source = mainInventory,
        fluid = kind == "water" and fluid(8) or nil,
    }
    function value:getFullType() return self.fullType end
    function value:getID() return self.id end
    function value:getContainer() return self.source end
    function value:getFluidContainer() return self.fluid end
    function value:canStoreWater() return self.kind == "water" end
    function value:isWaterSource() return self.kind == "water" end
    function value:isAnimalFeed() return self.kind == "feed" end
    function value:getCurrentUses() return self.kind == "feed" and 10 or 0 end
    function value:IsInventoryContainer() return false end
    return value
end

local water = item("Base.WaterBottleFull", 101, "water")
local feed = item("Base.AnimalFeedBag", 102, "feed")
mainInventory.values = { water, feed }

local approach = { x = 19, y = 20, z = 0 }
function approach:getX() return self.x end
function approach:getY() return self.y end
function approach:getZ() return self.z end

local troughSquare = { x = 20, y = 20, z = 0, approach = approach }
function troughSquare:getX() return self.x end
function troughSquare:getY() return self.y end
function troughSquare:getZ() return self.z end

local feedContainer = {}
local trough = {
    className = "IsoFeedingTrough",
    square = troughSquare,
    water = 0,
    maxWater = 20,
    feed = 0,
    maxFeed = 20,
    container = feedContainer,
    objectIndex = 3,
}
function trough:getMasterTrough() return self end
function trough:getSquare() return self.square end
function trough:getX() return self.square.x end
function trough:getY() return self.square.y end
function trough:getZ() return self.square.z end
function trough:getObjectIndex() return self.objectIndex end
function trough:getWater() return self.water end
function trough:getMaxWater() return self.maxWater end
function trough:getCurrentFeedAmount() return self.feed end
function trough:getMaxFeed() return self.maxFeed end
function trough:getContainer() return self.container end
function trough:canTransferFluidFrom(source)
    return source ~= nil and self.water < self.maxWater
end

local squareObjects = list({ trough })
function troughSquare:getObjects() return squareObjects end
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            if x == 20 and y == 20 and z == 0 then return troughSquare end
            return nil
        end,
    }
end

local character = { turning = false }
function character:getInventory() return mainInventory end
function character:faceThisObject(object) self.faced = object end
function character:shouldBeTurning() return self.turning end

local base = {
    id = "base-animal",
    zones = {
        pasture = {
            id = "pasture",
            type = "animal_care",
            x1 = 20, y1 = 20, x2 = 20, y2 = 20, z = 0,
            enabled = true,
        },
    },
}

local animalCare = dofile(
    rootPath .. "/mod/42/media/lua/client/KS_BaseAnimalCare.lua"
)

local waterTarget, waterResult = animalCare.findTask(base, character)
assert(waterTarget ~= nil and waterResult == "water")
assert(waterTarget.action == "animal_water")
assert(waterTarget.itemType == "Base.WaterBottleFull"
    and waterTarget.itemId == "101")
local waterResolved = assert(animalCare.resolveTarget(base, waterTarget, character))
assert(waterResolved.approach == approach and waterResolved.trough == trough)
local waterBefore = animalCare.snapshot(waterResolved)
local waterAction = assert(animalCare.queueAction(character, waterResolved))
assert(waterAction.kind == "water" and queued[#queued] == waterAction)
trough.water = 8
assert(animalCare.isComplete(waterResolved, waterBefore))

mainInventory.values = { feed }
local feedTarget, feedResult = animalCare.findTask(base, character)
assert(feedTarget ~= nil and feedResult == "feed")
assert(feedTarget.action == "animal_feed"
    and feedTarget.itemType == "Base.AnimalFeedBag")
local feedResolved = assert(animalCare.resolveTarget(base, feedTarget, character))
local feedBefore = animalCare.snapshot(feedResolved)
local feedAction = assert(animalCare.queueAction(character, feedResolved))
assert(feedAction.kind == "feed" and feedAction.destination == feedContainer)
trough.feed = 10
assert(animalCare.isComplete(feedResolved, feedBefore))

trough.water = 20
trough.feed = 20
local none, noneResult = animalCare.findTask(base, character)
assert(none == nil and noneResult == "no_animal_care_ready")

print("Base animal care PASS trough_scan=true water_action=true feed_transfer=true completion=true thresholds=true")
