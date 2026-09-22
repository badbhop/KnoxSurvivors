local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path
local data = { schemaVersion = 14 }
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 100 end } end
require "KS_Persistence"
require "KS_EventFactions"
require "KS_KnoxEvents"
local P, F, E = KnoxPersistence, KnoxEventFactions, KnoxEvents

-- Catalog: behavior fields present, black division disabled but registered.
local expected = { "black_division", "military", "pmc", "police", "scavengers", "scientists" }
assert(table.concat(F.ids(), ",") == table.concat(expected, ","))
assert(F.isDisabled("black_division") and not F.isDisabled("police"))
local police = F.get("police")
assert(police.persistsAfterEvent == false, "police patrol, never settle")
assert(police.schedulerWeight == 4 and police.partySize[1] == 3 and police.partySize[2] == 4)
local military = F.get("military")
assert(military.defaultDisposition == "hostile" and military.hostilePatrol == true
    and military.deserters == true, "military patrol hostile with deserters")
assert(military.schedulerWeight == 2 and military.partySize[1] == 4)
local scientists = F.get("scientists")
assert(scientists.minimumWorldDays == 14 and scientists.cureCarrier == true
    and scientists.schedulerWeight == 1 and scientists.partySize[1] == 2,
    "scientists stay rare through scheduler weight and small parties")
local auto = F.automaticPolicies()
assert(#auto == 3 and auto[1] == "military" and auto[2] == "police" and auto[3] == "scientists",
    "only the three patrol factions schedule automatically")

-- Disabled policy can never be scheduled, even directly.
assert(E.scheduleFactionEntry("black_division", "recover_knox_vials",
    { x = 1, y = 1, z = 0 }, 2, 60 * 24 + 1, 0) == nil, "black division stays out")

-- Faction creation wires hostility + a deserter for military patrols.
local function survivor(id)
    assert(P.setRecord(id, "native-record-" .. id))
    assert(P.ensureSurvivorIdentity(id, id, "Policy", 0))
end
for _, id in ipairs({ "m1", "m2", "m3", "m4", "p1", "p2", "p3" }) do survivor(id) end
local policeOrigins = {}
for i = 1, 3 do policeOrigins[i] = { x = 10 + i, y = 10, z = 0 } end
local cops = assert(F.createEntry("police", "police-seed", policeOrigins, 100))
local playerFaction = P.ensurePlayerFaction("player-9", 100)
local militaryOrigins = {}
for i = 1, 4 do militaryOrigins[i] = { x = 40 + i, y = 40, z = 0 } end
local patrol = assert(F.createEntry("military", "military-seed", militaryOrigins, 400))
assert(patrol.eventIdentity ~= nil, "faction created")
local storedPatrol = P.getFaction(patrol.id)
assert(storedPatrol.hostilePatrol == "military", "patrol flagged hostile")
local deserters = 0
for _, id in ipairs(patrol.memberIds) do
    if P.getSurvivorOrigin(id).source == "knox_event" and P.getSurvivorDuty(id) ~= nil then
        local s = data.survivors[id]
        if s ~= nil and s.deserter == true then deserters = deserters + 1 end
    end
end
assert(deserters == 1, "exactly one deserter flagged")
local relation = P.getFactionRelationship(patrol.id, cops.id)
assert(relation ~= nil and relation.disposition == "hostile", "patrol hostile to police faction")
local playerRelation = P.getFactionRelationship(patrol.id, playerFaction.id)
assert(playerRelation ~= nil and playerRelation.disposition == "hostile",
    "patrol hostile to player faction")

-- Disposition reads: patrol vs police hostile, patrol vs patrol neutral.
local copId, trooperId = cops.memberIds[1], patrol.memberIds[1]
assert(P.areSurvivorsHostile(trooperId, copId), "trooper shoots police")
local militaryOrigins2 = {}
for i = 1, 4 do militaryOrigins2[i] = { x = 60 + i, y = 60, z = 0 } end
local patrol2 = assert(F.createEntry("military", "military-seed-2", militaryOrigins2, 400))
assert(not P.areSurvivorsHostile(trooperId, patrol2.memberIds[1]),
    "fellow patrols do not shoot each other")
-- Deserter is exempt from hostility both ways.
local deserterId = nil
for _, id in ipairs(patrol.memberIds) do
    local s = data.survivors[id]
    if s ~= nil and s.deserter == true then deserterId = id end
end
assert(deserterId ~= nil)
assert(not P.isSurvivorHostileToPlayer(deserterId, "player-9"), "deserter not hostile to survivors")
assert(not P.areSurvivorsHostile(deserterId, copId), "deserter not hostile to police")
assert(P.isSurvivorHostileToPlayer(trooperId, "player-9"), "trooper hostile to survivors")

-- Deserters convert to recruitable independents when the event finishes.
local root = data
root.survivors[deserterId].duty = { mode = "autonomous", order = "survive",
    eventId = "military-event", revision = 1 }
root.survivors[deserterId].eventSourceId = "military-event"
local released = assert(P.releaseDeserters("military-event", 410))
assert(#released == 1 and released[1] == deserterId, "deserter released")
local affiliation = P.getSurvivorAffiliation(deserterId)
assert(affiliation.kind == "independent", "deserter independent and recruitable")
local duty = P.getSurvivorDuty(deserterId)
assert(duty.mode == "autonomous" and duty.eventId == nil)
assert(P.getSurvivorPersonality(deserterId).playerResponse == "join",
    "deserter wants a home")
assert(P.getTravelGroupFor(deserterId) == nil, "deserter left the patrol group")
assert(not P.isSurvivorHostileToPlayer(deserterId, "player-9"))
assert(P.releaseDeserters("no-such-event", 410)[1] == nil, "unknown event releases nothing")

-- Automatic scheduler: gated, deterministic, black division never picked.
local hours = E.scheduleAutomaticEntry(10, true, 1, 3)
assert(hours == nil, "entries respect policy gates")
local early, earlyReason = E.scheduleAutomaticEntry(23, true, 1, 3)
assert(early == nil and earlyReason == "world_too_young")
assert(P.getKnoxEventState().automatic.entryNextCheckHours == 24)
local off = E.scheduleAutomaticEntry(100, false, 1, 3)
assert(off == nil, "disabled scheduler stays silent")
getSpecificPlayer = nil
getNumActivePlayers = nil
local noload, noloadReason = E.scheduleAutomaticEntry(100, true, 1, 3, true)
assert(noload == nil and noloadReason == "no_loaded_players")
getSpecificPlayer = function(index)
    if index ~= 0 then return nil end
    return { getCurrentSquare = function()
        return { getX = function() return 5000 end, getY = function() return 5000 end,
            getZ = function() return 0 end }
    end }
end
getNumActivePlayers = function() return 1 end
local first, firstReason = E.scheduleAutomaticEntry(100, true, 1, 3, true)
assert(first ~= nil and firstReason == "automatic_entry_scheduled", firstReason)
assert(first.trigger == "automatic" and first.phase == "scheduled")
assert(first.policyId == "police" and first.objectiveKind == "secure_area"
    and first.partySize >= 3 and first.partySize <= 4, "weighted rotation opens with police")
local second = E.scheduleAutomaticEntry(100, true, 1, 3, true)
assert(second == nil, "one automatic event at a time")
assert(E.transition(first.id, first.revision, "failed", 101, "fixture") ~= nil)
local third = assert(E.scheduleAutomaticEntry(400, true, 1, 3, true))
assert(third.policyId == "police", "weighted rotation is deterministic")
assert(third.trigger == "automatic" and third.partySize >= 3 and third.partySize <= 4)
assert(third.policyId ~= "black_division", "disabled policy never auto-schedules")
local state = P.getKnoxEventState().automatic
assert(state.entryCursor == 2 and state.entryNextCheckHours == 400 + 72,
    "scheduler cursor and interval persist")

print("Event patrol factions PASS catalog=true disabled=true hostility=true deserters=true scheduler=true")
