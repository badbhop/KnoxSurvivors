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
    -- Keep the existing persisted task as the only source of duty state. A
    -- patrol that completes an unloaded watch shift advances its next route
    -- step before the task is requeued; a guard records relief without
    -- inventing movement or world changes. Loaded controllers continue to use
    -- CompanionPatrol.recordTaskArrival for physical waypoint traversal.
    task.offscreenShiftsCompleted = (tonumber(task.offscreenShiftsCompleted) or 0)
        + completedShifts
    if canonicalTaskType(task.type) == "patrol" then
        local patrol = rawget(_G, "KnoxCompanionPatrol")
        local points = patrol ~= nil and patrol.waypoints ~= nil
            and patrol.waypoints(task.target) or nil
        local count = type(points) == "table" and #points or 0
        if count > 0 then
            task.patrolStep = (math.max(0, math.floor(tonumber(task.patrolStep) or 0))
                + completedShifts) % count
            local stops = math.max(0,
                math.floor(tonumber(task.patrolStopsCompleted) or 0))
            -- Keep the completion counter in the same route phase as the
            -- advanced waypoint. This matters when several shifts elapse
            -- while the survivor is unloaded; leaving the old counter intact
            -- would make the next loaded arrival reset at the wrong stop.
            task.patrolStopsCompleted = (stops + completedShifts) % count
        end
    else
        task.guardReliefCount = (tonumber(task.guardReliefCount) or 0) + completedShifts
    end
    return true, completedShifts * SHIFT_HOURS
end

return Duty
