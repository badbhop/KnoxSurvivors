require "TimedActions/ISAddFluidFromItemAction"
require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"
require "KS_SurvivorInventoryActions"

local AnimalCare = rawget(_G, "KnoxBaseAnimalCare") or {}
_G.KnoxBaseAnimalCare = AnimalCare

local REFILL_FRACTION = 0.50

local function safeCall(object, method, ...)
    if object == nil or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    return success and value or nil
end

local function isTrough(object)
    if object == nil or instanceof == nil then
        return false
    end
    local success, result = pcall(function()
        return instanceof(object, "IsoFeedingTrough")
    end)
    return success and result == true
end

local function masterTrough(object)
    if not isTrough(object) then
        return nil
    end
    return safeCall(object, "getMasterTrough") or object
end

local function zoneBounds(zone)
    local minX = tonumber(zone.x1) or 0
    local minY = tonumber(zone.y1) or 0
    local maxX = tonumber(zone.x2) or minX
    local maxY = tonumber(zone.y2) or minY
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(zone.z) or 0
end

local function orderedZones(base)
    local zones = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == "animal_care" then
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(first, second)
        return tostring(first.id) < tostring(second.id)
    end)
    return zones
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

local function itemId(item)
    local value = safeCall(item, "getID")
    return value ~= nil and tostring(value) or nil
end

local function itemFullType(item)
    return tostring(safeCall(item, "getFullType") or "")
end

local function isAnimalFeed(item)
    return safeCall(item, "isAnimalFeed") == true
        and safeCall(item, "getCurrentUses") ~= nil
        and (tonumber(safeCall(item, "getCurrentUses")) or 0) > 0
end

local function isWaterSource(item)
    local fluid = safeCall(item, "getFluidContainer")
    return fluid ~= nil
        and safeCall(item, "canStoreWater") == true
        and safeCall(item, "isWaterSource") == true
        and (tonumber(safeCall(fluid, "getAmount")) or 0) > 0
end

local function matchingInventoryItem(character, kind, desiredType, desiredId, trough)
    if character == nil or character.getInventory == nil then
        return nil
    end
    local exact, fallback = nil, nil
    walkItems(character:getInventory(), function(item)
        if exact ~= nil then
            return
        end
        local valid = kind == "water" and isWaterSource(item)
            or kind == "feed" and isAnimalFeed(item)
        if valid and kind == "water" and trough ~= nil then
            valid = safeCall(trough, "canTransferFluidFrom",
                safeCall(item, "getFluidContainer")) == true
        end
        if not valid or (desiredType ~= nil and itemFullType(item) ~= desiredType) then
            return
        end
        if desiredId ~= nil and itemId(item) == tostring(desiredId) then
            exact = item
        elseif fallback == nil then
            fallback = item
        end
    end)
    return exact or fallback
end

local function approachSquare(trough, character)
    local square = safeCall(trough, "getSquare")
    if square == nil then
        return nil
    end
    if AdjacentFreeTileFinder ~= nil and character ~= nil then
        local success, result = pcall(function()
            return AdjacentFreeTileFinder.Find(square, character)
        end)
        if success and result ~= nil then
            return result
        end
    end
    return square
end

local function troughKey(trough)
    return tostring(safeCall(trough, "getX") or 0) .. ":"
        .. tostring(safeCall(trough, "getY") or 0) .. ":"
        .. tostring(safeCall(trough, "getZ") or 0) .. ":"
        .. tostring(safeCall(trough, "getObjectIndex") or 0)
end

local function troughsInZone(cell, zone)
    local result, seen = {}, {}
    local minX, minY, maxX, maxY, z = zoneBounds(zone)
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            local objects = square ~= nil and square:getObjects() or nil
            if objects ~= nil then
                for index = 0, objects:size() - 1 do
                    local trough = masterTrough(objects:get(index))
                    local key = trough ~= nil and troughKey(trough) or nil
                    if key ~= nil and not seen[key] then
                        seen[key] = true
                        result[#result + 1] = trough
                    end
                end
            end
        end
    end
    table.sort(result, function(first, second)
        return troughKey(first) < troughKey(second)
    end)
    return result
end

local function descriptor(base, zone, trough, action, item)
    return {
        id = "animal-care:" .. tostring(base.id) .. ":" .. tostring(zone.id)
            .. ":" .. tostring(action) .. ":" .. troughKey(trough),
        auto = true,
        action = action,
        zoneType = "animal_care",
        zoneId = zone.id,
        x = safeCall(trough, "getX"),
        y = safeCall(trough, "getY"),
        z = safeCall(trough, "getZ"),
        objectIndex = safeCall(trough, "getObjectIndex"),
        itemType = itemFullType(item),
        itemId = itemId(item),
    }
end

local function needsWater(trough)
    local amount = tonumber(safeCall(trough, "getWater")) or 0
    local maximum = tonumber(safeCall(trough, "getMaxWater")) or 0
    -- Empty troughs can switch from their empty food container to fluid mode.
    return amount <= 0 or (maximum > 0 and amount < maximum * REFILL_FRACTION)
end

local function needsFeed(trough)
    local container = safeCall(trough, "getContainer")
    if container == nil then
        return false
    end
    local amount = tonumber(safeCall(trough, "getCurrentFeedAmount")) or 0
    local maximum = tonumber(safeCall(trough, "getMaxFeed")) or 0
    return maximum > 0 and amount < maximum * REFILL_FRACTION
end

function AnimalCare.findTask(base, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil then
        return nil, "base_or_cell_unavailable"
    end
    for _, zone in ipairs(orderedZones(base)) do
        local troughs = troughsInZone(cell, zone)
        -- Water is life-critical and receives first claim on an empty trough.
        for _, trough in ipairs(troughs) do
            if needsWater(trough) then
                local item = matchingInventoryItem(character, "water", nil, nil, trough)
                if item ~= nil and approachSquare(trough, character) ~= nil then
                    return descriptor(base, zone, trough, "animal_water", item), "water"
                end
            end
        end
        for _, trough in ipairs(troughs) do
            if needsFeed(trough) then
                local item = matchingInventoryItem(character, "feed")
                if item ~= nil and approachSquare(trough, character) ~= nil then
                    return descriptor(base, zone, trough, "animal_feed", item), "feed"
                end
            end
        end
    end
    return nil, "no_animal_care_ready"
end

local function troughAt(cell, target)
    local square = cell:getGridSquare(
        tonumber(target.x) or 0,
        tonumber(target.y) or 0,
        tonumber(target.z) or 0
    )
    local objects = square ~= nil and square:getObjects() or nil
    if objects == nil then
        return nil
    end
    local fallback = nil
    for index = 0, objects:size() - 1 do
        local trough = masterTrough(objects:get(index))
        if trough ~= nil then
            fallback = fallback or trough
            if target.objectIndex == nil
                or tonumber(safeCall(trough, "getObjectIndex"))
                    == tonumber(target.objectIndex) then
                return trough
            end
        end
    end
    return fallback
end

function AnimalCare.resolveTarget(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then
        return nil, "missing_animal_care_target"
    end
    local trough = troughAt(cell, target)
    if trough == nil then
        return nil, "trough_unloaded_or_removed"
    end
    local actionKind = target.action == "animal_water" and "water" or "feed"
    local item = matchingInventoryItem(
        character,
        actionKind,
        target.itemType,
        target.itemId,
        trough
    )
    if item == nil then
        return nil, actionKind .. "_item_unavailable"
    end
    if actionKind == "water" and not needsWater(trough) then
        return nil, "trough_does_not_need_water"
    end
    if actionKind == "feed" and not needsFeed(trough) then
        return nil, "trough_does_not_need_feed"
    end
    local approach = approachSquare(trough, character)
    if approach == nil then
        return nil, "trough_path_unavailable"
    end
    return {
        action = target.action,
        trough = trough,
        item = item,
        approach = approach,
    }, "resolved"
end

function AnimalCare.queueAction(character, target)
    if character == nil or target == nil or target.trough == nil
        or target.item == nil then
        return nil, "missing_animal_care_target"
    end
    character:faceThisObject(target.trough)
    if character:shouldBeTurning() then
        return nil, "turning_to_trough"
    end
    if target.action == "animal_water" then
        local mainInventory = character:getInventory()
        local source = safeCall(target.item, "getContainer")
        if source ~= nil and source ~= mainInventory then
            local transfer = KnoxInventoryActions.queueTransfer(
                character,
                target.item,
                source,
                mainInventory,
                nil
            )
            if transfer == nil then
                return nil, "water_transfer_failed"
            end
        end
        local action = ISAddFluidFromItemAction:new(
            character,
            target.item,
            target.trough
        )
        ISTimedActionQueue.add(action)
        return action, "queued"
    end
    local container = safeCall(target.trough, "getContainer")
    local source = safeCall(target.item, "getContainer")
    if container == nil or source == nil then
        return nil, "trough_feed_container_unavailable"
    end
    return KnoxInventoryActions.queueTransfer(
        character,
        target.item,
        source,
        container,
        nil
    )
end

function AnimalCare.snapshot(target)
    local trough = target ~= nil and target.trough or nil
    return {
        water = tonumber(safeCall(trough, "getWater")) or 0,
        feed = tonumber(safeCall(trough, "getCurrentFeedAmount")) or 0,
    }
end

function AnimalCare.isComplete(target, before)
    if target == nil or target.trough == nil then
        return false
    end
    if target.action == "animal_water" then
        return (tonumber(safeCall(target.trough, "getWater")) or 0)
            > (tonumber(before ~= nil and before.water or 0) or 0)
    end
    return (tonumber(safeCall(target.trough, "getCurrentFeedAmount")) or 0)
        > (tonumber(before ~= nil and before.feed or 0) or 0)
end

function AnimalCare.resolveTaskSquare(base, target, character)
    local resolved = AnimalCare.resolveTarget(base, target, character)
    return resolved ~= nil and resolved.approach or nil
end

return AnimalCare
