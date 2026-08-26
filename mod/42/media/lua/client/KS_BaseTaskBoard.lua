require "KS_Persistence"
require "KS_BaseManager"

local TaskBoard = rawget(_G, "KnoxBaseTaskBoard") or {}
_G.KnoxBaseTaskBoard = TaskBoard

TaskBoard.TASK_TYPES = {
    haul = true,
    sort_depot = true,
    barricade = true,
    farm_seed = true,
    farm_water = true,
    farm_harvest = true,
    farm_plow = true,
    chop_tree = true,
    saw_logs = true,
    guard = true,
    patrol = true,
    haul_corpse = true,
    animal_care = true,
    animal_water = true,
    animal_feed = true,
    repair = true,
    construct_defense = true,
}

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

function TaskBoard.queue(baseId, taskType, target, requirements, priority)
    if TaskBoard.TASK_TYPES[taskType] ~= true then
        return nil, "unknown_task_type"
    end
    return KnoxPersistence.queueBaseTask(
        baseId,
        taskType,
        target,
        requirements or {},
        priority
    )
end

function TaskBoard.queued(baseId)
    local base = KnoxPersistence.getBase(baseId)
    local tasks = {}
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task.state == "queued" then
            tasks[#tasks + 1] = task
        end
    end
    table.sort(tasks, function(first, second)
        local firstPriority = tonumber(first.priority) or 0
        local secondPriority = tonumber(second.priority) or 0
        if firstPriority == secondPriority then
            return tostring(first.id) < tostring(second.id)
        end
        return firstPriority > secondPriority
    end)
    return tasks
end

function TaskBoard.claimBest(baseId, survivorId)
    for _, task in ipairs(TaskBoard.queued(baseId)) do
        local eligible = KnoxBaseManager.canPerformTask(survivorId, baseId, task)
        if eligible then
            return KnoxPersistence.claimBaseTask(
                baseId,
                task.id,
                survivorId,
                worldAge()
            )
        end
    end
    return nil, "no_eligible_task"
end

function TaskBoard.finish(baseId, taskId, survivorId, succeeded, reason)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil or task.state ~= "claimed" or task.claimedBy ~= survivorId then
        return nil, "not_claimed_by_survivor"
    end
    local finished, result = KnoxPersistence.finishBaseTask(
        baseId,
        taskId,
        survivorId,
        succeeded == true,
        reason,
        worldAge()
    )
    if finished == nil then
        return nil, result
    end
    return finished, succeeded and "complete" or "blocked"
end

return TaskBoard
