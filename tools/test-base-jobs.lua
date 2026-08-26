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
package.loaded["KS_BaseConstruction"] = true
local depotTransfer = nil
KnoxBaseStorage = {
    findTransfer = function()
        return depotTransfer, depotTransfer ~= nil and "found" or "no_matching_depot_item"
    end,
    transferTarget = function(value)
        return value ~= nil and value.target or nil
    end,
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
local task, result = jobs.ensureAutomaticTask(base)
assert(task ~= nil and task.type == "guard", "guard zone should be first supported job")
assert(result == "ready" and task.target.autoZoneId == "base-1-zone-guard")

local sameTask, sameResult = jobs.ensureAutomaticTask(base)
assert(sameTask == task and sameResult == "ready", "queued job should be reused")

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
assert(depotTask ~= nil and depotTask.type == "sort_depot"
    and depotResult == "ready", "available depot transfer should be scheduled")

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

print("Base jobs PASS automatic_guard=true recurring=true depot_sort=true priority=true animal_care=true repairs=true construction=true target_resolution=true")
