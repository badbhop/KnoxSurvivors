local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local modData = {}
ModData = {
    getOrCreate = function(key)
        modData[key] = modData[key] or {}
        return modData[key]
    end,
}
Events = {
    OnSave = { Add = function() end },
    OnPostSave = { Add = function() end },
    OnGameStart = { Add = function() end },
}
getGameTime = function()
    return { getWorldAgeHours = function() return 72 end }
end

require "KS_Persistence"

local function persist(ids)
    for _, id in ipairs(ids) do
        assert(KnoxPersistence.setRecord(id, "record-" .. id))
    end
end

local function prepareFaction(ids, hour)
    local group = assert(KnoxPersistence.createTravelGroup(ids, hour))
    for index = 2, #ids do
        KnoxPersistence.recordEncounter(ids[1], ids[index], {
            worldAgeHours = hour,
            began = true,
            sharedRoam = 1,
        })
    end
    local faction, result = KnoxPersistence.evaluateTravelGroupFaction(group.id, hour)
    assert(faction ~= nil and result == "created", tostring(result))
    return group, faction
end

persist({ "a", "b", "c", "d", "e", "f", "g" })
local firstGroup, firstFaction = prepareFaction({ "a", "b", "c" }, 72)
local secondGroup, secondFaction = prepareFaction({ "e", "f", "g" }, 72)
assert(type(firstFaction.name) == "string" and firstFaction.name ~= "",
    "NPC factions receive a persisted player-facing name")

assert(KnoxPersistence.areSurvivorsAllied("a", "b"),
    "same group/faction members must classify as allied")
KnoxPersistence.setRelationshipDisposition("a", "b", "hostile", 96)
assert(KnoxPersistence.areSurvivorsAllied("a", "b"),
    "active shared membership must override a stale personal hostile flag")
assert(KnoxPersistence.getSurvivorDisposition("a", "d") == "neutral",
    "unrelated survivors must default neutral")
KnoxPersistence.setRelationshipDisposition("c", "d", "hostile", 96)
assert(KnoxPersistence.areSurvivorsHostile("c", "d"),
    "explicit personal hostility must persist")
KnoxPersistence.setFactionRelationshipDisposition(
    firstFaction.id, secondFaction.id, "hostile", 72, "test"
)
assert(KnoxPersistence.areSurvivorsHostile("b", "e"),
    "hostile factions must classify their living members as hostile")

local camp = assert(KnoxPersistence.createFactionCamp(firstFaction.id, {
    name = "Coherence Camp",
    x = 10,
    y = 20,
    z = 0,
}, 72))
assert(#camp.memberIds == 3, "camp begins with faction membership")

-- Inject contradictions representative of old/interrupted saves: one survivor
-- listed in two groups/factions and a player companion copied into NPC rosters.
local data = modData["KnoxSurvivors_IsoPlayer"]
secondGroup.memberIds[#secondGroup.memberIds + 1] = "b"
secondFaction.memberIds[#secondFaction.memberIds + 1] = "b"
assert(KnoxPersistence.setPlayerCompanion("d", "player-1", "follow", 72))
firstGroup.memberIds[#firstGroup.memberIds + 1] = "d"
firstFaction.memberIds[#firstFaction.memberIds + 1] = "d"

local changes = KnoxPersistence.normalizeRelationshipDomains()
assert(changes > 0, "contradictory membership must be normalized")
assert(KnoxPersistence.getTravelGroupFor("b").id == firstGroup.id,
    "canonical faction-consistent group must survive duplicate cleanup")
assert(KnoxPersistence.getFactionForSurvivor("b").id == firstFaction.id,
    "canonical affiliation must win duplicate faction cleanup")
assert(KnoxPersistence.getTravelGroupFor("d") == nil,
    "player companion cannot remain in an NPC travel group")
assert(KnoxPersistence.getFactionForSurvivor("d").kind == "player",
    "player companion retains the player faction")

assert(KnoxPersistence.markSurvivorDead("a", 73, "test_death"))
assert(not KnoxPersistence.isSurvivorAlive("a"), "death remains authoritative")
assert(KnoxPersistence.getTravelGroupFor("a") == nil,
    "dead member leaves active travel membership")
assert(firstGroup.leaderId == "b", "dead group leader receives stable replacement")
assert(firstFaction.leaderId == "b", "dead faction leader receives stable replacement")
assert(#KnoxPersistence.getFactionCamp(firstFaction.id).memberIds == 2,
    "dead camp member is removed from active occupancy")

-- Simulate Lua reload while retaining ModData. Relationship and leadership
-- must come back from persistence without any runtime controller cache.
package.loaded["KS_Persistence"] = nil
_G.KnoxPersistence = nil
require "KS_Persistence"
assert(KnoxPersistence.areSurvivorsHostile("c", "d"),
    "personal hostility survives reload")
assert(KnoxPersistence.areSurvivorsHostile("b", "e"),
    "faction hostility survives reload")
assert(KnoxPersistence.getTravelGroupFor("b").leaderId == "b",
    "group leadership survives reload and separation")
assert(KnoxPersistence.getFactionForSurvivor("b").leaderId == "b",
    "faction leadership survives reload")
assert(KnoxPersistence.getFactionForSurvivor("b").name == firstFaction.name,
    "faction name survives reload and leader changes")

print("Relationship coherence PASS canonical=true allies=true neutral=true hostile=true death=true reload=true")
