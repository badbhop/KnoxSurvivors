local projectRoot = arg[1] or "."

require = function()
    return true
end

ZombRand = function()
    return 0
end

local bedObject = {
    getObjectIndex = function() return 3 end,
    getProperties = function()
        return { get = function(_, key)
            if key == "BedType" then return "goodBed" end
            return nil
        end }
    end,
    isFurnitureOccupied = function() return false end,
}
local crateObject = {
    getObjectIndex = function() return 7 end,
    getProperties = function()
        return { get = function() return nil end }
    end,
    isFurnitureOccupied = function() return false end,
}
local function objectsFor(list)
    return {
        size = function() return #list end,
        get = function(_, index) return list[index + 1] end,
    }
end
local bedSquare = {
    getX = function() return 10 end,
    getY = function() return 10 end,
    getZ = function() return 0 end,
    getObjects = function() return objectsFor({ bedObject, crateObject }) end,
}
local homeSquare = {
    getX = function() return 0 end,
    getY = function() return 0 end,
    getZ = function() return 0 end,
    getObjects = function() return objectsFor({}) end,
}
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            if x == 10 and y == 10 and z == 0 then return bedSquare end
            return homeSquare
        end,
    }
end

AdjacentFreeTileFinder = {
    Find = function(target)
        return target
    end,
}
KnoxActivityFeed = {
    speak = function() end,
}
local assignedBed = { x = 10, y = 10, z = 0, objectIndex = 3 }
KnoxPersistence = {
    getSurvivorPolicies = function()
        return { assignedBed = assignedBed }
    end,
}
KnoxSurvivorNeeds = {
    wakeForDanger = function() return false end,
}
KnoxGroupSupport = {
    plan = function() return nil end,
    queue = function() return {}, "queued" end,
    verify = function() return true end,
    mostUrgentNeed = function() return nil end,
}

local controllerPath = projectRoot
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
assert(loadfile(controllerPath))()
local Controller = assert(KnoxAutonomyController)

local function survivor()
    return setmetatable({
        id = "bed-user",
        character = {
            getCurrentSquare = function() return homeSquare end,
        },
        reservations = { threats = {}, items = {}, restSpots = {} },
    }, Controller)
end

-- Assigned bed wins outright.
local spot = survivor():assignedBedSpot(nil)
assert(spot ~= nil and spot.object == bedObject, "assigned bed resolves")
assert(spot.quality ~= nil and spot.quality >= 5, "assigned bed outranks generic")

-- Wrong object index: no match, normal search proceeds.
assignedBed = { x = 10, y = 10, z = 0, objectIndex = 99 }
assert(survivor():assignedBedSpot(nil) == nil, "stale index falls through")

-- Occupied bed: skipped.
assignedBed = { x = 10, y = 10, z = 0, objectIndex = 3 }
bedObject.isFurnitureOccupied = function() return true end
assert(survivor():assignedBedSpot(nil) == nil, "occupied bed falls through")
bedObject.isFurnitureOccupied = function() return false end

-- Territory filter respected.
assert(survivor():assignedBedSpot(function() return false end) == nil,
    "square filter respected")

-- No policy: nothing.
KnoxPersistence.getSurvivorPolicies = function() return {} end
assert(survivor():assignedBedSpot(nil) == nil, "missing policy falls through")

print("Assigned bed rest PASS priority=true stale=true occupied=true filter=true missing=true")
