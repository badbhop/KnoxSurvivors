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
    return { getWorldAgeHours = function() return 48 end }
end

require "KS_Persistence"
require "KS_KnoxEvents"

local function makeFaction(prefix, count)
    local ids = {}
    for index = 1, count do
        local id = prefix .. "-" .. index
        ids[#ids + 1] = id
        assert(KnoxPersistence.setRecord(id, "record-" .. id))
    end
    local group = assert(KnoxPersistence.createTravelGroup(ids, 48))
    for index = 2, #ids do
        KnoxPersistence.recordEncounter(ids[1], ids[index], {
            worldAgeHours = 48, began = true, sharedRoam = 1,
        })
    end
    local faction = assert(KnoxPersistence.evaluateTravelGroupFaction(group.id, 48))
    local base = assert(KnoxPersistence.createBase("faction", faction.id, {
        minX = prefix == "alpha" and 10 or 100,
        minY = 10,
        width = 8,
        height = 8,
    }, 48))
    faction.homeBaseId = base.id
    for _, id in ipairs(ids) do
        assert(KnoxPersistence.setFactionBaseResident(id, faction.id, base.id, 48))
    end
    return faction, base, ids
end

local alpha, alphaBase = makeFaction("alpha", 5)
local bravo, bravoBase = makeFaction("bravo", 3)

assert(KnoxPersistence.getFactionDisposition(alpha.id, bravo.id) == "neutral",
    "unrelated established factions remain neutral")
assert(KnoxEvents.proposeRaid(alpha.id, bravoBase.id, 48) == nil,
    "neutral factions are never raid eligible")
assert(KnoxPersistence.setRelationshipDisposition("alpha-1", "bravo-1", "hostile", 72))
assert(KnoxPersistence.areSurvivorsHostile("alpha-1", "bravo-1")
    and not KnoxPersistence.areSurvivorsHostile("alpha-2", "bravo-2")
    and KnoxPersistence.getFactionDisposition(alpha.id, bravo.id) == "neutral",
    "a personal grudge remains personal and cannot create a faction war")

alpha.hostilePatrol = "military"
assert(KnoxPersistence.getFactionDisposition(alpha.id, bravo.id) == "hostile",
    "persisted hostile patrol policy is a valid faction conflict source")
assert(KnoxPersistence.areSurvivorsHostile("alpha-2", "bravo-2")
    and not KnoxPersistence.areSurvivorsHostile("alpha-1", "alpha-2"),
    "hostile factions defend against each other without friendly fire")
local proposal, result = KnoxEvents.proposeRaid(alpha.id, bravoBase.id, 48)
assert(proposal ~= nil and proposal.targetFactionId == bravo.id
    and #proposal.memberIds >= 1 and result == nil,
    "raid eligibility uses the same valid hostility rule as member combat")

assert(KnoxPersistence.setFactionRelationshipDisposition(
    alpha.id, bravo.id, "allied", 49, "test_peace"
), "an explicit diplomacy row remains valid")
assert(KnoxPersistence.getFactionDisposition(alpha.id, bravo.id) == "hostile",
    "hostile patrol policy remains authoritative over a contradictory allied row")
alpha.hostilePatrol = nil
assert(KnoxPersistence.getFactionDisposition(alpha.id, bravo.id) == "allied",
    "normal diplomacy resumes when the hostile policy is removed")
assert(KnoxEvents.proposeRaid(alpha.id, bravoBase.id, 49) == nil,
    "allied factions are never raid eligible")

assert(KnoxPersistence.setFactionRelationshipDisposition(
    alpha.id, bravo.id, "hostile", 50, "test_hostility"
))
package.loaded["KS_Persistence"] = nil
_G.KnoxPersistence = nil
require "KS_Persistence"
assert(KnoxPersistence.getFactionDisposition(alpha.id, bravo.id) == "hostile",
    "faction hostility survives persistence reload")

print("Faction diplomacy PASS neutral=true patrol=true raid=true allied=true reload=true")
