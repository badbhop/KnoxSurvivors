local root = arg[1] or "."
require = function() return true end

local function character(x, y, z)
    return {
        x = x, y = y, z = z or 0,
        getX = function(self) return self.x end,
        getY = function(self) return self.y end,
        getZ = function(self) return self.z end,
        getCurrentSquare = function(self) return self.square end,
        getVehicle = function(self) return self.vehicle end,
    }
end
local function square(owner)
    return { getX = function() return owner.x end, getY = function() return owner.y end,
        getZ = function() return owner.z end }
end
local leader, passenger, player = character(0, 0), character(2, 0), character(200, 200)
leader.square, passenger.square, player.square = square(leader), square(passenger), square(player)
local vehicle = character(4, 0)
vehicle.square = square(vehicle)
vehicle.getDriver = function(self) return self.driver end
vehicle.isDriveable = function() return true end
vehicle.isEngineRunning = function() return true end
vehicle.getCurrentSpeedKmHour = function() return 0 end
vehicle.getVehicleTowing = function() return nil end
vehicle.getVehicleTowedBy = function() return nil end
vehicle.getSquare = function(self) return self.square end
vehicle.fuel, vehicle.locked = 50, false
vehicle.getRemainingFuelPercentage = function(self) return self.fuel end
vehicle.areAllDoorsLocked = function(self) return self.locked end
local collection = { size = function() return 1 end, get = function(_, index) return index == 0 and vehicle or nil end }
getCell = function() return { getVehicles = function() return collection end } end
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function(index) return index == 0 and player or nil end
KnoxPersistence = { getTravelGroupFor = function() return { leaderId = "leader" } end }
local boarded, drives = 0, 0
local seatsTaken, attached = 0, nil
KnoxCompanionVehicles = {
    board = function(member, candidate)
        assert(candidate == vehicle)
        if seatsTaken >= 1 then return false, "no_free_passenger_seat" end
        seatsTaken = seatsTaken + 1
        member.vehicle = candidate
        boarded = boarded + 1
        return true
    end,
    driveTo = function(driver, candidate, x, y, z)
        assert(driver == leader and candidate == vehicle and x == 100 and y == 0 and z == 0)
        drives = drives + 1
        return true, "driving_to_destination"
    end,
    setRunPassengers = function(driver, candidate, roster)
        assert(driver == leader and candidate == vehicle)
        attached = roster
        return true
    end,
}
local travel = dofile(root .. "/mod/42/media/lua/client/KS_NpcVehicleTravel.lua")
local controller = { id = "leader", character = leader, groupMembers = { leader, passenger } }
assert(travel.tryBegin(controller, { x = 100, y = 0, z = 0 }, 100),
    "leader may use an eligible distant running vehicle")
assert(boarded == 1 and drives == 1, "nearby group passengers board after driver request is accepted")
controller.id = "member"
assert(not travel.tryBegin(controller, { x = 100, y = 0, z = 0 }, 1000),
    "a non-leader cannot take group vehicle control")
controller.id, passenger.vehicle = "leader", nil
player.vehicle = vehicle
assert(not travel.tryBegin(controller, { x = 100, y = 0, z = 0 }, 2000),
    "an occupied player vehicle is never eligible for autonomous travel")
player.vehicle=nil
local before=boarded
KnoxCompanionVehicles.driveTo=function() return false, "drive_route_unavailable" end
assert(not travel.tryBegin(controller, {x=100,y=0,z=0},3000))
assert(boarded==before and passenger.vehicle==nil,
    "rejected driver request must not board or interrupt passengers")
local ready, reason = travel.assessReadiness(vehicle)
assert(ready and reason == "vehicle_ready", "a fueled unlocked running vehicle is admitted")
vehicle.fuel = 0
ready, reason = travel.assessReadiness(vehicle)
assert(not ready and reason == "vehicle_low_fuel", "an unfueled vehicle is rejected with reason")
before = boarded
assert(not travel.tryBegin(controller, {x=100,y=0,z=0},4000))
assert(boarded == before and passenger.vehicle == nil,
    "an unfueled vehicle must not board passengers")
vehicle.fuel, vehicle.locked = 50, true
ready, reason = travel.assessReadiness(vehicle)
assert(not ready and reason == "vehicle_doors_locked", "a fully locked vehicle is rejected with reason")
vehicle.locked = false
vehicle.getRemainingFuelPercentage = nil
ready, reason = travel.assessReadiness(vehicle)
assert(not ready and reason == "vehicle_state_unknown",
    "missing native fuel state fails closed instead of inventing usable")
vehicle.getRemainingFuelPercentage = function(self) return self.fuel end
local passenger2 = character(3, 0)
passenger2.square = square(passenger2)
controller.groupMembers = { leader, passenger, passenger2 }
seatsTaken = 0
passenger.vehicle = nil
KnoxCompanionVehicles.driveTo = function(driver, candidate, x, y, z)
    drives = drives + 1
    return true, "driving_to_destination"
end
assert(travel.tryBegin(controller, { x = 100, y = 0, z = 0 }, 5000))
assert(attached ~= nil and #attached == 1 and attached[1].member == passenger
    and attached[1].vehicle == vehicle,
    "the roster commits only seated members explicitly")
assert(passenger2.vehicle == nil, "overflow members stay unleased and unclaimed")
print("NPC vehicle travel PASS leader=true passengers=true player_vehicle_safe=true readiness=true")
