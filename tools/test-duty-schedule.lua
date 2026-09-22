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
local currentHour = 12
getTimeOfDay = function() return currentHour end

package.loaded["KS_BaseTaskBoard"] = true
package.loaded["KS_BaseStorage"] = true
package.loaded["KS_BaseBarricades"] = true
package.loaded["KS_BaseFarming"] = true
package.loaded["KS_BaseWoodcutting"] = true
package.loaded["KS_BaseCorpseHandling"] = true
package.loaded["KS_BaseCooking"] = true
package.loaded["KS_BaseRepairs"] = true
package.loaded["KS_BaseNeeds"] = true
package.loaded["KS_BaseSupplyPlanner"] = true
package.loaded["KS_CompanionPatrol"] = true
package.loaded["KS_JobTestSupplies"] = true

require "KS_Persistence"
require "KS_BaseJobs"

-- Model: windows match, overnight wraps, first match wins, garbage out.
assert(KnoxPersistence.validDutySchedule({
    { from = 22, to = 6, assignment = "sleep" },
    { from = 6, to = 22, assignment = "work" },
}))
assert(not KnoxPersistence.validDutySchedule({}), "empty schedule rejected")
assert(not KnoxPersistence.validDutySchedule({
    { from = 8, to = 12, assignment = "nap" },
}), "unknown assignment rejected")
assert(not KnoxPersistence.validDutySchedule({
    { from = -1, to = 12, assignment = "work" },
}), "out-of-range hours rejected")
assert(KnoxPersistence.scheduleAssignmentFor({
    { from = 22, to = 6, assignment = "sleep" },
    { from = 6, to = 22, assignment = "work" },
}, 23) == "sleep", "overnight window matches")
assert(KnoxPersistence.scheduleAssignmentFor({
    { from = 22, to = 6, assignment = "sleep" },
    { from = 6, to = 22, assignment = "work" },
}, 5) == "sleep", "overnight window covers early hours")
assert(KnoxPersistence.scheduleAssignmentFor({
    { from = 22, to = 6, assignment = "sleep" },
    { from = 6, to = 22, assignment = "work" },
}, 12) == "work", "day window matches")
assert(KnoxPersistence.scheduleAssignmentFor(nil, 12) == "anything",
    "missing schedule preserves historical behavior")

-- Player resident without a schedule keeps legacy behavior at every hour.
assert(KnoxPersistence.setRecord("resident-1", "record-resident-1"))
assert(KnoxPersistence.setPlayerCompanion("resident-1", "player-1", "follow", 48))
local base = assert(KnoxPersistence.createBase("player", "player-1", {
    minX = 10, minY = 10, width = 4, height = 4,
}, 48))
assert(KnoxPersistence.setPlayerBaseResident("resident-1", "player-1", base.id, 48))
currentHour = 23
assert(KnoxBaseJobs.scheduleAssignment("resident-1") == "anything",
    "player resident without a schedule stays on anything")

-- Explicit schedule drives the assignment clock.
assert(KnoxPersistence.setDutySchedule("resident-1", {
    { from = 22, to = 6, assignment = "sleep" },
    { from = 6, to = 22, assignment = "recreation" },
}, 48))
assert(KnoxBaseJobs.scheduleAssignment("resident-1") == "sleep")
currentHour = 14
assert(KnoxBaseJobs.scheduleAssignment("resident-1") == "recreation")
assert(not KnoxPersistence.setDutySchedule("resident-1", {
    { from = 8, to = 12, assignment = "nap" },
}, 48), "invalid schedule rejected")

-- NPC faction resident lazily receives the default clock once.
local npcIds = {}
for index = 1, 4 do
    local id = "npc-" .. index
    npcIds[#npcIds + 1] = id
    assert(KnoxPersistence.setRecord(id, "record-" .. id))
end
local group = assert(KnoxPersistence.createTravelGroup(npcIds, 48))
for index = 2, #npcIds do
    KnoxPersistence.recordEncounter(npcIds[1], npcIds[index], {
        worldAgeHours = 48, began = true, sharedRoam = 1,
    })
end
local faction = assert(KnoxPersistence.evaluateTravelGroupFaction(group.id, 48))
assert(faction ~= nil, "npc faction fixture")
local npcBase = assert(KnoxPersistence.createBase("faction", faction.id, {
    minX = 100, minY = 100, width = 8, height = 8,
}, 48))
for _, id in ipairs(npcIds) do
    assert(KnoxPersistence.setFactionBaseResident(id, faction.id, npcBase.id, 48))
end
currentHour = 3
assert(KnoxBaseJobs.scheduleAssignment("npc-1") == "sleep",
    "npc resident auto-defaults to the shared clock")
currentHour = 10
assert(KnoxBaseJobs.scheduleAssignment("npc-1") == "work",
    "npc work window defers to preference machinery")
local stored = KnoxPersistence.getDutySchedule("npc-1")
assert(stored ~= nil and #stored == 7, "auto default persists once")

print("Duty schedule PASS model=true player_legacy=true explicit=true npc_auto=true")
