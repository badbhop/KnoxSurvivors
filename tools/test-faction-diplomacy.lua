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
    return { getWorldAgeHours = function() return 42 end }
end

require "KS_Persistence"

for _, id in ipairs({ "a", "b", "c" }) do
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
    assert(KnoxPersistence.ensureSurvivorIdentity(id, id, "Tester", 42))
end

local group = assert(KnoxPersistence.createTravelGroup({ "a", "b", "c" }, 42))
for _, otherId in ipairs({ "b", "c" }) do
    KnoxPersistence.recordEncounter("a", otherId, {
        worldAgeHours = 42,
        began = true,
        sharedRoam = 1,
    })
end
local faction = assert(KnoxPersistence.evaluateTravelGroupFaction(group.id, 42))
local playerFaction = assert(KnoxPersistence.ensurePlayerFaction("player-1", 42))

assert(not KnoxPersistence.isSurvivorHostileToPlayer("a", "player-1"),
    "ordinary NPC factions must remain safe around player bases")
local relation, result = KnoxPersistence.setFactionRelationshipDisposition(
    faction.id, playerFaction.id, "hostile", 43, "test"
)
assert(relation ~= nil and result == "saved")
assert(KnoxPersistence.isSurvivorHostileToPlayer("a", "player-1"),
    "hostile faction relation must permit hostile survivor behavior")
local reverse = assert(KnoxPersistence.getFactionRelationship(playerFaction.id, faction.id))
assert(reverse.disposition == "hostile", "faction relation must be symmetric")
reverse.disposition = "allied"
assert(KnoxPersistence.getFactionRelationship(faction.id, playerFaction.id).disposition == "hostile",
    "read snapshot must not mutate saved diplomacy")
assert(KnoxPersistence.setFactionRelationshipDisposition(faction.id, faction.id, "hostile", 44) == nil,
    "a faction cannot be hostile to itself")

print("Faction diplomacy PASS safe_default=true hostile_relation=true symmetric=true")
