local root = arg[1] or "."
require = function() return true end

local occupied = {}
local function collection(count)
    return { size = function() return count or 0 end }
end
local function square(x, y, z, indoors)
    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z or 0 end,
        getRoom = function() return indoors and {} or nil end,
        getBuilding = function() return indoors and "home" or nil end,
        getMovingObjects = function() return collection(occupied[key] and 1 or 0) end,
        canStand = function() return true end,
    }
end

local squares = {}
for x = 10, 13 do
    for y = 10, 13 do
        squares[x .. ":" .. y .. ":0"] = square(x, y, 0, true)
    end
end
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            return squares[x .. ":" .. y .. ":" .. (z or 0)]
        end,
    }
end
KnoxBaseManager = {
    containsSquare = function(_, value)
        return value ~= nil and value:getX() >= 10 and value:getX() <= 13
            and value:getY() >= 10 and value:getY() <= 13
    end,
}

assert(loadfile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"))()
local Controller = assert(KnoxAutonomyController)
local reservations = { ambientSpots = {} }
local moves = {}
local base = {
    id = "base-1",
    home = { x = 9, y = 9, z = 0, minX = 10, minY = 10, width = 4, height = 4 },
    territory = { minX = 8, minY = 8, maxX = 15, maxY = 15 },
}

local function resident(id)
    local character = {
        getCurrentSquare = function() return square(8, 8, 0, false) end,
        isSitOnGround = function() return false end,
        isSittingOnFurniture = function() return false end,
    }
    return setmetatable({
        id = id,
        character = character,
        baseId = base.id,
        base = base,
        reservations = reservations,
        bridge = {
            moveNpcWithPace = function(_, survivorId, target)
                moves[survivorId] = target
                return "MOVE_STARTED"
            end,
            cancelNpcMove = function() end,
        },
        state = "IDLE",
        nextThink = 0,
    }, Controller)
end

local first = resident("resident-1")
local second = resident("resident-2")
assert(first:beginBaseMovement(100, true), "first resident must start return")
assert(second:beginBaseMovement(100, true), "second resident must start return")
assert(moves["resident-1"] ~= nil and moves["resident-2"] ~= nil,
    "both residents must receive an arrival destination")
assert(moves["resident-1"] ~= moves["resident-2"],
    "simultaneous residents must reserve different arrival squares")
assert(moves["resident-1"]:getRoom() ~= nil and moves["resident-2"]:getRoom() ~= nil,
    "base return must prefer indoor home squares over the exterior scout anchor")

local assigned = resident("resident-3")
assigned.baseId = nil
assigned.base = nil
assigned.interruptForDirective = function(self)
    self.state = "IDLE"
    self.nextThink = 0
    return true
end
assigned:setBaseAssignment(base.id, base)
assert(assigned.settlementArrivalPending == true and assigned.nextAmbientMoveAt == 0,
    "new base residents must receive an immediate one-time dispersal intent")

print("Base arrival PASS distinct=true indoor=true dispersal=true")
