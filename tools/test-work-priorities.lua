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
package.loaded["KS_NightShelter"] = true
package.loaded["KS_SurvivorOrigins"] = true

require "KS_Persistence"
require "KS_OrderCatalog"
require "KS_BaseJobs"

-- Fixture: one player resident at a player base.
assert(KnoxPersistence.setRecord("worker-1", "record-worker-1"))
assert(KnoxPersistence.setPlayerCompanion("worker-1", "player-1", "follow", 48))
local base = assert(KnoxPersistence.createBase("player", "player-1", {
    minX = 10, minY = 10, width = 4, height = 4,
}, 48))
assert(KnoxPersistence.setPlayerBaseResident("worker-1", "player-1", base.id, 48))

-- Shape validation: known groups, 1-4 or false, at least one entry.
assert(KnoxPersistence.validWorkPriorities({ cooking = 1, repair = 4 }))
assert(KnoxPersistence.validWorkPriorities({ guard = false }))
assert(not KnoxPersistence.validWorkPriorities({}), "empty map rejected")
assert(not KnoxPersistence.validWorkPriorities({ nap = 1 }), "unknown group rejected")
assert(not KnoxPersistence.validWorkPriorities({ cooking = 0 }), "zero rejected")
assert(not KnoxPersistence.validWorkPriorities({ cooking = 5 }), "five rejected")
assert(not KnoxPersistence.validWorkPriorities({ cooking = 2.5 }), "fractions rejected")
assert(not KnoxPersistence.validWorkPriorities("cooking"), "non-table rejected")

-- Owner-gated writer: same boundary rules as the other base-tab writers.
assert(KnoxPersistence.setBaseWorkPriorities("worker-1", "player-1", base.id,
    { cooking = 1, repair = 4 }, 48), "owner writes priorities")
local stored = KnoxPersistence.getWorkPriorities("worker-1")
assert(stored ~= nil and stored.cooking == 1 and stored.repair == 4,
    "priorities stored")
stored.cooking = 4
assert(KnoxPersistence.getWorkPriorities("worker-1").cooking == 1,
    "stored map is a copy")
assert(not KnoxPersistence.setBaseWorkPriorities("worker-1", "player-2", base.id,
    { cooking = 1 }, 48), "foreign player rejected")
assert(not KnoxPersistence.setBaseWorkPriorities("worker-1", "player-1", "other-base",
    { cooking = 1 }, 48), "wrong base rejected")
assert(not KnoxPersistence.setBaseWorkPriorities("worker-1", "player-1", base.id,
    { nap = 1 }, 48), "bad shape rejected")
assert(KnoxPersistence.setBaseWorkPriorities("worker-1", "player-1", base.id, nil, 48),
    "nil clears back to automatic")
assert(KnoxPersistence.getWorkPriorities("worker-1") == nil, "cleared reads nil")

-- Election: score-based hook inside the existing preference passes.
local function tasks()
    return {
        { id = "cook-1", type = "cook", state = "queued", priority = 85 },
        { id = "repair-1", type = "repair", state = "queued", priority = 50 },
    }
end
local function alwaysEligible() return true end
local picked = KnoxBaseJobs.selectEligibleTask(tasks(), "worker-1", base.id, "auto", alwaysEligible)
assert(picked ~= nil and picked.id == "cook-1", "legacy automatic behavior untouched")
assert(KnoxPersistence.setBaseWorkPriorities("worker-1", "player-1", base.id,
    { repair = 1 }, 48))
picked = KnoxBaseJobs.selectEligibleTask(tasks(), "worker-1", base.id, "auto", alwaysEligible)
assert(picked ~= nil and picked.id == "repair-1", "priority 1 outranks base urgency")
assert(KnoxPersistence.setBaseWorkPriorities("worker-1", "player-1", base.id,
    { cooking = false }, 48))
picked = KnoxBaseJobs.selectEligibleTask(tasks(), "worker-1", base.id, "auto", alwaysEligible)
assert(picked ~= nil and picked.id == "repair-1", "never excludes the group")
assert(KnoxPersistence.setBaseWorkPriorities("worker-1", "player-1", base.id,
    { cooking = 1, repair = 4 }, 48))
picked = KnoxBaseJobs.selectEligibleTask(tasks(), "worker-1", base.id, "auto", alwaysEligible)
assert(picked ~= nil and picked.id == "cook-1", "1 beats 4 across groups")

-- Overlap: barricade belongs to woodwork and barricade; one owner allowing
-- keeps it eligible, both never excludes it.
local function barricadeTasks()
    return {
        { id = "bar-1", type = "barricade", state = "queued", priority = 50 },
        { id = "repair-1", type = "repair", state = "queued", priority = 50 },
    }
end
assert(KnoxPersistence.setBaseWorkPriorities("worker-1", "player-1", base.id,
    { woodwork = false }, 48))
picked = KnoxBaseJobs.selectEligibleTask(barricadeTasks(), "worker-1", base.id, "auto", alwaysEligible)
assert(picked ~= nil and picked.id == "bar-1", "second owning group keeps eligibility")
assert(KnoxPersistence.setBaseWorkPriorities("worker-1", "player-1", base.id,
    { woodwork = false, barricade = false }, 48))
picked = KnoxBaseJobs.selectEligibleTask(barricadeTasks(), "worker-1", base.id, "auto", alwaysEligible)
assert(picked ~= nil and picked.id == "repair-1", "all owners never excludes the task")

print("Work priorities PASS validation=true ownership=true election=true overlap=true legacy=true")
