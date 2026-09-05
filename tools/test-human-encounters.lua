local rootPath = arg[1] or "."

require = function()
    return true
end

_G.KnoxSurvivorRelationships = nil
local worldAge = 72
local records = {}
local dispositions = {}
local groupMap = {}
local affiliationMap = {}
local dutyMap = {}

local function key(firstId, secondId)
    return firstId < secondId and firstId .. "::" .. secondId
        or secondId .. "::" .. firstId
end

KnoxSettings = {
    allowHostileEncounters = function() return false end,
    allowNPCFactions = function() return false end,
}
KnoxActivityFeed = {
    speak = function() end,
    event = function() end,
}
KnoxPersistence = {
    getSurvivorAffiliation = function(id)
        return affiliationMap[id] or { kind = "independent" }
    end,
    getSurvivorDuty = function(id)
        return dutyMap[id] or { mode = "autonomous" }
    end,
    getTravelGroupFor = function(id) return groupMap[id] end,
    getTravelGroupObjective = function() return nil end,
    setTravelGroupObjective = function() end,
    clearTravelGroupObjective = function() end,
    getSurvivorIdentity = function(id)
        return { forename = id, surname = "Tester", sociability = 85, aggression = 0 }
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
            meetings = 0,
            nearbyHours = 0,
            sharedRoam = 0,
            sharedLoot = 0,
            sharedCombat = 0,
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
}
getGameTime = function()
    return { getWorldAgeHours = function() return worldAge end }
end

assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_SurvivorRelationships.lua"))()
local Relationships = assert(KnoxSurvivorRelationships)

dispositions[key("ally-a", "ally-b")] = "allied"
dispositions[key("hostile-a", "hostile-b")] = "hostile"
assert(Relationships.classifyEncounter("ally-a", "ally-b") == "allied")
assert(Relationships.classifyEncounter("neutral-a", "neutral-b") == "neutral")
assert(Relationships.classifyEncounter("hostile-a", "hostile-b") == "hostile")
assert(Relationships.decideEncounterOutcome("hostile-a", "hostile-b", {}) == "avoid_hostile",
    "known hostile survivors must not re-enter friendly greeting flow")

local firstId, secondId
for first = 1, 30 do
    for second = first + 1, 30 do
        local candidateFirst = "neutral-" .. first
        local candidateSecond = "neutral-" .. second
        if Relationships.decideEncounterOutcome(candidateFirst, candidateSecond, {
            meetings = 1,
        }) == "greet" then
            firstId, secondId = candidateFirst, candidateSecond
            break
        end
    end
    if firstId ~= nil then break end
end
assert(firstId ~= nil, "test must locate a deterministic cautious greeting pair")
assert(Relationships.decideEncounterOutcome(firstId, secondId, { meetings = 1 }) == "greet",
    "first neutral contact may greet but must not force a group")

-- An established faction leader must be able to recruit an eligible loner on
-- first contact. Requiring prior shared activity here would make growth
-- unreachable because the loner cannot share activity before joining.
groupMap["faction-leader"] = {
    id = "travel-group-faction", factionId = "faction-1",
    memberIds = { "faction-leader", "faction-member", "faction-third" },
}
local recruitLeader, recruitLoner
for first = 1, 60 do
    for second = 1, 60 do
        local candidateLeader = "faction-leader"
        local candidateLoner = "faction-loner-" .. first .. "-" .. second
        if Relationships.decideEncounterOutcome(candidateLeader, candidateLoner, {}) == "join" then
            recruitLeader, recruitLoner = candidateLeader, candidateLoner
            break
        end
    end
    if recruitLeader ~= nil then break end
end
assert(recruitLeader ~= nil and recruitLoner ~= nil,
    "faction leader must have a bounded first-contact recruitment path")
groupMap["faction-leader"].recruitmentNextHours = worldAge + 12
assert(Relationships.decideEncounterOutcome("faction-leader", "faction-cooldown-loner", {}) ~= "join",
    "faction recruitment cooldown suppresses immediate chain recruitment")
assert(Relationships.isEncounterCooldownComplete({ nextEncounterHours = 73 }, 72) == false)
assert(Relationships.isEncounterCooldownComplete({ nextEncounterHours = 73 }, 73) == true)

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z or 0 end,
    }
end

local function character(x, y, z)
    local current = square(x, y, z)
    local result = {
        visible = true,
        getCurrentSquare = function() return current end,
        getX = function() return current:getX() end,
        getY = function() return current:getY() end,
        CanSee = function(self) return self.visible end,
        faceLocationF = function() end,
        getDescriptor = function()
            return { getForename = function() return "Test" end,
                getSurname = function() return "Human" end }
        end,
    }
    return result
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
    function result:canInterruptForMeeting()
        return self.state == "IDLE" or self.state == "BASE_IDLE"
            or self.state == "BASE_AMBIENT_REST"
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
    function result:holdForRobbery() end
    function result:beginRobbery() return false end
    return result
end

local thirdId = "neutral-third"
local controllers = {
    [firstId] = controller(firstId, 0, 0),
    [secondId] = controller(secondId, 3, 0),
    [thirdId] = controller(thirdId, 4, 0),
}
local ids = { firstId, secondId, thirdId }

local hiddenFirst = character(0, 0)
local hiddenSecond = character(3, 0)
hiddenFirst.visible = false
hiddenSecond.visible = false
assert(not Relationships.canPerceiveHuman(hiddenFirst, hiddenSecond),
    "near humans separated by blocked native LOS are not perceived")
assert(not Relationships.canPerceiveHuman(character(0, 0, 0), character(0, 0, 1)),
    "humans on different floors are not perceived as adjacent")
assert(Relationships.canPerceiveHuman(character(0, 0, 0), character(30, 0, 0)),
    "same-floor humans within the bounded contact radius can be perceived")

Relationships.observe(controllers, ids, 0)
Relationships.coordinate(controllers, ids, 1)
assert(controllers[firstId].interrupts + controllers[secondId].interrupts == 2,
    "one cautious encounter owns exactly two controllers")
assert(controllers[thirdId].interrupts == 0,
    "one survivor cannot queue a second simultaneous greeting")

controllers[firstId].state = "MEETING_READY"
Relationships.coordinate(controllers, ids, 2)
Relationships.coordinate(controllers, ids, 100)
Relationships.coordinate(controllers, ids, 250)
local record = assert(records[key(firstId, secondId)])
assert(record.disposition == "neutral" and record.nextEncounterHours > worldAge,
    "completed greeting remains neutral and receives a bounded cooldown")
assert(controllers[firstId].resumes == 1 and controllers[secondId].resumes == 1,
    "completed greeting restores normal controller ownership")
Relationships.observe(controllers, { firstId, secondId }, 300)
Relationships.coordinate(controllers, { firstId, secondId }, 301)
assert(controllers[firstId].interrupts + controllers[secondId].interrupts == 2,
    "greeting cooldown prevents repeat social approach spam")

Relationships.resetRuntime()
records = {}
local hostileFirst, hostileSecond = "hostile-a", "hostile-b"
local hostileControllers = {
    [hostileFirst] = controller(hostileFirst, 0, 0),
    [hostileSecond] = controller(hostileSecond, 3, 0),
}
Relationships.observe(hostileControllers, { hostileFirst, hostileSecond }, 0)
assert(hostileControllers[hostileFirst].interrupts == 0
        and hostileControllers[hostileSecond].interrupts == 0,
    "known hostility suppresses social approach until native human combat exists")
assert(records[key(hostileFirst, hostileSecond)].disposition == "hostile",
    "hostile state remains persistent while social contact is suppressed")

-- Leaders from two established groups may meet, but a social encounter must
-- not manufacture an invalid joinGroupId/lonerId pair or merge the groups.
Relationships.resetRuntime()
records = {}
groupMap = {
    ["group-a"] = { id = "travel-a", leaderId = "group-a", memberIds = { "group-a" } },
    ["group-b"] = { id = "travel-b", leaderId = "group-b", memberIds = { "group-b" } },
}
local groupFirst, groupSecond
for first = 1, 30 do
    for second = first + 1, 30 do
        local candidateFirst = "group-a-" .. first
        local candidateSecond = "group-b-" .. second
        groupMap[candidateFirst] = {
            id = "travel-a", leaderId = candidateFirst, memberIds = { candidateFirst },
        }
        groupMap[candidateSecond] = {
            id = "travel-b", leaderId = candidateSecond, memberIds = { candidateSecond },
        }
        if Relationships.decideEncounterOutcome(candidateFirst, candidateSecond, {}) == "greet" then
            groupFirst, groupSecond = candidateFirst, candidateSecond
            break
        end
    end
    if groupFirst ~= nil then break end
end
assert(groupFirst ~= nil, "test must locate a deterministic group greeting pair")
local groupControllers = {
    [groupFirst] = controller(groupFirst, 0, 0),
    [groupSecond] = controller(groupSecond, 3, 0),
}
Relationships.observe(groupControllers, { groupFirst, groupSecond }, 0)
Relationships.coordinate(groupControllers, { groupFirst, groupSecond }, 1)
assert(groupControllers[groupFirst].interrupts + groupControllers[groupSecond].interrupts == 2,
    "different group leaders can own one bounded social encounter")
groupControllers[groupFirst].state = "MEETING_READY"
Relationships.coordinate(groupControllers, { groupFirst, groupSecond }, 250)
assert(groupMap[groupFirst].id == "travel-a" and groupMap[groupSecond].id == "travel-b",
    "group-to-group greeting does not merge established travel groups")

-- NPC faction residents can make human contact only while their base duty is
-- genuinely idle; active work and player-owned companions remain protected.
Relationships.resetRuntime()
records = {}
affiliationMap = {
    ["base-a"] = { kind = "faction", factionId = "faction-a" },
    ["base-b"] = { kind = "faction", factionId = "faction-b" },
    ["player-companion"] = { kind = "player", playerId = "player-1" },
}
dutyMap = {
    ["base-a"] = { mode = "base" },
    ["base-b"] = { mode = "base" },
    ["player-companion"] = { mode = "companion" },
}
local baseControllers = {
    ["base-a"] = controller("base-a", 0, 0),
    ["base-b"] = controller("base-b", 3, 0),
}
baseControllers["base-a"].state = "BASE_IDLE"
baseControllers["base-b"].state = "BASE_AMBIENT_REST"
Relationships.observe(baseControllers, { "base-a", "base-b" }, 0)
Relationships.coordinate(baseControllers, { "base-a", "base-b" }, 1)
assert(baseControllers["base-a"].interrupts + baseControllers["base-b"].interrupts == 2,
    "idle NPC faction residents can participate in one bounded encounter")
local activeBase = controller("active-base", 0, 0)
local idleFaction = controller("idle-faction", 3, 0)
activeBase.state = "BASE_TASK_MOVE"
affiliationMap["active-base"] = { kind = "faction", factionId = "faction-a" }
affiliationMap["idle-faction"] = { kind = "faction", factionId = "faction-b" }
dutyMap["active-base"] = { mode = "base" }
dutyMap["idle-faction"] = { mode = "base" }
local activeControllers = { ["active-base"] = activeBase, ["idle-faction"] = idleFaction }
Relationships.observe(activeControllers, { "active-base", "idle-faction" }, 0)
assert(activeBase.interrupts == 0 and idleFaction.interrupts == 0,
    "active base work is not pulled into social encounters")

print("Human encounters PASS classify=true los=true floors=true cautious=true cooldown=true single_owner=true resume=true hostile_suppressed=true")
