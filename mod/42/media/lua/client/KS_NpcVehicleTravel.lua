require "KS_CompanionVehicles"
require "KS_SurvivorRuntime"

-- Loaded-world transport for autonomous travel groups. This deliberately
-- reuses the native boarding and driving boundary: faction transport cannot
-- teleport, create a vehicle, bypass a locked seat, or drive a player car.
-- If no safe vehicle or route exists, normal on-foot travel stays in control.
local VehicleTravel = rawget(_G, "KnoxNpcVehicleTravel") or {}
_G.KnoxNpcVehicleTravel = VehicleTravel

local MIN_TRIP_DISTANCE_SQUARED = 60 * 60
local SEARCH_DISTANCE_SQUARED = 28 * 28
local PLAYER_EXCLUSION_DISTANCE_SQUARED = 45 * 45
local RETRY_TICKS = 600

local function distanceSquared(first, second)
    local dx, dy = first:getX() - second:getX(), first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function currentPlayers()
    local result, count = {}, getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, count - 1) do
        local player = getSpecificPlayer ~= nil and getSpecificPlayer(playerNum) or nil
        if player ~= nil then result[#result + 1] = player end
    end
    return result
end

local function playerOwnsOrIsNear(vehicle)
    for _, player in ipairs(currentPlayers()) do
        if player:getVehicle() == vehicle then return true end
        local square = player:getCurrentSquare()
        if square ~= nil and square:getZ() == vehicle:getZ()
            and distanceSquared(player, vehicle) <= PLAYER_EXCLUSION_DISTANCE_SQUARED then
            return true
        end
    end
    return false
end

-- Shared admission verdict for one parked vehicle: intrinsic native state
-- only (driver, engine, driveability, speed, towing, fuel, locks). Returns
-- true plus "vehicle_ready", or false plus a snake_case reason reusing the
-- KS_CompanionVehicles drive-admission vocabulary where the meaning matches.
-- Discovery position/player filters stay in safeVehicle below; drive admission
-- in KS_CompanionVehicles consumes these same reason strings. Native fuel
-- evidence: BaseVehicle:getRemainingFuelPercentage() as used by the shipped
-- ISVehicleDashboard; native lock evidence: BaseVehicle:areAllDoorsLocked().
-- A sub-1% tank reads as unfueled; that threshold is implementation policy
-- awaiting live pacing evidence, not a native fuel rule. Missing optional
-- native methods fail closed with "vehicle_state_unknown" rather than an
-- invented usable verdict. Locked vehicles are rejected here; forced entry
-- remains an explicitly deferred future track.
local LOW_FUEL_PERCENT = 1
function VehicleTravel.assessReadiness(vehicle)
    if vehicle == nil then return false, "vehicle_missing" end
    if vehicle.getDriver ~= nil and vehicle:getDriver() ~= nil then
        return false, "driver_seat_occupied"
    end
    if vehicle.isEngineRunning == nil or not vehicle:isEngineRunning() then
        return false, "vehicle_engine_off"
    end
    if vehicle.isDriveable == nil or not vehicle:isDriveable() then
        return false, "vehicle_not_driveable"
    end
    if vehicle.getCurrentSpeedKmHour ~= nil
        and math.abs(vehicle:getCurrentSpeedKmHour()) > 1 then
        return false, "vehicle_moving"
    end
    if vehicle.getVehicleTowing ~= nil and vehicle:getVehicleTowing() ~= nil
        or vehicle.getVehicleTowedBy ~= nil and vehicle:getVehicleTowedBy() ~= nil then
        return false, "towing_not_supported"
    end
    if vehicle.getRemainingFuelPercentage == nil then
        return false, "vehicle_state_unknown"
    end
    local fueled, percent = pcall(function() return vehicle:getRemainingFuelPercentage() end)
    if not fueled or (tonumber(percent) or 0) < LOW_FUEL_PERCENT then
        return false, "vehicle_low_fuel"
    end
    if vehicle.areAllDoorsLocked == nil then
        return false, "vehicle_state_unknown"
    end
    local checked, allLocked = pcall(function() return vehicle:areAllDoorsLocked() end)
    if not checked then return false, "vehicle_state_unknown" end
    if allLocked then return false, "vehicle_doors_locked" end
    return true, "vehicle_ready"
end

local function safeVehicle(vehicle, origin)
    if VehicleTravel.assessReadiness(vehicle) ~= true then return false end
    if playerOwnsOrIsNear(vehicle) then return false end
    local square = vehicle:getSquare()
    return square ~= nil and square:getZ() == origin:getZ()
        and distanceSquared(origin, vehicle) <= SEARCH_DISTANCE_SQUARED
end

local function vehiclesInCell()
    local cell = getCell ~= nil and getCell() or nil
    local vehicles = cell ~= nil and cell.getVehicles ~= nil and cell:getVehicles() or nil
    if vehicles == nil then return {} end
    local result = {}
    if vehicles.iterator ~= nil then
        local iterator = vehicles:iterator()
        while iterator:hasNext() do result[#result + 1] = iterator:next() end
    else
        for index = 0, vehicles:size() - 1 do result[#result + 1] = vehicles:get(index) end
    end
    return result
end

local function boardNearbyMembers(controller, vehicle)
    local roster = {}
    for _, member in ipairs(controller.groupMembers or {}) do
        if member ~= nil and member ~= controller.character and member:getVehicle() == nil
            and member:getCurrentSquare() ~= nil and member:getCurrentSquare():getZ() == vehicle:getZ()
            and distanceSquared(member, vehicle) <= SEARCH_DISTANCE_SQUARED then
            -- Seat exhaustion is an explicit outcome, not a silent skip: only
            -- committed members join the roster the abort path rolls back.
            local success = KnoxCompanionVehicles.board(member, vehicle)
            if success then roster[#roster + 1] = { member = member, vehicle = vehicle } end
        end
    end
    return roster
end

function VehicleTravel.tryBegin(controller, destination, ticks)
    if controller == nil or controller.character == nil or destination == nil
        or controller.companionOrder ~= nil or controller.baseTask ~= nil
        or ticks < (controller.nextNpcVehicleTravelAt or 0) then return false end
    local origin = controller.character:getCurrentSquare()
    local group = KnoxPersistence.getTravelGroupFor(controller.id)
    local dx = destination.x - controller.character:getX()
    local dy = destination.y - controller.character:getY()
    if origin == nil or group == nil or group.leaderId ~= controller.id
        or origin:getZ() ~= destination.z
        or dx * dx + dy * dy < MIN_TRIP_DISTANCE_SQUARED then return false end
    controller.nextNpcVehicleTravelAt = ticks + RETRY_TICKS
    for _, vehicle in ipairs(vehiclesInCell()) do
        if safeVehicle(vehicle, origin) then
            local started, reason = KnoxCompanionVehicles.driveTo(
                controller.character, vehicle, destination.x, destination.y, destination.z
            )
            if started then
                -- Failed routing/disabled driving must not strand passengers
                -- in a vehicle the leader will never drive.
                local roster = boardNearbyMembers(controller, vehicle)
                KnoxCompanionVehicles.setRunPassengers(controller.character, vehicle, roster)
                print("[KnoxSurvivors][VehicleTravel] leader=" .. tostring(controller.id)
                    .. " passengers=" .. tostring(#roster) .. " destination="
                    .. tostring(destination.x) .. "," .. tostring(destination.y))
                return true
            end
            print("[KnoxSurvivors][VehicleTravel] rejected=" .. tostring(reason))
        end
    end
    return false
end

return VehicleTravel
