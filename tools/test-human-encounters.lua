local rootPath = arg[1] or "."

require = function()
    return true
end

_G.KnoxSurvivorRelationships = nil
local worldAge = 72
local records = {}
local dispositions = {}

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
    getSurvivorAffiliation = function() return { kind = "independent" } end,
    getSurvivorDuty = function() return { mode = "autonomous" } end,
    getTravelGroupFor = function() return nil end,
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
    function result:setGroupMembers() end
    function result:canInterruptForMeeting() return self.state == "IDLE" end
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

print("Human encounters PASS classify=true los=true floors=true cautious=true cooldown=true single_owner=true resume=true hostile_suppressed=true")
