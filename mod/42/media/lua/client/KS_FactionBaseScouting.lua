require "KS_Persistence"

local BaseScouting = rawget(_G, "KnoxFactionBaseScouting") or {}
_G.KnoxFactionBaseScouting = BaseScouting

local SCAN_RADIUS = 30
local MIN_ROOMS = 2
local MIN_AREA = 30

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function safehouseOverlaps(definition)
    local success, safehouse = pcall(function()
        return SafeHouse.getSafehouseOverlapping(
            definition:getX(),
            definition:getY(),
            definition:getX() + definition:getW(),
            definition:getY() + definition:getH()
        )
    end)
    return success and safehouse ~= nil
end

local function nearestExteriorSquare(origin, definition)
    local cell = getCell()
    if cell == nil then
        return nil
    end
    local best = nil
    local bestDistance = nil
    local minX = definition:getX() - 1
    local minY = definition:getY() - 1
    local maxX = definition:getX2()
    local maxY = definition:getY2()
    for x = minX, maxX do
        for _, y in ipairs({ minY, maxY }) do
            local square = cell:getGridSquare(x, y, origin:getZ())
            if square ~= nil and square:isOutside() and square:canStand() then
                local distance = distanceSquared(origin, square)
                if bestDistance == nil or distance < bestDistance then
                    best = square
                    bestDistance = distance
                end
            end
        end
    end
    for y = minY + 1, maxY - 1 do
        for _, x in ipairs({ minX, maxX }) do
            local square = cell:getGridSquare(x, y, origin:getZ())
            if square ~= nil and square:isOutside() and square:canStand() then
                local distance = distanceSquared(origin, square)
                if bestDistance == nil or distance < bestDistance then
                    best = square
                    bestDistance = distance
                end
            end
        end
    end
    return best, bestDistance
end

local function assessBuilding(origin, building)
    local definition = building ~= nil and building:getDef() or nil
    if definition == nil or safehouseOverlaps(definition) then
        return nil
    end
    local rooms = definition:getRoomsNumber()
    local area = definition:getArea()
    if rooms < MIN_ROOMS or area < MIN_AREA then
        return nil
    end
    local target, distance = nearestExteriorSquare(origin, definition)
    if target == nil then
        return nil
    end
    local residential = building:isResidential()
    local water = building:hasWater()
    local score = rooms * 8
        + math.min(area, 240) * 0.15
        + (residential and 25 or 0)
        + (water and 15 or 0)
        - math.sqrt(distance or 0) * 0.35
    return {
        buildingId = tostring(definition:getID()),
        x = target:getX(),
        y = target:getY(),
        z = target:getZ(),
        minX = definition:getX(),
        minY = definition:getY(),
        width = definition:getW(),
        height = definition:getH(),
        rooms = rooms,
        area = area,
        residential = residential,
        water = water,
        score = score,
    }
end

function BaseScouting.findBestCandidate(character, factionId, worldAgeHours)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    if origin == nil or getCell() == nil then
        return nil
    end
    local seen = {}
    local best = nil
    for dx = -SCAN_RADIUS, SCAN_RADIUS do
        for dy = -SCAN_RADIUS, SCAN_RADIUS do
            local square = getCell():getGridSquare(
                origin:getX() + dx,
                origin:getY() + dy,
                origin:getZ()
            )
            local building = square ~= nil and square:getBuilding() or nil
            if building ~= nil and not seen[building] then
                seen[building] = true
                local candidate = assessBuilding(origin, building)
                if candidate ~= nil
                    and not KnoxPersistence.isFactionBaseCandidateRejected(
                        factionId,
                        candidate.buildingId,
                        worldAgeHours
                    )
                    and (best == nil or candidate.score > best.score) then
                    best = candidate
                end
            end
        end
    end
    return best
end

function BaseScouting.resolveTarget(candidate)
    if type(candidate) ~= "table" or getCell() == nil then
        return nil
    end
    local square = getCell():getGridSquare(candidate.x, candidate.y, candidate.z)
    return square ~= nil and square:canStand() and square or nil
end

return BaseScouting
