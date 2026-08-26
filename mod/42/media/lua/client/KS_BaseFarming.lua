require "Farming/TimedActions/ISWaterPlantAction"
require "Farming/TimedActions/ISHarvestPlantAction"
require "TimedActions/ISTimedActionQueue"

local Farming = rawget(_G, "KnoxBaseFarming") or {}
_G.KnoxBaseFarming = Farming

local function farmingSystem()
    if CFarmingSystem ~= nil and CFarmingSystem.instance ~= nil then
        return CFarmingSystem.instance
    end
    if SFarmingSystem ~= nil and SFarmingSystem.instance ~= nil then
        return SFarmingSystem.instance
    end
    return nil
end

local function plantAt(square)
    local system = farmingSystem()
    if system == nil or square == nil then
        return nil
    end
    local success, plant = pcall(function()
        return system:getLuaObjectOnSquare(square)
    end)
    return success and plant or nil
end

local function safeCall(object, method, ...)
    if object == nil or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    return success and value or nil
end

local function walkItems(container, visitor)
    if container == nil or container.getItems == nil then
        return
    end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        visitor(item)
        if item ~= nil and item.IsInventoryContainer ~= nil
            and item:IsInventoryContainer() then
            walkItems(item:getInventory(), visitor)
        end
    end
end

local function wateringItem(character)
    if character == nil or ISFarmingMenu == nil
        or ISFarmingMenu.getWaterUsesInteger == nil then
        return nil, 0
    end
    local found, uses = nil, 0
    walkItems(character:getInventory(), function(item)
        if found ~= nil or item == nil then
            return
        end
        local success, count = pcall(function()
            return ISFarmingMenu.getWaterUsesInteger(item)
        end)
        if success and (tonumber(count) or 0) > 0 then
            found = item
            uses = tonumber(count) or 0
        end
    end)
    return found, uses
end

function Farming.findWaterItem(character, desiredFullType)
    local item, uses = wateringItem(character)
    if item == nil then
        return nil, 0
    end
    if desiredFullType ~= nil and item:getFullType() ~= desiredFullType then
        local found, foundUses = nil, 0
        walkItems(character:getInventory(), function(candidate)
            if found ~= nil or candidate == nil
                or candidate:getFullType() ~= desiredFullType
                or ISFarmingMenu == nil
                or ISFarmingMenu.getWaterUsesInteger == nil then
                return
            end
            local success, count = pcall(function()
                return ISFarmingMenu.getWaterUsesInteger(candidate)
            end)
            if success and (tonumber(count) or 0) > 0 then
                found = candidate
                foundUses = tonumber(count) or 0
            end
        end)
        return found, foundUses
    end
    return item, uses
end

local function canHarvest(plant)
    local result = safeCall(plant, "canHarvest")
    return result == true
end

local function isAlive(plant)
    local result = safeCall(plant, "isAlive")
    return result == nil or result == true
end

local function isSeeded(plant)
    return plant ~= nil and tostring(plant.state or "") == "seeded" and isAlive(plant)
end

local function descriptor(base, zone, square, plant, action, waterItem, waterUses)
    return {
        id = "farm:" .. tostring(base.id) .. ":" .. tostring(action) .. ":"
            .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
            .. tostring(square:getZ()),
        auto = true,
        zoneType = action,
        zoneId = zone.id,
        action = action,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        waterUses = tonumber(waterUses) or 0,
        waterItemType = waterItem ~= nil and waterItem:getFullType() or nil,
        plantType = tostring(plant.typeOfSeed or "unknown"),
    }
end

local function orderedZones(base)
    local zones = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == "farming" then
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(first, second)
        return tostring(first.id) < tostring(second.id)
    end)
    return zones
end

local function zoneBounds(zone)
    local minX = tonumber(zone.x1) or 0
    local minY = tonumber(zone.y1) or 0
    local maxX = tonumber(zone.x2) or minX
    local maxY = tonumber(zone.y2) or minY
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(zone.z) or 0
end

function Farming.findTask(base, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil then
        return nil, "base_or_cell_unavailable"
    end
    local water, waterUses = wateringItem(character)
    for _, zone in ipairs(orderedZones(base)) do
        local minX, minY, maxX, maxY, z = zoneBounds(zone)
        for x = minX, maxX do
            for y = minY, maxY do
                local square = cell:getGridSquare(x, y, z)
                local plant = square ~= nil and plantAt(square) or nil
                if plant ~= nil and canHarvest(plant) then
                    return descriptor(base, zone, square, plant, "farm_harvest"), "harvest"
                end
            end
        end
        if water ~= nil then
            for x = minX, maxX do
                for y = minY, maxY do
                    local square = cell:getGridSquare(x, y, z)
                    local plant = square ~= nil and plantAt(square) or nil
                    local waterLevel = plant ~= nil and tonumber(plant.waterLvl) or nil
                    if plant ~= nil and isSeeded(plant) and waterLevel ~= nil
                        and waterLevel < 100 then
                        local uses = math.min(
                            waterUses,
                            10,
                            math.max(1, math.ceil((100 - waterLevel) / 10))
                        )
                        return descriptor(
                            base,
                            zone,
                            square,
                            plant,
                            "farm_water",
                            water,
                            uses
                        ), "water"
                    end
                end
            end
        end
    end
    return nil, "no_farming_action_ready"
end

function Farming.resolveTarget(base, target)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then
        return nil, "missing_farming_target"
    end
    local square = cell:getGridSquare(
        tonumber(target.x) or 0,
        tonumber(target.y) or 0,
        tonumber(target.z) or 0
    )
    local plant = square ~= nil and plantAt(square) or nil
    if plant == nil then
        return nil, "plant_unloaded"
    end
    if target.action == "farm_harvest" and not canHarvest(plant) then
        return nil, "plant_not_harvestable"
    end
    if target.action == "farm_water"
        and (not isSeeded(plant) or (tonumber(plant.waterLvl) or 100) >= 100) then
        return nil, "plant_does_not_need_water"
    end
    return {
        action = target.action,
        square = square,
        plant = plant,
    }, "resolved"
end

function Farming.queueAction(character, target, water)
    if character == nil or target == nil then
        return nil, "missing_farming_target"
    end
    if target.action == "farm_harvest" then
        local action = ISHarvestPlantAction:new(character, target.plant, 100)
        ISTimedActionQueue.add(action)
        return action, "queued"
    end
    if target.action == "farm_water" then
        local item = water ~= nil and water.item or nil
        local uses = tonumber(water ~= nil and water.uses or target.waterUses) or 0
        if item == nil or uses <= 0 then
            return nil, "watering_item_unavailable"
        end
        local action = ISWaterPlantAction:new(
            character,
            item,
            uses,
            target.square,
            20 + (6 * uses)
        )
        ISTimedActionQueue.add(action)
        return action, "queued"
    end
    return nil, "unsupported_farming_action"
end

function Farming.snapshot(target)
    if target == nil or target.plant == nil then
        return { water = 0, harvestable = false }
    end
    return {
        water = tonumber(target.plant.waterLvl) or 0,
        harvestable = canHarvest(target.plant),
    }
end

function Farming.isComplete(target, before)
    if target == nil or target.plant == nil then
        return false
    end
    if target.action == "farm_harvest" then
        return not canHarvest(target.plant)
    end
    local after = tonumber(target.plant.waterLvl) or 0
    return after > (tonumber(before ~= nil and before.water or 0) or 0)
end

return Farming
