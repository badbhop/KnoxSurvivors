require "KS_Persistence"
require "KS_BaseTaskBoard"
require "KS_BaseStorage"
require "KS_BaseBarricades"
require "KS_BaseFarming"
require "KS_BaseWoodcutting"
require "KS_BaseCorpseHandling"
require "KS_BaseAnimalCare"

local BaseJobs = rawget(_G, "KnoxBaseJobs") or {}
_G.KnoxBaseJobs = BaseJobs

-- Only jobs with a complete, reversible world executor belong here.  The other
-- zone types are still persisted by the base planner, but must not be claimed
-- until their engine actions are ready.
BaseJobs.AUTOMATIC_TYPES = {
    guard = true,
    patrol = true,
    sort_depot = true,
    barricade = true,
    farm_water = true,
    farm_harvest = true,
    farm_plow = true,
    farm_seed = true,
}

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

local function zoneOf(task)
    local target = task ~= nil and task.target or nil
    local zoneId = target ~= nil and target.autoZoneId or nil
    return type(zoneId) == "string" and zoneId or nil
end

local function sortedZones(base)
    local zones = {}
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false
            and BaseJobs.AUTOMATIC_TYPES[zone.type] == true then
            zones[#zones + 1] = zone
        end
    end
    table.sort(zones, function(first, second)
        local firstPriority = tonumber(first.priority) or 50
        local secondPriority = tonumber(second.priority) or 50
        if firstPriority == secondPriority then
            return tostring(first.id) < tostring(second.id)
        end
        return firstPriority > secondPriority
    end)
    return zones
end

local function taskForZone(base, zone)
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task ~= nil and zoneOf(task) == zone.id then
            return task
        end
    end
    return nil
end

local function taskForTargetId(base, targetId)
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task ~= nil and task.target ~= nil
            and tostring(task.target.id or "") == tostring(targetId) then
            return task
        end
    end
    return nil
end

local function reopenWhenReady(task, now)
    if task == nil or (task.state ~= "complete" and task.state ~= "blocked") then
        return task
    end
    local retryAt = tonumber(task.retryAtHours) or 0
    if now < retryAt then
        return nil
    end
    local reopened, result = KnoxPersistence.requeueBaseTask(
        task.baseId,
        task.id,
        now
    )
    if reopened ~= nil then
        return reopened
    end
    print("[KnoxSurvivors][BaseJobs] reopen-failed task=" .. tostring(task.id)
        .. " result=" .. tostring(result))
    return nil
end

local function taskTarget(zone)
    return {
        auto = true,
        autoZoneId = zone.id,
        zoneType = zone.type,
        x1 = tonumber(zone.x1) or 0,
        y1 = tonumber(zone.y1) or 0,
        x2 = tonumber(zone.x2) or tonumber(zone.x1) or 0,
        y2 = tonumber(zone.y2) or tonumber(zone.y1) or 0,
        z = tonumber(zone.z) or 0,
    }
end

local function itemRequirements(...)
    local items = {}
    for index = 1, select("#", ...) do
        local fullType = select(index, ...)
        if type(fullType) == "string" and fullType ~= "" then
            items[fullType] = (items[fullType] or 0) + 1
        end
    end
    return next(items) ~= nil and { items = items } or {}
end

local function ensureDepotTask(base, now)
    local transfer = KnoxBaseStorage.findTransfer(base)
    if transfer == nil then
        return nil, "no_matching_depot_item"
    end
    local target = KnoxBaseStorage.transferTarget(transfer)
    if target == nil then
        return nil, "invalid_depot_target"
    end
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "queued" or existing.state == "claimed" then
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            -- The item type is deliberately refreshed only between runs. A
            -- claimed task keeps its original target until it completes.
            reopened.target = target
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        "sort_depot",
        target,
        {},
        90
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureBarricadeTask(base, now, character)
    if character == nil or not KnoxBaseBarricades.canPrepare(character) then
        return nil, "missing_barricade_materials"
    end
    local target = KnoxBaseBarricades.findTarget(base, character)
    if target == nil then
        return nil, "no_unbarricaded_window"
    end
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "queued" or existing.state == "claimed" then
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target = target
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        "barricade",
        target,
        itemRequirements(
            KnoxBaseBarricades.findHammer(character):getFullType(),
            "Base.Plank",
            "Base.Nails",
            "Base.Nails"
        ),
        95
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureFarmingTask(base, now, character)
    local target = KnoxBaseFarming.findTask(base, character)
    if target == nil then
        return nil, "no_farming_action_ready"
    end
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "queued" or existing.state == "claimed" then
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target = target
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        target.action,
        target,
        itemRequirements(
            target.waterItemType,
            target.plowToolType,
            target.seedItemType
        ),
        target.action == "farm_harvest" and 100
            or target.action == "farm_seed" and 95
            or target.action == "farm_water" and 85
            or 80
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureWoodcuttingTask(base, now, character)
    local target = KnoxBaseWoodcutting.findTask(base, character)
    if target == nil then
        return nil, "no_tree_ready"
    end
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "queued" or existing.state == "claimed" then
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target = target
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        target.action,
        target,
        itemRequirements(
            target.axeType,
            target.logType,
            target.sawType
        ),
        target.action == "saw_logs" and 78 or 75
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureCorpseTask(base, now, character)
    local target = KnoxBaseCorpseHandling.findTask(base, character)
    if target == nil then
        return nil, "no_corpse_ready"
    end
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "queued" or existing.state == "claimed" then
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target = target
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        "haul_corpse",
        target,
        {},
        92
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

local function ensureAnimalCareTask(base, now, character)
    local target = KnoxBaseAnimalCare.findTask(base, character)
    if target == nil then
        return nil, "no_animal_care_ready"
    end
    local existing = taskForTargetId(base, target.id)
    if existing ~= nil then
        existing.baseId = base.id
        if existing.state == "queued" or existing.state == "claimed" then
            return existing, "existing"
        end
        local reopened = reopenWhenReady(existing, now)
        if reopened ~= nil then
            reopened.target = target
            reopened.requirements = itemRequirements(target.itemType)
            return reopened, "reopened"
        end
        return nil, "retry_not_ready"
    end
    local task, result = KnoxBaseTaskBoard.queue(
        base.id,
        target.action,
        target,
        itemRequirements(target.itemType),
        target.action == "animal_water" and 89 or 87
    )
    if task ~= nil then
        task.baseId = base.id
        task.auto = true
        task.retryAtHours = now
        return task, result
    end
    return nil, result
end

function BaseJobs.ensureAutomaticTask(base, character, survivorId)
    if base == nil or base.settings == nil or base.settings.automaticJobs == false then
        return nil, "automatic_jobs_disabled"
    end
    local now = worldAge()
    -- Discover every currently executable job before choosing one. Returning from
    -- the first finder starved cleanup and security whenever a renewable farming or
    -- woodcutting target existed. The persistent task board already owns priority
    -- and claim ordering, so let it make that choice and leave lower-priority work
    -- queued for another eligible resident.
    ensureDepotTask(base, now)
    ensureFarmingTask(base, now, character)
    ensureWoodcuttingTask(base, now, character)
    ensureCorpseTask(base, now, character)
    ensureAnimalCareTask(base, now, character)
    ensureBarricadeTask(base, now, character)
    for _, zone in ipairs(sortedZones(base)) do
        local existing = taskForZone(base, zone)
        if existing ~= nil then
            existing.baseId = base.id
            if existing.state ~= "queued" and existing.state ~= "claimed" then
                reopenWhenReady(existing, now)
            end
        else
            local task, result = KnoxBaseTaskBoard.queue(
                base.id,
                zone.type,
                taskTarget(zone),
                {},
                tonumber(zone.priority) or 50
            )
            if task ~= nil then
                task.baseId = base.id
                task.auto = true
                task.retryAtHours = now + (zone.type == "guard" and 0.25 or 0.10)
            else
                print("[KnoxSurvivors][BaseJobs] queue-failed base=" .. tostring(base.id)
                    .. " zone=" .. tostring(zone.id) .. " result=" .. tostring(result))
            end
        end
    end
    local queued = KnoxBaseTaskBoard.queued(base.id)
    for _, task in ipairs(queued) do
        if survivorId == nil then
            return task, "ready"
        end
        local eligible = KnoxBaseManager.canPerformTask(
            survivorId,
            base.id,
            task
        )
        if eligible then
            return task, "ready"
        end
    end
    return nil, #queued > 0 and "no_eligible_task" or "no_ready_work_zone"
end

local function candidateSquare(cell, x, y, z, origin)
    local square = cell:getGridSquare(x, y, z)
    if square ~= nil and (square == origin or square:canStand()) then
        return square
    end
    return nil
end

local function searchAround(cell, x, y, z, origin)
    for radius = 0, 6 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = candidateSquare(cell, x + dx, y + dy, z, origin)
                    if square ~= nil then
                        return square
                    end
                end
            end
        end
    end
    return nil
end

function BaseJobs.resolveTaskSquare(task, character)
    local target = task ~= nil and task.target or nil
    local cell = getCell ~= nil and getCell() or nil
    if target == nil or cell == nil then
        return nil
    end
    if task.type == "haul_corpse" or target.action == "haul_corpse" then
        local resolved = KnoxBaseCorpseHandling.resolveTarget(
            KnoxBaseManager.get(task.baseId),
            target,
            character
        )
        return resolved ~= nil and resolved.approach or nil
    end
    if task.type == "animal_water" or task.type == "animal_feed" then
        return KnoxBaseAnimalCare.resolveTaskSquare(
            KnoxBaseManager.get(task.baseId),
            target,
            character
        )
    end
    local x1 = tonumber(target.x1 or target.x) or 0
    local y1 = tonumber(target.y1 or target.y) or 0
    local x2 = tonumber(target.x2 or x1) or x1
    local y2 = tonumber(target.y2 or y1) or y1
    local z = tonumber(target.z) or 0
    local centerX = math.floor((x1 + x2) / 2)
    local centerY = math.floor((y1 + y2) / 2)
    local origin = character ~= nil and character:getCurrentSquare() or nil
    local candidates = {
        { centerX, centerY },
        { x1, y1 },
        { x2, y1 },
        { x1, y2 },
        { x2, y2 },
    }
    if target.zoneType == "patrol" then
        local offset = ((tonumber(task.attempts) or 1) - 1) % #candidates
        local rotated = {}
        for index = 1, #candidates do
            rotated[index] = candidates[((index + offset - 1) % #candidates) + 1]
        end
        candidates = rotated
    end
    for _, point in ipairs(candidates) do
        local square = searchAround(cell, point[1], point[2], z, origin)
        if square ~= nil then
            return square
        end
    end
    return nil
end

function BaseJobs.workDuration(task)
    return task ~= nil and task.type == "guard" and 240 or 180
end

function BaseJobs.retryDelay(task)
    return task ~= nil and task.type == "guard" and 0.25 or 0.10
end

return BaseJobs
