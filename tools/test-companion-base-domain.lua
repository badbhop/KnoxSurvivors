local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local key = "KnoxSurvivors_IsoPlayer"
local modData = {
    [key] = {
        -- Reproduce a save that was already stamped by an earlier schema-7
        -- development build before its membership migration had run.
        schemaVersion = 7,
        survivors = {
            a = { id = "a", record = "record-a" },
            b = { id = "b", record = "record-b" },
            c = { id = "c", record = "record-c" },
        },
        relationships = {},
        travelGroups = {
            legacy = {
                id = "legacy",
                leaderId = "a",
                memberIds = { "a", "b", "c" },
                factionId = "legacy-faction",
            },
        },
        nextTravelGroupId = 2,
        factions = {
            ["legacy-faction"] = {
                id = "legacy-faction",
                leaderId = "a",
                memberIds = { "a", "b" },
            },
        },
        nextFactionId = 2,
    },
}

ModData = {
    getOrCreate = function(name)
        modData[name] = modData[name] or {}
        return modData[name]
    end,
}
Events = {
    OnSave = { Add = function() end },
    OnPostSave = { Add = function() end },
    OnGameStart = { Add = function() end },
}
getGameTime = function()
    return { getWorldAgeHours = function() return 24 end }
end

require "KS_Persistence"

local migrated = KnoxPersistence.getFaction("legacy-faction")
assert(migrated.kind == "npc", "legacy faction kind migration")
assert(#migrated.memberIds == 3, "travel-group member merged into faction")
assert(KnoxPersistence.getSurvivorAffiliation("c").factionId == migrated.id,
    "legacy survivor affiliation migration")
assert(not KnoxPersistence.isIndependentSurvivor("c"), "faction member is not independent")

local playerModData = {}
local player = {
    getModData = function() return playerModData end,
    getDescriptor = function()
        return {
            getForename = function() return "Test" end,
            getSurname = function() return "Player" end,
        }
    end,
}
local playerId = assert(KnoxPersistence.ensurePlayerId(player))

local ghostRecruit, ghostRecruitResult = KnoxPersistence.setPlayerCompanion(
    "ghost",
    playerId,
    "follow",
    24
)
assert(not ghostRecruit and ghostRecruitResult == "survivor_not_persisted")

assert(KnoxPersistence.setRecord("independent", "record-independent"))
KnoxPersistence.ensureSurvivorIdentity("independent", "June", "Reed", 24)
local relation = KnoxPersistence.getPlayerRelationship(playerId, "independent")
relation.trust = 60
local recruited, recruitResult = KnoxPersistence.setPlayerCompanion(
    "independent",
    playerId,
    "follow",
    24
)
assert(recruited and recruitResult == "companion", tostring(recruitResult))
assert(KnoxPersistence.getSurvivorDuty("independent").mode == "companion")
assert(#KnoxPersistence.getCompanionIds(playerId) == 1)
modData[key].travelGroups.stalePlayerGroup = {
    id = "stalePlayerGroup",
    leaderId = "independent",
    memberIds = { "independent", "ghost-member" },
}
assert(KnoxPersistence.setPlayerCompanion("independent", playerId, "follow", 24),
    "reapplying player ownership repairs stale NPC-group membership")
assert(KnoxPersistence.getTravelGroupFor("independent") == nil)
assert(KnoxPersistence.setCompanionClimbing("independent", playerId, false, 24))
assert(KnoxPersistence.getSurvivorPolicies("independent").allowClimbing == false)
assert(KnoxPersistence.setCompanionDirective("independent", playerId, {
    kind = "loot_area", minX = 1, minY = 2, maxX = 8, maxY = 9, z = 0,
}, 24))
assert(KnoxPersistence.getSurvivorDuty("independent").directive.kind == "loot_area")
assert(KnoxPersistence.clearCompanionDirective("independent", playerId, 24))
assert(KnoxPersistence.getSurvivorDuty("independent").directive == nil)

local base, baseResult = KnoxPersistence.createBase("player", playerId, {
    buildingId = "player-home",
    x = 10,
    y = 20,
    z = 0,
    minX = 8,
    minY = 18,
    width = 8,
    height = 9,
}, 24)
assert(base ~= nil and baseResult == "created", tostring(baseResult))
local territory, territoryResult = KnoxPersistence.updateBaseTerritory(base.id, {
    minX = 4, minY = 14, maxX = 20, maxY = 30,
}, 24)
assert(territory ~= nil and territoryResult == "updated")
assert(territory.allFloors and territory.minX == 4 and territory.maxY == 30)
local resident, residentResult = KnoxPersistence.setPlayerBaseResident(
    "independent",
    playerId,
    base.id,
    24
)
assert(resident and residentResult == "base_resident", tostring(residentResult))
assert(#KnoxPersistence.getCompanionIds(playerId) == 0)
assert(#KnoxPersistence.getBaseResidentIds(base.id) == 1)

local zone = assert(KnoxPersistence.addBaseZone(base.id, "guard", {
    x1 = 9, y1 = 19, x2 = 12, y2 = 22, z = 0,
}, "Front gate"))
assert(zone.type == "guard" and base.zones[zone.id] == zone)

local policy = assert(KnoxPersistence.setBaseStoragePolicy(base.id, {
    key = "container-stable-1",
    x = 10,
    y = 20,
    z = 0,
    objectIndex = 2,
    containerIndex = 1,
    containerType = "crate",
}, "food", false))
assert(policy.containerIndex == 1 and policy.category == "food")

local firstTask = assert(KnoxPersistence.queueBaseTask(base.id, "chop_tree", {
    x = 30, y = 40, z = 0,
}, { skills = { Woodwork = 2 } }, 70))
local secondTask = assert(KnoxPersistence.queueBaseTask(base.id, "chop_tree", {
    x = 31, y = 40, z = 0,
}, { skills = { Woodwork = 2 } }, 70))
assert(firstTask.id ~= secondTask.id, "coordinate targets must not collapse")
local ghost, ghostResult = KnoxPersistence.claimBaseTask(
    base.id,
    firstTask.id,
    "not-a-survivor",
    24
)
assert(ghost == nil and ghostResult == "unknown_survivor")
assert(KnoxPersistence.setRecord("outsider", "record-outsider"))
local outsider, outsiderResult = KnoxPersistence.claimBaseTask(
    base.id,
    firstTask.id,
    "outsider",
    24
)
assert(outsider == nil and outsiderResult == "not_base_resident")
local unclaimedFinish, unclaimedFinishResult = KnoxPersistence.finishBaseTask(
    base.id,
    secondTask.id,
    "independent",
    true,
    "invalid",
    24
)
assert(unclaimedFinish == nil and unclaimedFinishResult == "not_claimed_by_survivor")
local claimed, claimResult = KnoxPersistence.claimBaseTask(
    base.id,
    firstTask.id,
    "independent",
    24
)
assert(claimed ~= nil and claimResult == "claimed")

assert(KnoxPersistence.setSurvivorIndependent("independent", "dismissed", 25))
assert(firstTask.state == "queued" and firstTask.claimedBy == nil,
    "leaving a base must release claimed work")
assert(KnoxPersistence.isIndependentSurvivor("independent"))
assert(KnoxPersistence.getFactionForSurvivor("independent") == nil)
assert(KnoxPersistence.getTravelGroupFor("independent") == nil)

for _, id in ipairs({ "x", "y", "z", "resident-two" }) do
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
end
local npcGroup = assert(KnoxPersistence.createTravelGroup({ "x", "y", "z" }, 25))
for _, id in ipairs({ "y", "z" }) do
    KnoxPersistence.recordEncounter("x", id, {
        worldAgeHours = 25,
        began = true,
        sharedRoam = 1,
    })
end
local npcFaction = assert(KnoxPersistence.evaluateTravelGroupFaction(npcGroup.id, 25))
assert(KnoxPersistence.setPlayerCompanion("resident-two", playerId, "follow", 25))
assert(KnoxPersistence.setPlayerBaseResident("resident-two", playerId, base.id, 25))
local transferredTask = assert(KnoxPersistence.queueBaseTask(base.id, "guard", {
    x = 14, y = 20, z = 0,
}, {}, 50))
assert(KnoxPersistence.claimBaseTask(base.id, transferredTask.id, "resident-two", 25))
assert(not KnoxPersistence.addFactionMember(npcFaction.id, "resident-two", 25))
local transferredDuty = KnoxPersistence.getSurvivorDuty("resident-two")
local transferredAffiliation = KnoxPersistence.getSurvivorAffiliation("resident-two")
assert(transferredAffiliation.kind == "player"
    and transferredAffiliation.ownerId == playerId)
assert(transferredDuty.mode == "base" and transferredDuty.baseId == base.id,
    "NPC factions must not absorb player-owned base residents")
assert(transferredTask.state == "claimed"
    and transferredTask.claimedBy == "resident-two",
    "rejected faction transfer must preserve player-base work")

print("Companion/base domain PASS migration=true recruitment=true base=true tasks=true")
