require "TimedActions/ISGrabCorpseAction"
require "TimedActions/ISDropCorpseAction"
require "TimedActions/ISUnequipAction"
require "TimedActions/ISTimedActionQueue"

local CorpseHandling = rawget(_G, "KnoxBaseCorpseHandling") or {}
_G.KnoxBaseCorpseHandling = CorpseHandling

local MAX_SOURCE_SCAN_RADIUS = 36

local function safeCall(object, method, ...)
    if object == nil or object[method] == nil then
        return nil
    end
    local success, value = pcall(object[method], object, ...)
    return success and value or nil
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
        if zone ~= nil and zone.enabled ~= false and zone.type == "corpse" then
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(first, second)
        return tostring(first.id) < tostring(second.id)
    end)
    return zones
end

local function sourceBounds(base, zone)
    local territory = base ~= nil and (base.territory or base.home) or nil
    if territory == nil then
        return zoneBounds(zone)
    end
    local minX = tonumber(territory.minX) or 0
    local minY = tonumber(territory.minY) or 0
    local maxX = tonumber(territory.maxX)
        or minX + (tonumber(territory.width) or 1) - 1
    local maxY = tonumber(territory.maxY)
        or minY + (tonumber(territory.height) or 1) - 1
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(zone.z) or 0
end

local function insideZone(zone, square)
    if zone == nil or square == nil then
        return false
    end
    local minX, minY, maxX, maxY, z = zoneBounds(zone)
    return square:getZ() == z
        and square:getX() >= minX and square:getX() <= maxX
        and square:getY() >= minY and square:getY() <= maxY
end

local function isDeadBody(object)
    if object == nil or instanceof == nil then
        return false
    end
    local success, result = pcall(function()
        return instanceof(object, "IsoDeadBody")
    end)
    return success and result == true
end

local function isAnimalBody(object)
    if object == nil or object.isAnimal == nil then
        return false
    end
    local success, result = pcall(object.isAnimal, object)
    return success and result == true
end

local function haulable(object)
    if not isDeadBody(object) or isAnimalBody(object) then
        return false
    end
    local index = safeCall(object, "getStaticMovingObjectIndex")
    return index == nil or tonumber(index) == nil or tonumber(index) >= 0
end

local function distanceSquared(first, second)
    if first == nil or second == nil then
        return math.huge
    end
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function canStand(square)
    if square == nil then
        return false
    end
    if square.canStand == nil then
        return true
    end
    local success, result = pcall(square.canStand, square)
    return success and result == true
end

local function candidateDropSquare(cell, zone, character, corpseSquare)
    local minX, minY, maxX, maxY, z = zoneBounds(zone)
    local centerX = math.floor((minX + maxX) / 2)
    local centerY = math.floor((minY + maxY) / 2)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    local candidates = {
        { centerX, centerY },
        { minX, minY },
        { maxX, minY },
        { minX, maxY },
        { maxX, maxY },
    }
    local best, bestScore = nil, math.huge
    for _, point in ipairs(candidates) do
        for radius = 0, 4 do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                        local square = cell:getGridSquare(
                            point[1] + dx, point[2] + dy, z
                        )
                        if canStand(square) and square ~= corpseSquare then
                            local centerDistance = (square:getX() - centerX) ^ 2
                                + (square:getY() - centerY) ^ 2
                            local originDistance = distanceSquared(square, origin)
                            local score = centerDistance + originDistance * 0.05
                            if score < bestScore then
                                best = square
                                bestScore = score
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function approachSquare(corpseSquare, character)
    if corpseSquare == nil then
        return nil
    end
    if AdjacentFreeTileFinder ~= nil and character ~= nil then
        local success, result = pcall(function()
            return AdjacentFreeTileFinder.Find(corpseSquare, character)
        end)
        if success and result ~= nil then
            return result
        end
    end
    return canStand(corpseSquare) and corpseSquare or nil
end

local function targetId(base, zone, body, square)
    local corpseItem = safeCall(body, "getItem")
    local itemId = safeCall(corpseItem, "getID")
    local identity = itemId ~= nil and ("item-" .. tostring(itemId))
        or ("index-" .. tostring(safeCall(body, "getStaticMovingObjectIndex") or 0))
    return "corpse:" .. tostring(base.id) .. ":" .. tostring(zone.id) .. ":"
        .. tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
        .. tostring(square:getZ()) .. ":" .. identity
end

local function descriptor(base, zone, body, square, dropSquare)
    local corpseItem = safeCall(body, "getItem")
    local corpseItemId = safeCall(corpseItem, "getID")
    return {
        id = targetId(base, zone, body, square),
        auto = true,
        action = "haul_corpse",
        zoneType = "corpse",
        zoneId = zone.id,
        corpseX = square:getX(),
        corpseY = square:getY(),
        corpseZ = square:getZ(),
        corpseIndex = safeCall(body, "getStaticMovingObjectIndex"),
        corpseItemId = corpseItemId ~= nil and tostring(corpseItemId) or nil,
        dropX = dropSquare:getX(),
        dropY = dropSquare:getY(),
        dropZ = dropSquare:getZ(),
    }
end

local function firstHaulableBody(square)
    if square == nil or square.getStaticMovingObjects == nil then
        return nil
    end
    local objects = square:getStaticMovingObjects()
    if objects == nil then
        return nil
    end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if haulable(object) then
            return object
        end
    end
    return nil
end

local function insideBounds(x, y, minX, minY, maxX, maxY)
    return x >= minX and x <= maxX and y >= minY and y <= maxY
end

function CorpseHandling.findTask(base, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or cell == nil then
        return nil, "base_or_cell_unavailable"
    end
    local origin = character ~= nil and character:getCurrentSquare() or nil
    local best, bestDistance = nil, math.huge
    for _, zone in ipairs(orderedZones(base)) do
        local minX, minY, maxX, maxY, z = sourceBounds(base, zone)
        local zoneMinX, zoneMinY, zoneMaxX, zoneMaxY = zoneBounds(zone)
        local centerX = origin ~= nil and origin:getX()
            or math.floor((zoneMinX + zoneMaxX) / 2)
        local centerY = origin ~= nil and origin:getY()
            or math.floor((zoneMinY + zoneMaxY) / 2)
        -- Search outward from the worker so a very large player-drawn base remains
        -- bounded per decision. Patrol and ordinary base movement naturally expose
        -- other loaded sections later instead of scanning the whole territory at once.
        for radius = 0, MAX_SOURCE_SCAN_RADIUS do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                        local x, y = centerX + dx, centerY + dy
                        local square = insideBounds(x, y, minX, minY, maxX, maxY)
                            and cell:getGridSquare(x, y, z) or nil
                        local body = not insideZone(zone, square)
                            and firstHaulableBody(square) or nil
                        if body ~= nil then
                            local approach = approachSquare(square, character)
                            local dropSquare = candidateDropSquare(
                                cell, zone, character, square
                            )
                            if approach ~= nil and dropSquare ~= nil
                                and distanceSquared(square, dropSquare) > 1 then
                                local distance = distanceSquared(square, origin)
                                if distance < bestDistance then
                                    best = descriptor(
                                        base, zone, body, square, dropSquare
                                    )
                                    bestDistance = distance
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, best ~= nil and "found" or "no_corpse_ready"
end

local function bodyAtSquare(square, objectIndex, corpseItemId)
    if square == nil or square.getStaticMovingObjects == nil then
        return nil
    end
    local objects = square:getStaticMovingObjects()
    if objects == nil then
        return nil
    end
    for index = 0, objects:size() - 1 do
        local body = objects:get(index)
        if haulable(body) then
            local item = safeCall(body, "getItem")
            local itemId = safeCall(item, "getID")
            local currentIndex = safeCall(body, "getStaticMovingObjectIndex")
            if (corpseItemId ~= nil and tostring(itemId) == tostring(corpseItemId))
                or (corpseItemId == nil and (objectIndex == nil
                    or tonumber(currentIndex) == tonumber(objectIndex))) then
                return body
            end
        end
    end
    return nil
end

function CorpseHandling.resolveTarget(base, target, character)
    local cell = getCell ~= nil and getCell() or nil
    if base == nil or target == nil or cell == nil then
        return nil, "missing_corpse_target"
    end
    local corpseSquare = cell:getGridSquare(
        tonumber(target.corpseX) or 0,
        tonumber(target.corpseY) or 0,
        tonumber(target.corpseZ) or 0
    )
    local body = bodyAtSquare(
        corpseSquare,
        target.corpseIndex,
        target.corpseItemId
    )
    if body == nil then
        return nil, "corpse_unloaded_or_moved"
    end
    local approach = approachSquare(corpseSquare, character)
    local zone = base.zones[target.zoneId]
    local dropSquare = zone ~= nil and candidateDropSquare(
        cell, zone, character, corpseSquare
    ) or cell:getGridSquare(
        tonumber(target.dropX) or 0,
        tonumber(target.dropY) or 0,
        tonumber(target.dropZ) or 0
    )
    if approach == nil or dropSquare == nil then
        return nil, "corpse_path_unavailable"
    end
    return {
        body = body,
        corpseSquare = corpseSquare,
        approach = approach,
        dropSquare = dropSquare,
    }, "resolved"
end

local function unequipHeld(character)
    local primary = safeCall(character, "getPrimaryHandItem")
    local secondary = safeCall(character, "getSecondaryHandItem")
    if primary ~= nil then
        ISTimedActionQueue.add(ISUnequipAction:new(character, primary, 50))
    end
    if secondary ~= nil and secondary ~= primary then
        ISTimedActionQueue.add(ISUnequipAction:new(character, secondary, 50))
    end
end

function CorpseHandling.queueGrab(character, target)
    if character == nil or target == nil or target.body == nil then
        return nil, "missing_corpse"
    end
    if safeCall(character, "isDraggingCorpse") == true then
        return nil, "already_dragging_corpse"
    end
    unequipHeld(character)
    local action = ISGrabCorpseAction:new(character, target.body)
    ISTimedActionQueue.add(action)
    return action, "queued"
end

-- IsoPlayer shells normally complete the same vanilla grab action as a player.
-- If the action animation completes but the engine did not attach the corpse,
-- retry the native pickup call once before abandoning the cleanup job. This is
-- deliberately a fallback: the visible vanilla action remains the normal path.
function CorpseHandling.retryGrab(character, target)
    if character == nil or target == nil or target.body == nil then
        return false, "missing_corpse"
    end
    if CorpseHandling.isDragging(character) then
        return true, "already_dragging"
    end
    local success = pcall(function()
        character:pickUpCorpse(target.body, "BwdDrag")
    end)
    if success and CorpseHandling.isDragging(character) then
        return true, "native_retry"
    end
    return false, success and "native_pickup_not_attached" or "native_pickup_failed"
end

function CorpseHandling.queueDrop(character, target)
    if character == nil or target == nil or target.dropSquare == nil then
        return nil, "missing_drop_square"
    end
    if safeCall(character, "isDraggingCorpse") ~= true then
        return nil, "not_dragging_corpse"
    end
    local action = ISDropCorpseAction:new(character, target.dropSquare)
    ISTimedActionQueue.add(action)
    return action, "queued"
end

function CorpseHandling.isDragging(character)
    return safeCall(character, "isDraggingCorpse") == true
end

return CorpseHandling
