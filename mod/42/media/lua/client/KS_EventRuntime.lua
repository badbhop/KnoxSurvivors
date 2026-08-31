require "KS_KnoxEvents"
require "KS_SurvivorRuntime"
require "KS_SurvivorNeeds"
require "KS_FirearmSupport"
require "KS_BaseManager"

local Runtime = rawget(_G, "KnoxEventRuntime") or {}
_G.KnoxEventRuntime = Runtime
local cursor = 0
local READY_STATES = { IDLE = true, BASE_IDLE = true, BASE_PATROL = true, BASE_RETURN = true }

local function finished(event)
    return event == nil or event.phase == "completed" or event.phase == "failed"
end

local function owns(id, eventId)
    local duty = KnoxPersistence.getSurvivorDuty(id)
    return duty ~= nil and duty.eventId == eventId
end

local function indexOf(event, id)
    for index, member in ipairs(event.memberIds or {}) do if member == id then return index end end
end

local function sourceHome(event)
    local base = KnoxPersistence.getBase(event.sourceBaseId)
    return base ~= nil and base.ownerKind == "faction" and base.ownerId == event.sourceFactionId and base or nil
end

local function areaFor(event, returning)
    local base = returning and sourceHome(event) or nil
    if not returning then base = KnoxPersistence.getBase(event.targetBaseId) end
    return base ~= nil and base.home or nil
end

function Runtime.destination(event, id)
    local slot = indexOf(event, id)
    local returning = event.phase == "withdrawing"
    local area = areaFor(event, returning)
    if slot == nil or type(area) ~= "table" then return nil end
    local x, y, w, h = tonumber(area.minX), tonumber(area.minY), tonumber(area.width), tonumber(area.height)
    if x == nil or y == nil or w == nil or h == nil or w < 1 or h < 1 then return nil end
    for _, value in ipairs({ x, y, w, h, area.z or 0 }) do
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
    end
    if returning then
        return { x = x + math.min(w - 1, 1 + (slot - 1) % math.max(1, math.floor(w - 2))),
            y = y + math.min(h - 1, 1 + math.floor((slot - 1) / math.max(1, math.floor(w - 2)))), z = area.z or 0 }
    end
    -- Separate approach points outside the building; do not aim every member at
    -- one centre tile or require a door to be smashed just to arrive nearby.
    local offset = (slot - 1) * 2
    local source = sourceHome(event)
    source = source ~= nil and source.home or nil
    if source ~= nil then
        if type(source) ~= "table" then return nil end
        for _, key in ipairs({ "minX", "minY", "width", "height" }) do
            local value = source[key]
            if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
        end
    end
    local dx = source ~= nil and source.minX + source.width / 2 - (x + w / 2) or -1
    local dy = source ~= nil and source.minY + source.height / 2 - (y + h / 2) or 0
    if math.abs(dx) >= math.abs(dy) then
        return { x = (dx < 0 and x - 3 or x + w + 2)
                + (dx < 0 and -1 or 1) * math.floor(offset / h),
            y = y + offset % h, z = area.z or 0 }
    end
    return { x = x + offset % w, y = (dy < 0 and y - 3 or y + h + 2)
        + (dy < 0 and -1 or 1) * math.floor(offset / w), z = area.z or 0 }
end

function Runtime.memberReady(controller, base)
    if controller == nil or not READY_STATES[controller.state] then return false, "member_busy" end
    local character = controller.character
    local area = base ~= nil and (base.territory or base.home) or nil
    if character == nil or area == nil then return false, "member_unloaded" end
    local ok, ready, reason = pcall(function()
        local square = character:getCurrentSquare()
        if character:isDead() or square == nil then return false, "member_unloaded" end
        if not KnoxBaseManager.containsSquare(base, square) then
            return false, "member_not_home"
        end
        if not character:getCharacterActions():isEmpty() then return false, "member_busy" end
        local state = KnoxSurvivorNeeds.snapshot(character)
        if state.health < 70 or state.bleedingParts > 0 or state.endurance < 0.5
            or state.fatigue > 0.65 or state.hunger > 0.7 or state.thirst > 0.7 then
            return false, "member_needs_care"
        end
        local weapon = character:getPrimaryHandItem()
        if weapon == nil or not weapon:IsWeapon() or weapon:isBroken() then return false, "member_unarmed" end
        if weapon:isRanged() and not KnoxFirearmSupport.isReady(character, weapon) then
            return false, "member_gun_not_ready"
        end
        return true, "ready"
    end)
    return ok and ready == true, ok and reason or "readiness_unavailable"
end

local function nearDestination(character, destination)
    if character == nil or destination == nil then return false end
    local square = character:getCurrentSquare()
    if square == nil or square:getZ() ~= destination.z then return false end
    local dx, dy = character:getX() - destination.x, character:getY() - destination.y
    return dx * dx + dy * dy <= 9
end

local function returnedHome(id, character, home)
    local area = home ~= nil and (home.territory or home.home) or nil
    if area == nil then return false end
    local x, y, z
    if character ~= nil then
        local square = character:getCurrentSquare()
        if square == nil then return false end
        x, y, z = square:getX(), square:getY(), square:getZ()
    else
        local state = KnoxPersistence.getUnloadedSurvivalState(id)
        if state == nil or state.pendingMaterialization then return false end
        x, y, z = state.virtualX, state.virtualY, state.virtualZ
    end
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return false end
    return KnoxBaseManager.containsSquare(home, {
        getX = function() return math.floor(x) end,
        getY = function() return math.floor(y) end,
        getZ = function() return z end,
    })
end

local function change(event, phase, hours, reason)
    local result, status = KnoxEvents.transition(event.id, event.revision, phase, hours, reason)
    if result ~= nil and status == "changed" then
        print("[KnoxSurvivors][Events] id=" .. event.id .. " phase=" .. phase .. " reason=" .. tostring(reason))
    end
    return result
end

function Runtime.dispatch(event, controllers, hours)
    if event == nil or (event.phase ~= "scheduled" and event.phase ~= "spawning") then return false, "invalid_phase" end
    if hours < event.dueAtHours then return false, "not_due" end
    local valid, why = KnoxEvents.validate(event)
    if not valid then return false, why end
    local home = KnoxPersistence.getBase(event.sourceBaseId)
    for _, id in ipairs(event.memberIds) do
        if not owns(id, event.id) then
            local ready, reason = Runtime.memberReady(controllers[id], home)
            if not ready then return false, reason end
        end
    end
    if event.phase == "scheduled" then
        event = change(event, "spawning", hours, "claiming_real_members")
        if event == nil then return false, "event_changed" end
    end
    -- Single Lua callback, no yield: all-member persistence validation precedes
    -- any duty write. A restored spawning phase can repeat this idempotently.
    local claimed, reason = KnoxPersistence.claimEventDuty(event.id, hours)
    if not claimed then
        change(event, "withdrawing", hours, reason)
        return false, reason
    end
    event = change(event, "approaching", hours, "real_members_dispatched")
    return event ~= nil, event ~= nil and "dispatched" or "event_changed"
end

local function objectiveValid(event)
    return KnoxEvents.isValidRaidObjective(event)
end

function Runtime.reviewObjective(event, hours)
    event = event ~= nil and KnoxEvents.get(event.id) or nil
    if event == nil or event.phase ~= "objective" then return end
    if not objectiveValid(event) then change(event, "withdrawing", hours, "objective_state_missing"); return end
    local count, exhausted = KnoxEvents.objectiveCount(event), true
    for _, id in ipairs(event.memberIds) do
        if (tonumber(event.objective.misses[id]) or 0) < 3 then exhausted = false end
    end
    if count >= event.objective.requiredItems or exhausted or hours >= event.objective.deadlineHours then
        local outcome = count >= event.objective.requiredItems and "supplies_taken"
            or (count > 0 and "partial_supplies" or "no_supplies")
        local result = KnoxEvents.finishRaidObjective(event.id, event.revision, hours, outcome)
        if result ~= nil then
            print("[KnoxSurvivors][Events] id=" .. event.id .. " phase=withdrawing reason=" .. outcome .. " items=" .. count)
        end
    end
end

function Runtime.beginObjectiveWork(controller, ticks)
    local assignment = controller.eventAssignment
    local event = assignment ~= nil and KnoxEvents.get(assignment.id) or nil
    if event == nil or event.phase ~= "objective" or not objectiveValid(event) then
        controller.state, controller.nextThink = "EVENT_WAIT", math.max(controller.nextThink or 0, ticks + 90)
        return true
    end
    local base = KnoxPersistence.getBase(event.targetBaseId)
    local area = base ~= nil and (base.territory or base.home) or nil
    if area ~= nil and ticks >= (controller.nextExplorationSearch or 0)
        and (tonumber(event.objective.misses[controller.id]) or 0) < 3 then
        local directive = { kind = "loot_area", eventId = event.id, minX = area.minX, minY = area.minY,
            maxX = area.maxX or (area.minX + area.width - 1), maxY = area.maxY or (area.minY + area.height - 1),
            z = base.home.z or 0 }
        if controller:beginExploration(ticks, directive) then return true end
    end
    controller.state = "EVENT_WAIT"
    controller.nextThink = math.max(controller.nextThink or 0, ticks + 90)
    return true
end

function Runtime.captureLootContext(character, source, destination)
    if character == nil or source == nil or destination == nil then return nil end
    local id = KnoxSurvivorRuntime.idForCharacter(character)
    if id == nil or source == destination or destination ~= character:getInventory()
        or source:isInCharacterInventory(character) then return nil end
    local duty = KnoxPersistence.getSurvivorDuty(id)
    local event = duty ~= nil and duty.eventId ~= nil and KnoxEvents.get(duty.eventId) or nil
    if event == nil or event.phase ~= "objective" or not objectiveValid(event) then return nil end
    local square, parent = source:getSourceGrid(), source:getParent()
    if square == nil or parent == nil or instanceof(parent, "IsoGameCharacter")
        or not KnoxBaseManager.containsSquare(KnoxPersistence.getBase(event.targetBaseId), square) then return nil end
    return { eventId = event.id, memberId = id, x = square:getX(), y = square:getY(), z = square:getZ() }
end

function Runtime.lootTransferAllowed(context, character, source, destination)
    if context == nil then return true end
    if KnoxSurvivorRuntime.getCharacter(context.memberId) ~= character then return false end
    local current = Runtime.captureLootContext(character, source, destination)
    if current == nil or current.eventId ~= context.eventId or current.x ~= context.x
        or current.y ~= context.y or current.z ~= context.z then return false end
    local event = KnoxEvents.get(context.eventId)
    local valid = KnoxEvents.validate(event)
    return valid and KnoxEvents.objectiveCount(event) < event.objective.requiredItems
        and getGameTime():getWorldAgeHours() < event.objective.deadlineHours
end

function Runtime.observeLootTransfer(context, character, source, destination, original, transferred, wasPresent)
    if context == nil or not wasPresent or transferred == nil
        or not Runtime.lootTransferAllowed(context, character, source, destination)
        or source:contains(original) or not destination:contains(transferred)
        or transferred:getContainer() ~= destination then return false end
    local id, fullType = transferred:getID(), transferred:getFullType()
    if id == nil or type(fullType) ~= "string" then return false end
    return KnoxEvents.recordLoot(context.eventId, context.memberId,
        { itemId = tostring(id), fullType = fullType, x = context.x, y = context.y, z = context.z },
        getGameTime():getWorldAgeHours())
end

function Runtime.update(controllers, hours)
    local ids = KnoxEvents.activeIds()
    for _ = 1, math.min(8, #ids) do
        cursor = cursor % #ids + 1
        local event = KnoxEvents.get(ids[cursor])
        local valid, reason = KnoxEvents.validate(event)
        if not finished(event) and reason ~= "invalid_event_record" then
            if not valid and event.phase ~= "scheduled" and event.phase ~= "withdrawing" then
                event = change(event, "withdrawing", hours, reason) or event
            end
            if event.phase == "scheduled" or event.phase == "spawning" then
                Runtime.dispatch(event, controllers, hours)
            elseif event.phase == "approaching" or event.phase == "active" or event.phase == "objective" then
                local arrived = true
                for _, id in ipairs(event.memberIds) do
                    if not owns(id, event.id) then
                        change(event, "withdrawing", hours, "member_duty_changed")
                        arrived = false
                        break
                    end
                    local controller = controllers[id]
                    if controller ~= nil and controller.state == "FLEEING" then
                        change(event, "withdrawing", hours, "party_retreating")
                        arrived = false
                        break
                    end
                    if controller ~= nil and (controller.eventMoveFailures or 0) >= 3 then
                        change(event, "withdrawing", hours, "approach_failed")
                        arrived = false
                        break
                    end
                    arrived = nearDestination(controller ~= nil and controller.character or nil, Runtime.destination(event, id)) and arrived
                end
                if arrived and event.phase == "approaching" then
                    change(event, "active", hours, "party_arrived")
                elseif event.phase == "active" then
                    KnoxEvents.beginRaidObjective(event.id, event.revision, hours)
                elseif event.phase == "objective" then
                    Runtime.reviewObjective(event, hours)
                end
            elseif event.phase == "withdrawing" then
                local resolved, home = true, sourceHome(event)
                for _, id in ipairs(event.memberIds or {}) do
                    if owns(id, event.id) then
                        local controller = controllers[id]
                        if not KnoxPersistence.isSurvivorAlive(id) or home == nil
                            or returnedHome(id, controller ~= nil and controller.character or nil, home) then
                            KnoxPersistence.releaseEventDuty(id, event.id, hours)
                        else
                            resolved = false
                        end
                    end
                end
                if resolved then change(event, home ~= nil and "completed" or "failed", hours,
                    home ~= nil and "party_returned_or_released" or "home_removed") end
            end
        end
    end
end

function Runtime.syncController(id, controller)
    local duty = KnoxPersistence.getSurvivorDuty(id)
    local event = duty ~= nil and duty.eventId ~= nil and KnoxEvents.get(duty.eventId) or nil
    if not finished(event) and not KnoxEvents.isValidRecord(event) then
        controller:setEventAssignment({ id = event.id, phase = "withdrawing" })
        return
    end
    if finished(event) or indexOf(event, id) == nil then
        if duty ~= nil and duty.eventId ~= nil then
            KnoxPersistence.releaseEventDuty(id, duty.eventId, getGameTime():getWorldAgeHours())
        end
        controller:setEventAssignment(nil)
        return
    end
    controller:setEventAssignment({ id = event.id, phase = event.phase, destination = Runtime.destination(event, id) })
    local leaderId, leader, members = nil, nil, {}
    for _, memberId in ipairs(event.memberIds or {}) do
        local body = owns(memberId, event.id) and KnoxSurvivorRuntime.getCharacter(memberId) or nil
        if body ~= nil and not body:isDead() and body:getCurrentSquare() ~= nil then
            members[#members + 1] = body
            if leader == nil then leaderId, leader = memberId, body end
        end
    end
    if leaderId ~= nil and leaderId ~= id then
        controller:setGroupLeader(leaderId, leader, indexOf(event, id) - 1, #members)
        controller:setGroupMembers({})
    else
        controller:clearGroupLeader()
        controller:setGroupMembers(members)
    end
end

return Runtime
