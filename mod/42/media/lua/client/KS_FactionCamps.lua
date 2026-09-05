require "KS_Persistence"

local Camps = rawget(_G, "KnoxFactionCamps") or {}
_G.KnoxFactionCamps = Camps

local function safehouseOccupied(building)
    local definition = building ~= nil and building:getDef() or nil
    if definition == nil or SafeHouse == nil then return false end
    local success, safehouse = pcall(function()
        return SafeHouse.getSafehouseOverlapping(
            definition:getX(), definition:getY(),
            definition:getX() + definition:getW(), definition:getY() + definition:getH()
        )
    end)
    return success and safehouse ~= nil
end

local function locationFor(character)
    local square = character ~= nil and character:getCurrentSquare() or nil
    local building = square ~= nil and square:getBuilding() or nil
    local definition = building ~= nil and building:getDef() or nil
    if definition ~= nil and (definition.getX == nil or definition.getY == nil
        or definition.getX2 == nil or definition.getY2 == nil
        or definition.getID == nil) then
        definition = nil
    end
    if square == nil or safehouseOccupied(building) then
        return nil
    end
    -- A faction can form before it has found a building. Preserve the same
    -- temporary-camp lifecycle outdoors rather than leaving the group homeless
    -- until a building happens to stream in. The radius-based camp geometry is
    -- intentionally modest; permanent shelter scouting still owns buildings.
    if definition == nil then
        local outside = square.isOutside ~= nil and square:isOutside()
            or (square.getRoom ~= nil and square:getRoom() == nil)
        if outside and square.canStand ~= nil and square:canStand() then
            return {
                x = square:getX(), y = square:getY(), z = square:getZ(),
                name = "Temporary Camp",
            }
        end
        return nil
    end
    return {
        x = square:getX(), y = square:getY(), z = square:getZ(),
        buildingId = tostring(definition:getID()), name = "Temporary Shelter",
        minX = definition:getX(), minY = definition:getY(),
        maxX = definition:getX2(), maxY = definition:getY2(),
    }
end

local function buildingIdForSquare(square)
    local building = square ~= nil and square:getBuilding() or nil
    local definition = building ~= nil and building:getDef() or nil
    return definition ~= nil and tostring(definition:getID()) or nil
end

function Camps.contains(camp, square)
    if type(camp) ~= "table" or square == nil
        or square:getZ() ~= (tonumber(camp.z) or 0) then
        return false
    end
    if camp.buildingId ~= nil then
        return buildingIdForSquare(square) == tostring(camp.buildingId)
    end
    return math.abs(square:getX() - (tonumber(camp.x) or 0)) <= 5
        and math.abs(square:getY() - (tonumber(camp.y) or 0)) <= 5
end

function Camps.memberSlot(camp, survivorId)
    for index, id in ipairs(type(camp) == "table" and camp.memberIds or {}) do
        if id == survivorId then
            return index
        end
    end
    return 1
end

-- Camp positions are ordinary standable world squares. The slot merely rotates
-- the deterministic candidate order; native movement/traversal still owns the
-- route, and the controller's short-lived reservation prevents active stacking.
function Camps.positionFor(camp, slot, unavailable)
    if type(camp) ~= "table" or getCell() == nil then
        return nil
    end
    local centerX = tonumber(camp.x)
    local centerY = tonumber(camp.y)
    local z = tonumber(camp.z) or 0
    if centerX == nil or centerY == nil then
        return nil
    end
    local minX = tonumber(camp.minX) or (centerX - 4)
    local minY = tonumber(camp.minY) or (centerY - 4)
    local maxX = tonumber(camp.maxX) or (centerX + 4)
    local maxY = tonumber(camp.maxY) or (centerY + 4)
    local candidates = {}
    for x = minX, maxX do
        for y = minY, maxY do
            local square = getCell():getGridSquare(x, y, z)
            if square ~= nil and square:canStand() and Camps.contains(camp, square) then
                candidates[#candidates + 1] = {
                    square = square,
                    distance = (x - centerX) ^ 2 + (y - centerY) ^ 2,
                    x = x,
                    y = y,
                }
            end
        end
    end
    table.sort(candidates, function(first, second)
        if first.distance ~= second.distance then
            return first.distance < second.distance
        end
        if first.y ~= second.y then
            return first.y < second.y
        end
        return first.x < second.x
    end)
    if #candidates == 0 then
        return nil
    end
    local start = ((math.max(1, tonumber(slot) or 1) - 1) % #candidates) + 1
    for offset = 0, #candidates - 1 do
        local candidate = candidates[((start + offset - 1) % #candidates) + 1]
        if unavailable == nil or not unavailable(candidate.square) then
            return candidate.square
        end
    end
    return nil
end

-- Called at the low-frequency population reconciliation boundary.  A camp is
-- only formed when the current faction leader is physically present in an
-- unclaimed building; it never teleports members or claims territory.
function Camps.reconcile(controllers, activeIds, worldAgeHours)
    for _, id in ipairs(activeIds or {}) do
        local faction = KnoxPersistence.getFactionForSurvivor(id)
        local controller = controllers ~= nil and controllers[id] or nil
        if faction ~= nil and faction.kind == "npc" and faction.homeBase == nil
            and faction.leaderId == id and controller ~= nil
            and controller.state ~= "COMBAT" and controller.state ~= "STOPPED" then
            local location = locationFor(controller.character)
            if location ~= nil then
                local camp, result = KnoxPersistence.createFactionCamp(
                    faction.id, location, worldAgeHours
                )
                if camp ~= nil and result == "created" then
                    print("[KnoxSurvivors][Camps] established faction=" .. tostring(faction.id)
                        .. " camp=" .. tostring(camp.id)
                        .. " building=" .. tostring(camp.buildingId))
                elseif camp ~= nil then
                    KnoxPersistence.touchFactionCamp(faction.id, worldAgeHours)
                end
            end
        end
    end
    for _, id in ipairs(activeIds or {}) do
        local controller = controllers ~= nil and controllers[id] or nil
        if controller ~= nil then
            local faction = KnoxPersistence.getFactionForSurvivor(id)
            local camp = faction ~= nil
                and KnoxPersistence.syncFactionCampMembers(faction.id) or nil
            if camp ~= nil and controller.setCampAssignment ~= nil then
                controller:setCampAssignment(
                    camp.id,
                    camp,
                    Camps.memberSlot(camp, id)
                )
            elseif controller.clearCampAssignment ~= nil then
                controller:clearCampAssignment()
            end
        end
    end
end

return Camps
