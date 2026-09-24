require "ISUI/Maps/ISWorldMap"
require "KS_CompanionService"
require "KS_CompanionVehicles"
require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_SurvivorViewModel"

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

local function displayName(id)
    local identity=KnoxPersistence.getSurvivorIdentity(id) or {}
    local name=(tostring(identity.forename or "").." "..tostring(identity.surname or "")):match("^%s*(.-)%s*$")
    return name~="" and name or "Survivor"
end

local function recordLocation(id)
    local bridge=rawget(_G,"KnoxJavaBridge")
    local record=KnoxPersistence.getRecord~=nil and KnoxPersistence.getRecord(id) or nil
    if bridge==nil or record==nil then return nil end
    local ok,x,y,z=pcall(function()
        return bridge:getTestNpcRecordX(record),bridge:getTestNpcRecordY(record),bridge:getTestNpcRecordZ(record)
    end)
    if not ok or tonumber(x)==nil or tonumber(y)==nil or tonumber(z)==nil then return nil end
    return tonumber(x),tonumber(y),tonumber(z)
end

-- Read-only locator data for player-owned survivors.  It deliberately never
-- materializes, moves or persists a survivor/map symbol.
function Orders.ownedLocations(playerNum, lightweight)
    local player=getSpecificPlayer(playerNum)
    local playerId=player~=nil and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId==nil or KnoxPersistence.getSurvivorIds==nil then return {} end
    local locations={}
    for _,id in ipairs(KnoxPersistence.getSurvivorIds() or {}) do
        local affiliation=KnoxPersistence.getSurvivorAffiliation(id)
        if affiliation~=nil and affiliation.kind=="player" and affiliation.ownerId==playerId
            and KnoxPersistence.isSurvivorAlive(id) then
            local character=KnoxSurvivorRuntime~=nil and KnoxSurvivorRuntime.getCharacter(id) or nil
            local x,y,z,source=nil,nil,nil,nil
            if character~=nil then
                local ok,cx,cy,cz=pcall(function() return character:getX(),character:getY(),character:getZ() end)
                if ok and tonumber(cx)~=nil and tonumber(cy)~=nil and tonumber(cz)~=nil then
                    x,y,z,source=tonumber(cx),tonumber(cy),tonumber(cz),"loaded"
                end
            end
            local state=KnoxPersistence.getUnloadedSurvivalState~=nil
                and KnoxPersistence.getUnloadedSurvivalState(id) or nil
            if source==nil and state~=nil and tonumber(state.virtualX)~=nil
                and tonumber(state.virtualY)~=nil and tonumber(state.virtualZ)~=nil then
                x,y,z,source=tonumber(state.virtualX),tonumber(state.virtualY),tonumber(state.virtualZ),"logical"
            end
            if source==nil then x,y,z=recordLocation(id); if x~=nil then source="last_known" end end
            if source~=nil then
                local snapshot=not lightweight and KnoxSurvivorViewModel~=nil and KnoxSurvivorViewModel.getSurvivor~=nil
                    and KnoxSurvivorViewModel.getSurvivor(id,playerNum) or nil
                locations[#locations+1]={id=id,name=displayName(id),x=x,y=y,z=z,source=source,
                    confidence=source,activity=snapshot~=nil and snapshot.activity or (state~=nil and state.activity or "Unknown"),
                    status=snapshot~=nil and snapshot.locationLabel or source}
            end
        elseif KnoxPersistence.isSurvivorAlive(id)==false then
            local evidence=KnoxPersistence.getSurvivorDeathEvidence~=nil
                and KnoxPersistence.getSurvivorDeathEvidence(id) or nil
            if type(evidence)=="table" and evidence.ownerKind=="player"
                and evidence.ownerId==playerId and tonumber(evidence.x)~=nil
                and tonumber(evidence.y)~=nil and tonumber(evidence.z)~=nil then
                locations[#locations+1]={id=id,name=displayName(id),x=tonumber(evidence.x),y=tonumber(evidence.y),z=tonumber(evidence.z),
                    source="deceased",confidence="deceased",activity="Deceased",corpseState=evidence.corpseState,
                    status="Deceased - "..tostring(evidence.locationSource or "last-known").." location recorded"}
            end
        end
    end
    table.sort(locations,function(a,b) return a.id<b.id end)
    return locations
end

local renderedLocations=setmetatable({}, {__mode="k"})
local function drawOwnedLocations(map)
    local pn=tonumber(map.playerNum)
    if pn==nil or map.mapAPI==nil then return end
    -- The overlay needs positions/names, not inventory/health UI snapshots.
    -- Refresh at most four times a second; project coordinates every frame so
    -- zooming and panning remain smooth. A separate cache isolates split screen.
    local now=getTimestampMs~=nil and getTimestampMs() or nil
    local cached=renderedLocations[map]
    if now==nil or cached==nil or cached.playerNum~=pn or now<cached.at or now-cached.at>=250 then
        cached={playerNum=pn,at=now,locations=Orders.ownedLocations(pn,true)}
        renderedLocations[map]=cached
    end
    for _,location in ipairs(cached.locations) do
        local ok,x,y=pcall(function() return map.mapAPI:worldToUIX(location.x,location.y),map.mapAPI:worldToUIY(location.x,location.y) end)
        if ok and tonumber(x)~=nil and tonumber(y)~=nil then
            local exact=location.source=="loaded"
            local deceased=location.source=="deceased"
            local r,g,b=deceased and 0.85 or (exact and 0.25 or (location.source=="logical" and 0.95 or 0.70)),deceased and 0.25 or (exact and 0.95 or 0.75),deceased and 0.25 or (exact and 0.35 or 0.25)
            local prefix=deceased and "X " or (exact and "" or (location.source=="logical" and "~ " or "? "))
            map:drawRect(math.floor(x)-2,math.floor(y)-2,5,5,0.95,r,g,b)
            map:drawText(prefix..location.name,math.floor(x)+4,math.floor(y)-8,r,g,b,0.95,UIFont.Small)
        end
    end
end
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
    local originalPrerender=ISWorldMap.prerender
    function ISWorldMap:prerender()
        originalPrerender(self)
        drawOwnedLocations(self)
    end
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
