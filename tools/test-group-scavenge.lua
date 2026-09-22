local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController
local parties = dofile(root .. "/mod/42/media/lua/client/KS_GroupScavenge.lua")

local night = false
KnoxNightShelter = { isNight = function() return night end }
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
KnoxPersistence = {
    isSurvivorAlive = function() return true end,
    getClaimedBaseTaskForSurvivor = function() return nil end,
    getSurvivorDuty = function() return { mode = "base" } end,
}

local function member(state)
    local square = {}
    local c = {
        baseId = "b1",
        base = { ownerKind = "faction" },
        campId = nil,
        character = { getCurrentSquare = function() return square end },
        state = state,
        eventAssignment = nil,
        awayTeamId = nil,
        groupLeaderId = nil,
        groupMembers = {},
        calls = {},
    }
    c.setGroupLeader = function(self, id, char, slot, size, objective)
        self.groupLeaderId = id
        self.calls[#self.calls + 1] = "led-by-" .. tostring(id)
    end
    c.clearGroupLeader = function(self)
        self.groupLeaderId = nil
        self.calls[#self.calls + 1] = "cleared"
    end
    c.setGroupMembers = function(self, members)
        self.calls[#self.calls + 1] = "members-" .. tostring(#members)
    end
    return c
end

local controllers = { a = member("BASE_IDLE"), b = member("BASE_IDLE"), c = member("BASE_TASK_ACTION") }
local ids = { "a", "b", "c" }
parties.coordinate(controllers, ids, 100)
local lease = parties.leases()["base:b1"]
assert(lease ~= nil and lease.leaderId == "a" and lease.followerId == "b",
    "two idle members must pair out while the third works")
assert(controllers.a.scavengeSortieUntilHours == 12)
assert(controllers.b.groupLeaderId == "a")

KnoxSettings={allowNPCFactions=function() return false end}
dofile(root.."/mod/42/media/lua/client/KS_SurvivorRelationships.lua")
local relationships=KnoxSurvivorRelationships
local beforeCalls=#controllers.b.calls
relationships.coordinate(controllers,{"a","b"},160)
assert(controllers.b.groupLeaderId=="a" and #controllers.b.calls==beforeCalls,
    "social group reconciliation must preserve a temporary scavenging formation")

-- Throttle and lease: no second pair while one is out.
parties.coordinate(controllers, ids, 3701)
assert(parties.leases()["base:b1"] ~= nil, "live pair must not be replaced")

-- Nightfall dissolves the pair so members come home.
night = true
parties.coordinate(controllers, ids, 7302)
assert(parties.leases()["base:b1"] == nil, "pairs must dissolve at nightfall")
assert(controllers.b.groupLeaderId == nil)
assert(controllers.a.scavengeSortieUntilHours == nil)

-- In formation, the follower loots nearby containers instead of idling:
-- shared reservations split the building across the pair.
local function tile(x, y)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return 0 end }
end
local leaderChar = { getCurrentSquare = function() return tile(0, 0) end }
local follower = setmetatable({
    id = "follower",
    character = { getCurrentSquare = function() return tile(0, 0) end },
    groupLeader = leaderChar,
    groupLeaderId = "leader",
    groupObjective = { kind = "scavenge", phase = "traveling" },
    nextGroupObjectiveAssist = 0,
    state = "IDLE",
}, Controller)
local assisted = 0
follower.beginExploration = function() assisted = assisted + 1 return true end
assert(follower:followScavengeParty(100) == true)
assert(assisted == 1, "a formed-up follower must help loot the building")
assert(follower:scavengingForSettlement() == true)
local lone = setmetatable({ id = "lone" }, Controller)
assert(lone:scavengingForSettlement() == false)

print("Group scavenge PASS pair-out=true lease=true nightfall=true follower-loot=true")

night=false
KnoxPersistence.getSurvivorDuty=function(id)
    return {mode="base",jobPreference=id=="a" and "guard" or "auto"}
end
parties.coordinate(controllers,ids,11000)
assert(parties.leases()["base:b1"]==nil, "idle guards must not be drafted into scavenging")
KnoxPersistence.getSurvivorDuty=function() return {mode="base",jobPreference="auto"} end
parties.coordinate(controllers,ids,15000)
assert(parties.leases()["base:b1"]~=nil)
KnoxPersistence.isSurvivorAlive=function(id) return id~="a" end
parties.coordinate(controllers,ids,19000)
assert(parties.leases()["base:b1"]==nil and controllers.b.groupLeaderId==nil,
    "leader death dissolves the outing")
KnoxPersistence.isSurvivorAlive=function() return true end
parties.coordinate(controllers,ids,23000)
assert(parties.leases()["base:b1"]~=nil)
parties.coordinate({}, {},27000)
assert(parties.leases()["base:b1"]==nil,"unloaded settlements cannot retain orphaned leases")

-- A departed resident can still have a loaded controller and base duty record
-- during the handoff. Presence must keep that resident out of new sorties.
KnoxPersistence.isSurvivorPresent = function(id) return id ~= "a" end
parties.coordinate(controllers, ids, 31000)
assert(parties.leases()["base:b1"] == nil,
    "departed residents must not be drafted into a scavenging pair")
KnoxPersistence.isSurvivorPresent = function() return true end

-- A resident with an urgent personal need stays home until normal self-care
-- resolves it instead of breaking a new scavenging pair immediately.
local urgent = member("BASE_IDLE")
local urgentCharacter = urgent.character
local urgentControllers = {
    a = urgent,
    b = member("BASE_IDLE"),
    c = member("BASE_TASK_ACTION"),
}
KnoxSurvivorNeeds = {
    decide = function(character)
        return character == urgentCharacter and { kind = "find_food" } or { kind = "roam" }
    end,
}
parties.coordinate(urgentControllers, { "a", "b", "c" }, 31000)
assert(parties.leases()["base:b1"] == nil,
    "urgent needs must keep a resident home instead of forming a sortie")

-- Low endurance is also an urgent need. It must use the same home gate rather
-- than allowing a tired resident to leave and immediately interrupt the pair.
KnoxSurvivorNeeds.decide = function(character)
    return character == urgentCharacter and { kind = "rest" } or { kind = "roam" }
end
parties.coordinate(urgentControllers, { "a", "b", "c" }, 35000)
assert(parties.leases()["base:b1"] == nil,
    "low endurance must keep a resident home until recovery completes")

-- A sortie with no useful loaded destination returns to the safehouse instead
-- of falling through into ordinary random roaming.
KnoxBaseManager = { containsSquare = function() return false end }
local sortie = setmetatable({
    id = "sortie-leader",
    baseId = "b1",
    base = {},
    character = { getCurrentSquare = function() return {} end },
    scavengeSortieUntilHours = 12,
}, Controller)
sortie.beginExploration = function() return false end
sortie.beginBaseMovement = function(self, ticks, returning)
    self.returnedAt = ticks
    self.returning = returning
    return true
end
assert(sortie:runScavengeSortie(32100) == true
    and sortie.returnedAt == 32100 and sortie.returning == true
    and sortie.scavengeSortieReturning == true
    and sortie.scavengeSortieUntilHours == 12,
    "empty settlement sorties must return home")
sortie.character.getCurrentSquare = function() return { returnedHome = true } end
KnoxBaseManager.containsSquare = function() return true end
assert(sortie:runScavengeSortie(32160) == false
    and sortie.scavengeSortieReturning == nil
    and sortie.scavengeSortieUntilHours == nil,
    "arrival must clear the completed sortie state")

-- A failed return route must consume the decision and retry the return rather
-- than falling through into ordinary roaming or unrelated base work.
KnoxBaseManager.containsSquare = function() return false end
local blockedReturn = setmetatable({
    id = "blocked-return",
    baseId = "b1",
    base = {},
    character = { getCurrentSquare = function() return {} end },
    scavengeSortieUntilHours = 10.1,
}, Controller)
blockedReturn.beginExploration = function() return false end
blockedReturn.beginBaseMovement = function(self, ticks, returning)
    self.returnAttempts = (self.returnAttempts or 0) + 1
    return false
end
assert(blockedReturn:runScavengeSortie(32200) == true
    and blockedReturn.scavengeSortieReturning == true
    and blockedReturn.nextThink == 32380,
    "failed sortie returns must install a bounded retry")
local attempts = blockedReturn.returnAttempts
assert(blockedReturn:runScavengeSortie(32260) == true
    and blockedReturn.returnAttempts == attempts,
    "return retry cooldown must prevent immediate route churn")
blockedReturn.beginBaseMovement = function() return true end
assert(blockedReturn:runScavengeSortie(32380) == true
    and blockedReturn.scavengeSortieReturnRetryAt == nil,
    "a recovered return route must clear the retry marker")
KnoxBaseManager.containsSquare = function() return true end
