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

local function usablePassengerSeat(character, vehicle, seat)
    if character == nil or vehicle == nil or seat == nil
        or vehicle:isSeatOccupied(seat) then
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
    if ISTimedActionQueue == nil or ISPathFindAction == nil or ISEnterVehicle == nil then
        return false, "vanilla_vehicle_actions_unavailable"
    end
    local seat = CompanionVehicles.findFreePassengerSeat(character, vehicle)
    if seat == nil then
        return false, "no_free_passenger_seat"
    end
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleSeat(character, vehicle, seat))
    ISTimedActionQueue.add(ISEnterVehicle:new(character, vehicle, seat))
    local doorPart = vehicle:getPassengerDoor(seat)
    if doorPart ~= nil and doorPart:getDoor() ~= nil and doorPart:getDoor():isOpen()
        and ISCloseVehicleDoor ~= nil then
        ISTimedActionQueue.add(ISCloseVehicleDoor:new(character, vehicle, doorPart))
    end
    return true, "boarding_seat=" .. tostring(seat)
end

function CompanionVehicles.exit(character)
    if character == nil or character:getVehicle() == nil then
        return false, "not_in_vehicle"
    end
    if ISTimedActionQueue == nil or ISExitVehicle == nil then
        return false, "vanilla_vehicle_actions_unavailable"
    end
    ISTimedActionQueue.add(ISExitVehicle:new(character))
    return true, "exiting"
end

return CompanionVehicles
