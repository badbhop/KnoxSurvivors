require "Moveables/ISMoveableSpriteProps"
require "Moveables/ISMoveablesAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISWearClothing"
require "Util/AdjacentFreeTileFinder"
require "ISUI/ISWorldObjectContextMenu"
require "KS_SurvivorInventoryActions"

local Repairs = rawget(_G, "KnoxBaseRepairs") or {}
_G.KnoxBaseRepairs = Repairs

local MAX_SCAN_RADIUS = 36

local function safeCall(object, method, ...)
    if object == nil or object == false or object == true
        or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    return success and value or nil
end

local function instanceOf(object, className)
    if object == nil or instanceof == nil then
        return false
    end
    local success, result = pcall(function()
        return instanceof(object, className)
    end)
    return success and result == true
end

local function isStructure(object)
    return instanceOf(object, "IsoDoor")
        or instanceOf(object, "IsoThumpable")
        or instanceOf(object, "IsoBarricade")
end

local function damaged(object)
    local health = tonumber(safeCall(object, "getHealth")) or 0
    local maximum = tonumber(safeCall(object, "getMaxHealth")) or 0
    local fraction = maximum > 0 and health / maximum or 1
    return maximum > 0 and fraction >= 0.20 and fraction <= 0.95
end

local function repairProps(object, character)
    if not isStructure(object) or not damaged(object)
        or ISMoveableSpriteProps == nil
        or ISMoveableSpriteProps.fromObjectForRepair == nil then
        return nil
    end
    local success, props = pcall(
        ISMoveableSpriteProps.fromObjectForRepair,
        object
    )
    if not success or props == nil or props.canRepairObject == nil then
        return nil
    end
    local valid, result = pcall(props.canRepairObject, props, character)
    if not valid or result == nil or result.canRepair ~= true then
        return nil
    end
    return props
end

local function zoneBounds(zone)
    local minX = tonumber(zone.x1 or zone.minX) or 0
    local minY = tonumber(zone.y1 or zone.minY) or 0
    local maxX = tonumber(zone.x2 or zone.maxX)
        or minX + (tonumber(zone.width) or 1) - 1
    local maxY = tonumber(zone.y2 or zone.maxY)
        or minY + (tonumber(zone.height) or 1) - 1
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(zone.z) or 0
end

local function repairRegions(base, character)
    local regions = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == "repair" then
            regions[#regions + 1] = zone
        end
    end
    if #regions == 0 then
        local territory = base ~= nil and (base.territory or base.home) or nil
        if territory ~= nil then
            local current = character ~= nil and character:getCurrentSquare() or nil
            regions[1] = {
                id = "territory",
                x1 = territory.minX,
                y1 = territory.minY,
                x2 = territory.maxX
                    or (territory.minX + (territory.width or 1) - 1),
                y2 = territory.maxY
                    or (territory.minY + (territory.height or 1) - 1),
                z = current ~= nil and current:getZ() or territory.z or 0,
            }
        end
    end
    table.sort(regions, function(first, second)
        return tostring(first.id or "territory") < tostring(second.id or "territory")
    end)
    return regions
end

local function approachSquare(object, character)
    local square = safeCall(object, "getSquare")
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
    return nil
end

local function addRequirement(items, fullType, amount)
    if type(fullType) ~= "string" or fullType == ""
        or string.sub(fullType, 1, 4) == "Tag." then
        return
    end
    items[fullType] = math.max(
        tonumber(items[fullType]) or 0,
        math.max(1, tonumber(amount) or 1)
    )
end

local function requirementsFor(props, character)
    local items = {}
    local firstTool = safeCall(props, "hasRepairTool", character, false)
    local secondTool = safeCall(props, "hasRepairTool", character, true)
    if firstTool ~= true then
        addRequirement(items, safeCall(firstTool, "getFullType"), 1)
    end
    if secondTool ~= true then
        addRequirement(items, safeCall(secondTool, "getFullType"), 1)
    end
    local parts = safeCall(props, "getAllRepairParts") or {}
    local inventory = character ~= nil and character:getInventory() or nil
    local optionalAdded = false
    for _, part in ipairs(parts) do
        if part.required == true then
            addRequirement(items, part.itemType, part.amount)
        elseif not optionalAdded and inventory ~= nil
            and safeCall(props, "checkForRepairPart",
                inventory, part.itemType, part.amount) == true then
            addRequirement(items, part.itemType, part.amount)
            optionalAdded = true
        end
    end
    return items
end

local function spriteName(object)
    local sprite = safeCall(object, "getSprite")
    return tostring(safeCall(sprite, "getName") or "")
end

local function descriptor(base, region, object, props)
    local square = object:getSquare()
    local name = spriteName(object)
    return {
        id = "repair:" .. tostring(base.id) .. ":"
            .. tostring(region.id or "territory") .. ":"
            .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
            .. tostring(square:getZ()) .. ":" .. name,
        auto = true,
        action = "repair",
        zoneType = "repair",
        zoneId = region.id,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = object:getObjectIndex(),
        spriteName = name,
        requiredItems = {},
    }
end

local function inside(x, y, minX, minY, maxX, maxY)
    return x >= minX and x <= maxX and y >= minY and y <= maxY
end

local function closestRepairOnSquare(square, character, best, bestDistance, base, region, eligible)
    local objects = square ~= nil and square:getObjects() or nil
    if objects == nil then
        return best, bestDistance
    end
    local origin = character ~= nil and character:getCurrentSquare() or nil
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local props = repairProps(object, character)
        local approach = props ~= nil and approachSquare(object, character) or nil
        if props ~= nil and approach ~= nil then
            local dx = origin ~= nil and square:getX() - origin:getX() or 0
            local dy = origin ~= nil and square:getY() - origin:getY() or 0
            local distance = dx * dx + dy * dy
            if distance < bestDistance then
                local target = descriptor(base, region, object, props)
                target.requiredItems = requirementsFor(props, character)
                if eligible == nil or eligible(target) then
                    best = target
                    bestDistance = distance
                end
            end
        end
    end
    return best, bestDistance
end

function Repairs.findTask(base, character, eligible)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil or character == nil then
        return nil, "base_character_or_cell_unavailable"
    end
    local origin = character:getCurrentSquare()
    local best, bestDistance = nil, math.huge
    for _, region in ipairs(repairRegions(base, character)) do
        local minX, minY, maxX, maxY, z = zoneBounds(region)
        local centerX = origin ~= nil and origin:getX()
            or math.floor((minX + maxX) / 2)
        local centerY = origin ~= nil and origin:getY()
            or math.floor((minY + maxY) / 2)
        for radius = 0, MAX_SCAN_RADIUS do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                        local x, y = centerX + dx, centerY + dy
                        if inside(x, y, minX, minY, maxX, maxY) then
                            best, bestDistance = closestRepairOnSquare(
                                cell:getGridSquare(x, y, z),
                                character,
                                best,
                                bestDistance,
                                base,
                                region,
                                eligible
                            )
                        end
                    end
                end
            end
            -- Rings are visited nearest-first, so the first successful ring is
            -- already optimal. Avoid scanning thousands of farther squares once
            -- a valid loaded repair is known.
            if best ~= nil then
                return best, "found"
            end
        end
    end
    return best, best ~= nil and "found" or "no_repair_ready"
end

local function objectAt(square, target)
    local objects = square ~= nil and square:getObjects() or nil
    if objects == nil then
        return nil
    end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if isStructure(object) and spriteName(object) == tostring(target.spriteName or "") then
            if tonumber(object:getObjectIndex()) == tonumber(target.objectIndex) then
                return object
            end
        end
    end
    return nil
end

function Repairs.resolveTarget(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil or character == nil then
        return nil, "missing_repair_target"
    end
    local square = cell:getGridSquare(
        tonumber(target.x) or 0,
        tonumber(target.y) or 0,
        tonumber(target.z) or 0
    )
    local object = objectAt(square, target)
    local props = repairProps(object, character)
    local approach = props ~= nil and approachSquare(object, character) or nil
    if object == nil or props == nil or approach == nil then
        return nil, "repair_target_unavailable"
    end
    return {
        object = object,
        props = props,
        square = square,
        approach = approach,
        spriteName = spriteName(object),
    }, "resolved"
end

function Repairs.queueAction(character, target)
    if character == nil or target == nil or target.props == nil
        or target.object == nil or target.square == nil then
        return nil, "missing_repair_target"
    end
    local firstTool = safeCall(target.props, "hasRepairTool", character, false)
    local secondTool = safeCall(target.props, "hasRepairTool", character, true)
    if firstTool == nil or firstTool == false
        or secondTool == nil or secondTool == false then
        return nil, "repair_tool_unavailable"
    end
    if firstTool ~= true then
        ISWorldObjectContextMenu.equip(
            character,
            character:getPrimaryHandItem(),
            firstTool,
            true,
            false
        )
    end
    if secondTool ~= true then
        if instanceOf(secondTool, "Clothing") then
            if safeCall(character, "isEquippedClothing", secondTool) ~= true then
                local source = safeCall(secondTool, "getContainer")
                local inventory = character:getInventory()
                if source ~= nil and source ~= inventory then
                    local transfer = KnoxInventoryActions.queueTransfer(
                        character,
                        secondTool,
                        source,
                        inventory,
                        nil
                    )
                    if transfer == nil then
                        return nil, "repair_clothing_transfer_failed"
                    end
                end
                ISTimedActionQueue.add(ISWearClothing:new(character, secondTool))
            end
        else
            ISWorldObjectContextMenu.equip(
                character,
                character:getSecondaryHandItem(),
                secondTool,
                false,
                false
            )
        end
    end
    local action = ISMoveablesAction:new(
        character,
        target.square,
        "repair",
        target.spriteName,
        target.object,
        nil,
        nil,
        nil
    )
    ISTimedActionQueue.add(action)
    return action, "queued"
end

function Repairs.snapshot(target)
    return tonumber(safeCall(target ~= nil and target.object or nil, "getHealth")) or 0
end

function Repairs.isComplete(target, before)
    local health = tonumber(safeCall(target ~= nil and target.object or nil, "getHealth")) or 0
    return health > (tonumber(before) or 0)
end

function Repairs.resolveTaskSquare(base, target, character)
    local resolved = Repairs.resolveTarget(base, target, character)
    return resolved ~= nil and resolved.approach or nil
end

return Repairs
