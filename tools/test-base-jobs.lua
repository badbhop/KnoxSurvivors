local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["KS_Persistence"] = true
package.loaded["KS_BaseTaskBoard"] = true
package.loaded["KS_BaseStorage"] = true
package.loaded["KS_BaseBarricades"] = true
package.loaded["KS_BaseFarming"] = true
package.loaded["KS_BaseWoodcutting"] = true
package.loaded["KS_BaseCorpseHandling"] = true
package.loaded["KS_BaseAnimalCare"] = true
package.loaded["KS_BaseRepairs"] = true
package.loaded["KS_BaseCooking"] = true
package.loaded["KS_BaseConstruction"] = true
package.loaded["KS_BaseSupplyPlanner"] = true
local depotTransfer = nil
local storageSummary = nil
KnoxBaseStorage = {
    findTransfer = function()
        return depotTransfer, depotTransfer ~= nil and "found" or "no_matching_depot_item"
    end,
    transferTarget = function(value)
        return value ~= nil and value.target or nil
    end,
    summarize = function()
        return storageSummary or {
            totals = {}, loadedPolicies = 0,
            unavailablePolicies = 0, misplacedItems = 0,
        }
    end,
}
KnoxBaseSupplyPlanner = {
    reserveStatus = function(totals, residents)
        return {
            { kind = "find_food", category = "food", current = totals.food,
                target = residents * 2, missing = residents * 2 - totals.food },
        }
    end,
    shortages = function() return { "find_food", "find_weapon" } end,
}
KnoxBaseBarricades = {
    canPrepare = function() return false end,
}
KnoxBaseFarming = {
    findTask = function() return nil, "no_farming_action_ready" end,
}
KnoxBaseWoodcutting = {
    findTask = function() return nil, "no_tree_ready" end,
}
local corpseTarget = nil
KnoxBaseCorpseHandling = {
    findTask = function()
        return corpseTarget, corpseTarget ~= nil and "found" or "no_corpse_ready"
    end,
}
local animalTarget = nil
KnoxBaseAnimalCare = {
    findTask = function()
        return animalTarget,
            animalTarget ~= nil and "water" or "no_animal_care_ready"
    end,
}
local repairTarget = nil
KnoxBaseRepairs = {
    findTask = function()
        return repairTarget,
            repairTarget ~= nil and "found" or "no_repair_ready"
    end,
}
local constructionTarget = nil
KnoxBaseConstruction = {
    findTask = function() return constructionTarget end,
    requirements = function(target) return target ~= nil and {
        items = { ["Base.Hammer"] = 1, ["Base.Plank"] = 2, ["Base.Nails"] = 2 },
        skills = { Woodwork = 2 },
    } or nil end,
}

local now = 10
local persistedTasks = nil
local reconcileCalls = 0
getGameTime = function()
    return { getWorldAgeHours = function() return now end }
end

local base = {
    id = "base-1",
    settings = { automaticJobs = true },
    zones = {
        guard = {
            id = "base-1-zone-guard",
            type = "guard",
            label = "Front gate",
            x1 = 10, y1 = 20, x2 = 14, y2 = 24, z = 0,
            priority = 80,
            enabled = true,
        },
        farming = {
            id = "base-1-zone-farm",
            type = "farming",
            label = "Garden",
            x1 = 30, y1 = 40, x2 = 34, y2 = 44, z = 0,
            priority = 100,
            enabled = true,
        },
    },
    tasks = {},
    nextTaskId = 1,
}

KnoxPersistence = {
    reconcileBaseTaskClaims = function() reconcileCalls = reconcileCalls + 1 end,
    queueBaseTask = function(baseId, taskType, target, requirements, priority)
        local task = {
            id = "task-" .. tostring(base.nextTaskId),
            baseId = baseId,
            type = taskType,
            state = "queued",
            target = target,
            requirements = requirements,
            priority = priority,
            attempts = 0,
        }
        base.nextTaskId = base.nextTaskId + 1
        base.tasks[task.id] = task
        return task, "queued"
    end,
    requeueBaseTask = function(baseId, taskId, worldAgeHours)
        local task = base.tasks[taskId]
        assert(task ~= nil and task.state == "complete")
        task.state = "queued"
        task.requeuedAtHours = worldAgeHours
        return task, "requeued"
    end,
    getSurvivorDuty = function(id)
        return id == "resident-a" and { lastJobType = "guard" } or nil
    end,
    getBase = function(baseId)
        if baseId ~= base.id then return nil end
        return { tasks = persistedTasks or {} }
    end,
    getSurvivorCapabilities = function(id)
        return id == "skilled" and { skills = { Aiming = { level = 4 } } } or { skills = {} }
    end,
}
KnoxSurvivorCapabilities = {
    skillLevel = function(profile, perkId)
        local saved = profile ~= nil and profile.skills ~= nil and profile.skills[perkId] or nil
        return saved ~= nil and saved.level or 0
    end,
}

KnoxBaseTaskBoard = {
    queue = function(baseId, taskType, target, requirements, priority)
        return KnoxPersistence.queueBaseTask(
            baseId, taskType, target, requirements, priority
        )
    end,
    queued = function()
        local tasks = {}
        for _, value in pairs(base.tasks) do
            if value.state == "queued" then
                tasks[#tasks + 1] = value
            end
        end
        table.sort(tasks, function(first, second)
            return first.priority > second.priority
        end)
        return tasks
    end,
}

local function square(x, y, z)
    local result = { x = x, y = y, z = z }
    function result:getX() return self.x end
    function result:getY() return self.y end
    function result:getZ() return self.z end
    function result:canStand() return true end
    return result
end

getCell = function()
    return {
        getGridSquare = function(_, x, y, z) return square(x, y, z) end,
    }
end

local jobs = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseJobs.lua")

local coverage = jobs.securityCoverage({
    zones = {
        { type = "guard", enabled = true },
        { type = "patrol_area", enabled = true },
        { type = "guard", enabled = false },
    },
    tasks = {
        { id = "watch-1", type = "guard", state = "claimed", claimedBy = "a" },
        { type = "patrol_area", state = "claimed", claimedBy = "b" },
        { type = "patrol", state = "queued" },
        { id = "watch-1", type = "guard", state = "claimed", claimedBy = "a" },
    },
})
assert(coverage.guardPosts == 1 and coverage.patrolRoutes == 1,
    "security coverage must count enabled legacy patrol zones")
assert(coverage.activeGuard == 1 and coverage.activePatrol == 1
    and coverage.staffed == 2 and coverage.available == 0,
    "security coverage must normalize claimed legacy patrol tasks")
local originalResidentIds = KnoxPersistence.getBaseResidentIds
KnoxPersistence.getBaseResidentIds = function() return { "a", "b", "c", "d" } end
local understaffed = jobs.securityCoverage({
    id = "security-base",
    zones = { { type = "guard", enabled = true }, { type = "patrol", enabled = true } },
    tasks = { { id = "only-watch", type = "guard", state = "claimed", claimedBy = "a" } },
})
assert(understaffed.required == 2 and understaffed.understaffed == 1,
    "established bases should expose missing security coverage")
local staleCoverage = jobs.securityCoverage({
    id = "security-base",
    zones = { { type = "guard", enabled = true }, { type = "patrol", enabled = true } },
    tasks = {
        { id = "dead-watch", type = "guard", state = "claimed", claimedBy = "former" },
        { id = "live-patrol", type = "patrol", state = "claimed", claimedBy = "b" },
    },
})
assert(staleCoverage.activeGuard == 0 and staleCoverage.activePatrol == 1
    and staleCoverage.understaffed == 1,
    "stale security claimants must not count as staffed coverage")
KnoxPersistence.getBaseResidentIds = originalResidentIds

-- Workforce projection is read-only and must classify persisted claims without
-- creating a second scheduler or treating resting residents as available work.
local workforceBase = {
    id = "workforce-base",
    tasks = {
        manual = { id = "manual", type = "guard", state = "claimed", claimedBy = "worker-a", manual = true },
        automatic = { id = "automatic", type = "farm_water", state = "claimed", claimedBy = "worker-b", auto = true },
        stale = { id = "stale", type = "repair", state = "claimed", claimedBy = "former-resident", manual = true },
        queued = { id = "queued", type = "repair", state = "queued" },
    },
}
local savedResidents = KnoxPersistence.getBaseResidentIds
local savedDuty = KnoxPersistence.getSurvivorDuty
KnoxPersistence.getBaseResidentIds = function()
    return { "worker-a", "worker-b", "resting-c", "idle-d", "supply-e" }
end
KnoxPersistence.getSurvivorDuty = function(id)
    if id == "resting-c" then return { jobPreference = "rest" } end
    if id == "supply-e" then
        return { jobPreference = "auto", activeSupplyRun = { kind = "find_food" } }
    end
    return { jobPreference = "auto" }
end
local workforce = jobs.workforceSummary(workforceBase)
assert(workforce.residents == 5 and workforce.working == 3
    and workforce.resting == 1 and workforce.idle == 1
    and workforce.supplyRuns == 1
    and workforce.manual == 1 and workforce.automatic == 1
    and workforce.queued == 1 and workforce.claimed == 2,
    "workforce summary should classify resident duty and persisted claims")
assert(workforce.claimedBy["former-resident"] == nil and workforce.manual == 1,
    "stale non-resident claims must not inflate workforce ownership counts")
assert(workforce.taskTypes.guard == 1 and workforce.taskTypes.farm_water == 1,
    "workforce summary should expose canonical claimed task types")
storageSummary = {
    totals = { food = 2, water = 8, medical = 1, weapons = 0, tools = 1 },
    loadedPolicies = 2, unavailablePolicies = 1, misplacedItems = 0,
}
local settlement = jobs.settlementSummary(workforceBase, 10)
assert(settlement.stockKnown == true and #settlement.shortages == 2,
    "settlement summary should expose authoritative loaded-storage shortages")
assert(settlement.tasks.queued == 1 and settlement.tasks.claimed == 3,
    "settlement summary should count the persisted task board without mutation")
workforceBase.tasks.blocked = {
    id = "blocked", type = "barricade", state = "blocked",
    retryAtHours = 12, result = "missing_materials",
}
settlement = jobs.settlementSummary(workforceBase, 10)
assert(settlement.tasks.blocked == 1 and settlement.tasks.retrying == 1,
    "settlement summary should distinguish blocked work cooling down for retry")
storageSummary = nil
KnoxPersistence.getBaseResidentIds = savedResidents
KnoxPersistence.getSurvivorDuty = savedDuty

-- Every task type exposed by the automatic executors must remain selectable at
-- the task-board boundary. This catches a real executor being added without
-- admitting its persisted task type to automatic resident duty.
for _, taskType in ipairs({
    "chop_tree", "saw_logs", "haul_corpse", "animal_care", "animal_water",
    "animal_feed", "repair", "construct_defense",
}) do
    assert(jobs.AUTOMATIC_TYPES[taskType] == true,
        "supported task type must be admitted to automatic duty: " .. taskType)
end
assert(jobs.effectivePreference({ jobPreference = "guard" }, {
    professionId = "base:carpenter",
}) == "guard", "explicit base role must remain authoritative")
assert(jobs.effectivePreference({ jobPreference = "auto" }, {
    professionId = "base:carpenter",
}) == "woodwork", "auto carpenter should receive a woodwork hint")
assert(jobs.effectivePreference({ jobPreference = "auto" }, {
    professionId = "base:policeofficer",
}) == "guard", "auto security profession should receive a guard hint")
assert(jobs.effectivePreference({ jobPreference = "auto" }, {
    professionId = "base:farmer",
}) == "farming", "auto farmer should receive a farming hint")
assert(jobs.effectivePreference({ jobPreference = "auto" }, {
    professionId = "base:unemployed",
}) == "auto", "unmatched profession should remain auto")
assert(jobs.effectivePreference({ jobPreference = "barricade" }, {}) == "woodwork",
    "legacy barricade preference should normalize to woodwork")
local preferredSecurity = jobs.selectEligibleTask({
    { id = "task-aim", type = "guard", state = "queued", priority = 50 },
    { id = "task-other", type = "repair", state = "queued", priority = 50 },
}, "skilled", base.id, "auto", function() return true end)
assert(preferredSecurity ~= nil and preferredSecurity.type == "guard",
    "eligible residents should prefer a matching skill on equal-priority work")
local savedSecurityResidents = KnoxPersistence.getBaseResidentIds
KnoxPersistence.getBaseResidentIds = function() return { "auto-a", "auto-b" } end
local minimumWatch = jobs.selectEligibleTask({
    { id = "watch", type = "guard", state = "queued", priority = 20 },
    { id = "urgent-work", type = "repair", state = "queued", priority = 100 },
}, "auto-a", base.id, "auto", function() return true end)
assert(minimumWatch ~= nil and minimumWatch.type == "guard",
    "automatic workforce must fill minimum security before routine work")
local explicitFarmer = jobs.selectEligibleTask({
    { id = "watch", type = "guard", state = "queued", priority = 100 },
    { id = "crops", type = "farm_water", state = "queued", priority = 20 },
}, "auto-a", base.id, "farming", function() return true end)
assert(explicitFarmer ~= nil and explicitFarmer.type == "farm_water",
    "explicit non-security roles must remain authoritative")
KnoxPersistence.getBaseResidentIds = savedSecurityResidents
local task, result = jobs.ensureAutomaticTask(base)
assert(task ~= nil and task.type == "guard", "guard zone should be first supported job")
assert(result == "ready" and task.target.autoZoneId == "base-1-zone-guard")

local sameTask, sameResult = jobs.ensureAutomaticTask(base)
assert(sameTask == task and sameResult == "ready", "queued job should be reused")
assert(reconcileCalls == 1,
    "unchanged settlement should not reconcile claims on every resident tick")

task.state = "complete"
task.retryAtHours = now
local reopened, reopenedResult = jobs.ensureAutomaticTask(base)
assert(reopened == task and reopenedResult == "ready")
assert(task.state == "queued" and task.requeuedAtHours == now)

local target = jobs.resolveTaskSquare(task, {
    getCurrentSquare = function() return square(0, 0, 0) end,
})
assert(target ~= nil and target:getZ() == 0, "work zone should resolve to a loaded square")
assert(jobs.workDuration({ type = "guard" }) > jobs.workDuration({ type = "patrol" }))

task.claimedBy = "resident-a"
local guardPost = jobs.resolveTaskSquare(task, {
    getCurrentSquare = function() return square(0, 0, 0) end,
})
assert(guardPost ~= nil and not (guardPost:getX() == 12 and guardPost:getY() == 22),
    "guard work should hold a deterministic area post rather than its center")
local patrolTask = {
    id = "patrol-test", claimedBy = "resident-a", type = "patrol",
    patrolStep = 0,
    target = { zoneType = "patrol", x1 = 20, y1 = 30, x2 = 28, y2 = 38, z = 0 },
}
local patrolFirst = jobs.resolveTaskSquare(patrolTask, {
    getCurrentSquare = function() return square(0, 0, 0) end,
})
patrolTask.patrolStep = 1
local patrolSecond = jobs.resolveTaskSquare(patrolTask, {
    getCurrentSquare = function() return square(0, 0, 0) end,
})
assert(patrolFirst ~= nil and patrolSecond ~= nil
    and (patrolFirst:getX() ~= patrolSecond:getX()
        or patrolFirst:getY() ~= patrolSecond:getY()),
    "base patrol progress should resolve consecutive distinct route stops")

-- A resident's chosen role should be a first choice without becoming a hard
-- lock that leaves useful work untouched when that role is unavailable.
base.zones = {}
base.tasks = {
    guard = { id = "guard", type = "guard", state = "queued", priority = 80 },
    farm = { id = "farm", type = "farm_water", state = "queued", priority = 40 },
}
local preferredTask, preferredResult = jobs.ensureAutomaticTask(base, nil, nil, "farming")
assert(preferredTask ~= nil and preferredTask.id == "farm"
    and preferredResult == "ready", "farming preference should choose farming first")
base.tasks.farm.state = "claimed"
local fallbackTask, fallbackResult = jobs.ensureAutomaticTask(base, nil, nil, "farming")
assert(fallbackTask ~= nil and fallbackTask.id == "guard"
    and fallbackResult == "fallback_ready", "preference should fall back to needed work")

local distributed = jobs.selectEligibleTask({
    { id = "guard-active", type = "guard", state = "claimed", priority = 90 },
    { id = "guard-next", type = "guard", state = "queued", priority = 90 },
    { id = "farm-next", type = "farm_water", state = "queued", priority = 86 },
}, "resident-b", base.id, "auto", function() return true end)
assert(distributed ~= nil and distributed.id == "farm-next",
    "active work-type penalty should distribute equally useful jobs")
KnoxPersistence.getBaseResidentIds = function() return { "resident-a", "resident-b" } end
KnoxPersistence.getSurvivorDuty = function() return nil end
local coverage = jobs.selectEligibleTask({
    { id = "coverage-guard", type = "guard", state = "queued", priority = 80 },
    { id = "coverage-farm", type = "farm_water", state = "queued", priority = 90 },
}, "resident-a", base.id, "auto", function() return true end)
assert(coverage ~= nil and coverage.id == "coverage-guard",
    "a populated base should establish security coverage when none is active")
persistedTasks = {
    ["active-watch"] = { id = "active-watch", type = "guard", state = "claimed" },
}
local covered = jobs.selectEligibleTask({
    { id = "covered-farm", type = "farm_water", state = "queued", priority = 90 },
}, "resident-b", base.id, "auto", function() return true end)
assert(covered ~= nil and covered.id == "covered-farm",
    "security coverage bonus should yield to useful work once a guard is active")
persistedTasks = {
    ["legacy-active-sort"] = {
        id = "legacy-active-sort", type = "storage_sorting", state = "claimed",
    },
}
local legacyActive = jobs.selectEligibleTask({
    { id = "legacy-next-sort", type = "haul", state = "queued", priority = 70 },
    { id = "legacy-next-farm", type = "farm_water", state = "queued", priority = 70 },
}, "resident-b", base.id, "auto", function() return true end)
assert(legacyActive ~= nil and legacyActive.id == "legacy-next-farm",
    "legacy active task types must share canonical fairness accounting")
persistedTasks = nil
local relief = jobs.selectEligibleTask({
    { id = "relief-guard", type = "guard", state = "queued", priority = 90,
        lastClaimedBy = "resident-a", lastClaimedAtHours = now - 1 },
    { id = "relief-farm", type = "farm_water", state = "queued", priority = 80 },
}, "resident-a", base.id, "auto", function() return true end)
assert(relief ~= nil and relief.id == "relief-farm",
    "recurring security work should prefer resident relief when alternatives exist")
KnoxPersistence.getSurvivorDuty = function(id)
    return id == "resident-a" and { lastJobType = "guard" } or nil
end
KnoxPersistence.getBaseResidentIds = function() return { "resident-a" } end
local rotated = jobs.selectEligibleTask({
    { id = "same-kind", type = "guard", state = "queued", priority = 80 },
    { id = "new-kind", type = "farm_water", state = "queued", priority = 76 },
}, "resident-a", base.id, "auto", function() return true end)
assert(rotated ~= nil and rotated.id == "new-kind",
    "automatic residents should receive a different near-equal job after guard work")
local explicitRotation = jobs.selectEligibleTask({
    { id = "preferred-guard", type = "guard", state = "queued", priority = 80 },
    { id = "other-work", type = "farm_water", state = "queued", priority = 86 },
}, "resident-a", base.id, "guard", function() return true end)
assert(explicitRotation ~= nil and explicitRotation.id == "preferred-guard",
    "explicit resident preference must override the soft rotation hint")
local legacyPreference = jobs.selectEligibleTask({
    { id = "legacy-woodwork", type = "barricade", state = "queued", priority = 70 },
    { id = "legacy-farm", type = "farm_water", state = "queued", priority = 95 },
}, "resident-a", base.id, "barricade", function() return true end)
assert(legacyPreference ~= nil and legacyPreference.id == "legacy-woodwork",
    "legacy player-facing labels must normalize before task selection")
local legacyTaskType = jobs.selectEligibleTask({
    { id = "legacy-storage", type = "storage_sorting", state = "queued", priority = 75 },
    { id = "ordinary-farm", type = "farm_water", state = "queued", priority = 80 },
}, "resident-a", base.id, "hauling", function() return true end)
assert(legacyTaskType == nil or legacyTaskType.id ~= "legacy-storage",
    "legacy task types must normalize before resident preference matching")
KnoxPersistence.getBaseResidentIds = function() return {
    "resident-a", "resident-b", "resident-c", "resident-d",
} end
local secondWatch = jobs.selectEligibleTask({
    { id = "active-watch", type = "guard", state = "claimed", priority = 80 },
    { id = "second-patrol", type = "patrol", state = "queued", priority = 80 },
    { id = "second-farm", type = "farm_water", state = "queued", priority = 94 },
}, "resident-c", base.id, "auto", function() return true end)
assert(secondWatch ~= nil and secondWatch.id == "second-patrol",
    "larger bases should add one relief watch without staffing every resident")
KnoxPersistence.getBaseResidentIds = nil
base.zones = {
    guard = {
        id = "base-1-zone-guard", type = "guard", label = "Front gate",
        x1 = 10, y1 = 20, x2 = 14, y2 = 24, z = 0, priority = 80, enabled = true,
    },
    farming = {
        id = "base-1-zone-farm", type = "farming", label = "Garden",
        x1 = 30, y1 = 40, x2 = 34, y2 = 44, z = 0, priority = 100, enabled = true,
    },
}
base.tasks = {}
base.nextTaskId = 1

depotTransfer = {
    target = {
        id = "sort-depot:depot:food",
        zoneType = "sort_depot",
        sourceKey = "depot",
        destinationKey = "food",
        itemType = "Base.TinnedSoup",
        category = "food",
        x = 10, y = 20, z = 0,
    },
}
local depotTask, depotResult = jobs.ensureAutomaticTask(base)
assert(depotTask == nil or depotTask.type ~= "sort_depot", "available depot transfer should be scheduled")

corpseTarget = {
    id = "corpse:base-1:cleanup:10:20:0:item-99",
    action = "haul_corpse",
    zoneType = "corpse",
    zoneId = "cleanup",
    corpseX = 10, corpseY = 20, corpseZ = 0,
    dropX = 12, dropY = 22, dropZ = 0,
}
local corpseTask, corpseResult = jobs.ensureAutomaticTask(base)
assert(corpseTask ~= nil and corpseTask.type == "haul_corpse"
    and corpseTask.priority == 92 and corpseResult == "ready",
    "task-board priority should prevent renewable work from starving cleanup")

base.tasks = {}
base.nextTaskId = 1
depotTransfer = nil
corpseTarget = nil
animalTarget = {
    id = "animal-care:base-1:pasture:animal_water:30:40:0:2",
    action = "animal_water",
    zoneType = "animal_care",
    zoneId = "pasture",
    x = 30, y = 40, z = 0,
    objectIndex = 2,
    itemType = "Base.WaterBottleFull",
    itemId = "123",
}
local animalTask, animalResult = jobs.ensureAutomaticTask(base)
assert(animalTask ~= nil and animalTask.type == "animal_water"
    and animalTask.priority == 89 and animalResult == "ready")
assert(animalTask.requirements.items["Base.WaterBottleFull"] == 1,
    "animal task should require the exact carried supply type")

-- An Animal Care zone is only a discovery area for the concrete trough
-- executors above.  It must never be emitted as an unsupported generic task.
base.tasks = {}
base.nextTaskId = 1
animalTarget = nil
base.zones = {
    animal = {
        id = "base-1-zone-animal", type = "animal_care", label = "Trough",
        x1 = 30, y1 = 40, x2 = 34, y2 = 44, z = 0, priority = 86, enabled = true,
    },
}
local noGenericAnimalTask = jobs.ensureAutomaticTask(base)
assert(noGenericAnimalTask == nil,
    "animal care zone must not create an unsupported generic task")

-- A migrated patrol-area zone should still feed the recurring patrol executor
-- without rewriting the saved zone label or creating a second work area.
base.tasks = {}
base.nextTaskId = 1
base.zones = {
    legacyPatrol = {
        id = "base-1-zone-legacy-patrol", type = "patrol_area", label = "Old Watch",
        x1 = 20, y1 = 30, x2 = 24, y2 = 34, z = 0, priority = 72, enabled = true,
    },
}
local legacyPatrolTask = jobs.ensureAutomaticTask(base)
assert(legacyPatrolTask ~= nil and legacyPatrolTask.type == "patrol"
    and legacyPatrolTask.target.zoneType == "patrol"
    and base.zones.legacyPatrol.type == "patrol_area",
    "legacy patrol-area zones must schedule patrol without mutating the saved zone")

base.tasks = {}
base.nextTaskId = 1
animalTarget = nil
repairTarget = {
    id = "repair:base-1:territory:12:20:0:4:door",
    action = "repair",
    zoneType = "repair",
    x = 12, y = 20, z = 0,
    objectIndex = 4,
    spriteName = "door",
    requiredItems = {
        ["Base.Hammer"] = 1,
        ["Base.Plank"] = 2,
    },
}
local repairTask, repairResult = jobs.ensureAutomaticTask(base)
assert(repairTask ~= nil and repairTask.type == "repair"
    and repairTask.priority == 94 and repairResult == "ready")
assert(repairTask.requirements.items["Base.Plank"] == 2,
    "repair task should retain vanilla material requirements")

base.tasks = {}
base.nextTaskId = 1
repairTarget = nil
constructionTarget = {
    id = "construct:base-1:wall_frame:10:10:0:N",
    action = "construct_defense", kind = "wall_frame", entityName = "WoodenWallFrame",
    x = 10, y = 10, z = 0, north = true,
}
local constructionTask, constructionResult = jobs.ensureAutomaticTask(base)
assert(constructionTask ~= nil and constructionTask.type == "construct_defense"
    and constructionTask.priority == 96 and constructionResult == "ready",
    "available defense construction should be queued ahead of routine work")
assert(constructionTask.requirements.skills.Woodwork == 2,
    "construction task preserves entity recipe skill requirements")

-- Log Processing is an existing player-facing work-area type and must use the
-- same real log/saw executor as a Woodcutting area.
base.tasks = {}
base.nextTaskId = 1
base.zones = {
    logs = {
        id = "base-1-zone-logs", type = "log_processing", label = "Saw bench",
        x1 = 50, y1 = 60, x2 = 54, y2 = 64, z = 0, priority = 78, enabled = true,
    },
}
constructionTarget = nil
repairTarget, animalTarget, corpseTarget = nil, nil, nil
KnoxBaseFarming.findTask = function() return nil, "no_farming_action_ready" end
KnoxBaseWoodcutting.findTask = function()
    return {
        id = "sawlogs:base-1:log-1", action = "saw_logs",
        zoneType = "saw_logs", zoneId = "base-1-zone-logs",
        x = 52, y = 62, z = 0, logType = "Base.Log", sawType = "Base.HandSaw",
    }, "saw_logs"
end
local logTask, logResult = jobs.ensureAutomaticTask(base)
assert(logTask ~= nil and logTask.type == "saw_logs" and logResult == "ready"
    and logTask.target.zoneId == "base-1-zone-logs",
    "log-processing zone should schedule the native saw-log task")
KnoxBaseWoodcutting.findTask = function() return nil, "no_tree_ready" end

-- Reproduce Kahlua's missing select() with optional nils before real requirements.
base.tasks = {}
constructionTarget, repairTarget, animalTarget = nil, nil, nil
KnoxBaseFarming.findTask = function() return {
    id = "seed-test", action = "farm_seed", seedItemType = "Base.CarrotSeed",
} end
local savedSelect = select
select = nil
local farmTask = jobs.ensureAutomaticTask(base, nil, nil, "farming")
select = savedSelect
assert(farmTask and farmTask.requirements.items["Base.CarrotSeed"] == 1,
    "base farming works in Kahlua and does not lose requirements after nil arguments")

-- Recurring work is shared fairly when two otherwise equal tasks are available,
-- but a genuinely higher-priority task still wins.  The selector is pure and
-- uses a callback here so this regression test does not need a live character.
local fairTasks = {
    { id = "guard-a", type = "guard", state = "queued", priority = 80,
        lastClaimedBy = "survivor-1" },
    { id = "guard-b", type = "guard", state = "queued", priority = 80 },
}
local fairChoice = jobs.selectEligibleTask(fairTasks, "survivor-1", "base-1", "guard",
    function() return true end)
assert(fairChoice ~= nil and fairChoice.id == "guard-b",
    "same-priority recurring work should rotate away from the last claimer")
fairTasks[1].priority = 120
local priorityChoice = jobs.selectEligibleTask(fairTasks, "survivor-1", "base-1", "guard",
    function() return true end)
assert(priorityChoice ~= nil and priorityChoice.id == "guard-a",
    "fairness must not override substantially higher priority work")
local ineligibleChoice = jobs.selectEligibleTask(fairTasks, "survivor-1", "base-1", "guard",
    function(_, _, task) return task.id == "guard-b" end)
assert(ineligibleChoice ~= nil and ineligibleChoice.id == "guard-b",
    "selector must skip ineligible residents tasks")
local claimedChoice = jobs.selectEligibleTask({
    { id = "already-claimed", type = "guard", state = "claimed", priority = 200 },
    { id = "available-farm", type = "farm_water", state = "queued", priority = 20 },
}, "survivor-2", "base-1", "auto", function() return true end)
assert(claimedChoice ~= nil and claimedChoice.id == "available-farm",
    "selector must not return a task already claimed by another resident")
local jobsSourceFile = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_BaseJobs.lua", "r"))
local jobsSource = jobsSourceFile:read("*a")
jobsSourceFile:close()
assert(string.find(jobsSource, "local taskType = canonicalTaskType(task.type)", 1, true)
    and string.find(jobsSource, "canonicalTaskType(task.type) == \"guard\"", 1, true),
    "direct task resolution and timing helpers should share canonical task types")
local controllerSourceFile = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r"))
local controllerSource = controllerSourceFile:read("*a")
controllerSourceFile:close()
assert(string.find(controllerSource, "function Controller:suspendBaseTaskForThreat", 1, true)
    and string.find(controllerSource, 'self:suspendBaseTaskForThreat("combat_interrupt")', 1, true)
    and string.find(controllerSource, 'self:suspendBaseTaskForThreat("survival_flee")', 1, true),
    "temporary threat interruption must preserve the resident base-task claim")
assert(not string.find(controllerSource, "base_task_sort_depot", 1, true)
    and not string.find(controllerSource, "KnoxBaseStorage.queueTransfer", 1, true),
    "retired category storage must not have a live controller executor")
-- Count actual discovery calls while continuously polling an unchanged base.
depotTransfer, corpseTarget, animalTarget, repairTarget, constructionTarget = nil, nil, nil, nil, nil
local quietBase = {id = 'quiet-base', zones = {}, tasks = {}}
quietBase.tasks.legacy = { type = "sort_depot", state = "claimed", claimedBy = "resident-a" }
local workerA, workerB = {}, {}
local millis, discoveries, depotDiscoveries = 1000, 0, 0
getTimestampMs = function() return millis end
KnoxBaseFarming.findTask = function() discoveries = discoveries + 1; return nil end
KnoxBaseStorage.findTransfer = function() depotDiscoveries = depotDiscoveries + 1; return nil end
local reconciledBefore = reconcileCalls
jobs.prepareWorkforce(quietBase, workerA, 100)
assert(quietBase.tasks.legacy.state == "cancelled" and quietBase.tasks.legacy.claimedBy == nil,
    "legacy sorting claims are retired instead of repurposed into corpse targets")
for i = 1, 10 do jobs.prepareWorkforce(quietBase, workerA, 100 + i * 0.02) end
assert(discoveries == 1 and depotDiscoveries == 0, 'repeated worker polling coalesces world discovery')
assert(reconcileCalls == reconciledBefore + 1)
jobs.prepareWorkforce(quietBase, workerB, 100.21)
assert(discoveries == 2 and depotDiscoveries == 0, 'different worker gets capability-specific discovery, shared depot does not rescan')
jobs.prepareWorkforce(quietBase, workerA, 100.26)
assert(reconcileCalls == reconciledBefore + 2, 'frequent calls must not postpone claim reconciliation forever')
local beforeExpiry = discoveries
millis = 3100
jobs.prepareWorkforce(quietBase, workerA, 100.27)
assert(discoveries == beforeExpiry + 1, 'new world/inventory work is rediscovered within two seconds')
quietBase.tasks.changed = {id = 'changed', state = 'claimed', type = 'guard', claimedBy = 'other'}
local beforeChange = discoveries
jobs.prepareWorkforce(quietBase, workerA, 100.28)
assert(discoveries == beforeChange + 1, 'task ownership changes invalidate cached discovery')
local beforeReload = discoveries
jobs.prepareWorkforce({id = quietBase.id, zones = {}, tasks = {}}, workerA, 100.28)
assert(discoveries == beforeReload + 1, 'restored base object cannot inherit old runtime leases')
print("Base jobs PASS automatic_guard=true recurring=true depot_sort=true priority=true discovery_bounded=true reconciliation_not_starved=true")

-- Recurring discovery must refresh supplies together with the world target.
getTimestampMs = nil
KnoxBaseFarming.findTask = function() return {
    id = "seed-test", action = "farm_seed", seedItemType = "Base.TomatoSeed",
} end
jobs.prepareWorkforce(base, nil, 200)
assert(farmTask.requirements.items["Base.TomatoSeed"] == 1
    and farmTask.requirements.items["Base.CarrotSeed"] == nil,
    "queued planting must use the currently discovered seed")
farmTask.state, farmTask.claimedBy = "claimed", "worker-a"
KnoxBaseFarming.findTask = function() return {
    id = "seed-test", action = "farm_seed", seedItemType = "Base.CabbageSeed",
} end
jobs.prepareWorkforce(base, nil, 201)
assert(farmTask.requirements.items["Base.TomatoSeed"] == 1,
    "another worker cannot change an active claim's supplies")
farmTask.state, farmTask.claimedBy = "complete", nil
farmTask.retryAtHours = 201
jobs.prepareWorkforce(base, nil, 202)
assert(farmTask.requirements.items["Base.CabbageSeed"] == 1
    and farmTask.target.seedItemType == "Base.CabbageSeed",
    "reopened planting refreshes target and supply list together")
KnoxBaseWoodcutting.findTask = function() return {
    id = "wood-test", action = "chop_tree", axeType = "Base.Axe",
} end
jobs.prepareWorkforce(base, nil, 203)
local woodTask
for _, task in pairs(base.tasks) do
    if task.target.id == "wood-test" then woodTask = task end
end
assert(woodTask ~= nil)
woodTask.state, woodTask.retryAtHours = "complete", 203
KnoxBaseWoodcutting.findTask = function() return {
    id = "wood-test", action = "chop_tree", axeType = "Base.HandAxe",
} end
jobs.prepareWorkforce(base, nil, 204)
assert(woodTask.requirements.items["Base.HandAxe"] == 1
    and woodTask.requirements.items["Base.Axe"] == nil,
    "reopened woodwork does not send workers after a stale tool")
print("Recurring task supplies PASS")

local outdoorBase = { zones = {
    forest = { x1 = 35, y1 = 45, x2 = 30, y2 = 40, z = 1, enabled = true },
} }
assert(jobs.containsWorkSquare(outdoorBase, square(33, 42, 1)), "reversed external bounds support work")
assert(not jobs.containsWorkSquare(outdoorBase, square(33, 42, 0)), "work areas respect floors")
assert(not jobs.containsWorkSquare(outdoorBase, square(90, 90, 1)), "areas do not authorize roaming")
outdoorBase.zones.forest.enabled = false
assert(not jobs.containsWorkSquare(outdoorBase, square(33, 42, 1)), "disabled area cannot retain outdoor workers")

assert(woodTask.requirements.itemRules["Base.HandAxe"].usable == true
    and woodTask.requirements.itemRules["Base.Axe"] == nil,
    "recurring work replaces usable-tool rules together with the selected tool")
KnoxBaseFarming.findTask = function() return {
    id = "water-test", action = "farm_water", waterItemType = "Base.WaterBottle",
} end
jobs.prepareWorkforce(base, nil, 205)
local wateringTask
for _, task in pairs(base.tasks) do
    if task.target.id == "water-test" then wateringTask = task end
end
assert(wateringTask and wateringTask.requirements.itemRules["Base.WaterBottle"].water,
    "discovered crop watering requires a nonempty water container")

-- Appliance discovery uses the same recurring board/claim lifecycle.
local cookingTarget={id="cook:"..base.id,action="cook",x=4,y=0,z=0,objectIndex=1}
KnoxBaseCooking={findTask=function() return cookingTarget end}
jobs.prepareWorkforce(base,nil,206)
local cookTask
for _,task in pairs(base.tasks) do if task.type=="cook" then assert(cookTask==nil);cookTask=task end end
assert(cookTask and cookTask.target==cookingTarget and jobs.AUTOMATIC_TYPES.cook)
cookTask.state,cookTask.claimedBy="claimed","cook"
local original=cookTask.target
cookingTarget={id="cook:"..base.id,action="cook",x=8,y=0,z=0,objectIndex=2}
jobs.prepareWorkforce(base,nil,207)
assert(cookTask.target==original,"discovery cannot redirect the active cook")
cookTask.state,cookTask.claimedBy,cookTask.retryAtHours="complete",nil,207
jobs.prepareWorkforce(base,nil,208)
assert(cookTask.state=="queued" and cookTask.target==cookingTarget,"completed cooking can prepare another meal")
assert(KnoxBaseNeeds.priorityBonus(cookTask,{totals={food=0}},2)==20)
print("Cooking task lifecycle PASS recurring=true claim_owner=true food_priority=true")

KnoxBaseAnimalCare.findTask=function() return {
    id="trough-water",action="animal_water",itemType="Base.Bottle",itemId="41",
} end
jobs.prepareWorkforce(base,nil,210)
local animalTask
for _,task in pairs(base.tasks) do if task.target.id=="trough-water" then animalTask=task end end
assert(animalTask and animalTask.requirements.itemRules["Base.Bottle"].animalWater,
    "animal jobs require actual water, not just a container of the same type")
KnoxBaseAnimalCare.findTask=function() return {
    id="trough-water",action="animal_water",itemType="Base.Bucket",itemId="42",
} end
jobs.prepareWorkforce(base,nil,211)
assert(animalTask.requirements.items["Base.Bucket"]==1
    and animalTask.requirements.items["Base.Bottle"]==nil,
    "unclaimed jobs refresh supply choices when the cupboard changes")
animalTask.state,animalTask.claimedBy="claimed","worker"
KnoxBaseAnimalCare.findTask=function() return {
    id="trough-water",action="animal_water",itemType="Base.Bottle",itemId="41",
} end
jobs.prepareWorkforce(base,nil,212)
assert(animalTask.target.itemId=="42","discovery cannot redirect an active worker")
KnoxBaseAnimalCare.findTask=function() return {
    id="trough-feed",action="animal_feed",itemType="Base.AnimalFeedBag",
} end
jobs.prepareWorkforce(base,nil,213)
for _,task in pairs(base.tasks) do
    if task.target.id=="trough-feed" then
        assert(task.requirements.itemRules["Base.AnimalFeedBag"].animalFeed)
    end
end
print("Animal task lifecycle PASS usable_supplies=true refresh_unclaimed=true preserve_claim=true")
