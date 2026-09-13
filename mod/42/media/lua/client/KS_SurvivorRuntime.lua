local Runtime = rawget(_G, "KnoxSurvivorRuntime") or {}
_G.KnoxSurvivorRuntime = Runtime

local entries = {}

local ACTIVITY_BY_STATE = {
    COMBAT = "fighting",
    FLEEING = "retreating",
    BASE_AMBIENT_REST = "resting",
    BASE_RECREATION = "reading",
    BASE_SECURITY_WAIT = "waiting_for_route", COMPANION_DUTY_WAIT = "waiting_for_route",
    BASE_TASK_MOVE = "working_at_base",
    BASE_TASK_WORK = "working_at_base",
    BASE_TASK_ACTION = "working_at_base",
    BASE_TASK_PATROL_WAIT = "patrolling",
    BASE_TASK_SUPPLY_MOVE = "collecting_job_supplies",
    BASE_TASK_SUPPLY_TRANSFER = "collecting_job_supplies",
    BASE_TASK_SUPPLY_WAIT = "waiting_for_materials",
    COMPANION_GUARD = "guarding",
    COMPANION_RELAX = "resting",
    COMPANION_PATROL_WAIT = "patrolling",
    MOVING_TO_COMPANION_PATROL = "patrolling",
    MOVING_TO_COMPANION_POINT = "travelling",
    INVENTORY_CLEANUP = "sorting_inventory",
    MOVING_TO_DEPOSIT = "storing_supplies",
    AWAY_RETURN = "returning_home",
    LOOTING = "looting",
    SEARCHING = "searching",
    MOVING_TO_SUPPLY = "seeking_supplies",
    MOVING_TO_EXPLORE = "exploring",
    ROAMING = "exploring",
    MOVING_TO_REST = "resting",
    WAITING_TO_RECOVER = "resting",
    SLEEPING_RECOVERY = "resting",
    TIMED_ACTION = "busy",
    GROUP_FOLLOW = "travelling",
    GROUP_WAIT = "travelling",
    GROUP_REGROUP = "travelling",
    COMPANION_FOLLOW = "following",
    COMPANION_WAIT = "following",
    COMPANION_HOLD = "holding",
    BASE_RETURN = "returning_home",
    EVENT_TRAVEL = "travelling",
    EVENT_WAIT = "waiting",
    BASE_PATROL = "walking_at_base",
    BASE_IDLE = "at_base",
    CAMP_RETURN = "returning_to_shelter",
    CAMP_REPOSITION = "at_shelter",
    CAMP_IDLE = "at_shelter",
    CAMP_AMBIENT_REST = "resting",
    MOVING_TO_BASE_CANDIDATE = "scouting_base",
    MEETING_APPROACH = "meeting",
    MEETING_WAIT = "meeting",
    MEETING_READY = "meeting",
    GREETING = "meeting",
    ROBBING = "fighting",
    STORED = "away",
    STOPPED = "stopped",
    IDLE = "idle",
    TRADING = "trading",
    PLAYER_CONVERSATION = "meeting",
}

local function validId(id)
    return type(id) == "string" and id ~= ""
end

function Runtime.register(id, controller)
    if not validId(id) or type(controller) ~= "table" then
        return false
    end
    entries[id] = {
        id = id,
        controller = controller,
        character = controller.character,
    }
    return true
end

function Runtime.unregister(id, controller)
    local entry = validId(id) and entries[id] or nil
    if entry ~= nil and (controller == nil or entry.controller == controller) then
        local vehicles = rawget(_G, "KnoxCompanionVehicles")
        if vehicles ~= nil and vehicles.cancel ~= nil then vehicles.cancel(entry.character) end
        entries[id] = nil
        return true
    end
    return false
end

local function getEntry(id)
    return validId(id) and entries[id] or nil
end

function Runtime.getCharacter(id)
    local entry = getEntry(id)
    if entry == nil then
        return nil
    end
    local controller = entry.controller
    local character = controller ~= nil and controller.character or entry.character
    entry.character = character
    return character
end

function Runtime.activeIds()
    local ids = {}
    for id in pairs(entries) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

function Runtime.idForCharacter(character)
    if character == nil then
        return nil
    end
    for id in pairs(entries) do
        if Runtime.getCharacter(id) == character then
            return id
        end
    end
    return nil
end

function Runtime.snapshot(id)
    local entry = getEntry(id)
    if entry == nil then
        return {
            id = id,
            loaded = false,
            activity = "away",
        }
    end
    local controller = entry.controller
    local character = Runtime.getCharacter(id)
    local square = character ~= nil and character:getCurrentSquare() or nil
    local state = controller ~= nil and tostring(controller.state or "IDLE") or "IDLE"
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    local vehicleActivity = character ~= nil and vehicles ~= nil and vehicles.activity ~= nil
        and vehicles.activity(character) or nil
    local task = controller ~= nil and controller.baseTask or nil
    local dutyActivity
    if task ~= nil and (state == "BASE_TASK_MOVE" or state == "BASE_TASK_WORK"
        or state == "BASE_TASK_PATROL_WAIT") then
        if task.type == "guard" then dutyActivity = "guarding"
        elseif task.type == "patrol" then dutyActivity = "patrolling" end
    end
    return {
        id = id,
        loaded = square ~= nil,
        state = state,
        activity = vehicleActivity or dutyActivity
            or ((state == "BASE_RECREATION" or state == "BASE_COOKING") and controller.activeDecision) or ACTIVITY_BY_STATE[state] or "busy",
        decision = controller ~= nil and controller.activeDecision or nil,
        driving = character ~= nil and vehicles ~= nil and vehicles.driverStatus ~= nil
            and vehicles.driverStatus(character) or nil,
        x = square ~= nil and square:getX() or nil,
        y = square ~= nil and square:getY() or nil,
        z = square ~= nil and square:getZ() or nil,
    }
end

function Runtime.notifyDutyChanged(id)
    local entry = getEntry(id)
    if entry == nil then return false end
    if entry.controller ~= nil and entry.controller.onDutyChanged ~= nil then
        entry.controller:onDutyChanged()
    end
    return true
end

function Runtime.prepareVehicle(id)
    local entry = getEntry(id)
    if entry == nil or entry.controller == nil then return false end
    local character = Runtime.getCharacter(id)
    local queue = ISTimedActionQueue.queues[character]
    if queue ~= nil and #queue.queue > 0 then return false end
    return entry.controller:interruptForDirective() == true
end

-- Transient action lease only. Identity, orders and inventory stay in their
-- existing owners; a replacement/detached controller cannot inherit this lease.
function Runtime.beginPlayerConversation(id, player)
    local entry = getEntry(id)
    if entry == nil or entry.controller.beginPlayerConversation == nil then
        return false, "survivor_unavailable"
    end
    return entry.controller:beginPlayerConversation(player)
end

function Runtime.endPlayerConversation(id, player)
    local entry = getEntry(id)
    return entry ~= nil and entry.controller:endPlayerConversation(player) or false
end

function Runtime.beginTrade(id, action)
    local entry = getEntry(id)
    return entry ~= nil and entry.controller:beginTrade(action) or false
end

function Runtime.ownsTrade(id, action)
    local entry = getEntry(id)
    return entry ~= nil and entry.controller.tradeAction == action
        and entry.controller.state == "TRADING" and Runtime.getCharacter(id) == action.npc
end

function Runtime.releaseTrade(id, action)
    local entry = getEntry(id)
    return entry ~= nil and entry.controller:releaseTrade(action) or false
end

function Runtime.nearestToSquare(square, maximumDistance)
    if square == nil then
        return nil, nil
    end
    local limit = math.max(0, tonumber(maximumDistance) or 3)
    local bestId = nil
    local bestDistance = limit * limit
    for id in pairs(entries) do
        local character = Runtime.getCharacter(id)
        local current = character ~= nil and character:getCurrentSquare() or nil
        if current ~= nil and current:getZ() == square:getZ() then
            local dx = current:getX() - square:getX()
            local dy = current:getY() - square:getY()
            local distance = dx * dx + dy * dy
            if distance <= bestDistance then
                bestId = id
                bestDistance = distance
            end
        end
    end
    return bestId, bestId ~= nil and math.sqrt(bestDistance) or nil
end

function Runtime.clear()
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    if vehicles ~= nil and vehicles.cancel ~= nil then
        for _, entry in pairs(entries) do vehicles.cancel(entry.character) end
    end
    entries = {}
end

return Runtime
