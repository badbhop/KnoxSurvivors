local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

local function tile(x, y, z)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return z or 0 end }
end
KnoxBaseManager = { containsSquare = function(base, square) return base ~= nil end }
getCell = function()
    return { getGridSquare = function(_, x, y, z) return tile(x, y, z) end }
end
local function controller()
    local moves = 0
    local c = setmetatable({
        id = "resident",
        character = { getCurrentSquare = function() return tile(0, 0, 0) end },
        state = "IDLE",
        baseId = "base-1",
        base = { id = "base-1" },
        baseTask = nil,
        currentTicks = 1000,
        groupMembers = {},
        bridge = { moveNpc = function() moves = moves + 1 return "MOVE_STARTED" end,
            cancelNpcMove = function() end },
    }, Controller)
    c.moveCount = function() return moves end
    return c
end

-- Combat inside home territory raises an alarm with the intruder position.
local c = controller()
assert(c:soundBaseAlarm(tile(10, 10, 0)) == true)
local alarm = Controller.baseAlarmFor("base-1")
assert(alarm ~= nil and alarm.x == 10 and alarm.y == 10 and alarm.untilTick == 2800,
    "alarm must carry the intruder square with a bounded lease")
c.base = nil
assert(c:soundBaseAlarm(tile(10, 10, 0)) == false, "baseless fighters raise no alarm")

-- Off-duty residents converge; the engaged, the tasked, and the nearby hold.
c = controller()
assert(c:answerBaseAlarm(1100) == true)
assert(c.moveCount() == 1 and c.state == "BASE_DEFEND")
c = controller()
c.baseTask = { type = "guard" }
assert(c:answerBaseAlarm(1100) == false, "posted guards keep their posts")
c = controller()
c.character = { getCurrentSquare = function() return tile(11, 10, 0) end }
assert(c:answerBaseAlarm(1100) == false, "residents next to the alarm hold position")
assert(c:answerBaseAlarm(5000) == false, "expired alarms dissolve silently")
assert(Controller.baseAlarmFor("base-1") == nil)

-- Camps rally the same way through their own alarm key.
KnoxFactionCamps = { contains = function() return true end }
local camper = controller()
camper.baseId = nil
camper.base = nil
camper.campId = "camp-1"
camper.camp = { id = "camp-1" }
camper.currentTicks = 1000
assert(camper:soundBaseAlarm(tile(20, 20, 0)) == true)
local campAlarm = Controller.baseAlarmFor("camp:camp-1")
assert(campAlarm ~= nil and campAlarm.untilTick == 2800,
    "camp alarm must carry a real lease, got " .. tostring(campAlarm and campAlarm.untilTick))
local camper2 = controller()
camper2.baseId = nil
camper2.base = nil
camper2.campId = "camp-1"
camper2.camp = { id = "camp-1" }
assert(camper2:answerBaseAlarm(1100) == true, "idle camp members must converge")
assert(camper2.state == "BASE_DEFEND")

print("Base rally PASS alarm=true converge=true posts=true expiry=true camp=true")
