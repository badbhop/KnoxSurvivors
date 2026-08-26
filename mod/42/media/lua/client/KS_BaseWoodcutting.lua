require "TimedActions/ISChopTreeAction"
require "TimedActions/ISTimedActionQueue"

local Woodcutting = rawget(_G, "KnoxBaseWoodcutting") or {}
_G.KnoxBaseWoodcutting = Woodcutting

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

local function findAxe(character)
    if character == nil or character.getInventory == nil
        or ItemTag == nil or ItemTag.CHOP_TREE == nil then
        return nil
    end
    local found = nil
    walkItems(character:getInventory(), function(item)
        if found ~= nil or item == nil or item.hasTag == nil then
            return
        end
        local success, isAxe = pcall(item.hasTag, item, ItemTag.CHOP_TREE)
        local broken = safeCall(item, "isBroken") == true
        if success and isAxe == true and broken ~= true then
            found = item
        end
    end)
    return found
end

local function treeAt(square)
    if square == nil or square.HasTree == nil then
        return nil
    end
    local hasTree = safeCall(square, "HasTree")
    if hasTree ~= true or square.getTree == nil then
        return nil
    end
    return safeCall(square, "getTree")
end

local function orderedZones(base)
    local zones = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == "woodcutting" then
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

local function descriptor(base, zone, square, tree)
    return {
        id = "woodcut:" .. tostring(base.id) .. ":"
            .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
            .. tostring(square:getZ()),
        auto = true,
        zoneType = "chop_tree",
        zoneId = zone.id,
        action = "chop_tree",
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = tree ~= nil and tree:getObjectIndex() or -1,
    }
end

function Woodcutting.findAxe(character)
    return findAxe(character)
end

function Woodcutting.findTask(base, character)
    local cell = getCell ~= nil and getCell() or nil
    local axe = findAxe(character)
    if base == nil or cell == nil then
        return nil, "base_or_cell_unavailable"
    end
    if axe == nil then
        return nil, "missing_axe"
    end
    for _, zone in ipairs(orderedZones(base)) do
        local minX, minY, maxX, maxY, z = zoneBounds(zone)
        maxX = math.min(maxX, minX + 96)
        maxY = math.min(maxY, minY + 96)
        for x = minX, maxX do
            for y = minY, maxY do
                local square = cell:getGridSquare(x, y, z)
                local tree = treeAt(square)
                if tree ~= nil then
                    return descriptor(base, zone, square, tree), "found"
                end
            end
        end
    end
    return nil, "no_tree_ready"
end

function Woodcutting.resolveTarget(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then
        return nil, "missing_woodcutting_target"
    end
    local square = cell:getGridSquare(
        tonumber(target.x) or 0,
        tonumber(target.y) or 0,
        tonumber(target.z) or 0
    )
    local tree = treeAt(square)
    if tree == nil or (target.objectIndex ~= nil
        and tonumber(target.objectIndex) ~= tonumber(tree:getObjectIndex())) then
        return nil, "tree_no_longer_valid"
    end
    local axe = findAxe(character)
    if axe == nil then
        return nil, "missing_axe"
    end
    return { square = square, tree = tree, axe = axe }, "resolved"
end

function Woodcutting.queueAction(character, target)
    if character == nil or target == nil or target.tree == nil or target.axe == nil then
        return nil, "missing_tree_or_axe"
    end
    character:setPrimaryHandItem(target.axe)
    local action = ISChopTreeAction:new(character, target.tree)
    ISTimedActionQueue.add(action)
    return action, "queued"
end

function Woodcutting.isComplete(target)
    if target == nil or target.tree == nil then
        return false
    end
    local objectIndex = safeCall(target.tree, "getObjectIndex")
    return objectIndex ~= nil and tonumber(objectIndex) < 0
end

return Woodcutting
