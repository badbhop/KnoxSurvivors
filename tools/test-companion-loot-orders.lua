local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end
local squareObjects = {}
local originSquare = {
    getX = function() return 50 end, getY = function() return 50 end, getZ = function() return 0 end,
    getObjects = function() return list(squareObjects) end,
    canStand = function() return true end, getRoom = function() return nil end,
    getBuilding = function() return nil end,
}
local lootItem = {}
local lootContainer = {
    isExistYet = function() return true end,
    getSourceGrid = function() return originSquare end,
}
local worldObject = {
    getContainerCount = function() return 1 end,
    getContainerByIndex = function() return lootContainer end,
    getSquare = function() return originSquare end,
}
local actor = { getCurrentSquare = function() return originSquare end }
squareObjects[1] = worldObject
getCell = function()
    return { getGridSquare = function() return originSquare end }
end
instanceof = function(object, class) return false end
AdjacentFreeTileFinder = { Find = function() return originSquare end }
KnoxSurvivorLooting = { plan = function() return { { item = lootItem } } end }
KnoxActivityFeed = { speak = function() end, event = function() end }

local function companion()
    local c = setmetatable({
        id = "comp-1",
        character = actor,
        state = "IDLE",
        nextThink = 0,
        nextThreatScan = 100000,
        nextExplorationSearch = 0,
        directiveMisses = 0,
        inspectedContainers = {},
        blockedAreas = {},
        recentRoamGoals = {},
        reservations = { threats = {}, items = {}, containers = {}, restSpots = {} },
        bridge = {
            moveNpc = function() return "MOVE_STARTED" end,
            moveNpcWithPace = function() return "MOVE_STARTED" end,
            cancelNpcMove = function() end,
        },
    }, Controller)
    return c
end

-- Loot area: a container in the box must dispatch the survivor.
local c = companion()
local directive = { kind = "loot_area", minX = 0, minY = 0, maxX = 100, maxY = 100, z = 0 }
assert(c:beginExploration(100, directive) == true, "loot_area must dispatch to a real container")
assert(c.state == "MOVING_TO_EXPLORE")

-- Loot bodies: only corpse objects match.
worldObject.__corpse = false
instanceof = function(object, class)
    return class == "IsoDeadBody" and object.__corpse == true or false
end
c = companion()
local bodies = { kind = "loot_corpses", minX = 0, minY = 0, maxX = 100, maxY = 100, z = 0 }
assert(c:beginExploration(200, bodies) == false, "no corpses means no dispatch, not an error")
worldObject.__corpse = true
c = companion()
assert(c:beginExploration(300, bodies) == true, "loot_corpses must dispatch to a dead body")
assert(c.state == "MOVING_TO_EXPLORE")

-- Uniform split: a second survivor never takes the claimed container.
c = companion()
local claimed = c:beginExploration(400, directive)
assert(claimed == true)
local c2 = companion()
c2.id = "comp-2"
c2.reservations = c.reservations
c2.nextExplorationSearch = 0
assert(c2:beginExploration(400, directive) == false,
    "the second looter must pick another container, not the claimed one")

print("Companion loot orders PASS area=true bodies=true split=true")
