require "Vehicles/TimedActions/ISPathFindAction"
require "Vehicles/TimedActions/ISEnterVehicle"
require "Vehicles/TimedActions/ISExitVehicle"
require "Vehicles/TimedActions/ISCloseVehicleDoor"
require "KS_Settings"

-- Passenger actions use the same vanilla path/enter/exit actions as a player.
-- The separate Drive Ahead slice is opt-in and deliberately short: it only
-- takes an already-running vehicle, checks a straight loaded lane, and gives
-- control back before an obstacle or the bounded destination.
local CompanionVehicles = rawget(_G, "KnoxCompanionVehicles") or {}
_G.KnoxCompanionVehicles = CompanionVehicles

-- Short-lived native action ownership; no seats or actions enter save data.
local pending = setmetatable({}, { __mode = "k" })
local driverRuns = setmetatable({}, { __mode = "k" })
local ACTION_TIMEOUT_MS = 45000
local DRIVER_DISTANCE = 18
local DRIVER_STOP_DISTANCE = 2.5
local DRIVER_TIMEOUT_MS = 90000

local function resetDriverControls(run)
    local vehicle = run ~= nil and run.vehicle or nil
    local controller = vehicle ~= nil and vehicle.getController ~= nil
        and vehicle:getController() or nil
    if controller == nil then return end
    local controls = controller.getClientControls ~= nil
        and controller:getClientControls() or nil
    if controls ~= nil and controls.reset ~= nil then
        pcall(controls.reset, controls)
    end
    if controller.park ~= nil then pcall(controller.park, controller) end
    if controller.control_NoControl ~= nil then
        pcall(controller.control_NoControl, controller)
    end
end

local function stopDriver(character)
    local run = driverRuns[character]
    if run ~= nil then resetDriverControls(run) end
    driverRuns[character] = nil
end

local function health(character)
    if character == nil or character.getBodyDamage == nil then return nil end
    local ok, value = pcall(function() return character:getBodyDamage():getHealth() end)
    return ok and tonumber(value) or nil
end

function CompanionVehicles.cancel(character)
    stopDriver(character)
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
    if driverRuns[character] ~= nil then
        return "driving"
    end
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

local function usableDriverSeat(character, vehicle)
    if character == nil or vehicle == nil or vehicle:isSeatOccupied(0)
        or reserved(vehicle, 0, character) then
        return false
    end
    if vehicle.isSeatInstalled ~= nil and not vehicle:isSeatInstalled(0) then
        return false
    end
    if vehicle.isEnterBlocked ~= nil and vehicle:isEnterBlocked(character, 0) then
        return false
    end
    local doorPart = vehicle.getPassengerDoor ~= nil
        and vehicle:getPassengerDoor(0) or nil
    local door = doorPart ~= nil and doorPart:getDoor() or nil
    return door == nil or not door:isLocked()
end

local function driverForward(vehicle)
    if vehicle == nil or vehicle.getAngleZ == nil then return nil, nil end
    local angle = tonumber(vehicle:getAngleZ())
    if angle == nil then return nil, nil end
    local radians = angle * math.pi / 180
    -- Build 42 reports BaseVehicle.getAngleZ in degrees.  The vehicle's
    -- forward basis uses the same north-facing convention as IsoPlayer.
    return -math.sin(radians), math.cos(radians)
end

local function driverLaneClear(origin, target)
    local cell = getCell ~= nil and getCell() or nil
    if origin == nil or target == nil or cell == nil
        or origin:getZ() ~= target:getZ() then return false end
    local dx, dy = target:getX() - origin:getX(), target:getY() - origin:getY()
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps <= 0 or steps > DRIVER_DISTANCE + 1 then return false end
    local previous = origin
    for step = 1, steps do
        local square = cell:getGridSquare(
            math.floor(origin:getX() + dx * step / steps + 0.5),
            math.floor(origin:getY() + dy * step / steps + 0.5),
            origin:getZ()
        )
        if square == nil or (square.canStand ~= nil and not square:canStand())
            or (previous.isBlockedTo ~= nil and previous:isBlockedTo(square)) then
            return false
        end
        previous = square
    end
    return true
end

local function driveTarget(vehicle)
    local cell = getCell ~= nil and getCell() or nil
    local origin = vehicle ~= nil and vehicle.getSquare ~= nil
        and vehicle:getSquare() or nil
    local fx, fy = driverForward(vehicle)
    if cell == nil or origin == nil or fx == nil then return nil end
    for distance = DRIVER_DISTANCE, 8, -1 do
        local target = cell:getGridSquare(
            math.floor(vehicle:getX() + fx * distance + 0.5),
            math.floor(vehicle:getY() + fy * distance + 0.5),
            origin:getZ()
        )
        if target ~= nil and (target.canStand == nil or target:canStand())
            and driverLaneClear(origin, target) then
            return target
        end
    end
    return nil
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

-- Start a short, straight, opt-in drive for a companion. The player must
-- already be a passenger (or otherwise have vacated seat zero); this prevents
-- Knox from silently stealing a player's driver seat or keys.
function CompanionVehicles.driveAhead(character, vehicle)
    if KnoxSettings == nil or KnoxSettings.enableExperimentalNpcDriving == nil
        or not KnoxSettings.enableExperimentalNpcDriving() then
        return false, "npc_driving_disabled"
    end
    if character == nil or vehicle == nil then return false, "vehicle_unavailable" end
    if character:getVehicle() ~= nil then return false, "already_in_vehicle" end
    if CompanionVehicles.isBusy(character) then return false, "vehicle_action_pending" end
    if vehicle.getDriver == nil or vehicle:getDriver() ~= nil then
        return false, "driver_seat_occupied"
    end
    if vehicle.isEngineRunning == nil or not vehicle:isEngineRunning() then
        return false, "vehicle_engine_off"
    end
    if vehicle.isDriveable ~= nil and not vehicle:isDriveable() then
        return false, "vehicle_not_driveable"
    end
    if not usableDriverSeat(character, vehicle) then
        return false, "driver_seat_unavailable"
    end
    if ISTimedActionQueue == nil or ISPathFindAction == nil or ISEnterVehicle == nil then
        return false, "vanilla_vehicle_actions_unavailable"
    end
    local target = driveTarget(vehicle)
    if target == nil then return false, "drive_lane_unavailable" end
    local built, actions = pcall(function()
        return {
            assert(ISPathFindAction:pathToVehicleSeat(character, vehicle, 0)),
            assert(ISEnterVehicle:new(character, vehicle, 0)),
        }
    end)
    if not built then return false, "vehicle_action_failed" end
    local run = {
        vehicle = vehicle,
        target = target,
        phase = "boarding",
        deadline = getTimestampMs() + DRIVER_TIMEOUT_MS,
    }
    driverRuns[character] = run
    local queued, reason = queueActions(character, vehicle, 0, actions)
    if not queued then
        driverRuns[character] = nil
        return false, reason
    end
    return true, "driving_ahead"
end

function CompanionVehicles.tick()
    for character, run in pairs(driverRuns) do
        local vehicle = run.vehicle
        if getTimestampMs() >= run.deadline
            or character == nil or vehicle == nil
            or (character.isDead ~= nil and character:isDead()) then
            CompanionVehicles.cancel(character)
        elseif run.phase == "boarding" then
            local seated = character:getVehicle() == vehicle
                and vehicle.getDriver ~= nil and vehicle:getDriver() == character
            if seated then
                run.phase = "driving"
                run.startedAt = getTimestampMs()
            elseif pending[character] == nil and character:getVehicle() == nil then
                CompanionVehicles.cancel(character)
            end
        elseif run.phase == "driving" then
            local controller = vehicle.getController ~= nil
                and vehicle:getController() or nil
            local controls = controller ~= nil and controller.getClientControls ~= nil
                and controller:getClientControls() or nil
            local current = vehicle.getSquare ~= nil and vehicle:getSquare() or nil
            local target = run.target
            local distance = current ~= nil and target ~= nil
                and math.sqrt((vehicle:getX() - target:getX()) ^ 2
                    + (vehicle:getY() - target:getY()) ^ 2) or math.huge
            local valid = character:getVehicle() == vehicle
                and vehicle.getDriver ~= nil and vehicle:getDriver() == character
                and (vehicle.isDriveable == nil or vehicle:isDriveable())
                and vehicle.isEngineRunning ~= nil and vehicle:isEngineRunning()
                and controls ~= nil and current ~= nil and target ~= nil
                and driverLaneClear(current, target)
            if not valid or distance <= DRIVER_STOP_DISTANCE then
                CompanionVehicles.cancel(character)
            else
                local fx, fy = driverForward(vehicle)
                local dx, dy = target:getX() - vehicle:getX(), target:getY() - vehicle:getY()
                local length = math.max(1, math.sqrt(dx * dx + dy * dy))
                local cross = fx * dy - fy * dx
                local dot = fx * dx + fy * dy
                controls.steering = math.max(-1, math.min(1, cross / length * 3))
                controls.forward = dot > 0
                controls.backward = false
                controls.brake = dot <= 0
                controls.shift = false
            end
        end
    end
end

return CompanionVehicles
