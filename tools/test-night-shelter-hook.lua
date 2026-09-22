local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_NightShelter.lua")
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

local hour = 23
getTimeOfDay = function() return hour end
getCell = function() return { getGridSquare = function() return nil end } end
KnoxSurvivorNeeds = { wakeForDanger = function() end }

local function square(room)
    return {
        getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
        canStand = function() return true end, getRoom = function() return room end,
    }
end
local function controller(state, room)
    local moves = 0
    local c = setmetatable({
        id = "drifter",
        character = { getCurrentSquare = function() return square(room) end },
        state = state,
        groupMembers = {},
        bridge = { moveNpc = function() moves = moves + 1 return "MOVE_STARTED" end },
    }, Controller)
    c.moveCount = function() return moves end
    c.recovered = nil
    c.beginRecovery = function(self, kind) self.recovered = kind return true end
    c.decided = false
    c.finishDecision = function(self) self.decided = true end
    return c
end

-- Night outdoors: walk to a roof. findShelter needs a reachable indoor cell.
hour = 23
local refuge = square({ id = "room" })
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        if x == 0 and y == 0 then return refuge end
        return nil
    end }
end
local c = controller("IDLE", nil)
assert(c:beginNightShelter(100) == true)
assert(c.moveCount() == 1 and c.state == "NIGHT_SHELTER_MOVE")

-- Night indoors: sleep till dawn through the normal recovery path.
c = controller("IDLE", { id = "room" })
assert(c:beginNightShelter(200) == true)
assert(c.recovered == "sleep", "sheltered survivors must sleep the night away")
assert(c.shelteredOvernight == true, "shelter sleep must arm the dawn sweep")

-- Already sleeping: hold, do not restart recovery.
c = controller("SLEEPING_RECOVERY", { id = "room" })
assert(c:beginNightShelter(300) == true)
assert(c.recovered == nil)

-- Based life owns the night for residents.
c = controller("IDLE", nil)
c.baseId = "base-1"
assert(c:beginNightShelter(400) == false)

-- Dawn wakes oversleeping drifters so the day resumes.
hour = 8
c = controller("SLEEPING_RECOVERY", { id = "room" })
assert(c:beginNightShelter(500) == true and c.decided == true)
assert((c.nightSweepUntil or 0) > 500, "dawn wake must open the sweep window")

-- Daytime roamers are untouched.
c = controller("IDLE", nil)
assert(c:beginNightShelter(600) == false)

-- A pre-faction leader owns one ordinary group objective. Followers keep
-- formation until indoors, then enter the same recovery path without creating
-- a faction/camp/base record of their own.
hour = 23
local group = { id = "travel-1", leaderId = "leader", memberIds = { "leader", "follower" } }
KnoxPersistence = {
    getTravelGroupFor = function(id) return id == "leader" and group or group end,
    setSurvivorLifeIntent = function() return true end,
    clearSurvivorLifeIntent = function() return true end,
    setTravelGroupObjective = function(_, leaderId, intent)
        group.objective = {}
        for key, value in pairs(intent) do group.objective[key] = value end
        group.objective.leaderId = leaderId
        return true
    end,
    getTravelGroupObjective = function() return group.objective end,
    clearTravelGroupObjective = function() group.objective = nil return true end,
}
local leader = controller("IDLE", nil)
leader.id = "leader"
leader.groupMembers = { {}, {} }
assert(leader:beginNightShelter(700) == true and group.objective ~= nil
    and group.objective.kind == "night_shelter",
    "group leader must publish one temporary shelter objective")
local follower = controller("IDLE", { id = "room" })
follower.id = "follower"
follower.groupLeaderId = "leader"
follower.groupObjective = group.objective
assert(follower:beginNightShelter(710) == true and follower.recovered == "sleep",
    "formed-up follower must recover inside the leader's temporary refuge")

print("Night shelter hook PASS move=true sleep=true hold=true resident-exempt=true dawn-wake=true group=true")
