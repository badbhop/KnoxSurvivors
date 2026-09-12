local Patrol = rawget(_G, "KnoxCompanionPatrol") or {}
_G.KnoxCompanionPatrol = Patrol

local function stableHash(value)
    local result = 5381
    for index = 1, #tostring(value or "") do
        result = (result * 33 + string.byte(tostring(value), index)) % 2147483647
    end
    return result
end

local function boundsOf(directive)
    if type(directive) ~= "table" then return nil end
    local minX = tonumber(directive.minX or directive.x1 or directive.x)
    local minY = tonumber(directive.minY or directive.y1 or directive.y)
    local maxX = tonumber(directive.maxX or directive.x2 or minX)
    local maxY = tonumber(directive.maxY or directive.y2 or minY)
    if minX == nil or minY == nil or maxX == nil or maxY == nil then return nil end
    return math.min(minX, maxX), math.min(minY, maxY),
        math.max(minX, maxX), math.max(minY, maxY), tonumber(directive.z) or 0
end

function Patrol.contains(directive, square)
    local minX, minY, maxX, maxY, z = boundsOf(directive)
    return minX ~= nil and square ~= nil and square:getZ() == z
        and square:getX() >= minX and square:getX() <= maxX
        and square:getY() >= minY and square:getY() <= maxY
end

function Patrol.waypoints(directive)
    local minX, minY, maxX, maxY, z = boundsOf(directive)
    if minX == nil then return {} end
    local insetX = maxX - minX >= 4 and 1 or 0
    local insetY = maxY - minY >= 4 and 1 or 0
    minX, maxX = minX + insetX, maxX - insetX
    minY, maxY = minY + insetY, maxY - insetY
    local candidates = {
        { x = minX, y = minY, z = z },
        { x = maxX, y = minY, z = z },
        { x = maxX, y = maxY, z = z },
        { x = minX, y = maxY, z = z },
    }
    local points, seen = {}, {}
    for _, point in ipairs(candidates) do
        local key = tostring(point.x) .. ":" .. tostring(point.y) .. ":" .. tostring(point.z)
        if not seen[key] then
            seen[key] = true
            points[#points + 1] = point
        end
    end
    return points
end

function Patrol.waypointForStep(directive, survivorId, step)
    local points = Patrol.waypoints(directive)
    if #points == 0 then return nil end
    local start = stableHash(survivorId) % #points
    local index = ((start + math.max(0, math.floor(tonumber(step) or 0))) % #points) + 1
    return points[index], #points
end

-- Guard and patrol share the same area geometry but not the same intent. A
-- guard owns one repeatable post; a patrol advances around the route.
function Patrol.guardPost(directive, survivorId)
    return Patrol.waypointForStep(directive, survivorId, 0)
end

function Patrol.recordTaskArrival(task)
    if type(task) ~= "table" then return false, 0, 0 end
    local count = #Patrol.waypoints(task.target)
    if count == 0 then return false, 0, 0 end
    local visited = math.max(0, math.floor(tonumber(task.patrolStopsCompleted) or 0)) + 1
    if visited >= count then
        task.patrolStep = 0
        task.patrolStopsCompleted = 0
        return true, 0, count
    end
    task.patrolStopsCompleted = visited
    task.patrolStep = (math.max(0, math.floor(tonumber(task.patrolStep) or 0)) + 1) % count
    return false, task.patrolStep, count
end

function Patrol.nextWaypoint(directive, current, survivorId)
    local points = Patrol.waypoints(directive)
    if #points == 0 or current == nil then return nil end
    local cx = current.getX ~= nil and current:getX() or tonumber(current.x)
    local cy = current.getY ~= nil and current:getY() or tonumber(current.y)
    if cx == nil or cy == nil then return nil end
    local start = stableHash(survivorId) % #points
    local nearest, nearestDistance = nil, math.huge
    for offset = 0, #points - 1 do
        local index = ((start + offset) % #points) + 1
        local point = points[index]
        local distance = (point.x - cx) ^ 2 + (point.y - cy) ^ 2
        if distance < nearestDistance then
            nearest, nearestDistance = index, distance
        end
    end
    if nearestDistance <= 2.25 then nearest = (nearest % #points) + 1 end
    return points[nearest]
end

return Patrol
