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

-- Owner-gated production writer: the schedule tab boundary.
local rota = {
    { from = 22, to = 6, assignment = "sleep" },
    { from = 6, to = 22, assignment = "work" },
}
assert(KnoxPersistence.setBaseDutySchedule("resident-1", "player-1", base.id, rota, 48),
    "owner writes resident rota")
local saved = KnoxPersistence.getDutySchedule("resident-1")
assert(saved ~= nil and #saved == 2 and saved[1].assignment == "sleep",
    "rota stored")
saved[1].assignment = "work"
assert(KnoxPersistence.getDutySchedule("resident-1")[1].assignment == "sleep",
    "stored rota is a copy")
assert(not KnoxPersistence.setBaseDutySchedule("resident-1", "player-2", base.id, rota, 48),
    "foreign player rejected")
assert(not KnoxPersistence.setBaseDutySchedule("resident-1", "player-1", "other-base", rota, 48),
    "wrong base rejected")
assert(not KnoxPersistence.setBaseDutySchedule("resident-1", "player-1", base.id, {}, 48),
    "empty schedule rejected")
assert(not KnoxPersistence.setBaseDutySchedule("resident-1", "player-1", base.id,
    { { from = 8, to = 12, assignment = "nap" } }, 48),
    "unknown assignment rejected")
assert(not KnoxPersistence.setBaseDutySchedule("resident-1", "player-1", base.id,
    { { from = -1, to = 12, assignment = "work" } }, 48),
    "out-of-range hours rejected")
local big = {}
for hour = 0, 12 do big[#big + 1] = { from = hour, to = hour + 1, assignment = "work" } end
assert(not KnoxPersistence.setBaseDutySchedule("resident-1", "player-1", base.id, big, 48),
    "oversized schedule rejected")
assert(KnoxPersistence.setBaseDutySchedule("resident-1", "player-1", base.id, nil, 48),
    "nil clears back to anything")
assert(KnoxPersistence.getDutySchedule("resident-1") == nil, "cleared rota reads nil")

-- RimWorld strip transforms: hours expand from windows and compress back.
local defaultHours = KnoxPersistence.dutyWindowsToHours(
    KnoxPersistence.defaultDutySchedule())
assert(#defaultHours == 24, "strip has 24 hours")
assert(defaultHours[24] == "sleep" and defaultHours[1] == "sleep",
    "overnight sleep spans midnight")
assert(defaultHours[9] == "work" and defaultHours[13] == "recreation",
    "day blocks expand")
local rebuilt = KnoxPersistence.hoursToDutyWindows(defaultHours)
assert(rebuilt ~= nil and KnoxPersistence.validDutySchedule(rebuilt),
    "compressed strip stays valid")
for hour = 0, 23 do
    assert(KnoxPersistence.scheduleAssignmentFor(rebuilt, hour)
        == KnoxPersistence.scheduleAssignmentFor(
            KnoxPersistence.defaultDutySchedule(), hour),
        "round trip preserves every hour")
end
local clearHours = {}
for hour = 1, 24 do clearHours[hour] = "anything" end
assert(KnoxPersistence.hoursToDutyWindows(clearHours) == nil,
    "all-anything strip clears to nil")
local striped = {}
for hour = 1, 24 do striped[hour] = (hour % 2 == 0) and "work" or "sleep" end
local merged = KnoxPersistence.hoursToDutyWindows(striped)
assert(merged ~= nil and #merged <= 12
    and KnoxPersistence.validDutySchedule(merged),
    "pathological striping merges within the backend cap")
local dirty = { [1] = "nap", [2] = "work" }
local cleaned = KnoxPersistence.hoursToDutyWindows(dirty)
assert(cleaned ~= nil and cleaned[1].assignment == "anything"
    and cleaned[2].assignment == "work",
    "unknown hours sanitize to anything")
local solo = {}
for hour = 1, 24 do solo[hour] = "recreation" end
local soloWindows = KnoxPersistence.hoursToDutyWindows(solo)
assert(soloWindows ~= nil and #soloWindows == 1
    and soloWindows[1].from == 0 and soloWindows[1].to == 24
    and soloWindows[1].assignment == "recreation",
    "single-assignment strip becomes one full-day window")

-- Watch assignments: patrol and guard validate, resolve, and round-trip.
assert(KnoxPersistence.validDutySchedule({
    { from = 22, to = 6, assignment = "sleep" },
    { from = 6, to = 14, assignment = "work" },
    { from = 14, to = 18, assignment = "patrol" },
    { from = 18, to = 22, assignment = "guard" },
}), "patrol/guard windows validate")
assert(KnoxPersistence.scheduleAssignmentFor({
    { from = 14, to = 18, assignment = "patrol" },
    { from = 18, to = 22, assignment = "guard" },
}, 15) == "patrol", "patrol hour resolves")
assert(KnoxPersistence.scheduleAssignmentFor({
    { from = 14, to = 18, assignment = "patrol" },
    { from = 18, to = 22, assignment = "guard" },
}, 20) == "guard", "guard hour resolves")
local watchHours = {}
for hour = 1, 24 do watchHours[hour] = "anything" end
for hour = 15, 18 do watchHours[hour] = "patrol" end
for hour = 19, 22 do watchHours[hour] = "guard" end
local watchWindows = KnoxPersistence.hoursToDutyWindows(watchHours)
assert(watchWindows ~= nil and KnoxPersistence.validDutySchedule(watchWindows),
    "watch strip compresses valid")
for hour = 0, 23 do
    assert(KnoxPersistence.scheduleAssignmentFor(watchWindows, hour) == watchHours[hour + 1],
        "watch round trip preserves every hour")
end

-- Plain-words summary backing: 24-hour totals, unknowns fold to anything.
local counts = KnoxPersistence.dutyHourCounts(defaultHours)
local total = counts.sleep + counts.work + counts.patrol + counts.guard
    + counts.recreation + counts.anything
assert(total == 24, "counts always total a full day")
assert(counts.sleep == 8 and counts.work == 9 and counts.recreation == 3
    and counts.anything == 4, "default rota counts read correctly")
local messy = { [1] = "nap", [2] = "work" }
local messyCounts = KnoxPersistence.dutyHourCounts(messy)
assert(messyCounts.work == 1 and messyCounts.anything == 23,
    "unknown and missing hours fold to anything")

print("Duty schedule PASS model=true player_legacy=true explicit=true npc_auto=true writer=true strip=true watch=true")
