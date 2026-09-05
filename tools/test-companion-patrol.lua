local root = arg[1] or "."
local patrol = dofile(root .. "/mod/42/media/lua/client/KS_CompanionPatrol.lua")

local directive = { minX = 0, minY = 0, maxX = 10, maxY = 8, z = 0 }
local points = patrol.waypoints(directive)
assert(#points == 4 and points[1].x == 1 and points[1].y == 1,
    "patrol route should stay inside the selected boundary")
local current = { getX = function() return 1 end, getY = function() return 1 end }
local nextPoint = patrol.nextWaypoint(directive, current, "survivor-a")
assert(nextPoint ~= nil and not (nextPoint.x == 1 and nextPoint.y == 1),
    "arrival should advance to another patrol waypoint")
assert(#patrol.waypoints(nil) == 0 and patrol.nextWaypoint(nil, current, "x") == nil,
    "invalid patrol orders should fail safely")

local baseZone = { x1 = 20, y1 = 30, x2 = 28, y2 = 38, z = 1 }
local basePoints = patrol.waypoints(baseZone)
assert(#basePoints == 4 and basePoints[1].x == 21 and basePoints[1].y == 31,
    "base-zone bounds should use the same inset patrol route")
local visited = {}
for step = 0, 3 do
    local point, count = patrol.waypointForStep(baseZone, "resident-a", step)
    assert(point ~= nil and count == 4 and point.z == 1)
    visited[tostring(point.x) .. ":" .. tostring(point.y)] = true
end
local visitedCount = 0
for _ in pairs(visited) do visitedCount = visitedCount + 1 end
assert(visitedCount == 4, "one patrol cycle should visit four distinct area positions")
local post = patrol.guardPost(baseZone, "resident-a")
local repeatedPost = patrol.guardPost(baseZone, "resident-a")
assert(post ~= nil and repeatedPost.x == post.x and repeatedPost.y == post.y,
    "guard should hold one deterministic post rather than circulate")

local task = { target = baseZone, patrolStep = 0, patrolStopsCompleted = 0 }
for expected = 1, 3 do
    local complete, step, stopCount = patrol.recordTaskArrival(task)
    assert(not complete and step == expected and stopCount == 4
        and task.patrolStopsCompleted == expected,
        "intermediate patrol arrivals should persist route progress")
end
local complete, step, stopCount = patrol.recordTaskArrival(task)
assert(complete and step == 0 and stopCount == 4
    and task.patrolStep == 0 and task.patrolStopsCompleted == 0,
    "a complete patrol cycle should reset its persisted progress")

local tiny = patrol.waypoints({ x1 = 4, y1 = 5, x2 = 4, y2 = 5, z = 0 })
assert(#tiny == 1, "small zones should not create duplicate patrol stops")

local controllerFile = assert(io.open(root
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r"))
local controllerSource = controllerFile:read("*a")
controllerFile:close()
assert(string.find(controllerSource, 'self.state = "BASE_TASK_PATROL_WAIT"', 1, true)
    and string.find(controllerSource, "KnoxCompanionPatrol.recordTaskArrival", 1, true)
    and string.find(controllerSource, "self:beginBaseTaskWorkMove(ticks)", 1, true),
    "base controller must advance, pause, and resume a patrol cycle")
print("companion patrol tests passed")
