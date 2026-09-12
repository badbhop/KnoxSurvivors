require "Vehicles/TimedActions/ISPathFindAction"
require "Vehicles/TimedActions/ISEnterVehicle"
require "Vehicles/TimedActions/ISExitVehicle"
require "Vehicles/TimedActions/ISCloseVehicleDoor"
require "KS_Settings"
require "KS_VehicleNavigation"
require "Vehicles/TimedActions/ISSwitchVehicleSeat"

-- Native entry/seat/exit actions and physics, with bounded Knox route planning
-- on loaded ground. Driving remains opt-in until live physics acceptance.
local CompanionVehicles = rawget(_G, "KnoxCompanionVehicles") or {}
_G.KnoxCompanionVehicles = CompanionVehicles

-- Short-lived native action ownership; no seats or actions enter save data.
local pending = setmetatable({}, { __mode = "k" })
local driverRuns = setmetatable({}, { __mode = "k" })
local ACTION_TIMEOUT_MS = 45000
local DRIVER_DISTANCE = 18
local DRIVER_STOP_DISTANCE = 2.5
local DRIVER_TIMEOUT_MS = 180000

local function resetDriverControls(run, character)
    local vehicle = run ~= nil and run.vehicle or nil
    if vehicle ~= nil and vehicle.getDriver ~= nil then
        local driver=vehicle:getDriver()
        if driver~=nil and driver~=character then return end
    end
    local controller = vehicle ~= nil and vehicle.getController ~= nil
        and vehicle:getController() or nil
    if controller == nil then return end
    local controls = controller.getClientControls ~= nil
        and controller:getClientControls() or nil
    if controls ~= nil and controls.reset ~= nil then
        pcall(controls.reset, controls)
    end
    if controller.park ~= nil then pcall(controller.park, controller) end
    -- park() resets controls. Keep the brake applied until a real driver or a
    -- later NPC request takes control; clearing it immediately allowed coasting.
    if controls ~= nil then controls.brake=true end
end

local function stopDriver(character)
    local run = driverRuns[character]
    if run ~= nil then resetDriverControls(run, character) end
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
    local run=driverRuns[character]
    if run ~= nil then
        if run.phase=="boarding" then return "boarding" end
        return run.blockedSince~=nil and "waiting_for_road" or "driving"
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

local function driveTarget(vehicle, geometry, character)
    local origin=vehicle:getSquare()
    local fx,fy=KnoxVehicleNavigation.forward(vehicle)
    if origin==nil or fx==nil then return nil end
    for distance=DRIVER_DISTANCE,8,-2 do
        local x,y=vehicle:getX()+fx*distance,vehicle:getY()+fy*distance
        local route=KnoxVehicleNavigation.plan(vehicle,x,y,origin:getZ(),geometry,character)
        if route~=nil then return route end
    end
    return nil
end

function CompanionVehicles.findFreePassengerSeat(character, vehicle)
    if character == nil or vehicle == nil or vehicle.getMaxPassengers == nil then
        return nil
    end
    -- Ordinary boarding always leaves seat zero for an explicit driver order.
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
    local speed=character:getVehicle().getCurrentSpeedKmHour~=nil
        and math.abs(character:getVehicle():getCurrentSpeedKmHour()) or 0
    if speed>1 then return false, "vehicle_moving" end
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

local function startDrive(character,vehicle,destination)
    if KnoxSettings==nil or not KnoxSettings.enableExperimentalNpcDriving() then return false,"npc_driving_disabled" end
    if character==nil or vehicle==nil then return false,"vehicle_unavailable" end
    local occupied=character:getVehicle()
    if occupied~=nil and occupied~=vehicle then return false,"already_in_vehicle" end
    if CompanionVehicles.isBusy(character) then return false,"vehicle_action_pending" end
    local driver=vehicle:getDriver()
    if driver~=nil and driver~=character then return false,"driver_seat_occupied" end
    if not vehicle:isEngineRunning() then return false,"vehicle_engine_off" end
    if not vehicle:isDriveable() then return false,"vehicle_not_driveable" end
    if vehicle.getVehicleTowing~=nil and vehicle:getVehicleTowing()~=nil
        or vehicle.getVehicleTowedBy~=nil and vehicle:getVehicleTowedBy()~=nil then
        return false,"towing_not_supported"
    end
    local geometry=KnoxVehicleNavigation.geometry(vehicle)
    if geometry==nil then return false,"vehicle_geometry_unavailable" end
    local route,reason
    if destination~=nil then
        route,reason=KnoxVehicleNavigation.plan(vehicle,destination.x,destination.y,destination.z,geometry,character)
    else route=driveTarget(vehicle,geometry,character) end
    if route==nil then return false,reason or "drive_route_unavailable" end
    local phase="boarding"
    if driver==character then
        local runtime=rawget(_G,"KnoxSurvivorRuntime")
        local id=runtime~=nil and runtime.idForCharacter(character) or nil
        if id==nil or not runtime.prepareVehicle(id) then return false,"survivor_busy" end
        phase="driving"
    else
        if occupied~=vehicle and not usableDriverSeat(character,vehicle) then return false,"driver_seat_unavailable" end
        if occupied==vehicle and (vehicle:isSeatOccupied(0) or reserved(vehicle,0,character)
            or not vehicle:isSeatInstalled(0)) then return false,"driver_seat_unavailable" end
        local built,actions=pcall(function()
            if occupied==vehicle then
                return {assert(ISSwitchVehicleSeat:new(character,0,vehicle:getSeat(character)))}
            end
            return {assert(ISPathFindAction:pathToVehicleSeat(character,vehicle,0)),
                assert(ISEnterVehicle:new(character,vehicle,0))}
        end)
        if not built then return false,"vehicle_action_failed" end
        local queued,result=queueActions(character,vehicle,0,actions)
        if not queued then return false,result end
    end
    -- prepareVehicle interrupts the old duty and cancels its vehicle lease.
    -- Publish this new run AFTER that boundary, so it cannot cancel itself.
    driverRuns[character]={vehicle=vehicle,route=route,index=1,goal=route[#route],
        geometry=geometry,phase=phase,deadline=getTimestampMs()+DRIVER_TIMEOUT_MS,
        health=health(character),lastProgress=getTimestampMs(),lastX=vehicle:getX(),lastY=vehicle:getY()}
    return true,destination~=nil and "driving_to_destination" or "driving_ahead"
end

function CompanionVehicles.driveAhead(character,vehicle)
    return startDrive(character,vehicle,nil)
end
function CompanionVehicles.driveTo(character,vehicle,x,y,z)
    return startDrive(character,vehicle,{x=x,y=y,z=z})
end
function CompanionVehicles.stopDriving(character)
    local active=driverRuns[character]~=nil
    CompanionVehicles.cancel(character)
    return active
end
function CompanionVehicles.driverStatus(character)
    local run=driverRuns[character]
    return run~=nil and {phase=run.phase,blocked=run.blockedSince~=nil,destination=run.goal,
        waypoint=run.index,waypoints=#run.route} or nil
end

local function finishDrive(character,reason)
    CompanionVehicles.cancel(character)
    if KnoxActivityFeed~=nil and KnoxActivityFeed.speak~=nil then
        KnoxActivityFeed.speak(character,reason=="arrived" and "We've arrived."
            or "I'm stopping here. I can't safely continue.")
    end
    print("[KnoxSurvivors][Driving] stop="..tostring(reason))
end

local function tickDrive(character,run,now)
    local vehicle=run.vehicle
    if now>=run.deadline or character:isDead() or not KnoxSettings.enableExperimentalNpcDriving() then
        finishDrive(character,"interrupted");return
    end
    if run.phase=="boarding" then
        if character:getVehicle()==vehicle and vehicle:getDriver()==character then
            run.phase="driving";run.lastProgress=now
        elseif not CompanionVehicles.isBusy(character) then finishDrive(character,"boarding_failed") end
        return
    end
    if character:getVehicle()~=vehicle or vehicle:getDriver()~=character then
        finishDrive(character,"driver_changed");return
    end
    local current=vehicle:getSquare()
    local controller=vehicle:getController()
    local controls=controller~=nil and controller:getClientControls() or nil
    local healthNow=health(character)
    if current==nil or controls==nil or not vehicle:isDriveable() or not vehicle:isEngineRunning()
        or (healthNow~=nil and run.health~=nil and healthNow<run.health) then
        finishDrive(character,"vehicle_unavailable");return
    end
    local x,y=vehicle:getX(),vehicle:getY()
    local target=run.route[run.index]
    local dx,dy=target.x-x,target.y-y
    local distance=math.sqrt(dx*dx+dy*dy)
    local speed=math.abs(vehicle:getCurrentSpeedKmHour())
    if distance<=DRIVER_STOP_DISTANCE and run.index==#run.route and speed<=1 then
        finishDrive(character,"arrived");return
    end
    if distance<=3 and run.index<#run.route then
        run.index=run.index+1;target=run.route[run.index]
        dx,dy=target.x-x,target.y-y;distance=math.sqrt(dx*dx+dy*dy)
    end
    local fx,fy=KnoxVehicleNavigation.forward(vehicle)
    if fx==nil then finishDrive(character,"heading_unavailable");return end
    if now>=(run.nextSafetyCheck or 0) then
        run.nextSafetyCheck=now+150
        local context=KnoxVehicleNavigation.context(vehicle,run.geometry,character)
        local lookahead=run.geometry.halfLength+2+(speed/3.6)^2/4
        local routeLength=math.min(distance,lookahead)
        run.laneClear=KnoxVehicleNavigation.clear(context,x,y,x+fx*lookahead,y+fy*lookahead,current:getZ())
            and KnoxVehicleNavigation.clear(context,x,y,x+dx/math.max(0.1,distance)*routeLength,
                y+dy/math.max(0.1,distance)*routeLength,current:getZ())
    end
    local dot=(fx*dx+fy*dy)/math.max(0.1,distance)
    if not run.laneClear or dot<0 then
        controls.forward,controls.backward,controls.brake,controls.shift=false,false,true,false
        controls.steering=0
        run.blockedSince=run.blockedSince or now
        if now-run.blockedSince>15000 then finishDrive(character,"route_blocked");return end
        if speed<=1 and now>=(run.nextReplan or 0) then
            run.nextReplan=now+3000
            local replacement=KnoxVehicleNavigation.plan(vehicle,run.goal.x,run.goal.y,run.goal.z,run.geometry,character)
            if replacement~=nil then run.route,run.index=replacement,1 end
        end
        return
    end
    run.blockedSince=nil
    if (x-run.lastX)^2+(y-run.lastY)^2>=1 then
        run.lastProgress,run.lastX,run.lastY=now,x,y
    elseif now-run.lastProgress>15000 then finishDrive(character,"no_progress");return end
    local limit=KnoxSettings.npcDrivingSpeed~=nil and KnoxSettings.npcDrivingSpeed() or 20
    local command=KnoxVehicleNavigation.controls(speed,distance,dot,(fx*dy-fy*dx)/math.max(0.1,distance),limit)
    for key,value in pairs(command) do controls[key]=value end
end

function CompanionVehicles.tick()
    for character,run in pairs(driverRuns) do
        local ok,reason=pcall(tickDrive,character,run,getTimestampMs())
        if not ok then
            -- Failures cannot leave throttle latched on the native controller.
            CompanionVehicles.cancel(character)
            print("[KnoxSurvivors][Driving] error="..tostring(reason))
        end
    end
end
return CompanionVehicles
