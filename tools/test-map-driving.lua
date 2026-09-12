local root=arg[1] or "."
local w=dofile(root.."/tools/vehicle-test-world.lua")
dofile(root.."/mod/42/media/lua/client/KS_VehicleNavigation.lua")
local vehicles=dofile(root.."/mod/42/media/lua/client/KS_CompanionVehicles.lua")
local lines={}
KnoxActivityFeed={speak=function(_,line) lines[#lines+1]=line end}
w.character.getCurrentSquare=function() return w.vehicle:getSquare() end
KnoxSurvivorRuntime.getCharacter=function(id) return id=="driver" and w.character or nil end
local player={getVehicle=function() return w.vehicle end,getCurrentSquare=function() return w.vehicle:getSquare() end,
    isDead=function() return false end}
KnoxPersistence={ensurePlayerId=function() return "owner" end,getCompanionIds=function() return {"driver"} end,
    getSurvivorIdentity=function() return {forename="Alex",surname="Reed"} end}
dofile(root.."/mod/42/media/lua/client/KS_CompanionService.lua")
local function menu()
    local m={options={}}
    function m:addOption(label,target,fn,...)
        local option={label=label,target=target,fn=fn,args={...}}
        self.options[#self.options+1]=option;return option
    end
    function m:addSubMenu(option,child) option.child=child end
    return m
end
local context=menu();local clears,originalCalls=0,0
ISContextMenu={get=function() context=menu();clears=clears+1;return context end,getNew=function() return menu() end}
getPlayerContextMenu=function() return context end
local debugging,consumed=false,false
getDebug=function() return debugging end
isClient=function() return false end
getSpecificPlayer=function() return player end
ISWorldMap={onRightMouseUp=function() originalCalls=originalCalls+1;return consumed end}
local map={playerNum=0,getAbsoluteX=function() return 100 end,getAbsoluteY=function() return 200 end,
    mapAPI={uiToWorldX=function() return 0 end,uiToWorldY=function() return 30 end}}
setmetatable(map,{__index=ISWorldMap})
local orders=dofile(root.."/mod/42/media/lua/client/KS_MapOrders.lua")
assert(map:onRightMouseUp(20,20) and originalCalls==1 and clears==1)
local choice=context.options[1].child.options[1]
assert(choice.label=="Alex Reed" and not choice.notAvailable)
choice.fn(choice.target,unpack(choice.args))
local status=assert(vehicles.driverStatus(w.character))
assert(status.destination.x==0.5 and status.destination.y==30.5,
    "map coordinates reach the actual native driving request")
w.seatDriver();vehicles.tick()
map:onRightMouseUp(21,21)
local stop=context.options[2]
assert(stop.label=="Stop Driving")
stop.fn(stop.target,unpack(stop.args))
assert(vehicles.driverStatus(w.character)==nil and w.controls.brake)
-- Native map annotation tools and debug context entries retain ownership.
consumed=true
local before=clears
map:onRightMouseUp(22,22);assert(clears==before)
consumed=false;debugging=true
context=menu();context:addOption("Native debug entry")
map:onRightMouseUp(23,23)
assert(clears==before and context.options[1].label=="Native debug entry")
w.vehicle.driver=player
context=menu();orders.fill(context,player,0,30)
assert(context.options[1].child.options[1].notAvailable, "a player's driver seat is protected in the menu")
local ok,reason=KnoxCompanionService.drivePlayerVehicleTo(player,"driver",0,30)
assert(not ok and reason=="player_must_vacate_driver_seat")
w.vehicle.driver=w.character
ok,reason=KnoxCompanionService.drivePlayerVehicleTo(player,"stranger",0,30)
assert(not ok and reason=="not_companion", "UI callbacks cannot commandeer someone else's survivor")
orders.drive(player,"driver",0,1000)
assert(lines[#lines]:find("closer destination",1,true))
print("Map driving PASS map_coordinates=true native_request=true stop=true symbol_tools=true debug_menu=true authorization=true feedback=true")
