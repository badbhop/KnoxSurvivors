local projectRoot = arg[1] or "."

require = function() return true end
SafeHouse = nil

local definition = {
    getID = function() return "building-1" end,
}
local building = { getDef = function() return definition end }
local function square(x, y, z, inside)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z or 0 end,
        getBuilding = function() return inside == false and nil or building end,
        getRoom = function() return inside == false and nil or {} end,
        canStand = function() return true end,
    }
end

local squares = {}
local cell = {
    getGridSquare = function(_, x, y, z)
        local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
        squares[key] = squares[key] or square(x, y, z, x >= 8 and x <= 12 and y >= 18 and y <= 22)
        return squares[key]
    end,
    getZombieList = function()
        return { size = function() return 0 end, get = function() return nil end }
    end,
}
getCell = function() return cell end
ZombRand = function() return 0 end

KnoxPersistence = {}
assert(loadfile(projectRoot .. "/mod/42/media/lua/client/KS_FactionCamps.lua"))()
local Camps = assert(KnoxFactionCamps)
local camp = {
    id = "camp-1", factionId = "faction-1", buildingId = "building-1",
    x = 10, y = 20, z = 0, minX = 8, minY = 18, maxX = 12, maxY = 22,
    memberIds = { "one", "two" },
}

local first = assert(Camps.positionFor(camp, 1))
local second = assert(Camps.positionFor(camp, 2, function(candidate) return candidate == first end))
assert(first ~= second, "two camp members must not intentionally select one idle square")
assert(Camps.contains(camp, first) and Camps.contains(camp, second),
    "camp positions must remain in the assigned shelter")
assert(Camps.memberSlot(camp, "one") == 1 and Camps.memberSlot(camp, "two") == 2,
    "persistent member order supplies stable occupancy slots")

local assignedCamp = nil
KnoxPersistence.getFactionForSurvivor = function()
    return { id = "faction-1", kind = "npc", leaderId = "one", homeBase = nil }
end
KnoxPersistence.syncFactionCampMembers = function() return camp end
local assignedController = {
    state = "COMBAT",
    setCampAssignment = function(_, campId, value, slot)
        assignedCamp = { id = campId, value = value, slot = slot }
    end,
}
Camps.reconcile({ one = assignedController }, { "one" }, 20)
assert(assignedCamp ~= nil and assignedCamp.id == camp.id
        and assignedCamp.value == camp and assignedCamp.slot == 1,
    "loaded camp members must recognize their persisted shelter even during combat")

AdjacentFreeTileFinder = { Find = function(target) return target end }
ISTimedActionQueue = { clear = function() end }
KnoxSurvivorNeeds = {
    wakeForDanger = function() return false end,
    decide = function() return { kind = "roam" } end,
}
KnoxActivityFeed = { speak = function() end }
KnoxFirearmSupport = {}
assert(loadfile(projectRoot
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"))()
local Controller = assert(KnoxAutonomyController)

assert(Controller.campIdleChoice(0, 1, true)
        ~= Controller.campIdleChoice(0, 2, true),
    "member slots should stagger bounded ambient choices")

local outside = square(30, 30, 0, false)
local character = {
    getCurrentSquare = function() return outside end,
    getCharacterActions = function()
        return { isEmpty = function() return true end }
    end,
    isSitOnGround = function() return false end,
    isSittingOnFurniture = function() return false end,
    setVariable = function() end,
    setIsResting = function() end,
    setBed = function() end,
}
local controller = setmetatable({
    id = "one",
    character = character,
    bridge = {
        moveNpc = function() return "MOVE_STARTED" end,
        cancelNpcMove = function() end,
        resetNpcCombat = function() end,
    },
    reservations = {
        threats = {}, items = {}, containers = {}, restSpots = {}, campPositions = {},
    },
    state = "COMBAT",
    campSlot = 1,
    campPositionCycle = 0,
    counts = { failures = 0 },
    failureReasons = {},
    selfCareRetryAt = {},
}, Controller)

controller:setCampAssignment(camp.id, camp, 1)
assert(controller.campId == camp.id and controller.state == "COMBAT",
    "combat interruption must preserve camp identity")
assert(controller:beginCampMovement(100, true)
        and controller.state == "CAMP_RETURN"
        and controller.campId == camp.id,
    "an away member should retain home intent and begin a native return route")
controller.state = "ROAMING"
controller.campExcursion = true
assert(controller.campId == camp.id,
    "leaving for ordinary survival activity must not delete camp membership")
controller.state = "COMBAT"
controller:clearCampAssignment()
assert(controller.campId == nil and controller.campPosition == nil,
    "camp removal/conversion must release stale runtime ownership")

print("Camp living PASS positions=true stagger=true combat=true return=true cleanup=true")
