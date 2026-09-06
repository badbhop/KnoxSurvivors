require "Vehicles/TimedActions/ISPathFindAction"
require "Vehicles/TimedActions/ISEnterVehicle"
require "Vehicles/TimedActions/ISExitVehicle"
require "Vehicles/TimedActions/ISCloseVehicleDoor"

-- Passenger-only vehicle support.  NPC driving remains deliberately out of
-- scope until it can be designed around the contained off-slot IsoPlayer
-- shell.  These helpers use the same vanilla path/enter/exit actions as a
-- player and do not change vehicle ownership, keys, or engine state.
local CompanionVehicles = rawget(_G, "KnoxCompanionVehicles") or {}
_G.KnoxCompanionVehicles = CompanionVehicles

-- Short-lived native action ownership; no seats or actions enter save data.
local pending = setmetatable({}, { __mode = "k" })
local ACTION_TIMEOUT_MS = 45000

local function health(character)
    if character == nil or character.getBodyDamage == nil then return nil end
    local ok, value = pcall(function() return character:getBodyDamage():getHealth() end)
    return ok and tonumber(value) or nil
end

function CompanionVehicles.cancel(character)
    local request = pending[character]
    if request == nil then return end
    pending[character] = nil
    local queue = ISTimedActionQueue.queues[character]
    if queue ~= nil then
        for _, action in ipairs(queue.queue) do
            if request.actions[action] then
                ISTimedActionQueue.clear(character)
                break
            end
        end
    end
end

function CompanionVehicles.isBusy(character)
    local request = pending[character]
    if request == nil then return false end
    local currentHealth = health(character)
    if getTimestampMs() >= request.deadline
        or (character.isDead ~= nil and character:isDead())
        or (currentHealth ~= nil and request.health ~= nil and currentHealth < request.health) then
        CompanionVehicles.cancel(character)
        return false, "interrupted"
    end
    local queue = ISTimedActionQueue.queues[character]
    for _, action in ipairs(queue ~= nil and queue.queue or {}) do
        if request.actions[action] then return true end
    end
    pending[character] = nil
    return false
end

function CompanionVehicles.activity(character)
    -- Read-only presentation: expiry/cleanup belongs to isBusy in the controller.
    if pending[character] ~= nil then return "boarding" end
    if character ~= nil and character:getVehicle() ~= nil then return "riding" end
    return nil
end

local function reserved(vehicle, seat, character)
    for other, request in pairs(pending) do
        if other ~= character and request.vehicle == vehicle and request.seat == seat
            and CompanionVehicles.isBusy(other) then return true end
    end
    return false
end

local function queueActions(character, vehicle, seat, actions)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local id = runtime ~= nil and runtime.idForCharacter(character) or nil
    if id == nil or runtime.prepareVehicle == nil or not runtime.prepareVehicle(id) then
        return false, "survivor_busy"
    end
    local request = { vehicle = vehicle, seat = seat,
        deadline = getTimestampMs() + ACTION_TIMEOUT_MS, health = health(character), actions = {} }
    for _, action in ipairs(actions) do request.actions[action] = true end
    pending[character] = request
    local ok, queued = pcall(function()
        for _, action in ipairs(actions) do
            ISTimedActionQueue.add(action)
            -- Native add can silently refuse an action (for example during
            -- sleep). Never queue entry after a rejected path or report success
            -- without the actual native action owning the character.
            local queue = ISTimedActionQueue.queues[character]
            local found = false
            for _, queuedAction in ipairs(queue ~= nil and queue.queue or {}) do
                if queuedAction == action then found = true; break end
            end
            if not found then return false end
        end
        return true
    end)
    if not ok or not queued then
        CompanionVehicles.cancel(character)
        return false, "vehicle_action_failed"
    end
    return true
end

local function usablePassengerSeat(character, vehicle, seat)
    if character == nil or vehicle == nil or seat == nil
        or vehicle:isSeatOccupied(seat) or reserved(vehicle, seat, character) then
        return false
    end
    if vehicle.isSeatInstalled ~= nil and not vehicle:isSeatInstalled(seat) then
        return false
    end
    if vehicle.isEnterBlocked ~= nil and vehicle:isEnterBlocked(character, seat) then
        return false
    end
    local doorPart = vehicle:getPassengerDoor(seat)
    local door = doorPart ~= nil and doorPart:getDoor() or nil
    -- Never bypass a locked passenger door. A missing physical door is valid
    -- for open vehicles and vanilla's enter action handles that case itself.
    if door ~= nil and door:isLocked() then
        return false
    end
    return true
end

function CompanionVehicles.findFreePassengerSeat(character, vehicle)
    if character == nil or vehicle == nil or vehicle.getMaxPassengers == nil then
        return nil
    end
    -- Seat zero is the driver seat. Never take it: the local player remains
    -- responsible for driving until a dedicated NPC-driving implementation.
    for seat = 1, vehicle:getMaxPassengers() - 1 do
        if usablePassengerSeat(character, vehicle, seat) then
            return seat
        end
    end
    return nil
end

function CompanionVehicles.board(character, vehicle)
    if character == nil or vehicle == nil then
        return false, "vehicle_unavailable"
    end
    if character:getVehicle() ~= nil then
        return false, "already_in_vehicle"
    end
    if CompanionVehicles.isBusy(character) then return false, "vehicle_action_pending" end
    if ISTimedActionQueue == nil or ISPathFindAction == nil or ISEnterVehicle == nil then
        return false, "vanilla_vehicle_actions_unavailable"
    end
    local seat = CompanionVehicles.findFreePassengerSeat(character, vehicle)
    if seat == nil then
        return false, "no_free_passenger_seat"
    end
    -- Construct the complete sequence before interrupting the controller.
    -- A missing path must not leave a sparse array that silently skips entry.
    local built, actions = pcall(function()
        local path = assert(ISPathFindAction:pathToVehicleSeat(character, vehicle, seat))
        local enter = assert(ISEnterVehicle:new(character, vehicle, seat))
        local result = { path, enter }
        local doorPart = vehicle:getPassengerDoor(seat)
        if doorPart ~= nil and doorPart:getDoor() ~= nil and doorPart:getDoor():isOpen()
            and ISCloseVehicleDoor ~= nil then
            result[#result + 1] = assert(ISCloseVehicleDoor:new(character, vehicle, doorPart))
        end
        return result
    end)
    if not built then return false, "vehicle_action_failed" end
    local queued, reason = queueActions(character, vehicle, seat, actions)
    if not queued then return false, reason end
    return true, "boarding_seat=" .. tostring(seat)
end

function CompanionVehicles.exit(character)
    if character == nil or character:getVehicle() == nil then
        return false, "not_in_vehicle"
    end
    if ISTimedActionQueue == nil or ISExitVehicle == nil then
        return false, "vanilla_vehicle_actions_unavailable"
    end
    if CompanionVehicles.isBusy(character) then return false, "vehicle_action_pending" end
    local built, action = pcall(function() return assert(ISExitVehicle:new(character)) end)
    if not built then return false, "vehicle_action_failed" end
    local queued, reason = queueActions(character, character:getVehicle(), nil, { action })
    if not queued then return false, reason end
    return true, "exiting"
end

return CompanionVehicles
