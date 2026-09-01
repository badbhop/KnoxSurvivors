local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path
local data = { schemaVersion = 14 }
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 100 end } end
require "KS_Persistence"
require "KS_EventFactions"
local P, F = KnoxPersistence, KnoxEventFactions

local expected = { "black_division", "military", "pmc", "police", "scavengers", "scientists" }
assert(table.concat(F.ids(), ",") == table.concat(expected, ","), "all event policies are registered deterministically")
for _, id in ipairs(expected) do
    local profile = assert(F.get(id))
    assert(profile.healthMultiplier == nil and profile.damageMultiplier == nil and profile.accuracyMultiplier == nil,
        "policy cannot grant artificial combat multipliers: " .. id)
    assert(#profile.objectives > 0 and profile.loadoutTheme ~= "", "policy is incomplete: " .. id)
end
local police = F.get("police"); police.displayName = "Changed"; police.objectives[1] = "changed"
assert(F.get("police").displayName == "Police" and F.allowsObjective("police", "assist"),
    "callers cannot mutate the policy catalog")
assert(not F.allowsObjective("police", "recover_knox_vials"))
assert(not F.isWorldAgeEligible("black_division", 60 * 24 - 0.01)
    and F.isWorldAgeEligible("black_division", 60 * 24), "late-game gate is explicit")
assert(F.get("scavengers").bossEnabled == false, "scavenger boss hook remains disabled")
assert(F.get("pmc").contractEligible == true, "PMC policy retains future contract role")
local scientists = F.get("scientists")
assert(scientists.professionId == "base:doctor"
    and scientists.appearanceItem == "Base.JacketLong_Doctor",
    "Scientists use a real balanced medical profession and real lab-coat item")

local ids = { "a", "b", "c" }
for _, id in ipairs(ids) do
    assert(P.setRecord(id, "native-record-" .. id))
    assert(P.ensureSurvivorIdentity(id, id, "Policy", 0))
end
local group = assert(P.createTravelGroup(ids, 0))
for _, id in ipairs({ "b", "c" }) do
    P.recordEncounter("a", id, { worldAgeHours = 0, began = true, sharedRoam = 1 })
end
local faction = assert(P.evaluateTravelGroupFaction(group.id, 0))
local before = {}
for _, id in ipairs(ids) do before[id] = { record = P.getRecord(id), duty = P.getSurvivorDuty(id) } end
local bound, result = F.bindExistingFaction(faction.id, "police", "knox-event-test", 100)
assert(bound ~= nil and result == "bound" and bound.eventIdentity.policyId == "police")
assert(bound.name == "Police" and bound.kind == "npc" and #bound.memberIds == 3)
for _, id in ipairs(ids) do
    assert(P.getRecord(id) == before[id].record, "binding changed native inventory")
    assert(P.getSurvivorDuty(id).revision == before[id].duty.revision, "binding changed survivor duty")
    assert(P.getSurvivorAffiliation(id).factionId == faction.id, "binding created parallel affiliation")
end
assert(F.bindExistingFaction(faction.id, "police", "knox-event-test", 100) ~= nil, "same binding is idempotent")
local rebound, reboundReason = F.bindExistingFaction(faction.id, "military", "another-event", 101)
assert(rebound == nil and reboundReason == "event_faction_already_bound", "faction identity cannot be rewritten")
assert(F.bindExistingFaction(faction.id, "unknown", "event", 100) == nil, "unknown policy rejected")
local playerFaction = assert(P.ensurePlayerFaction("player-1", 0))
assert(F.bindExistingFaction(playerFaction.id, "police", "event", 100) == nil, "player faction cannot become an event faction")

data.factions[faction.id].eventIdentity = { policyId = {}, sourceEventId = "bad",
    basePolicy = "event_only", boundAtHours = 100 }
assert(P.getFaction(faction.id).eventIdentity == nil, "malformed saved event identity normalizes safely")
assert(#P.getSurvivorIds() == 3, "policy foundation never allocates survivors")

print("Event faction policies PASS catalog=true no_buffs=true defensive=true native_faction=true persistence=true no_spawn=true")
