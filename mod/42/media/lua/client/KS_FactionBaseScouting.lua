require "KS_Persistence"

local BaseScouting = rawget(_G, "KnoxFactionBaseScouting") or {}
_G.KnoxFactionBaseScouting = BaseScouting

-- Search locally first, then widen only when the nearby ring produced no valid
-- shelter.  Faction scouting remains loaded-world work; the staged radii keep
-- the common case cheap without making a group give up because its first block
-- contains only tiny or already-claimed buildings.
local SCAN_RADII = { 30, 60, 90 }
local MIN_ROOMS = 2
local MIN_AREA = 30

local function overlaps(first, second)
    if first == nil or second == nil then return false end
    local firstMinX = tonumber(first.minX)
    local firstMinY = tonumber(first.minY)
    local firstMaxX = tonumber(first.maxX)
        or (firstMinX ~= nil and firstMinX + (tonumber(first.width) or 1) - 1)
    local firstMaxY = tonumber(first.maxY)
        or (firstMinY ~= nil and firstMinY + (tonumber(first.height) or 1) - 1)
    local secondMinX = tonumber(second.minX)
    local secondMinY = tonumber(second.minY)
    local secondMaxX = tonumber(second.maxX)
        or (secondMinX ~= nil and secondMinX + (tonumber(second.width) or 1) - 1)
    local secondMaxY = tonumber(second.maxY)
        or (secondMinY ~= nil and secondMinY + (tonumber(second.height) or 1) - 1)
    if firstMinX == nil or firstMinY == nil or firstMaxX == nil or firstMaxY == nil
        or secondMinX == nil or secondMinY == nil
        or secondMaxX == nil or secondMaxY == nil then
        return false
    end
    return firstMinX <= secondMaxX and firstMaxX >= secondMinX
        and firstMinY <= secondMaxY and firstMaxY >= secondMinY
end

local function overlapsPersistedBase(definition, z)
    for _, base in pairs(KnoxPersistence.getBases() or {}) do
        local area = base ~= nil and (base.territory or base.home) or nil
        if area ~= nil and tonumber(area.z or 0) == tonumber(z or 0)
            and overlaps({
                minX = definition:getX(), minY = definition:getY(),
                maxX = definition:getX2(), maxY = definition:getY2(),
            }, area) then
            return true
        end
    end
    return false
end

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
    if definition == nil or safehouseOverlaps(definition)
        or overlapsPersistedBase(definition, origin:getZ()) then
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
        distance = distance,
    }
end

function BaseScouting.findBestCandidate(character, factionId, worldAgeHours)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    if origin == nil or getCell() == nil then
        return nil
    end
    local best = nil
    local seen = {}
    for _, radius in ipairs(SCAN_RADII) do
        for dx = -radius, radius do
            for dy = -radius, radius do
                -- Only inspect the newly-added outer ring after the first
                -- radius. This avoids rescanning the same loaded squares while
                -- preserving the nearest-first scoring behavior.
                local outsidePrevious = radius == SCAN_RADII[1]
                    or math.max(math.abs(dx), math.abs(dy)) > (radius - 30)
                if outsidePrevious then
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
                            and (best == nil or candidate.score > best.score
                                or (candidate.score == best.score
                                    and (candidate.distance < best.distance
                                        or (candidate.distance == best.distance
                                            and candidate.buildingId < best.buildingId)))) then
                            best = candidate
                        end
                    end
                end
            end
        end
        if best ~= nil then break end
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
