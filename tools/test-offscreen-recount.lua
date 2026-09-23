local projectRoot = arg[1] or "."

local spoken = {}
KnoxActivityFeed = {
    speak = function(character, line)
        spoken[#spoken + 1] = line
    end,
}
KnoxSettings = {
    showSurvivorSpeech = function() return true end,
}
package.preload.KS_ActivityFeed = function() return KnoxActivityFeed end
package.preload.KS_Settings = function() return KnoxSettings end
package.path = projectRoot .. "/mod/42/media/lua/client/?.lua;" .. package.path
require("KS_OffscreenStories")

local states = {
    teller = {
        history = {
            { t = 10, kind = "meet", with = "friend", detail = "x", outcome = "friendly" },
            { t = 20, kind = "close_call", detail = "x", outcome = "hurt" },
            { t = 30, kind = "meet", with = "foe", detail = "x", outcome = "hostile" },
        },
    },
    fresh = {},
}
local relationships = {
    ["foe::teller"] = { meetings = 1, disposition = "hostile" },
    ["friend::teller"] = { meetings = 3, disposition = "neutral" },
    ["ally::teller"] = { meetings = 5, disposition = "allied" },
}
local groups = {
    teller = { id = "g-1" },
    mate = { id = "g-1" },
    other = { id = "g-2" },
}
local factions = {
    teller = { id = "f-1", name = "Teller Crew" },
    kin = { id = "f-1", name = "Teller Crew" },
    stranger = { id = "f-9", name = "Strangers" },
}
local identities = {
    friend = { forename = "Mara" },
}

KnoxPersistence = {
    getRelationship = function(a, b)
        local key = a < b and (a .. "::" .. b) or (b .. "::" .. a)
        return relationships[key]
    end,
    getTravelGroupFor = function(id) return groups[id] end,
    getFactionForSurvivor = function(id) return factions[id] end,
    getSurvivorIdentity = function(id) return identities[id] or {} end,
    getSurvivorPersonality = function() return nil end,
    getUnloadedSurvivalState = function(id) return states[id] end,
    setUnloadedSurvivalState = function(id, state) states[id] = state return true end,
}

local Dialogue = assert(loadfile(projectRoot
    .. "/mod/42/media/lua/client/KS_SurvivorDialogue.lua"))()
local character = {}

-- Relation nouns follow disposition and shared affiliation, never invention.
assert(Dialogue.relationNoun("teller", "teller") == "myself", "self reads myself")
assert(Dialogue.relationNoun("teller", "foe") == "that hostile soul", "hostile reads hostile")
assert(Dialogue.relationNoun("teller", "mate") == "my groupmate", "shared group reads groupmate")
assert(Dialogue.relationNoun("teller", "kin") == "one of ours", "shared faction reads ours")
assert(Dialogue.relationNoun("teller", "ally") == "my friend", "allied reads friend")
assert(Dialogue.relationNoun("teller", "friend") == "someone I have crossed before", "repeat meetings read familiar")
assert(Dialogue.relationNoun("teller", "nobody") == "a traveler", "strangers read traveler")
assert(Dialogue.relationNoun(nil, "nobody") == "a traveler", "missing viewer reads traveler")
print("Relation nouns PASS")

-- Recounts retell ledger history newest-first with relation-aware subjects.
local lines = Dialogue.recountLines("teller")
assert(#lines >= 1 and #lines <= 3, "recount returns one to three lines")
local joined = table.concat(lines, " | ")
assert(string.find(joined, "that hostile soul", 1, true) ~= nil, "hostile meets recount hostile")
assert(string.find(joined, "Mara", 1, true) ~= nil, "familiar meets speak forenames")
assert(string.find(joined, "torn up", 1, true) ~= nil, "injuries are recounted")
assert(#Dialogue.recountLines("fresh") == 0, "no history means no recount")
assert(#Dialogue.recountLines("nobody") == 0, "unknown survivors mean no recount")
print("Recount lines PASS lines=" .. #lines)

-- Campfire hook: base_social sometimes retells history, otherwise the bank.
Dialogue.resetRuntime()
local sawRecount, sawBank = false, false
for window = 0, 30 do
    Dialogue.resetRuntime()
    local ok, line = Dialogue.say(character, "teller", "base_social", window * 1800, 1)
    assert(ok, "base_social speaks with history present")
    if string.find(line, "Mara", 1, true) ~= nil
        or string.find(line, "hostile soul", 1, true) ~= nil
        or string.find(line, "torn up", 1, true) ~= nil then
        sawRecount = true
    else
        sawBank = true
    end
end
assert(sawRecount and sawBank, "campfire mixes recounts with lifestyle banks")
Dialogue.resetRuntime()
local freshOk = Dialogue.say(character, "fresh", "base_social", 0, 1)
assert(freshOk, "base_social speaks without history")
local secondOk, secondReason = Dialogue.say(character, "fresh", "base_social", 1, 100000)
assert(secondOk == false and secondReason == "cooldown", "speech cooldowns hold")
print("Campfire hook PASS recount=" .. tostring(sawRecount) .. " bank=" .. tostring(sawBank))

print("Offscreen recount PASS nouns=true recount=true campfire=true cooldown=true")
