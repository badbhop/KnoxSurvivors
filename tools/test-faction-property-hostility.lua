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
getGameTime = function() return { getWorldAgeHours = function() return 42 end } end

require "KS_Persistence"

for _, id in ipairs({ "a", "b", "c" }) do
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
end
local group = assert(KnoxPersistence.createTravelGroup({ "a", "b", "c" }, 42))
for _, id in ipairs({ "b", "c" }) do
    assert(KnoxPersistence.recordEncounter("a", id, {
        worldAgeHours = 42, began = true, sharedRoam = 1,
    }))
end
local faction = assert(KnoxPersistence.evaluateTravelGroupFaction(group.id, 42))
local playerFaction = assert(KnoxPersistence.ensurePlayerFaction("player-1", 42))
local base = assert(KnoxPersistence.createBase("faction", faction.id, {
    minX = 100, minY = 200, width = 8, height = 6,
}, 42))

assert(KnoxPersistence.getBaseAtSquare(102, 203, 0, "faction").id == base.id,
    "faction property lookup must honor claimed territory")
assert(KnoxPersistence.getBaseAtSquare(99, 203, 0, "faction") == nil,
    "nearby unclaimed containers must not be treated as faction property")
assert(not KnoxPersistence.isSurvivorHostileToPlayer("b", "player-1"),
    "a neutral faction is initially safe")

local relation, status = KnoxPersistence.recordPlayerFactionTheft("player-1", base.id, 43)
assert(relation ~= nil and status == "hostile" and relation.reason == "player_theft",
    "a completed theft must create durable faction hostility")
assert(KnoxPersistence.isSurvivorHostileToPlayer("a", "player-1")
    and KnoxPersistence.isSurvivorHostileToPlayer("c", "player-1"),
    "all faction defenders inherit a property-theft hostility")
assert(KnoxPersistence.getFactionRelationship(faction.id, playerFaction.id).disposition == "hostile",
    "property hostility is symmetric at the diplomacy layer")
local repeatRelation, repeatStatus = KnoxPersistence.recordPlayerFactionTheft("player-1", base.id, 44)
assert(repeatRelation ~= nil and repeatStatus == "already_hostile",
    "repeated transfers must not repeatedly announce or churn hostility")

print("Faction property hostility PASS territory=true theft=true defenders=true")
