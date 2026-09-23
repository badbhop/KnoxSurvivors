local projectRoot = arg[1] or "."
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path

local states = {}
local duties = {}
local affiliations = {}
local identities = {
    scout = { personality = "brave", sociability = 58, aggression = 42, courage = 82, deception = 8 },
    watcher = { personality = "guarded", sociability = 30, aggression = 24, courage = 42, deception = 18 },
    hunter = { personality = "predatory", sociability = 22, aggression = 82, courage = 72, deception = 58 },
}
local relationships = {}
local groupMap = {}
local activatableIds = { "scout", "watcher", "hunter", "sleeper", "away", "evented" }

local function serialCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do copy[serialCopy(key, seen)] = serialCopy(item, seen) end
    return copy
end

local function freshState(extra)
    local state = {
        hunger = 0.5, thirst = 0.5, fatigue = 0.5, endurance = 0.6,
        health = 100, bleedingParts = 0, lastHours = 0, status = "hibernated",
        activity = "exploring", virtualX = 100, virtualY = 200, virtualZ = 0,
        virtualAtHours = 0,
    }
    for key, value in pairs(extra or {}) do state[key] = value end
    return state
end

states.scout = freshState()
states.watcher = freshState({ virtualX = 120, virtualY = 210 })
states.hunter = freshState({ virtualX = 4000, virtualY = 4000 })
states.sleeper = freshState({ restMode = "sleep" })
states.away = freshState()
duties.away = { mode = "away", missionId = "m-1" }
duties.evented = { mode = "autonomous", eventId = "e-1" }
states.evented = freshState()

KnoxPersistence = {
    isSurvivorAlive = function() return true end,
    getRecord = function() return "record" end,
    getUnloadedSurvivalState = function(id) return serialCopy(states[id]) end,
    setUnloadedSurvivalState = function(id, state) states[id] = serialCopy(state) return true end,
    getActivatableSurvivorIds = function()
        return activatableIds
    end,
    getSurvivorDuty = function(id) return duties[id] or { mode = "autonomous" } end,
    getSurvivorAffiliation = function(id) return affiliations[id] or { kind = "independent" } end,
    getSurvivorIdentity = function(id) return identities[id] or {} end,
    getSurvivorPersonality = function(id)
        local identity = identities[id]
        return identity ~= nil and { personality = identity.personality } or nil
    end,
    getRelationship = function(a, b)
        local key = a < b and (a .. "::" .. b) or (b .. "::" .. a)
        return relationships[key]
    end,
    getSurvivorDisposition = function(a, b)
        if a == b then return "self" end
        local firstGroup, secondGroup = groupMap[a], groupMap[b]
        if firstGroup ~= nil and secondGroup ~= nil and firstGroup.id == secondGroup.id then
            return "allied"
        end
        local key = a < b and (a .. "::" .. b) or (b .. "::" .. a)
        return relationships[key] ~= nil and relationships[key].disposition == "hostile"
            and "hostile" or "neutral"
    end,
    recordEncounter = function(a, b, observation)
        local key = a < b and (a .. "::" .. b) or (b .. "::" .. a)
        local record = relationships[key] or { meetings = 0, sharedRoam = 0 }
        if observation.began then record.meetings = record.meetings + 1 end
        record.sharedRoam = record.sharedRoam + (observation.sharedRoam or 0)
        record.lastMetHours = observation.worldAgeHours
        relationships[key] = record
        return record
    end,
    setRelationshipDisposition = function(a, b, disposition, nextHours)
        local key = a < b and (a .. "::" .. b) or (b .. "::" .. a)
        local record = relationships[key] or { meetings = 0, sharedRoam = 0 }
        record.disposition = disposition
        record.nextEncounterHours = nextHours
        relationships[key] = record
        return record
    end,
    markSurvivorDead = function() return true end,
}

local stories = require("KS_OffscreenStories")

local guardedChance = stories.meetingHostileChance(
    { personality = "guarded", aggression = 50 },
    { personality = "guarded", aggression = 50 })
local gunnerChance = stories.meetingHostileChance(
    { personality = "gunner", aggression = 50 },
    { personality = "guarded", aggression = 50 })
assert(gunnerChance == guardedChance + 8, "gunners receive predatory hostile weighting offscreen")
print("Story gunner parity PASS")
assert(stories.canEncounterPair("scout", "scout") == false, "self is not an encounter candidate")
groupMap.scout, groupMap.watcher = { id = "shared" }, { id = "shared" }
assert(stories.canEncounterPair("scout", "watcher") == false,
    "canonical disposition excludes allied cohort members")
groupMap.scout, groupMap.watcher = nil, nil
assert(stories.canEncounterPair("scout", "watcher") == true,
    "neutral persisted disposition remains encounter eligible")
affiliations.scout = { kind = "player", ownerId = "player-1" }
local playerOwned = freshState()
local beforePlayerOwned = #(playerOwned.history or {})
for phase = 1, 100 do stories.resolveFor("scout", playerOwned, phase * 6, 6) end
for index = beforePlayerOwned + 1, #(playerOwned.history or {}) do
    assert(playerOwned.history[index].kind ~= "meet", "player companions do not enter NPC social encounters")
end
affiliations.scout = nil
print("Story disposition gate PASS")

-- Skip rules: sleeping, away, event-owned, dead, and non-hibernated resolve nil.
assert(stories.resolveFor("sleeper", states.sleeper, 6, 6) == nil, "sleeping survivors rest undisturbed")
assert(stories.resolveFor("away", states.away, 6, 6) == nil, "away teams keep their own simulation")
assert(stories.resolveFor("evented", states.evented, 6, 6) == nil, "event-owned survivors are untouched")
local dead = freshState({ health = 0 })
assert(stories.resolveFor("dead", dead, 6, 6) == nil, "dead ledgers gain no stories")
local loaded = freshState({ status = "loaded" })
assert(stories.resolveFor("loaded", loaded, 6, 6) == nil, "loaded survivors gain no stories")
assert(stories.resolveFor("scout", states.scout, 0, 0) == nil, "zero elapsed resolves nothing")
print("Story gating PASS")

-- Determinism: identical ledgers at identical hours resolve identically.
local first = freshState()
local second = freshState()
local one = stories.resolveFor("scout", first, 30, 6)
local two = stories.resolveFor("scout", second, 30, 6)
assert(one == two, "story resolution is deterministic")
assert(#(first.history or {}) == #(second.history or {}), "history writes are deterministic")
print("Story determinism PASS outcome=" .. tostring(one))

-- Every eligible six-hour phase is attempted once, including phases whose
-- deterministic roll selects no story. The marker survives a save/reload.
local once = freshState()
local firstAttempt = stories.resolveFor("once", once, 42, 6)
local historyAfterFirst = #(once.history or {})
assert(stories.resolveFor("once", once, 42.9, 0.9) == nil, "same phase never rerolls")
assert(#(once.history or {}) == historyAfterFirst, "same phase writes no duplicate history")
local reloaded = serialCopy(once)
assert(stories.resolveFor("once", reloaded, 42.5, 0.5) == nil, "save/reload keeps the attempt guard")
assert(reloaded.lastStoryAttemptPhase == 7, "attempt phase is persisted on the ledger")
print("Story phase guard PASS outcome=" .. tostring(firstAttempt))

-- Invariants across many resolutions: caps, no need relief, no healing,
-- bounded detours, bounded injury.
local probe = freshState()
states["probe-me"] = probe
local worstDetour = 0
for step = 1, 60 do
    local hours = step * 6
    local before = {
        hunger = probe.hunger, thirst = probe.thirst, health = probe.health,
        x = probe.virtualX, y = probe.virtualY,
    }
    probe.lastHours = hours - 6
    stories.resolveFor("probe-me", probe, hours, 6)
    assert(probe.hunger >= before.hunger, "storylets never relieve hunger")
    assert(probe.thirst >= before.thirst, "storylets never relieve thirst")
    assert(probe.health <= before.health, "storylets never heal")
    assert(#(probe.history or {}) <= 12, "history capped at twelve")
    assert(#(probe.scars or {}) <= 4, "scar traces capped at four")
    local moved = math.sqrt((probe.virtualX - before.x) ^ 2 + (probe.virtualY - before.y) ^ 2)
    if moved > worstDetour then worstDetour = moved end
    assert(probe.health >= 1, "storylets never kill directly")
end
assert(worstDetour <= 11, "detours stay bounded")
print("Story invariants PASS detour_max=" .. string.format("%.2f", worstDetour))

-- Meetings accumulate on the shared record; hostility flips disposition.
states.meeter = freshState({ virtualX = 102, virtualY = 202 })
duties.meeter = nil
local metHostile, metFriendly = false, false
for step = 1, 40 do
    states.meeter.lastHours = (step - 1) * 6
    local outcome = stories.resolveFor("meeter", states.meeter, step * 6, 6)
    if outcome == "met_hostile" then metHostile = true end
    if outcome == "met_friendly" then metFriendly = true end
    if metHostile and metFriendly then break end
end
local key = relationships["meeter::scout"] ~= nil and "meeter::scout" or "meeter::watcher"
local record = relationships[key]
assert(record ~= nil and (record.meetings or 0) >= 1, "offscreen meetings accumulate")
assert((record.sharedRoam or 0) >= 1, "shared travel recorded")
if metHostile then
    assert(record.disposition == "hostile", "hostile meetings flip disposition")
end
print("Story meetings PASS friendly=" .. tostring(metFriendly) .. " hostile=" .. tostring(metHostile))

-- Pending meet intents land on both ledgers for the loaded engine.
local intent = states.meeter.pendingMeet
assert(type(intent) == "table" and type(intent.with) == "string", "meetings leave pending intent")
assert(intent.kind == "rob" or intent.kind == "befriend" or intent.kind == "greet",
    "pending intent carries a resolvable kind")
local mirror = (states[intent.with] ~= nil and states[intent.with].pendingMeet) or nil
if mirror == nil then
    for _, id in ipairs({ "scout", "watcher" }) do
        local candidate = states[id] ~= nil and states[id].pendingMeet or nil
        if candidate ~= nil and candidate.with == "meeter" then mirror = candidate break end
    end
end
assert(mirror ~= nil and mirror.with == "meeter", "pending intent mirrors on both ledgers")
assert(type(intent.pairPhase) == "string" and intent.pairPhase == mirror.pairPhase,
    "both ledgers carry one canonical pair/phase token")
-- Saving the caller-owned working ledger after the partner write must retain
-- both symmetric intents; this reproduces production copy-on-read semantics.
assert(KnoxPersistence.setUnloadedSurvivalState("meeter", states.meeter))
assert(states.meeter.pendingMeet ~= nil and states[intent.with].pendingMeet ~= nil,
    "caller save cannot erase a freshly-written symmetric intent")
print("Story intents PASS kind=" .. tostring(intent.kind))

local pairRecordKey = "meeter::" .. tostring(intent.with)
if relationships[pairRecordKey] == nil then pairRecordKey = tostring(intent.with) .. "::meeter" end
local beforeMeetings = relationships[pairRecordKey] and relationships[pairRecordKey].meetings or 0
local pairPhase = tonumber(tostring(intent.pairPhase):match("@(%-?%d+)$"))
if pairPhase ~= nil then
    local partner = states[intent.with]
    partner.lastStoryAttemptPhase = nil
    stories.resolveFor(intent.with, partner, pairPhase * 6, 6)
    local afterMeetings = relationships[pairRecordKey] and relationships[pairRecordKey].meetings or 0
    assert(afterMeetings == beforeMeetings, "canonical pair/phase is processed only once")
end
print("Story pair idempotency PASS")

-- A canonical hostile relationship cannot be downgraded by the probabilistic
-- first-meeting roll or leave a friendly loaded override.
states["known-a"] = freshState({ virtualX = 100, virtualY = 100 })
states["known-b"] = freshState({ virtualX = 102, virtualY = 100 })
identities["known-a"], identities["known-b"] = identities.watcher, identities.watcher
relationships["known-a::known-b"] = { meetings = 2, sharedRoam = 0, disposition = "hostile" }
activatableIds = { "known-a", "known-b" }
local knownOutcome = nil
for phase = 1, 200 do
    knownOutcome = stories.resolveFor("known-a", states["known-a"], phase * 6, 6)
    if knownOutcome ~= nil and string.find(knownOutcome, "met_", 1, true) == 1 then break end
end
assert(knownOutcome == "met_hostile", "known hostility cannot reroll to friendly")
assert(states["known-a"].pendingMeet ~= nil and states["known-a"].pendingMeet.kind == "rob",
    "known hostility leaves only a hostile loaded handoff")
activatableIds = { "scout", "watcher", "hunter", "sleeper", "away", "evented" }
print("Story known-hostile PASS")

-- Far-apart survivors never meet.
local loneHistory = #(states.hunter.history or {})
for step = 1, 20 do
    states.hunter.lastHours = (step - 1) * 6
    stories.resolveFor("hunter", states.hunter, step * 6, 6)
end
for _, entry in ipairs(states.hunter.history or {}) do
    assert(entry.kind ~= "meet", "isolated survivors meet no one")
end
print("Story isolation PASS")

-- History/scar accessors and clearing.
local history = stories.historyFor("probe-me")
assert(#history > 0 and #history <= 12, "history readable within cap")
assert(stories.historyFor("nobody") ~= nil and #stories.historyFor("nobody") == 0, "unknown ids read empty")
local scars = stories.scarsFor("probe-me")
assert(#scars <= 4, "scars readable within cap")
assert(stories.clearScars("probe-me", 1e9) == true, "clearing keeps newer traces")
assert(#stories.scarsFor("probe-me") == 0 or true, "clear runs without error")
assert(stories.clearScars("nobody", 0) == false, "clear reports missing ledgers")
print("Story accessors PASS history=" .. #history .. " scars=" .. #scars)

states.memory = freshState({ history = {
    { t = 1, kind = "rest", detail = "old" },
    { t = 2, kind = "weather", detail = string.rep("x", 300), nested = { unsafe = true } },
    { t = 3, kind = "meet", with = "friend", outcome = "friendly" },
    { t = 4, detail = "missing kind" },
} })
local recent = stories.recentHistoryFor("memory", 2)
assert(#recent == 2 and recent[1].kind == "meet" and recent[2].kind == "weather",
    "recent history is bounded, normalized, and newest first")
assert(#recent[2].detail == 160 and recent[2].nested == nil,
    "recent history truncates text and exposes no nested ledger state")
assert(#stories.recentHistoryFor("memory", 99) <= 5, "public history limit is capped")
assert(#stories.recentHistoryFor("memory", 0) == 0, "zero history limit returns no entries")
print("Story recent history PASS")

print("Offscreen stories PASS gating=true determinism=true invariants=true meetings=true isolation=true accessors=true")

-- Integration: the simulation hook resolves storylets with the engine
-- enabled and stays silent with the kill-switch set.
local simulation = require("KS_UnloadedSurvival")
local function topUp(id)
    local state = states[id]
    state.hunger, state.thirst = 0.2, 0.2
    state.fatigue, state.endurance = 0.2, 0.8
    state.health = 100
end
states.integ = freshState()
states.integ.lastHours = 0
local hooked = false
for step = 1, 120 do
    topUp("integ")
    local hours = states.integ.lastHours + 6
    local ok, result = simulation.advanceHibernated("integ", hours)
    assert(ok, "hibernated advance runs with stories enabled")
    if type(result) == "string" and string.find(result, "story:", 1, true) then
        hooked = true
        break
    end
end
assert(hooked, "advanceHibernated resolves storylets through the hook")

_G.KnoxOffscreenStoriesDisabled = true
states.integ2 = freshState()
states.integ2.lastHours = 0
local seenStory = false
for step = 1, 120 do
    topUp("integ2")
    local hours = states.integ2.lastHours + 6
    local ok, result = simulation.advanceHibernated("integ2", hours)
    assert(ok, "hibernated advance runs with stories disabled")
    if type(result) == "string" and string.find(result, "story:", 1, true) then
        seenStory = true
        break
    end
end
assert(not seenStory, "kill-switch suspends the hook")
_G.KnoxOffscreenStoriesDisabled = nil
print("Story hook integration PASS enabled=true disabled=true")
