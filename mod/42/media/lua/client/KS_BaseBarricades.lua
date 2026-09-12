require "TimedActions/ISBarricadeAction"
require "TimedActions/ISTimedActionQueue"

local Barricades = rawget(_G, "KnoxBaseBarricades") or {}
_G.KnoxBaseBarricades = Barricades

local HAMMER_TYPES = {
    ["Base.Hammer"] = true,
    ["Base.BallPeenHammer"] = true,
    ["Base.ClubHammer"] = true,
    ["Base.WoodenMallet"] = true,
}

local function fullType(item)
    return item ~= nil and item.getFullType ~= nil
        and tostring(item:getFullType() or "") or ""
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

local function findItem(character, predicate)
    local found = nil
    walkItems(character ~= nil and character:getInventory() or nil, function(item)
        if found == nil and predicate(item) then
            found = item
        end
    end)
    return found
end

function Barricades.findHammer(character, base)
    local function usableHammer(item)
        local full = fullType(item)
        if HAMMER_TYPES[full] then
            return item.isBroken == nil or not item:isBroken()
        end
        return false
    end
    local found = findItem(character, usableHammer)
    local storage = rawget(_G, "KnoxBaseStorage")
    if found == nil and base ~= nil and storage ~= nil and storage.findItemType ~= nil then
        local _, stored = storage.findItemType(base, usableHammer)
        found = stored
    end
    return found
end

function Barricades.findPlank(character)
    return findItem(character, function(item)
        return fullType(item) == "Base.Plank"
    end)
end

function Barricades.canPrepare(character, base)
    if character == nil or character.getInventory == nil then
        return false
    end
    local hammer = Barricades.findHammer(character, base)
    if hammer == nil then return false end
    local storage = rawget(_G, "KnoxBaseStorage")
    if base ~= nil and storage ~= nil and storage.requirementsAvailable ~= nil then
        local hammerType = hammer:getFullType()
        return storage.requirementsAvailable(base, character, {
            items = { [hammerType] = 1, ["Base.Plank"] = 1, ["Base.Nails"] = 2 },
            itemRules = { [hammerType] = { usable = true } },
        })
    end
    local inventory = character:getInventory()
    return Barricades.findHammer(character) ~= nil
        and Barricades.findPlank(character) ~= nil
        and inventory:getItemCount("Base.Nails", true) >= 2
end

local function isBarricadeAble(object)
    if object == nil or object.getBarricadeForCharacter == nil then
        return false
    end
    if instanceof ~= nil then
        local success, result = pcall(function()
            return instanceof(object, "BarricadeAble")
        end)
        if success and not result then
            return false
        end
    end
    if object.isBarricadeAllowed ~= nil then
        local success, result = pcall(function()
            return object:isBarricadeAllowed()
        end)
        if success and result == false then
            return false
        end
    end
    return true
end

local function isOpen(object)
    if object == nil or object.IsOpen == nil then
        return false
    end
    local success, result = pcall(function() return object:IsOpen() end)
    return success and result == true
end

local function targetId(base, object, square)
    return "barricade:" .. tostring(base.id) .. ":"
        .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
        .. tostring(square:getZ()) .. ":" .. tostring(object:getObjectIndex())
end

local function targetFromObject(base, object, square)
    return {
        id = targetId(base, object, square),
        auto = true,
        zoneType = "barricade",
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = object:getObjectIndex(),
    }
end

local function targetNeedsBarricade(object, character)
    if not isBarricadeAble(object) or isOpen(object) then
        return false
    end
    local success, barricade = pcall(function()
        return object:getBarricadeForCharacter(character)
    end)
    if not success then
        return false
    end
    return barricade == nil or barricade:canAddPlank()
end

function Barricades.findTarget(base, character)
    local territory = base ~= nil and (base.territory or base.home) or nil
    local cell = getCell ~= nil and getCell() or nil
    if territory == nil or cell == nil then
        return nil, "base_or_cell_unavailable"
    end
    local minX = tonumber(territory.minX) or 0
    local minY = tonumber(territory.minY) or 0
    local maxX = tonumber(territory.maxX)
        or minX + (tonumber(territory.width) or 1) - 1
    local maxY = tonumber(territory.maxY)
        or minY + (tonumber(territory.height) or 1) - 1
    -- Work scans are bounded per decision so a player-drawn large territory
    -- cannot turn a normal autonomy tick into a full-map object search.
    maxX = math.min(maxX, minX + 96)
    maxY = math.min(maxY, minY + 96)
    local startZ = tonumber((base.home or {}).z) or 0
    for z = startZ, startZ + 3 do
        for x = minX, maxX do
            for y = minY, maxY do
                local square = cell:getGridSquare(x, y, z)
                if square ~= nil and square.getObjects ~= nil then
                    local objects = square:getObjects()
                    for index = 0, objects:size() - 1 do
                        local object = objects:get(index)
                        if targetNeedsBarricade(object, character) then
                            return targetFromObject(base, object, square), "found"
                        end
                    end
                end
            end
        end
    end
    return nil, "no_unbarricaded_window"
end

function Barricades.resolveTarget(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then
        return nil, "missing_target"
    end
    local square = cell:getGridSquare(
        tonumber(target.x) or 0,
        tonumber(target.y) or 0,
        tonumber(target.z) or 0
    )
    if square == nil or square.getObjects == nil then
        return nil, "target_unloaded"
    end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if object ~= nil and object:getObjectIndex() == tonumber(target.objectIndex)
            and targetNeedsBarricade(object, character) then
            return {
                object = object,
                square = square,
            }, "resolved"
        end
    end
    return nil, "target_no_longer_valid"
end

function Barricades.queueAction(character, target)
    if character == nil or target == nil or target.object == nil then
        return nil, "missing_barricade_target"
    end
    if not Barricades.canPrepare(character) then
        return nil, "missing_hammer_plank_or_nails"
    end
    local hammer = Barricades.findHammer(character)
    local plank = Barricades.findPlank(character)
    character:setPrimaryHandItem(hammer)
    character:setSecondaryHandItem(plank)
    local action = ISBarricadeAction:new(character, target.object, false, false)
    ISTimedActionQueue.add(action)
    return action, "queued"
end

function Barricades.isComplete(target, character, beforePlanks)
    if target == nil or target.object == nil then
        return false
    end
    local success, barricade = pcall(function()
        return target.object:getBarricadeForCharacter(character)
    end)
    if not success or barricade == nil then
        return false
    end
    local count = tonumber(barricade:getNumPlanks()) or 0
    return count > (tonumber(beforePlanks) or 0)
end

function Barricades.plankCount(target, character)
    if target == nil or target.object == nil then
        return 0
    end
    local success, barricade = pcall(function()
        return target.object:getBarricadeForCharacter(character)
    end)
    if not success or barricade == nil then
        return 0
    end
    return tonumber(barricade:getNumPlanks()) or 0
end

return Barricades
