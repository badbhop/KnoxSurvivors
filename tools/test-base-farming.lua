local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["Farming/TimedActions/ISWaterPlantAction"] = true
package.loaded["Farming/TimedActions/ISHarvestPlantAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true

ISWaterPlantAction = {
    new = function(_, character, item, uses, square, maxTime)
        return { kind = "water", character = character, item = item,
            uses = uses, square = square, maxTime = maxTime }
    end,
}
ISHarvestPlantAction = {
    new = function(_, character, plant, maxTime)
        return { kind = "harvest", character = character, plant = plant,
            maxTime = maxTime }
    end,
}
ISTimedActionQueue = {
    add = function(action) _G.queuedAction = action end,
}

ISFarmingMenu = {
    getWaterUsesInteger = function(item)
        return item.uses or 0
    end,
}

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function item(full, uses)
    local result = { full = full, uses = uses or 0 }
    function result:getFullType() return self.full end
    function result:IsInventoryContainer() return false end
    return result
end

local function plant(seed, harvestable, water)
    local result = {
        typeOfSeed = seed,
        state = "seeded",
        waterLvl = water,
        harvestable = harvestable,
    }
    function result:canHarvest() return self.harvestable end
    function result:isAlive() return true end
    return result
end

local ripe = plant("Base.Tomato", true, 100)
local dry = plant("Base.Cabbage", false, 40)
local squares = {}
local function square(x, y, z, value)
    local result = { x = x, y = y, z = z, plant = value }
    function result:getX() return self.x end
    function result:getY() return self.y end
    function result:getZ() return self.z end
    return result
end
squares["10:20:0"] = square(10, 20, 0, ripe)
squares["11:20:0"] = square(11, 20, 0, dry)

CFarmingSystem = {
    instance = {
        getLuaObjectOnSquare = function(_, value) return value.plant end,
    },
}
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            return squares[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)]
        end,
    }
end

local waterBottle = item("Base.WaterBottleFull", 8)
local inventory = {}
function inventory:getItems() return list({ waterBottle }) end
local character = {}
function character:getInventory() return inventory end

local base = {
    id = "base-farming",
    zones = {
        garden = {
            id = "garden",
            type = "farming",
            x1 = 10, y1 = 20, x2 = 11, y2 = 20, z = 0,
            enabled = true,
        },
    },
}

local farming = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseFarming.lua")
local harvestTarget, harvestResult = farming.findTask(base, character)
assert(harvestTarget ~= nil and harvestResult == "harvest")
assert(harvestTarget.action == "farm_harvest")
local harvestResolved = assert(farming.resolveTarget(base, harvestTarget))
assert(harvestResolved.action == "farm_harvest")
local harvestAction = assert(farming.queueAction(character, harvestResolved))
assert(harvestAction.kind == "harvest" and queuedAction == harvestAction)
local harvestBefore = farming.snapshot(harvestResolved)
ripe.harvestable = false
assert(farming.isComplete(harvestResolved, harvestBefore))

local waterTarget, waterResult = farming.findTask(base, character)
assert(waterTarget ~= nil and waterResult == "water")
assert(waterTarget.action == "farm_water" and waterTarget.waterUses == 6)
local waterResolved = assert(farming.resolveTarget(base, waterTarget))
local waterAction = assert(farming.queueAction(character, waterResolved, {
    item = waterBottle,
    uses = waterTarget.waterUses,
}))
assert(waterAction.kind == "water" and waterAction.uses == 6)
local waterBefore = farming.snapshot(waterResolved)
dry.waterLvl = 100
assert(farming.isComplete(waterResolved, waterBefore))

print("Base farming PASS harvest_discovery=true watering_discovery=true vanilla_actions=true completion=true")
