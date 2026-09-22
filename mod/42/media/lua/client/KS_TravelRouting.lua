-- Road-biased travel staging for foot survivors.
-- Native pathToLocationF owns the actual route; Lua can only choose waypoints.
-- For far travel we split into road-like legs (outside, no trees, standable)
-- so survivors favor roads/buildings over straight lines through woods.
local Routing = rawget(_G, "KnoxTravelRouting") or {}
_G.KnoxTravelRouting = Routing

local ROAD_STAGING_MIN_DISTANCE_SQUARED = 48 * 48
local ROAD_SEARCH_RADIUS = 12

local function safeCall(object, method, ...)
    if object == nil or object[method] == nil then return nil end
    local ok, value = pcall(object[method], object, ...)
    return ok and value or nil
end

function Routing.isRoadLike(square)
    if square == nil then return false end
    if safeCall(square, "canStand") ~= true then return false end
    -- Woods have trees; roads/outdoors do not. Buildings are also good staging.
    if square.HasTree ~= nil then
        local ok, hasTree = pcall(function() return square:HasTree() end)
        if ok and hasTree == true then return false end
    end
    if safeCall(square, "isSolid") == true then return false end
    if safeCall(square, "isSolidTrans") == true then return false end
    return true
end

local function travelScore(square, origin, destination)
    -- Higher is better for staging.
    local score = 0
    if safeCall(square, "isOutside") == true then score = score + 30 end
    if square.getRoom ~= nil then
        local ok, room = pcall(function() return square:getRoom() end)
        if ok and room == nil then score = score + 10 end
    end
    if square.getBuilding ~= nil then
        local ok, building = pcall(function() return square:getBuilding() end)
        if ok and building ~= nil then score = score + 20 end
    end
    -- Prefer squares roughly along the straight line, not detours.
    if origin ~= nil and destination ~= nil then
        local ox, oy = origin:getX(), origin:getY()
        local dx, dy = destination:getX(), destination:getY()
        local sx, sy = square:getX(), square:getY()
        local lineLen2 = (dx - ox) ^ 2 + (dy - oy) ^ 2
        if lineLen2 > 0 then
            local t = ((sx - ox) * (dx - ox) + (sy - oy) * (dy - oy)) / lineLen2
            t = math.max(0, math.min(1, t))
            local px, py = ox + (dx - ox) * t, oy + (dy - oy) * t
            local off2 = (sx - px) ^ 2 + (sy - py) ^ 2
            score = score - math.min(40, off2)
        end
    end
    return score
end

-- Find a road-like staging square near the midpoint of a far trip.
-- Returns nil when the trip is short or no better square is loaded.
function Routing.findRoadWaypoint(origin, destination)
    local cell = getCell ~= nil and getCell() or nil
    if origin == nil or destination == nil or cell == nil then return nil end
    if origin.getZ == nil or destination.getZ == nil then return nil end
    if origin:getZ() ~= destination:getZ() then return nil end
    local dx = destination:getX() - origin:getX()
    local dy = destination:getY() - origin:getY()
    local dist2 = dx * dx + dy * dy
    if dist2 < ROAD_STAGING_MIN_DISTANCE_SQUARED then return nil end
    local z = origin:getZ()
    local midX = math.floor((origin:getX() + destination:getX()) / 2 + 0.5)
    local midY = math.floor((origin:getY() + destination:getY()) / 2 + 0.5)
    local best, bestScore = nil, -math.huge
    for x = midX - ROAD_SEARCH_RADIUS, midX + ROAD_SEARCH_RADIUS do
        for y = midY - ROAD_SEARCH_RADIUS, midY + ROAD_SEARCH_RADIUS do
            local square = cell:getGridSquare(x, y, z)
            if square ~= nil and Routing.isRoadLike(square) then
                -- Staging must itself be reachable in a straight lane check.
                local blocked = false
                if origin.isBlockedTo ~= nil then
                    local ok, isBlocked = pcall(function()
                        return origin:isBlockedTo(square)
                    end)
                    if ok and isBlocked == true then blocked = true end
                end
                if not blocked then
                    local score = travelScore(square, origin, destination)
                    if score > bestScore then
                        best, bestScore = square, score
                    end
                end
            end
        end
    end
    -- Only detour when the staging point is meaningfully better than going
    -- straight; otherwise keep the direct native route.
    if best == nil then return nil end
    return best
end

function Routing.stagingThresholdSquared()
    return ROAD_STAGING_MIN_DISTANCE_SQUARED
end

return Routing
