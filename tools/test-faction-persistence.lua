local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local autonomySource = assert(io.open(
    rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomy.lua",
    "r"
)):read("*a")
assert(autonomySource:find(
    "KnoxPersistence.promoteTravelGroupToFaction(",
    1,
    true
) and autonomySource:find("minimumMembers", 1, true),
    "developer faction promotion uses the configured minimum")
assert(autonomySource:find(
    "faction = factionMinimum",
    1,
    true
), "developer faction scenarios allocate the configured minimum")

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
    return { getWorldAgeHours = function() return 10 end }
end

require "KS_Persistence"

for _, id in ipairs({ "a", "b", "c" }) do
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
end

local identity = KnoxPersistence.ensureSurvivorIdentity("a", "A", "One", 10)
assert(type(identity.sociability) == "number", "persistent sociability")
assert(type(identity.aggression) == "number", "persistent aggression")

local group = assert(KnoxPersistence.createTravelGroup({ "a", "b", "c" }, 10))
KnoxPersistence.recordEncounter("a", "b", {
    worldAgeHours = 10,
    began = true,
    sharedRoam = 1,
})
KnoxPersistence.recordEncounter("a", "c", {
    worldAgeHours = 10,
    began = true,
    sharedRoam = 1,
})

local gatedFaction, gatedResult = KnoxPersistence.evaluateTravelGroupFaction(group.id, 10, 4)
assert(gatedFaction == nil and gatedResult == "requires_4_members",
    "normal-play faction threshold can preserve a three-person travel group")
local faction, result = KnoxPersistence.evaluateTravelGroupFaction(group.id, 10)
assert(faction ~= nil and result == "created", tostring(result))
assert(#faction.memberIds == 3, "faction member count")

-- Faction growth is bounded without changing the original travel-group
-- membership rule. Existing members remain intact; a new member is accepted
-- only while the configured faction size permits it.
KnoxSettings = { npcFactionMaxMembers = function() return 3 end }
assert(KnoxPersistence.setRecord("d", "record-d"))
KnoxPersistence.ensureSurvivorIdentity("d", "D", "Four", 10)
local rejected, rejectedResult = KnoxPersistence.addTravelGroupMember(group.id, "d")
assert(rejected == nil and rejectedResult == "faction_member_limit",
    "faction growth respects configured maximum")

local candidate = {
    buildingId = "building-42",
    x = 100,
    y = 200,
    z = 0,
    minX = 98,
    minY = 198,
    width = 8,
    height = 10,
    rooms = 4,
    area = 80,
    water = true,
    score = 72,
}
local recorded, recordedResult = KnoxPersistence.recordFactionBaseCandidate(
    faction.id,
    candidate,
    10
)
assert(recorded == candidate and recordedResult == "recorded", tostring(recordedResult))
local scoutIntent = {
    kind = "investigate_building",
    phase = "reassess",
    targetKey = "faction-scout:building-42",
    startedAtHours = 10,
}
assert(KnoxPersistence.setSurvivorLifeIntent(faction.leaderId, scoutIntent, 10),
    "leader owns durable shelter-scout intent before confirmation")
assert(KnoxPersistence.setTravelGroupObjective(
    group.id, faction.leaderId, scoutIntent, 10
), "faction group shares shelter-scout objective before confirmation")
local home, homeResult = KnoxPersistence.confirmFactionHomeBase(
    faction.id,
    candidate.buildingId,
    10
)
assert(home == candidate and homeResult == "selected", tostring(homeResult))
assert(KnoxPersistence.getFactionForSurvivor("c").homeBase.buildingId == "building-42")
assert(KnoxPersistence.getSurvivorLifeIntent(faction.leaderId) == nil
    and KnoxPersistence.getTravelGroupObjective(group.id) == nil,
    "home confirmation atomically retires leader and group scouting purpose")

-- Save normalization keeps the durable home definition but drops a stale
-- runtime base link so restoration can rebuild the correct owner record.
faction.homeBaseId = "missing-base"
local normalizedLinks = KnoxPersistence.normalizeRelationshipDomains()
assert(normalizedLinks > 0 and faction.homeBase ~= nil and faction.homeBaseId == nil,
    "stale faction base links are cleared without losing the home definition")


-- Once a faction already has a home, an admitted independent becomes a base
-- resident immediately instead of remaining in autonomous roaming duty.
KnoxSettings.npcFactionMaxMembers = function() return 8 end
assert(KnoxPersistence.setRecord("growth", "record-growth"))
KnoxPersistence.ensureSurvivorIdentity("growth", "Growth", "Resident", 10)
local factionBase = assert(KnoxPersistence.createBase(
    "faction", faction.id, candidate, 10
))
faction.homeBaseId = factionBase.id
local grownGroup, grownResult = KnoxPersistence.addTravelGroupMember(group.id, "growth")
assert(grownGroup == group, "faction member admission succeeds")
local growthDuty = KnoxPersistence.getSurvivorDuty("growth")
assert(growthDuty ~= nil and growthDuty.mode == "base"
    and growthDuty.baseId == factionBase.id,
    "new faction member enters the existing home as a resident")

-- A restored faction/base must never absorb a dead identity back into its
-- roster or convert it into a resident.  Death is durable and wins over
-- settlement reconciliation.
assert(KnoxPersistence.setRecord("dead", "record-dead"))
KnoxPersistence.ensureSurvivorIdentity("dead", "Dead", "Member", 10)
assert(KnoxPersistence.markSurvivorDead("dead", 11, "test"))
assert(not KnoxPersistence.addFactionMember(faction.id, "dead", 11),
    "dead identities cannot rejoin a faction")
modData.KnoxSurvivors_IsoPlayer.bases["faction-base"] = {
    id = "faction-base", ownerKind = "faction", ownerId = faction.id,
    tasks = {},
}
local deadBaseResult = KnoxPersistence.setFactionBaseResident(
    "dead", faction.id, "faction-base", 11
)
assert(deadBaseResult == false, "dead identities cannot become residents")

local activeSafehouse = nil
SafeHouse = {
    getSafehouseOverlapping = function(x1, y1, x2, y2)
        assert(x1 == 98 and y1 == 198 and x2 == 106 and y2 == 208,
            "safehouse overlap uses x1/y1/x2/y2")
        return activeSafehouse
    end,
    addSafeHouse = function(_, _, _, _, owner)
        activeSafehouse = {
            owner = owner,
            title = "",
            getOwner = function(self) return self.owner end,
            getId = function() return "safehouse-test" end,
            getTitle = function(self) return self.title end,
            setTitle = function(self, title) self.title = title end,
        }
        return activeSafehouse
    end,
}
require "KS_FactionSafehouse"
local safehouse, safehouseResult = KnoxFactionSafehouse.ensure(faction)
assert(safehouse ~= nil and safehouseResult == "protected", tostring(safehouseResult))
assert(safehouse:getOwner() == "KnoxSurvivors:" .. faction.id)
assert(string.find(safehouse.title, "Safehouse", 1, true) ~= nil,
    "safehouse should use a readable faction title")

for _, id in ipairs({ "d", "e", "f" }) do
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
end
local secondGroup = assert(KnoxPersistence.createTravelGroup({ "d", "e", "f" }, 10))
KnoxPersistence.recordEncounter("d", "e", { worldAgeHours = 10, began = true, sharedRoam = 1 })
KnoxPersistence.recordEncounter("d", "f", { worldAgeHours = 10, began = true, sharedRoam = 1 })
local secondFaction = assert(KnoxPersistence.evaluateTravelGroupFaction(secondGroup.id, 10))
assert(KnoxPersistence.recordFactionBaseCandidate(secondFaction.id, {
    buildingId = "overlap-after-scout",
    x = 100, y = 200, z = 0, minX = 98, minY = 198,
    width = 8, height = 10, rooms = 4, area = 80, score = 99,
}, 12))
local overlapHome, overlapResult = KnoxPersistence.confirmFactionHomeBase(
    secondFaction.id, "overlap-after-scout", 12
)
assert(overlapHome == nil and overlapResult == "overlaps_existing_base",
    "stale shelter candidate cannot commit over an existing base")
assert(KnoxPersistence.recordFactionBaseCandidate(secondFaction.id, {
    buildingId = "rejected-building", x = 20, y = 30, z = 0,
}, 10))
assert(KnoxPersistence.getFactionBaseCandidate(secondFaction.id) ~= nil)
assert(KnoxPersistence.expireFactionBaseCandidate(secondFaction.id, 83, 72),
    "stale shelter leads should expire for a fresh scouting pass")
assert(KnoxPersistence.getFactionBaseCandidate(secondFaction.id) == nil)
assert(KnoxPersistence.recordFactionBaseCandidate(secondFaction.id, {
    buildingId = "rejected-building", x = 20, y = 30, z = 0,
}, 83))
assert(KnoxPersistence.rejectFactionBaseCandidate(secondFaction.id,
    "rejected-building", 83))
assert(KnoxPersistence.isFactionBaseCandidateRejected(
    secondFaction.id, "rejected-building", 83),
    "failed shelter candidates should be suppressed for a bounded period")

local disposition = KnoxPersistence.setRelationshipDisposition("a", "b", "hostile", 34)
assert(disposition.disposition == "hostile" and disposition.nextEncounterHours == 34)

print("Faction persistence PASS members=3 traits=true hostility=true home=building-42 protected=true")
