-- Diagnostic dynamics only: independent rear-axle integration with the native
-- control smoothing/deadband. This catches planner/follower contradictions;
-- Bullet collisions, tire grip and real stopping distances still need live tests.
local root=arg[1] or "."
local function journey(gx,gy,obstructed)
    local w=dofile(root.."/tools/vehicle-test-world.lua")
    local nav=dofile(root.."/mod/42/media/lua/client/KS_VehicleNavigation.lua")
    local vehicles=dofile(root.."/mod/42/media/lua/client/KS_CompanionVehicles.lua")
    local g=assert(nav.geometry(w.vehicle))
    if obstructed then w.blocked['0:12']=true end
    w.seatDriver()
    local ok,reason=vehicles.driveTo(w.character,w.vehicle,gx,gy,0)
    assert(ok,reason)
    local angle,velocity,steering=math.pi/2,0,0
    w.controller.getVehicleSteering=function() return steering end
    local dt=0.05
    local maxError,stops=0,0
    local arrived=false
    for tick=1,2400 do
        w.now=tick*dt*1000
        vehicles.tick()
        local status=vehicles.driverStatus(w.character)
        if status==nil then
            assert((w.vehicle.x-gx)^2+(w.vehicle.y-gy)^2<=2.5^2,
                "journey ended before destination "..gx..","..gy.." at "..w.vehicle.x..","..w.vehicle.y)
            arrived=true;break
        end
        if status.routeError then maxError=math.max(maxError,status.routeError) end
        if status.blocked then stops=stops+1 end
        local input=w.controls.steering or 0
        -- CarController update at the corresponding 60 Hz simulation scale.
        if math.abs(input)>0.1 then
            steering=steering+(-input-steering)*math.min(1,0.075*dt*60*math.max(0.1,1-velocity*3.6/100))
        elseif math.abs(steering)<=0.04*dt*60 then steering=0
        else steering=steering-(steering>0 and 1 or -1)*0.04*dt*60 end
        steering=math.max(-0.7,math.min(0.7,steering))
        if w.controls.brake then velocity=math.max(0,velocity-2*dt)
        elseif w.controls.forward then velocity=velocity+1.8*dt
        else velocity=math.max(0,velocity-0.12*dt) end
        -- Integrate the rear axle independently; do not use Navigation.advance.
        local rx=w.vehicle.x+math.cos(angle)*g.rearZ+math.sin(angle)*g.rearX
        local ry=w.vehicle.y+math.sin(angle)*g.rearZ-math.cos(angle)*g.rearX
        local change=-math.tan(steering)*velocity/g.wheelbase*dt
        rx=rx+math.cos(angle+change/2)*velocity*dt
        ry=ry+math.sin(angle+change/2)*velocity*dt
        angle=angle+change
        w.vehicle.x=rx-math.cos(angle)*g.rearZ-math.sin(angle)*g.rearX
        w.vehicle.y=ry-math.sin(angle)*g.rearZ+math.cos(angle)*g.rearX
        w.vehicle.fx,w.vehicle.fy=math.cos(angle),math.sin(angle)
        w.vehicle.speed=velocity*3.6
        assert(nav.poseClear(nav.context(w.vehicle,g,w.character),w.vehicle.x,w.vehicle.y,angle,0),
            "simulated whole body overlapped an obstacle")
    end
    assert(arrived,"journey failed to arrive within diagnostic deadline")
    assert(maxError<3,"route tracking exceeded the recovery boundary")
    print("Vehicle journey PASS goal="..gx..","..gy.." obstacle="..tostring(obstructed)
        .." maxError="..string.format("%.2f",maxError).." waitingTicks="..stops)
end
journey(0,30,false)
journey(20,20,false)
journey(0,-30,false)
journey(0,30,true)
