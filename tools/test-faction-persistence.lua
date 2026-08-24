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

local faction, result = KnoxPersistence.evaluateTravelGroupFaction(group.id, 10)
assert(faction ~= nil and result == "created", tostring(result))
assert(#faction.memberIds == 3, "faction member count")

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
local home, homeResult = KnoxPersistence.confirmFactionHomeBase(
    faction.id,
    candidate.buildingId,
    10
)
assert(home == candidate and homeResult == "selected", tostring(homeResult))
assert(KnoxPersistence.getFactionForSurvivor("c").homeBase.buildingId == "building-42")

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
            setTitle = function(self, title) self.title = title end,
        }
        return activeSafehouse
    end,
}
require "KS_FactionSafehouse"
local safehouse, safehouseResult = KnoxFactionSafehouse.ensure(faction)
assert(safehouse ~= nil and safehouseResult == "protected", tostring(safehouseResult))
assert(safehouse:getOwner() == "KnoxSurvivors:" .. faction.id)

local disposition = KnoxPersistence.setRelationshipDisposition("a", "b", "hostile", 34)
assert(disposition.disposition == "hostile" and disposition.nextEncounterHours == 34)

print("Faction persistence PASS members=3 traits=true hostility=true home=building-42 protected=true")
