local projectRoot = arg[1] or "."

require = function()
    return true
end

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return true end,
    }
end

local cell = {
    getGridSquare = function(_, x, y, z)
        return square(x, y, z)
    end,
}
getCell = function()
    return cell
end
ZombRand = function()
    return 0
end

AdjacentFreeTileFinder = {
    Find = function(target)
        return target
    end,
}
KnoxActivityFeed = {
    speak = function() end,
}
KnoxPersistence = {
    captureActiveSurvivor = function() end,
}

local controllerPath = projectRoot
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
assert(loadfile(controllerPath))()
local Controller = assert(KnoxAutonomyController)

local threat = {}
local owners = { survivor = true }
local combatController = setmetatable({
    id = "survivor",
    reservations = { threats = { [threat] = owners } },
    combatTarget = threat,
}, Controller)
local originalNext = next
next = nil
combatController:releaseCombat()
next = originalNext
assert(combatController.combatTarget == nil, "combat target released")
assert(combatController.reservations.threats[threat] == nil,
    "empty reservation removed without global next")

local leaderSquare = square(10, 10, 0)
local leader = {
    getX = function() return 10.5 end,
    getY = function() return 10.5 end,
    getCurrentSquare = function() return leaderSquare end,
    getForwardDirectionX = function() return 1 end,
    getForwardDirectionY = function() return 0 end,
}
local follower = {
    getX = function() return 0.5 end,
    getY = function() return 0.5 end,
    getCurrentSquare = function() return square(0, 0, 0) end,
}
local captured = {}
local bridge = {
    moveNpc = function(_, id, target)
        captured[id] = target
        return "MOVE_STARTED"
    end,
    moveNpcWithPace = function(_, id, target, pace)
        captured[id] = target
        captured[id .. ":pace"] = pace
        return "MOVE_STARTED"
    end,
    cancelNpcMove = function() return true end,
}

local function followerController(id, slot)
    return setmetatable({
        id = id,
        character = follower,
        bridge = bridge,
        groupLeader = leader,
        groupFormationSlot = slot,
        groupMembers = {},
        nextFormationRefresh = 0,
        nextThink = 0,
        formationFailureCount = 0,
        failureReasons = {},
        counts = { failures = 0 },
    }, Controller)
end

local left = followerController("left", 1)
local right = followerController("right", 2)
assert(left:beginGroupFollow(10), "left formation movement")
assert(right:beginGroupFollow(10), "right formation movement")
assert(captured.left:getX() == 9 and captured.left:getY() == 9,
    "left follower receives back-left slot")
assert(captured.right:getX() == 9 and captured.right:getY() == 11,
    "right follower receives back-right slot")
assert(captured["left:pace"] == "sprint",
    "distant follower requests sprint catch-up")

leaderSquare = square(12, 10, 0)
assert(left:refreshFormationFollow(60), "moving leader refreshes formation path")
assert(captured.left:getX() == 11 and captured.left:getY() == 9,
    "formation destination follows moving leader")

local originalMoveWithPace = bridge.moveNpcWithPace
local cancelCount = 0
bridge.cancelNpcMove = function()
    cancelCount = cancelCount + 1
    return true
end
bridge.moveNpcWithPace = function()
    return "MOVE_ALREADY_REQUESTED"
end
leaderSquare = square(14, 10, 0)
assert(left:refreshFormationFollow(120),
    "failed formation refresh is consumed")
assert(left.state == "GROUP_WAIT", "failed formation enters bounded wait")
assert(left.nextThink >= 300,
    "failed formation keeps full route cooldown")
assert(left.formationFailureCount == 1 and cancelCount > 0,
    "failed formation cancels stale owner and records retry")

left:finishDecision(120)
assert(left.nextThink >= 300,
    "group fast refresh cannot overwrite a recorded failure cooldown")

bridge.moveNpcWithPace = originalMoveWithPace

local droppedCorpse = false
local clearedActions = false
KnoxBaseCorpseHandling = {
    isDragging = function() return true end,
}
KnoxBaseTaskBoard = {
    finish = function()
        return {}, "complete"
    end,
}
ISTimedActionQueue = {
    clear = function() clearedActions = true end,
}
local corpseCharacter = {
    getCharacterActions = function()
        return { isEmpty = function() return false end }
    end,
    setDoGrappleLetGo = function()
        droppedCorpse = true
    end,
}
local corpseController = setmetatable({
    id = "corpse-worker",
    character = corpseCharacter,
    bridge = bridge,
    baseId = "base-1",
    baseTask = { id = "corpse-task", baseId = "base-1", type = "haul_corpse" },
}, Controller)
assert(corpseController:abandonBaseTask("combat_interrupt"),
    "interrupted corpse task should be closed")
assert(clearedActions and droppedCorpse,
    "interruption should clear actions and release a dragged corpse")

print("Autonomy formation PASS release=true slots=true refresh=true corpse_interrupt=true")
