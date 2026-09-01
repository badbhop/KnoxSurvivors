local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path
local data = {}
ModData = { getOrCreate = function(key) data[key] = data[key] or {} return data[key] end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 24 end } end
package.preload.SpawnRegions = function() return true end
SpawnRegionMgr = { getSpawnRegions = function() return { { name = "Town", points = { unemployed = {
    { posX = 100, posY = 100, posZ = 0 }, { posX = 300, posY = 100, posZ = 0 },
    { posX = 500, posY = 100, posZ = 0 }, { posX = 700, posY = 100, posZ = 0 },
} } } } end }
getWorld = function() return { getMap = function() return "Event entry test" end } end
require "KS_Settings"
require "KS_Persistence"
require "KS_WorldPopulation"
require "KS_EventFactions"
require "KS_UnloadedSurvival"
local P, W, F, S = KnoxPersistence, KnoxWorldPopulation, KnoxEventFactions, KnoxUnloadedSurvival

local playerSquare = { getX = function() return 200 end, getY = function() return 100 end,
    getZ = function() return 0 end }
local player = { getCurrentSquare = function() return playerSquare end }
local origins = assert(W.eventEntryOrigins({ x = 200, y = 100 }, 3, "police-event-1",
    { players = { player }, minimumTargetDistance = 60, maximumTargetDistance = 400,
        minimumPlayerDistance = 60 }))
assert(#origins == 3 and origins[1].source == "knox_event")
local anchor = origins[1].eventAnchorKey
local originKeys = {}
for _, origin in ipairs(origins) do
    assert(origin.eventAnchorKey == anchor, "one party uses one believable world anchor")
    assert(not originKeys[origin.key], "party origins are distinct")
    originKeys[origin.key] = true
    local dx, dy = origin.x - playerSquare:getX(), origin.y - playerSquare:getY()
    assert(dx * dx + dy * dy >= 60 * 60, "entry origin cannot appear beside the player")
end

local faction, result = F.createEntry("police", "police-event-1", origins, 24)
assert(faction ~= nil and result == "created" and faction.eventIdentity.policyId == "police")
assert(#faction.memberIds == 3 and faction.name == "Police" and faction.kind == "npc")
local worldIds = P.getLivingWorldSurvivorIds()
assert(#worldIds == 3, "event participants are ordinary persistent world survivors")
local group = P.getTravelGroupFor(faction.memberIds[1])
assert(group ~= nil and group.factionId == faction.id and #group.memberIds == 3,
    "event party reuses ordinary travel group and faction state")
for _, id in ipairs(faction.memberIds) do
    assert(P.getRecord(id) == nil and P.getSurvivorOrigin(id).source == "knox_event")
    assert(P.getSurvivorAffiliation(id).factionId == faction.id
        and P.getSurvivorDuty(id).mode == "autonomous")
    local state = P.getUnloadedSurvivalState(id)
    local x, y = state.virtualX, state.virtualY
    local moved, why = W.advanceOriginTravel(id, 30)
    state = P.getUnloadedSurvivalState(id)
    assert(not moved and why == "event_entry_waiting" and state.virtualX == x and state.virtualY == y,
        "unmaterialized event party cannot scatter into independent itineraries")
end
local activatable = {}; for _, id in ipairs(P.getActivatableSurvivorIds()) do activatable[id] = true end
for _, id in ipairs(faction.memberIds) do assert(activatable[id], "entry survivor uses normal activation catalog") end

local beforeCount = #P.getAllWorldSurvivorIds()
local existing, existingResult = F.createEntry("police", "police-event-1", origins, 30)
assert(existing ~= nil and existingResult == "existing" and #P.getAllWorldSurvivorIds() == beforeCount,
    "reload/retry cannot duplicate an event party")
assert(F.createEntry("black_division", "too-early", origins, 24) == nil, "world-age policy is authoritative")

local unused = {
    { x = 800, y = 100, z = 0, region = "Town" },
    { x = 802, y = 100, z = 0, region = "Town" },
}
local originalAllocate, calls = P.allocateWorldSurvivor, 0
P.allocateWorldSurvivor = function(origin, hours)
    calls = calls + 1
    if calls == 2 then return nil, "fixture_failure" end
    return originalAllocate(origin, hours)
end
local root = data.KnoxSurvivors_IsoPlayer
local beforeNext, beforeFactions, beforeGroups = root.nextWorldSurvivorId, 0, 0
for _ in pairs(root.factions) do beforeFactions = beforeFactions + 1 end
for _ in pairs(root.travelGroups) do beforeGroups = beforeGroups + 1 end
local failed, failure = F.createEntry("police", "police-event-failure", unused, 24)
P.allocateWorldSurvivor = originalAllocate
local afterFactions, afterGroups = 0, 0
for _ in pairs(root.factions) do afterFactions = afterFactions + 1 end
for _ in pairs(root.travelGroups) do afterGroups = afterGroups + 1 end
assert(failed == nil and failure == "fixture_failure" and root.nextWorldSurvivorId == beforeNext)
assert(#P.getAllWorldSurvivorIds() == beforeCount and afterFactions == beforeFactions
    and afterGroups == beforeGroups, "failed batch rolls back identities, faction, group and serial")

local materializedId = faction.memberIds[1]
assert(P.setRecord(materializedId, "real-event-record"))
KnoxJavaBridge = { getTestNpcRecordX = function() return origins[1].x end,
    getTestNpcRecordY = function() return origins[1].y end,
    getTestNpcRecordZ = function() return 0 end }
assert(S.captureLoaded(materializedId, { hunger = .1, thirst = .1, fatigue = .1,
    endurance = .9, health = 100, bleedingParts = 0 }, 31))
assert(P.getUnloadedSurvivalState(materializedId).eventEntryId == nil,
    "first real body capture releases entry waiting state")

print("Event entry PASS world_origin=true player_distance=true atomic=true real_identity=true faction=true no_scatter=true retry=true")
