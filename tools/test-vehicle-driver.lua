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
