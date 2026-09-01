local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path
local data = { schemaVersion = 14 }
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return 168 end } end
require "KS_Persistence"
require "KS_KnoxEvents"
local P, E = KnoxPersistence, KnoxEvents

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, entry in pairs(value) do result[key] = clone(entry) end
    return result
end

local ids = { "a", "b", "c", "d", "e" }
for _, id in ipairs(ids) do
    assert(P.setRecord(id, "native-record-" .. id))
    assert(P.ensureSurvivorIdentity(id, id, "Scheduler", 0))
end
local group = assert(P.createTravelGroup(ids, 0))
for _, id in ipairs({ "b", "c", "d", "e" }) do
    P.recordEncounter("a", id, { worldAgeHours = 0, began = true, sharedRoam = 1 })
end
local faction = assert(P.evaluateTravelGroupFaction(group.id, 0))
local playerFaction = assert(P.ensurePlayerFaction("player-1", 0))
local home = assert(P.createBase("faction", faction.id,
    { minX = 100, minY = 100, width = 10, height = 10 }, 0))
local target = assert(P.createBase("player", "player-1",
    { minX = 200, minY = 200, width = 10, height = 10 }, 0))
for _, id in ipairs(ids) do assert(P.setFactionBaseResident(id, faction.id, home.id, 0)) end
local survivorCount = #P.getSurvivorIds()

local event, reason = E.scheduleAutomaticRaid(167, true, 7, 7)
assert(event == nil and reason == "world_too_young")
assert(P.getKnoxEventState().automatic.nextCheckHours == 168, "first check is persisted at minimum day")
event, reason = E.scheduleAutomaticRaid(168, false, 7, 7)
assert(event == nil and reason == "automatic_raids_disabled", "disabled policy cannot schedule")
event, reason = E.scheduleAutomaticRaid(168, true, 7, 7)
assert(event == nil and reason == "no_eligible_raid", "neutral relationship cannot trigger raid")
assert(P.getKnoxEventState().automatic.nextCheckHours == 174, "ineligible world retries at bounded interval")

assert(P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "hostile", 168, "fixture"))
P.getKnoxEventState().automatic.nextCheckHours = 168
local duties = {}; for _, id in ipairs(ids) do duties[id] = P.getSurvivorDuty(id) end
event, reason = E.scheduleAutomaticRaid(168, true, 7, 7)
assert(event ~= nil and reason == "automatic_raid_scheduled" and event.trigger == "automatic")
assert(event.phase == "scheduled" and event.dueAtHours > 168 and event.dueAtHours <= 172)
assert(event.triggerDistance > 0 and event.triggerDistance <= 600, "scheduler records plausible travel distance")
assert(#event.memberIds == 2 and #P.getSurvivorIds() == survivorCount, "scheduler uses real minority roster")
for _, id in ipairs(ids) do
    assert(P.getRecord(id) == "native-record-" .. id, "scheduler never creates or replaces equipment")
    assert(P.getSurvivorDuty(id).revision == duties[id].revision, "proposal never steals persistent duty")
end
assert(P.getKnoxEventState().automatic.nextCheckHours == 336, "successful global interval persists")
local duplicate, duplicateReason = E.scheduleAutomaticRaid(168, true, 7, 7, true)
assert(duplicate == nil and duplicateReason == "automatic_event_active", "one automatic raid at a time")

local saved = clone(data)
data = clone(saved); _G.KnoxEvents, package.loaded.KS_KnoxEvents = nil, nil; E = require "KS_KnoxEvents"
assert(E.get(event.id).trigger == "automatic"
    and P.getKnoxEventState().automatic.nextCheckHours == 336, "schedule survives save reconstruction")

data = clone(saved); _G.KnoxEvents, package.loaded.KS_KnoxEvents = nil, nil; E = require "KS_KnoxEvents"
local stored = P.getKnoxEventState().records[event.id]
assert(E.transition(event.id, stored.revision, "failed", 169, "fixture_complete"))
P.getKnoxEventState().automatic.nextCheckHours = 180
local duringCooldown, cooldownReason = E.scheduleAutomaticRaid(180, true, 7, 7, true)
assert(duringCooldown == nil and cooldownReason == "no_eligible_raid",
    "faction cooldown remains authoritative: " .. tostring(cooldownReason))

data = clone(saved); _G.KnoxEvents, package.loaded.KS_KnoxEvents = nil, nil; E = require "KS_KnoxEvents"
P.getKnoxEventState().records = {}
local targetRecord = P.getBase(target.id)
targetRecord.home.minX, targetRecord.home.minY = 1000, 1000
targetRecord.territory.minX, targetRecord.territory.minY = 1000, 1000
local distant, distantReason = E.scheduleAutomaticRaid(168, true, 7, 7, true)
assert(distant == nil and distantReason == "no_eligible_raid", "automatic raids reject implausibly distant target")

data.knoxEvents.automatic.nextCheckHours = 0 / 0
data.knoxEvents.automatic.cursor = math.huge
local normalized = P.getKnoxEventState().automatic
assert(normalized.nextCheckHours == 0 and normalized.cursor == 0, "poisoned scheduler state normalizes")

print("Automatic event scheduler PASS age=true settings=true hostility=true real_roster=true distance=true bounded=true reload=true")
