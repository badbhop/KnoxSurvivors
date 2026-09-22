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

persist({ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" })
local firstGroup, firstFaction = prepareFaction({ "a", "b", "c" }, 72)
local secondGroup, secondFaction = prepareFaction({ "e", "f", "g" }, 72)
local thirdGroup, thirdFaction = prepareFaction({ "h", "i", "j" }, 72)
assert(type(firstFaction.name) == "string" and firstFaction.name ~= "",
    "NPC factions receive a persisted player-facing name")

assert(KnoxPersistence.setSurvivorLifeIntent("a", {
    kind = "investigate_building",
    phase = "traveling",
    targetKey = "building:10:20:0",
    targetX = 10,
    targetY = 20,
    targetZ = 0,
}, 72))
local leaderIntent = assert(KnoxPersistence.getSurvivorLifeIntent("a"))
assert(KnoxPersistence.setTravelGroupObjective(
    firstGroup.id, "a", leaderIntent, 72
))
local sharedObjective = assert(KnoxPersistence.getTravelGroupObjective(firstGroup.id))
assert(sharedObjective.kind == "investigate_building"
    and sharedObjective.leaderId == "a" and sharedObjective.revision == 1,
    "travel groups persist one leader-owned shared purpose")
sharedObjective.targetX = 999
assert(KnoxPersistence.getTravelGroupObjective(firstGroup.id).targetX == 10,
    "callers cannot mutate the persisted group objective by reference")
assert(not KnoxPersistence.setTravelGroupObjective(
    firstGroup.id, "a", leaderIntent, 73
), "unchanged group objective must not churn revisions")
assert(not KnoxPersistence.setTravelGroupObjective(
    firstGroup.id, "b", leaderIntent, 73
), "only the current group leader can replace shared purpose")

assert(KnoxPersistence.areSurvivorsAllied("a", "b"),
    "same group/faction members must classify as allied")
KnoxPersistence.setRelationshipDisposition("a", "b", "hostile", 96)
assert(KnoxPersistence.areSurvivorsAllied("a", "b"),
    "active shared membership must override a stale personal hostile flag")
assert(KnoxPersistence.getSurvivorDisposition("a", "d") == "neutral",
    "unrelated survivors must default neutral")
local personalConflict, personalResult = KnoxPersistence.escalateSurvivorConflict(
    "c", "d", 72, "test_personal"
)
assert(personalConflict ~= nil and personalResult == "personal_hostile",
    "a conflict between non-faction survivors remains personal")
assert(KnoxPersistence.areSurvivorsHostile("c", "d"),
    "explicit personal hostility must persist")
local factionConflict, factionResult = KnoxPersistence.escalateSurvivorConflict(
    "b", "e", 72, "test_faction"
)
assert(factionConflict ~= nil and factionResult == "faction_hostile",
    "a conflict between established NPC factions escalates through diplomacy")
assert(KnoxPersistence.areSurvivorsHostile("b", "e"),
    "hostile factions must classify their living members as hostile")
assert(KnoxPersistence.getFactionDisposition(firstFaction.id, thirdFaction.id) == "neutral",
    "unrelated factions remain neutral by default")
firstFaction.hostilePatrol = "military"
assert(KnoxPersistence.getFactionDisposition(firstFaction.id, thirdFaction.id) == "hostile"
    and KnoxPersistence.areSurvivorsHostile("b", "h"),
    "persisted hostile-patrol policy applies to factions formed afterward")
assert(KnoxPersistence.getFactionDisposition(firstFaction.id, firstFaction.id) == "allied",
    "a faction never treats its own members as hostile")

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
assert(KnoxPersistence.getTravelGroupObjective(firstGroup.id) == nil,
    "leader replacement clears the old leader's objective")
assert(firstFaction.leaderId == "b", "dead faction leader receives stable replacement")
assert(#KnoxPersistence.getFactionCamp(firstFaction.id).memberIds == 2,
    "dead camp member is removed from active occupancy")

assert(KnoxPersistence.setSurvivorLifeIntent("e", {
    kind = "scavenge",
    phase = "traveling",
    targetKey = "container:40:50:0",
    targetX = 40,
    targetY = 50,
    targetZ = 0,
}, 73))
assert(KnoxPersistence.setTravelGroupObjective(
    secondGroup.id,
    secondGroup.leaderId,
    KnoxPersistence.getSurvivorLifeIntent("e"),
    73
))
firstGroup.objective = {
    kind = "travel_area", phase = "traveling", leaderId = "removed-leader",
    targetX = 1, targetY = 1, targetZ = 0,
}

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
assert(KnoxPersistence.getTravelGroupObjective(firstGroup.id) == nil,
    "restore rejects an objective that is not owned by the current leader")
local restoredObjective = assert(
    KnoxPersistence.getTravelGroupObjective(secondGroup.id)
)
assert(restoredObjective.kind == "scavenge" and restoredObjective.leaderId == "e",
    "valid shared purpose survives a Lua reload")

-- A normal faction that loses its final member must release every faction-owned
-- record immediately: successor selection keeps it alive through the first
-- loss, then the last loss removes base ownership and stale diplomacy.
local factionBase = assert(KnoxPersistence.createBase("faction", firstFaction.id, {
    minX = 120, minY = 220, width = 6, height = 6,
}, 74))
firstFaction.homeBaseId = factionBase.id
assert(KnoxPersistence.setFactionRelationshipDisposition(
    firstFaction.id, secondFaction.id, "hostile", 74, "collapse_test"
))
local removedSafehouses = 0
SafeHouse = {
    getSafehouseByOwner = function(owner)
        return owner == "KnoxSurvivors:" .. firstFaction.id and { owner = owner } or nil
    end,
    removeSafeHouse = function() removedSafehouses = removedSafehouses + 1 end,
}
assert(KnoxPersistence.markSurvivorDead("b", 75, "collapse_test"))
assert(KnoxPersistence.getFaction(firstFaction.id).leaderId == "c",
    "remaining living member must become deterministic successor")
assert(KnoxPersistence.markSurvivorDead("c", 76, "collapse_test"))
assert(KnoxPersistence.getFaction(firstFaction.id) == nil,
    "empty ordinary faction must collapse")
assert(KnoxPersistence.getBase(factionBase.id) == nil,
    "collapsed faction must release its complete base record")
assert(KnoxPersistence.getFactionRelationship(firstFaction.id, secondFaction.id) == nil,
    "collapsed faction must not retain diplomacy")
assert(removedSafehouses == 1,
    "collapsed faction must release the generated engine safehouse when available")

print("Relationship coherence PASS canonical=true allies=true neutral=true hostile=true death=true reload=true collapse=true")
