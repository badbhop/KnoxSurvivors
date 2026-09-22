require "ISUI/Maps/ISWorldMap"
require "KS_CompanionService"
require "KS_CompanionVehicles"
require "KS_Settings"

local Orders={}
KnoxMapOrders=Orders
local failureLines={
    destination_too_far="Choose a closer destination. I can plan nearby routes for now.",
    destination_too_close="We're already close to that point.",
    destination_unavailable="Choose loaded, open ground for our destination.",
    drive_route_unavailable="I can't find a clear route there.",
    drive_planning_budget="I can't work out a route through those obstacles. Try an intermediate point.",
    vehicle_geometry_unavailable="I can't safely plan turns for this vehicle yet.",
    vehicle_heading_unavailable="The vehicle needs to be upright before I can drive.",
    vehicle_moving="Stop the vehicle before I take the driver's seat.",
    vehicle_engine_off="Start the engine first, then move to a passenger seat.",
    driver_seat_occupied="Someone is already driving.",
    player_must_vacate_driver_seat="Move to a passenger seat so I can drive.",
    towing_not_supported="I can't drive safely with a trailer yet.",
}
function Orders.drive(player,id,x,y)
    local success,reason=KnoxCompanionService.drivePlayerVehicleTo(player,id,x,y)
    if not success and KnoxActivityFeed~=nil then
        KnoxActivityFeed.speak(player,failureLines[reason] or "That driving order isn't available right now.")
    end
end
function Orders.fill(context,player,x,y)
    if player==nil or player:getVehicle()==nil or not KnoxSettings.enableExperimentalNpcDriving() then return false end
    local ids=KnoxCompanionService.getCompanionIds(player)
    local candidates={}
    for _,id in ipairs(ids) do
        local character=KnoxSurvivorRuntime.getCharacter(id)
        if character~=nil and not character:isDead() then candidates[#candidates+1]=id end
    end
    if #candidates==0 then return false end
    local option=context:addOption("Drive Here",nil,nil)
    local menu=ISContextMenu:getNew(context);context:addSubMenu(option,menu)
    for _,id in ipairs(candidates) do
        local identity=KnoxPersistence.getSurvivorIdentity(id) or {}
        local name=(tostring(identity.forename or "").." "..tostring(identity.surname or "")):match("^%s*(.-)%s*$")
        local item=menu:addOption(name~="" and name or "Survivor",player,Orders.drive,id,x,y)
        if player:getVehicle():getDriver()==player then item.notAvailable=true end
        local character=KnoxSurvivorRuntime.getCharacter(id)
        if character:getVehicle()==player:getVehicle() and KnoxCompanionVehicles.driverStatus(character)~=nil then
            context:addOption("Stop Driving",player,KnoxCompanionService.stopPlayerVehicle,id)
        end
    end
    return true
end

if ISWorldMap~=nil and not ISWorldMap.knoxDrivingOrdersInstalled then
    ISWorldMap.knoxDrivingOrdersInstalled=true
    local original=ISWorldMap.onRightMouseUp
    function ISWorldMap:onRightMouseUp(x,y)
        local result=original(self,x,y)
        if result==true then return result end -- A map-symbol tool consumed it.
        local pn = tonumber(self.playerNum)
        if pn == nil then return result end
        local player=getSpecificPlayer(pn)
        if player==nil or player:getVehicle()==nil or not KnoxSettings.enableExperimentalNpcDriving()
            or #KnoxCompanionService.getCompanionIds(player)==0 then return result end
        local context
        if getDebug() or (isClient() and getAccessLevel()=="admin") then
            context=getPlayerContextMenu(pn) -- Preserve native debug entries.
        else context=ISContextMenu.get(pn,x+self:getAbsoluteX(),y+self:getAbsoluteY()) end
        Orders.fill(context,player,math.floor(self.mapAPI:uiToWorldX(x,y))+0.5,
            math.floor(self.mapAPI:uiToWorldY(x,y))+0.5)
        return true
    end
end
return Orders
