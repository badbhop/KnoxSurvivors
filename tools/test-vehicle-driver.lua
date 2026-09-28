local root=arg[1] or "."
local w=dofile(root.."/tools/vehicle-test-world.lua")
local nav=dofile(root.."/mod/42/media/lua/client/KS_VehicleNavigation.lua")
local vehicles=dofile(root.."/mod/42/media/lua/client/KS_CompanionVehicles.lua")
local started,reason=vehicles.driveAhead(w.character,w.vehicle)
assert(started and reason=="driving_ahead")
assert(vehicles.activity(w.character)=="boarding", "new driver lease survives prepareVehicle cancelling the old duty")
w.seatDriver();vehicles.tick();vehicles.tick()
assert(w.controls.forward and not w.controls.brake)
w.vehicle.speed=24;vehicles.tick()
assert(not w.controls.forward and w.controls.brake, "overspeed is braked before reaching the destination")
w.vehicle.speed=5;w.vehicle.y=14;w.now=200;vehicles.tick()
assert(vehicles.driverStatus(w.character)~=nil, "a moving driver retains control while approaching")
w.vehicle.speed=0;w.vehicle.y=17;w.now=400;vehicles.tick();vehicles.tick()
assert(vehicles.activity(w.character)=="riding" and not w.controls.forward and w.controls.brake
    and w.controller.parkCount>0, "arrival retains braking rather than coasting")
-- Restart from the already occupied driver seat with a map destination.
w.vehicle.y=0
assert(vehicles.driveTo(w.character,w.vehicle,0,30,0))
vehicles.tick();assert(w.controls.forward)
w.blocked['0:4']=true;w.now=600;vehicles.tick()
assert(not w.controls.forward and w.controls.brake and vehicles.activity(w.character)=="waiting_for_road")
w.blocked={};w.now=800;vehicles.tick()
assert(w.controls.forward and vehicles.activity(w.character)=="driving", "cleared lane resumes the same request")
-- Do not brake a real player who takes over the driver's seat.
local player={};w.vehicle.driver=player
local resets=w.controls.resetCount;vehicles.tick()
assert(w.controls.resetCount==resets and vehicles.driverStatus(w.character)==nil)
w.vehicle.driver=nil;w.character.vehicle=w.vehicle
assert(vehicles.driveTo(w.character,w.vehicle,0,20,0))
assert(ISTimedActionQueue.queues[w.character].queue[1].kind=="switch", "a passenger uses native seat-switching")
w.seatDriver();vehicles.tick()
w.character.health=90;vehicles.tick()
assert(vehicles.driverStatus(w.character)==nil and w.controls.brake, "injury releases throttle")
w.vehicle.speed=10
local exited,exitReason=vehicles.exit(w.character)
assert(not exited and exitReason=="vehicle_moving", "exit cannot interrupt a moving vehicle")
w.vehicle.speed=0;w.character.health=100
KnoxSettings.enableExperimentalNpcDriving=function() return false end
assert(not vehicles.driveAhead(w.character,w.vehicle))
print("Vehicle driver PASS boarding_ownership=true native_heading=true speed=true obstacles=true arrival=true takeover=true seat_switch=true")

KnoxSettings.enableExperimentalNpcDriving=function() return true end
w.vehicle.driver=w.character
assert(vehicles.driveTo(w.character,w.vehicle,0,20,0))
vehicles.tick();assert(w.controls.forward)
local originalContext=nav.context
nav.context=function() error("simulated unavailable geometry") end
w.now=1000;vehicles.tick()
assert(not w.controls.forward and w.controls.brake and vehicles.driverStatus(w.character)==nil,
    "a route update error must release native throttle")
nav.context=originalContext

-- Intentional waiting has its own deadline and must not age the movement timer.
w.vehicle.x,w.vehicle.y,w.vehicle.speed=0,0,0
w.vehicle.driver=w.character;w.character.vehicle=w.vehicle
w.now=2000
assert(vehicles.driveTo(w.character,w.vehicle,0,30,0))
vehicles.tick()
w.blocked['0:4']=true;w.now=3000;vehicles.tick()
assert(vehicles.driverStatus(w.character).blocked)
w.blocked={};w.now=17001;vehicles.tick()
assert(vehicles.driverStatus(w.character)~=nil and w.controls.forward,
    "a cleared 14-second obstruction resumes instead of triggering no_progress")
vehicles.stopDriving(w.character)

-- A boarding lease is not ownership of the car's controls.
w.character.vehicle=nil;w.vehicle.driver=nil
local parked=w.controller.parkCount
assert(vehicles.driveAhead(w.character,w.vehicle))
vehicles.cancel(w.character)
assert(w.controller.parkCount==parked,"cancelled boarding must not park a vehicle the NPC never drove")
w.vehicle.speed=3
local movingAccepted,movingReason=vehicles.driveAhead(w.character,w.vehicle)
assert(not movingAccepted and movingReason=="vehicle_moving")
w.vehicle.speed=0
print("Driver handoff PASS boarding_no_remote_brake=true wait_progress=true moving_boarding_rejected=true")
-- Passenger roster rolls back when the driver run aborts.
local function rider()
    return { vehicle = nil, getVehicle = function(self) return self.vehicle end,
        isDead = function() return false end }
end
local riderA, riderB = rider(), rider()
local realPrepare = KnoxSurvivorRuntime.prepareVehicle
KnoxSurvivorRuntime.prepareVehicle = function() return true end
assert(vehicles.board(riderA, w.vehicle) and vehicles.board(riderB, w.vehicle))
KnoxSurvivorRuntime.prepareVehicle = realPrepare
assert(vehicles.driveAhead(w.character, w.vehicle))
assert(vehicles.setRunPassengers(w.character, w.vehicle,
    { { member = riderA, vehicle = w.vehicle }, { member = riderB, vehicle = w.vehicle } }))
riderB.vehicle = w.vehicle
ISTimedActionQueue.clear(riderB)
ISTimedActionQueue.clear(w.character)
vehicles.tick()
assert(not vehicles.isBusy(riderA)
    and #(ISTimedActionQueue.queues[riderA] and ISTimedActionQueue.queues[riderA].queue or {}) == 0,
    "driver abort releases unseated passenger leases at once")
local exitQueue = ISTimedActionQueue.queues[riderB] and ISTimedActionQueue.queues[riderB].queue or {}
assert(#exitQueue >= 1 and exitQueue[#exitQueue].kind == "exit",
    "driver abort offers seated passengers the native exit")
assert(not vehicles.setRunPassengers(w.character, w.vehicle, {}),
    "a finished run accepts no new roster")
print("Driver roster PASS rollback=true seated_exit=true stale_run_rejected=true")
-- Cancelling the driver settles the attached roster; player takeover keeps it.
local function commuter()
    return { vehicle = nil, getVehicle = function(self) return self.vehicle end,
        isDead = function() return false end }
end
local commuterA, commuterB = commuter(), commuter()
local driverPrepare = KnoxSurvivorRuntime.prepareVehicle
KnoxSurvivorRuntime.prepareVehicle = function() return true end
assert(vehicles.board(commuterA, w.vehicle) and vehicles.board(commuterB, w.vehicle))
KnoxSurvivorRuntime.prepareVehicle = driverPrepare
assert(vehicles.driveAhead(w.character, w.vehicle))
assert(vehicles.setRunPassengers(w.character, w.vehicle,
    { { member = commuterA, vehicle = w.vehicle }, { member = commuterB, vehicle = w.vehicle } }))
vehicles.cancel(w.character)
assert(not vehicles.isBusy(commuterA) and not vehicles.isBusy(commuterB),
    "driver cancel settles every attached passenger lease at once")
assert(vehicles.driveAhead(w.character, w.vehicle))
KnoxSurvivorRuntime.prepareVehicle = function() return true end
assert(vehicles.board(commuterA, w.vehicle))
assert(vehicles.board(commuterB, w.vehicle))
KnoxSurvivorRuntime.prepareVehicle = driverPrepare
assert(vehicles.setRunPassengers(w.character, w.vehicle,
    { { member = commuterA, vehicle = w.vehicle }, { member = commuterB, vehicle = w.vehicle } }))
assert(vehicles.stopDriving(w.character))
assert(vehicles.isBusy(commuterA) and vehicles.isBusy(commuterB),
    "player takeover preserves passenger leases instead of settling them")
print("Driver arbitration PASS cancel_settles=true takeover_keeps=true")
-- Readiness fallback without the travel module: fuel and locks still gate.
w.vehicle.fuel=0
local dryAccepted,dryReason=vehicles.driveAhead(w.character,w.vehicle)
assert(not dryAccepted and dryReason=="vehicle_low_fuel", "unfueled vehicle rejected without travel module")
w.vehicle.fuel=50;w.vehicle.locked=true
local lockedAccepted,lockedReason=vehicles.driveAhead(w.character,w.vehicle)
assert(not lockedAccepted and lockedReason=="vehicle_doors_locked", "locked vehicle rejected without travel module")
w.vehicle.locked=false
w.vehicle.getRemainingFuelPercentage=nil
local unknownAccepted,unknownReason=vehicles.driveAhead(w.character,w.vehicle)
assert(not unknownAccepted and unknownReason=="vehicle_state_unknown", "missing fuel state fails closed")
print("Driver readiness PASS low_fuel=true locked=true unknown_state=true")
