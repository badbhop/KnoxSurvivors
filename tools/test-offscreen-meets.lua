local rootPath = arg[1] or "."

require = function()
    return true
end

_G.KnoxSurvivorRelationships = nil
local worldAge = 72
local records = {}
local dispositions = {}
local groupMap = {}
local ledgers = {}

local function key(firstId, secondId)
    return firstId < secondId and firstId .. "::" .. secondId
        or secondId .. "::" .. firstId
end

KnoxSettings = {
    allowHostileEncounters = function() return true end,
    allowNPCFactions = function() return false end,
}
local feedEvents = {}
KnoxActivityFeed = {
    speak = function() end,
    event = function(text) feedEvents[#feedEvents + 1] = text end,
}
KnoxPersistence = {
    getSurvivorAffiliation = function()
        return { kind = "independent" }
    end,
    getSurvivorDuty = function() return { mode = "autonomous" } end,
    getTravelGroupFor = function(id) return groupMap[id] end,
    getSurvivorIdentity = function(id)
        return { forename = id, surname = "Tester", sociability = 50, aggression = 20 }
    end,
    ensureSurvivorIdentity = function() end,
    getSurvivorDisposition = function(firstId, secondId)
        return dispositions[key(firstId, secondId)] or "neutral"
    end,
    getRelationship = function(firstId, secondId)
        return records[key(firstId, secondId)]
    end,
    recordEncounter = function(firstId, secondId, observation)
        local recordKey = key(firstId, secondId)
        local record = records[recordKey] or {
            meetings = 0, nearbyHours = 0, sharedRoam = 0, sharedLoot = 0, sharedCombat = 0,
        }
        if observation.began then record.meetings = record.meetings + 1 end
        record.nearbyHours = record.nearbyHours + (observation.nearbyHours or 0)
        record.sharedRoam = record.sharedRoam + (observation.sharedRoam or 0)
        record.sharedLoot = record.sharedLoot + (observation.sharedLoot or 0)
        record.sharedCombat = record.sharedCombat + (observation.sharedCombat or 0)
        records[recordKey] = record
        return record
    end,
    setRelationshipDisposition = function(firstId, secondId, disposition, nextHours)
        local recordKey = key(firstId, secondId)
        local record = records[recordKey] or { meetings = 0 }
        record.disposition = disposition
        record.nextEncounterHours = nextHours
        records[recordKey] = record
        dispositions[recordKey] = disposition == "hostile" and "hostile" or "neutral"
        return record
    end,
    escalateSurvivorConflict = function()
        return true, "failed"
    end,
    areSurvivorsAllied = function() return false end,
    getUnloadedSurvivalState = function(id) return ledgers[id] end,
    setUnloadedSurvivalState = function(id, state) ledgers[id] = state return true end,
}
getGameTime = function()
    return { getWorldAgeHours = function() return worldAge end }
end

assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_SurvivorRelationships.lua"))()
local Relationships = assert(KnoxSurvivorRelationships)

local function flag(id, with, kind, atHours)
    ledgers[id] = {
        status = "hibernated",
        pendingMeet = { with = with, kind = kind, atHours = atHours },
    }
end

-- Mapping: fresh mutual intents resolve, stale/unknown/missing do not.
flag("a", "b", "rob", worldAge - 1)
flag("b", "a", "rob", worldAge - 1)
assert(Relationships.pendingMeetOutcome("a", "b", worldAge) == "hostile", "rob forces hostile")
flag("c", "d", "tail", worldAge - 1)
flag("d", "c", "tail", worldAge - 1)
assert(Relationships.pendingMeetOutcome("c", "d", worldAge) == "lure", "tail forces ambush")
flag("e", "f", "befriend", worldAge - 1)
assert(Relationships.pendingMeetOutcome("e", "f", worldAge) == "greet", "befriend resolves warm")
flag("g", "h", "greet", worldAge - 1)
assert(Relationships.pendingMeetOutcome("g", "h", worldAge) == "greet", "greet resolves warm")
flag("old-a", "old-b", "rob", worldAge - 73)
flag("old-b", "old-a", "rob", worldAge - 73)
assert(Relationships.pendingMeetOutcome("old-a", "old-b", worldAge) == nil, "stale intents expire")
flag("weird-a", "weird-b", "dance", worldAge - 1)
assert(Relationships.pendingMeetOutcome("weird-a", "weird-b", worldAge) == nil, "unknown kinds resolve nothing")
assert(Relationships.pendingMeetOutcome("nobody", "nowhere", worldAge) == nil, "missing ledgers resolve nothing")
assert(Relationships.pendingMeetOutcome(nil, "b", worldAge) == nil, "missing ids resolve nothing")
print("Pending outcome mapping PASS")

-- One-sided flags still count: either materializing survivor carries intent.
flag("solo-a", "solo-b", "greet", worldAge - 1)
assert(Relationships.pendingMeetOutcome("solo-a", "solo-b", worldAge) == "greet", "one-sided intent counts")
print("Pending one-sided PASS")

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z or 0 end,
    }
end

local function character(x, y, z)
    local current = square(x, y, z)
    return {
        getCurrentSquare = function() return current end,
        getX = function() return current:getX() end,
        getY = function() return current:getY() end,
        CanSee = function() return true end,
        faceLocationF = function() end,
        isDead = function() return false end,
        getDescriptor = function()
            return { getForename = function() return "Test" end,
                getSurname = function() return "Human" end }
        end,
    }
end

local function controller(id, x, y)
    local result = {
        id = id,
        character = character(x, y),
        state = "IDLE",
        counts = { roam = 0, groupTravel = 0, loot = 0, combat = 0 },
        interrupts = 0,
        resumes = 0,
    }
    function result:clearGroupLeader() end
    function result:setGroupLeader() end
    function result:setGroupMembers() end
    function result:setGroupObjective() end
    function result:registerAllyDefenseThreat() end
    function result:canInterruptForMeeting()
        return self.state == "IDLE"
    end
    function result:interruptForMeeting()
        self.interrupts = self.interrupts + 1
        self.state = "MEETING_WAIT"
        return true
    end
    function result:beginMeetingApproach()
        self.state = "MEETING_APPROACH"
        return true
    end
    function result:beginGreeting()
        self.state = "GREETING"
    end
    function result:resumeAfterGreeting()
        self.resumes = self.resumes + 1
        self.state = "IDLE"
    end
    function result:holdForRobbery() self.held = true end
    function result:releaseRobberyHold() self.held = false self.released = true end
    function result:beginRobbery() return false end
    return result
end

-- End to end: a befriend intent becomes a warm loaded greeting.
flag("walker-a", "walker-b", "befriend", worldAge - 1)
flag("walker-b", "walker-a", "befriend", worldAge - 1)
local walkers = {
    ["walker-a"] = controller("walker-a", 0, 0),
    ["walker-b"] = controller("walker-b", 3, 0),
}
Relationships.observe(walkers, { "walker-a", "walker-b" }, 0)
Relationships.coordinate(walkers, { "walker-a", "walker-b" }, 1)
walkers["walker-a"].state = "MEETING_READY"
Relationships.coordinate(walkers, { "walker-a", "walker-b" }, 2)
Relationships.coordinate(walkers, { "walker-a", "walker-b" }, 100)
Relationships.coordinate(walkers, { "walker-a", "walker-b" }, 250)
assert(walkers["walker-a"].resumes == 1 and walkers["walker-b"].resumes == 1,
    "befriend intent resolves to a completed greeting")
assert(ledgers["walker-a"].pendingMeet == nil and ledgers["walker-b"].pendingMeet == nil,
    "consumed intents clear from both ledgers")
local greetRecord = assert(records[key("walker-a", "walker-b")], "greeting writes relationship record")
assert(greetRecord.disposition == "neutral", "befriend greeting stays neutral")
print("Pending greet end-to-end PASS")

-- End to end: a rob intent becomes a hostile robbery attempt, no transfer
-- happens here because the stubbed controllers decline the native action.
flag("raider-a", "mark-b", "rob", worldAge - 1)
flag("mark-b", "raider-a", "rob", worldAge - 1)
local raiders = {
    ["raider-a"] = controller("raider-a", 10, 0),
    ["mark-b"] = controller("mark-b", 13, 0),
}
Relationships.observe(raiders, { "raider-a", "mark-b" }, 0)
Relationships.coordinate(raiders, { "raider-a", "mark-b" }, 1)
raiders["raider-a"].state = "MEETING_READY"
Relationships.coordinate(raiders, { "raider-a", "mark-b" }, 2)
Relationships.coordinate(raiders, { "raider-a", "mark-b" }, 100)
Relationships.coordinate(raiders, { "raider-a", "mark-b" }, 300)
assert(raiders["raider-a"].resumes == 1, "rob intent releases the aggressor")
assert(raiders["mark-b"].released == true, "rob intent releases the victim hold")
assert(ledgers["raider-a"].pendingMeet == nil, "rob intent consumed")
local hostileFeed = false
for _, text in ipairs(feedEvents) do
    if string.find(text, "hostile", 1, true) then hostileFeed = true break end
end
assert(hostileFeed, "hostile resolution announces itself")
print("Pending rob end-to-end PASS")

print("Offscreen meets PASS mapping=true onesided=true greet=true rob=true")
