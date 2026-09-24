local root=arg[1] or "."
for _,module in ipairs({"ISUI/Maps/ISWorldMap","KS_CompanionService","KS_CompanionVehicles","KS_Settings","KS_Persistence","KS_SurvivorRuntime","KS_SurvivorViewModel"}) do
    package.preload[module]=function() return true end
end
UIFont={Small="small"}
local originalPrerenderCalls=0
ISWorldMap={prerender=function() originalPrerenderCalls=originalPrerenderCalls+1 end,onRightMouseUp=function() return false end}
ISContextMenu={getNew=function() return {} end,get=function() return {} end}
local player={getVehicle=function() return nil end}
getSpecificPlayer=function(pn) return pn==0 and player or nil end
KnoxPersistence={
    ensurePlayerId=function() return "owner" end,
    getSurvivorIds=function() return {"loaded","logical","stale","foreign","dead","dead-cleared","dead-foreign","dead-invalid"} end,
    getSurvivorAffiliation=function(id) if id=="dead-cleared" then return nil end return id=="foreign" and {kind="player",ownerId="other"} or {kind="player",ownerId="owner"} end,
    isSurvivorAlive=function(id) return id~="dead" and id~="dead-cleared" and id~="dead-foreign" and id~="dead-invalid" end,
    getSurvivorIdentity=function(id) return {forename=id,surname="NPC"} end,
    getUnloadedSurvivalState=function(id) return id=="logical" and {virtualX=20,virtualY=30,virtualZ=1,activity="base_life"} or nil end,
    getRecord=function(id) return id=="stale" and "stale-record" or nil end,
    getSurvivorDeathEvidence=function(id)
        if id=="dead" or id=="dead-cleared" then return {ownerKind="player",ownerId="owner",x=60,y=70,z=0,locationSource="logical",corpseState="logical_only"} end
        if id=="dead-foreign" then return {ownerKind="player",ownerId="other",x=61,y=70,z=0} end
        if id=="dead-invalid" then return {ownerKind="player",ownerId="owner",x="bad",y=70,z=0} end
        return nil
    end,
}
KnoxJavaBridge={getTestNpcRecordX=function() return 40 end,getTestNpcRecordY=function() return 50 end,getTestNpcRecordZ=function() return 0 end}
KnoxSurvivorRuntime={getCharacter=function(id) return id=="loaded" and {getX=function() return 10 end,getY=function() return 11 end,getZ=function() return 0 end} or nil end}
local snapshots=0
KnoxSurvivorViewModel={getSurvivor=function(id) snapshots=snapshots+1; return {activity=id.." active",locationLabel=id.." location"} end}
assert(loadfile(root.."/mod/42/media/lua/client/KS_MapOrders.lua"))()
local locations=KnoxMapOrders.ownedLocations(0)
assert(#locations==5 and locations[1].source=="deceased" and locations[2].source=="deceased" and locations[3].source=="loaded" and locations[4].source=="logical" and locations[5].source=="last_known",
    "owned locator returns loaded, virtual and stale coordinates only for alive owned survivors")
assert(locations[1].x==60 and locations[2].id=="dead-cleared" and locations[3].x==10 and locations[4].z==1 and locations[5].y==50,
    "owned locator preserves authoritative coordinates by confidence tier")
local drawn,markers={},{}
local now=1000
getTimestampMs=function() return now end
local scans=0
local originalIds=KnoxPersistence.getSurvivorIds
KnoxPersistence.getSurvivorIds=function() scans=scans+1; return originalIds() end
snapshots=0
local map={playerNum=0,mapAPI={worldToUIX=function(_,x) return x*2 end,worldToUIY=function(_,y) return y*3 end},drawText=function(_,text,x,y) drawn[#drawn+1]={text=text,x=x,y=y} end,drawRect=function(_,x,y,w,h,a,r,g,b) markers[#markers+1]={x=x,y=y,w=w,h=h,a=a,r=r,g=g,b=b} end}
ISWorldMap.prerender(map)
assert(originalPrerenderCalls==1 and #drawn==5 and #markers==5 and drawn[1].text:find("X dead NPC",1,true)
    and drawn[3].text:find("loaded NPC",1,true) and drawn[4].text:find("~ logical NPC",1,true) and drawn[5].text:find("? stale NPC",1,true)
    and markers[1].r~=markers[3].r and markers[3].g~=markers[4].g and markers[4].r~=markers[5].r,
    "world map overlay renders ASCII labels and distinct confidence marker primitives after native prerender")
assert(ISWorldMap.onRightMouseUp({playerNum=0},1,1)==false,
    "owned overlay does not consume existing right-click map behavior")
for i=1,60 do ISWorldMap.prerender(map) end
assert(scans==1 and snapshots==0, "drawing must not rebuild survivor snapshots or scan every frame")
now=1250
ISWorldMap.prerender(map)
assert(scans==2 and snapshots==0, "positions refresh on a bounded real-time interval")
now=10
ISWorldMap.prerender(map)
assert(scans==3, "clock reset invalidates the cache")
print("Owned map locations PASS ownership=true confidence=true render=true right_click=true")
