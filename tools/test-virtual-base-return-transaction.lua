local root=arg[1] or "."
local originalRequire=require
require=function() return true end
Events=setmetatable({}, {__index=function() return {Add=function() end,Remove=function() end} end})
local now=42
getGameTime=function() return {getWorldAgeHours=function() return now end} end
getCell=function() return {getGridSquare=function() return nil end} end
KnoxPersistence={getBase=function() return {id="base",territory={minX=100,minY=100,z=0}} end,getPopulationState=function() return {} end}
local marked,started,removed=true,true,"REMOVED"
local markCalls,startCalls,rollbackCalls,removeCalls,unregisterCalls=0,0,0,0,0
KnoxUnloadedSurvival={
    markStored=function() markCalls=markCalls+1 return marked,"store" end,
    beginBaseReturn=function() startCalls=startCalls+1 return started,"route" end,
    rollbackBaseReturn=function() rollbackCalls=rollbackCalls+1 return true,"rolled" end,
}
KnoxSettings={enabled=function() return true end}
KnoxSurvivorRuntime={unregister=function() unregisterCalls=unregisterCalls+1 end}
KnoxJavaBridge={removeNpc=function() removeCalls=removeCalls+1 return removed end}
assert(loadfile(root.."/mod/42/media/lua/client/KS_SurvivorAutonomy.lua"))()
require=originalRequire
local autonomy=KnoxSurvivorAutonomy
local function run(label)
    local controller={shutdown=function() return true,"captured" end}
    autonomy.status().controllers[label]=controller
    local ok,reason=autonomy.beginVirtualBaseReturn(label,"base")
    return ok,reason,controller
end

marked,started,removed=false,true,"REMOVED"
markCalls,startCalls,rollbackCalls,removeCalls,unregisterCalls=0,0,0,0,0
local ok,reason,controller=run("mark-fail")
assert(not ok and reason:find("store_failed=",1,true) and startCalls==0 and removeCalls==0
    and unregisterCalls==0 and autonomy.status().controllers["mark-fail"]==controller,
    "mark failure keeps the captured live controller registered and never removes its shell")

marked,started,removed=true,false,"REMOVED"
markCalls,startCalls,rollbackCalls,removeCalls,unregisterCalls=0,0,0,0,0
ok,reason,controller=run("route-fail")
assert(not ok and reason:find("route_failed=",1,true) and rollbackCalls==1 and removeCalls==0
    and unregisterCalls==0 and autonomy.status().controllers["route-fail"]==controller,
    "route failure rolls back the prepared ledger before native removal")

marked,started,removed=true,true,"REMOVE_FAILED"
markCalls,startCalls,rollbackCalls,removeCalls,unregisterCalls=0,0,0,0,0
ok,reason,controller=run("remove-fail")
assert(not ok and reason:find("remove_failed=",1,true) and rollbackCalls==1 and removeCalls==1
    and unregisterCalls==0 and autonomy.status().controllers["remove-fail"]==controller,
    "native removal failure rolls back and leaves controller/runtime ownership live")

marked,started,removed=true,true,"REMOVED"
markCalls,startCalls,rollbackCalls,removeCalls,unregisterCalls=0,0,0,0,0
ok,reason,controller=run("success")
assert(ok and markCalls==1 and startCalls==1 and removeCalls==1 and unregisterCalls==1
    and autonomy.status().controllers.success==nil,
    "successful handoff persists route, removes shell, then unregisters exactly once")

print("Virtual base return transaction PASS store=true route=true remove=true ordering=true")
