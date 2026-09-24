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

local function safeVehicle(vehicle, origin)
    if vehicle == nil or vehicle:getDriver() ~= nil or playerOwnsOrIsNear(vehicle)
        or not vehicle:isDriveable() or not vehicle:isEngineRunning()
        or math.abs(vehicle:getCurrentSpeedKmHour()) > 1 then return false end
    if vehicle.getVehicleTowing ~= nil and vehicle:getVehicleTowing() ~= nil
        or vehicle.getVehicleTowedBy ~= nil and vehicle:getVehicleTowedBy() ~= nil then return false end
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
    local boarded = 0
    for _, member in ipairs(controller.groupMembers or {}) do
        if member ~= nil and member ~= controller.character and member:getVehicle() == nil
            and member:getCurrentSquare() ~= nil and member:getCurrentSquare():getZ() == vehicle:getZ()
            and distanceSquared(member, vehicle) <= SEARCH_DISTANCE_SQUARED then
            local success = KnoxCompanionVehicles.board(member, vehicle)
            boarded = boarded + (success and 1 or 0)
        end
    end
    return boarded
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
                local boarded = boardNearbyMembers(controller, vehicle)
                print("[KnoxSurvivors][VehicleTravel] leader=" .. tostring(controller.id)
                    .. " passengers=" .. tostring(boarded) .. " destination="
                    .. tostring(destination.x) .. "," .. tostring(destination.y))
                return true
            end
            print("[KnoxSurvivors][VehicleTravel] rejected=" .. tostring(reason))
        end
    end
    return false
end

return VehicleTravel
