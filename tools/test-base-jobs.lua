local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["KS_Persistence"] = true
package.loaded["KS_BaseTaskBoard"] = true
package.loaded["KS_BaseStorage"] = true
package.loaded["KS_BaseBarricades"] = true
package.loaded["KS_BaseFarming"] = true
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
assert(result == "queued" and task.target.autoZoneId == "base-1-zone-guard")

local sameTask, sameResult = jobs.ensureAutomaticTask(base)
assert(sameTask == task and sameResult == "existing", "queued job should be reused")

task.state = "complete"
task.retryAtHours = now
local reopened, reopenedResult = jobs.ensureAutomaticTask(base)
assert(reopened == task and reopenedResult == "reopened")
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
    and depotResult == "queued", "available depot transfer should be scheduled")

print("Base jobs PASS automatic_guard=true recurring=true depot_sort=true target_resolution=true")
