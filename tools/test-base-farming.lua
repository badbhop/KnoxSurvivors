local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["Farming/TimedActions/ISWaterPlantAction"] = true
package.loaded["Farming/TimedActions/ISHarvestPlantAction"] = true
package.loaded["Farming/TimedActions/ISPlowAction"] = true
package.loaded["Farming/TimedActions/ISSeedActionNew"] = true
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
ISPlowAction = {
    new = function(_, character, square, item)
        return { kind = "plow", character = character, square = square, item = item }
    end,
}
ISSeedActionNew = {
    new = function(_, character, seed, typeOfSeed, plant)
        return { kind = "seed", character = character, seed = seed,
            typeOfSeed = typeOfSeed, plant = plant }
    end,
}
ISTimedActionQueue = {
    add = function(action) _G.queuedAction = action end,
}

ISFarmingMenu = {
    getWaterUsesInteger = function(item)
        return item.uses or 0
    end,
    canDigHereSquare = function(square)
        return square.diggable == true
    end,
}
ItemTag = { DIG_PLOW = "DIG_PLOW", IS_SEED = "IS_SEED" }
farming_vegetableconf = {
    props = {
        Tomato = { seedTypes = { "Base.TomatoSeed" } },
    },
}

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function item(full, uses, tags)
    local result = { full = full, uses = uses or 0, tags = tags or {} }
    function result:getFullType() return self.full end
    function result:IsInventoryContainer() return false end
    function result:hasTag(tag) return self.tags[tag] == true end
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
local function square(x, y, z, value, diggable)
    local result = { x = x, y = y, z = z, plant = value, diggable = diggable }
    function result:getX() return self.x end
    function result:getY() return self.y end
    function result:getZ() return self.z end
    return result
end
squares["10:20:0"] = square(10, 20, 0, ripe)
squares["11:20:0"] = square(11, 20, 0, dry)
squares["12:20:0"] = square(12, 20, 0, nil, true)

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
local inventoryItems = { waterBottle }
local inventory = {}
function inventory:getItems() return list(inventoryItems) end
local character = {}
function character:getInventory() return inventory end

local base = {
    id = "base-farming",
    zones = {
        garden = {
            id = "garden",
            type = "farming",
            x1 = 10, y1 = 20, x2 = 12, y2 = 20, z = 0,
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

local shovel = item("Base.GardenShovel", 0, { [ItemTag.DIG_PLOW] = true })
local seed = item("Base.TomatoSeed", 0, { [ItemTag.IS_SEED] = true })
table.insert(inventoryItems, shovel)
table.insert(inventoryItems, seed)
local plowTarget, plowResult = farming.findTask(base, character)
assert(plowTarget ~= nil and plowResult == "plow")
local plowResolved = assert(farming.resolveTarget(base, plowTarget, character))
local plowAction = assert(farming.queueAction(character, plowResolved))
assert(plowAction.kind == "plow" and queuedAction == plowAction)
squares["12:20:0"].plant = plant("none", false, 0)
squares["12:20:0"].plant.state = "plow"
plowResolved.plant = squares["12:20:0"].plant
assert(farming.isComplete(plowResolved, farming.snapshot(plowResolved)))

local seedTarget, seedResult = farming.findTask(base, character)
assert(seedTarget ~= nil and seedResult == "seed")
local seedResolved = assert(farming.resolveTarget(base, seedTarget, character))
local seedAction = assert(farming.queueAction(character, seedResolved))
assert(seedAction.kind == "seed" and queuedAction == seedAction)
seedResolved.plant.state = "seeded"
assert(farming.isComplete(seedResolved, farming.snapshot(seedResolved)))

print("Base farming PASS harvest_discovery=true watering_discovery=true plow_seed=true vanilla_actions=true completion=true")

-- Empty-handed workers discover real cupboard supplies, but cannot execute
-- planting until the native supply transfer has delivered the seed.
inventoryItems = {}
local cupboardItems = { seed, shovel, waterBottle }
KnoxBaseStorage = { findItemType = function(owner, predicate)
    assert(owner == base)
    for _, value in ipairs(cupboardItems) do
        if predicate(value) then return value:getFullType(), value end
    end
end }
dry.waterLvl = 40
local storedTask = assert(farming.findTask(base, character))
assert(storedTask.action == "farm_water", "cupboard water enables watering discovery")
dry.waterLvl = 100
squares["12:20:0"].plant = nil
storedTask = assert(farming.findTask(base, character))
assert(storedTask.action == "farm_plow" and storedTask.plowToolType == "Base.GardenShovel",
    "cupboard seed and shovel enable plowing discovery")
squares["12:20:0"].plant = plant("none", false, 0)
squares["12:20:0"].plant.state = "plow"
storedTask = assert(farming.findTask(base, character))
assert(storedTask.action == "farm_seed" and storedTask.seedItemType == "Base.TomatoSeed",
    "cupboard seed enables planting discovery")
local unready = farming.resolveTarget(base, storedTask, character)
assert(unready == nil or unready.seedItem == nil, "discovery cannot manufacture carried seed")
cupboardItems = {}
assert(farming.findTask(base, character) == nil, "empty cupboard cannot promise planting supplies")
print("Cupboard farming discovery PASS")
