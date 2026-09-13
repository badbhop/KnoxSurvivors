local Duty = rawget(_G, "KnoxBaseDutySimulation") or {}
_G.KnoxBaseDutySimulation = Duty

local SHIFT_HOURS = 4

local function canonicalTaskType(taskType)
    local catalog = rawget(_G, "KnoxOrderCatalog")
    if catalog ~= nil and catalog.normalizeTaskType ~= nil then
        return catalog.normalizeTaskType(taskType) or taskType
    end
    return taskType
end

function Duty.canAdvanceOffscreen(task)
    local kind = task ~= nil and tostring(canonicalTaskType(task.type) or "") or ""
    return kind == "guard" or kind == "patrol"
end

-- Only abstractable watch shifts advance here.  World-changing jobs remain
-- claimed and resume in the loaded engine where their native action can run.
function Duty.advance(task, elapsed)
    if task == nil or task.state ~= "claimed" or not Duty.canAdvanceOffscreen(task) then
        return false, 0
    end
    local hours = math.max(0, tonumber(elapsed) or 0)
    local accumulated = (tonumber(task.offscreenWorkHours) or 0) + hours
    local completedShifts = math.floor(accumulated / SHIFT_HOURS)
    task.offscreenWorkHours = accumulated - completedShifts * SHIFT_HOURS
    if completedShifts <= 0 then
        return false, task.offscreenWorkHours
    end
    -- This records time on duty, not permission to finish the order. Keep the
    -- claim and actual waypoint evidence until the player releases the watch.
    -- Streaming cannot invent a patrol arrival or a replacement guard.
    task.offscreenShiftsCompleted = math.min(1000000,
        (tonumber(task.offscreenShiftsCompleted) or 0) + completedShifts)
    return true, completedShifts * SHIFT_HOURS
end

return Duty
