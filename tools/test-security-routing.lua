local root=arg[1] or "."
require=function() return true end
local data={}
ModData={getOrCreate=function(key) data[key]=data[key] or {};return data[key] end}
Events={OnSave={Add=function() end},OnPostSave={Add=function() end},OnGameStart={Add=function() end}}
getGameTime=function() return {getWorldAgeHours=function() return 48 end} end
getNumActivePlayers=function() return 0 end
KnoxSettings={allowSurvivorFleeing=function() return false end}
dofile(root.."/mod/42/media/lua/client/KS_OrderCatalog.lua")
dofile(root.."/mod/42/media/lua/client/KS_CompanionPatrol.lua")
dofile(root.."/mod/42/media/lua/client/KS_Persistence.lua")
local p=KnoxPersistence
assert(p.setRecord("watch","record-watch"))
assert(p.setPlayerCompanion("watch","owner","hold",48))
assert(p.setCompanionDirective("watch","owner",{kind="patrol_area",minX=0,minY=0,maxX=10,maxY=8,z=0},48))
local duty=p.getSurvivorDuty("watch")
local directive=duty.directive
local revision=duty.revision
assert(not p.advanceCompanionPatrol("watch","intruder",directive,0,true))
assert(not p.advanceCompanionPatrol("watch","owner",{},0,true))
assert(not p.advanceCompanionPatrol("watch","owner",nil,0,true))

local blocked,unloaded={},false
local squares={}
local function square(x,y,z)
    local key=x..":"..y..":"..(z or 0)
    if squares[key]==nil then
        local s={x=x,y=y,z=z or 0,key=key}
        function s:getX() return self.x end;function s:getY() return self.y end;function s:getZ() return self.z end
        function s:canStand() return not blocked[self.key] end
        squares[key]=s
    end
    return squares[key]
end
local cell={getGridSquare=function(_,x,y,z) return not unloaded and square(x,y,z) or nil end}
getCell=function() return cell end
local current=square(5,4)
local actor={getCurrentSquare=function() return current end,
    getCharacterActions=function() return {isEmpty=function() return true end} end}
local moves,cancels,speeches=0,0,0
local destination,moveResult,tickResult=nil,"MOVE_STARTED","Succeeded"
local wrongArrival=false
local bridge={
    moveNpcWithinArea=function(_,id,target,x1,y1,x2,y2,z)
        assert(id=="watch" and target:getZ()==z and target:getX()>=x1 and target:getX()<=x2
            and target:getY()>=y1 and target:getY()<=y2,"real area passed through the native bridge")
        moves=moves+1;destination=target;return moveResult
    end,
    cancelNpcMove=function() cancels=cancels+1 end,
    tickNpc=function()
        if tickResult=="Succeeded" and not wrongArrival then current=destination end
        return tickResult
    end,
}
local need="roam"
KnoxSurvivorNeeds={decide=function() return {kind=need} end}
KnoxActivityFeed={speak=function() speeches=speeches+1 end}
KnoxBaseCorpseHandling={isDragging=function() return false end}
dofile(root.."/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local c=setmetatable({id="watch",character=actor,bridge=bridge,companionOwnerId="owner",companionOrder="hold",
    companionDirective=directive,nextThink=0,nextThreatScan=math.huge,state="IDLE",counts={failures=0},
    resetMovementRecovery=function() end,releaseSupply=function() end,
    finishDecision=function(self,ticks) self.state="IDLE";self.nextThink=ticks end},KnoxAutonomyController)
local seen={}
for i=0,3 do
    assert(c:beginCompanionPatrolDirective(i*300,directive))
    assert(c.state=="MOVING_TO_COMPANION_PATROL")
    seen[KnoxCompanionPatrol.squareKey(destination)]=true
    c:tick(i*300+1)
    assert(c.state=="COMPANION_PATROL_WAIT" and c.companionDirective==directive)
end
local n=0;for _ in pairs(seen) do n=n+1 end
assert(n==4 and directive.patrolLaps==1,"four physical arrivals advance a persistent circuit")
assert(p.getSurvivorDuty("watch").revision==revision,"progress never reissues an order")
local restored=p.getSurvivorDuty("watch").directive
assert(restored.patrolLaps==1 and restored.patrolStep==0)

-- A blocked waypoint uses a nearby standing tile inside the selected area.
local point=KnoxCompanionPatrol.waypointForStep(directive,c.id,0)
blocked[point.x..":"..point.y..":"..point.z]=true
current=square(5,4)
assert(c:beginCompanionPatrolDirective(1300,directive))
assert(destination:canStand() and not (destination:getX()==point.x and destination:getY()==point.y))

-- Actual path failure advances away from that stop, but never deletes Guard or Patrol.
tickResult="FailedDutyAreaRoute"
for i=1,5 do
    c:tick(1400+i*2500)
    assert(c.state=="COMPANION_DUTY_WAIT" and p.getSurvivorDuty("watch").directive==directive)
    local untilTick=c.securityRetryAt
    local before=moves
    c:updateSecurityRouteWait(untilTick-1,false)
    assert(moves==before,"blocked routes do not spam the native pathfinder")
    assert(c:beginCompanionPatrolDirective(untilTick,directive))
end
assert(directive.patrolLaps==1,"failed/skipped stops cannot fabricate a completed lap")
need="drink"
c:deferSecurityRoute(16000,"blocked",false)
c:updateSecurityRouteWait(16001,false)
assert(c.state=="IDLE" and c.companionDirective==directive,"waiting on a route yields to real needs")
need="roam";tickResult="Succeeded"
c.securityRetryAt=0
assert(c:beginCompanionPatrolDirective(17000,directive));wrongArrival=true;current=square(20,20)
c:tick(17001)
assert(c.state=="COMPANION_DUTY_WAIT","engine success outside the area is not a patrol arrival")
wrongArrival=false

-- A new command invalidates old progress updates even if it repeats the same area.
assert(p.setCompanionDirective("watch","owner",{kind="patrol_area",minX=0,minY=0,maxX=10,maxY=8,z=0},49))
assert(not p.advanceCompanionPatrol("watch","owner",directive,0,true))
local replacement=p.getSurvivorDuty("watch").directive
assert(replacement.patrolStep==nil)

-- Base guards and patrols use the same route owner and keep their task claim.
c.companionDirective,c.companionOrder=nil,nil
local task={id="base-patrol",type="patrol",state="claimed",claimedBy="watch",
    target={x1=0,y1=0,x2=10,y2=8,z=0,zoneId="yard"}}
c.base={id="home",zones={yard={enabled=true}}};c.baseId="home";c.baseTask=task
current=square(5,4);unloaded=true
assert(c:beginBaseTaskWorkMove(18000) and c.state=="BASE_SECURITY_WAIT" and c.baseTask==task)
need="eat";c:updateSecurityRouteWait(18001,true)
assert(c.state=="IDLE" and c.baseTask==task and task.claimedBy==c.id)
need="roam";unloaded=false;c.securityRetryAt=0
assert(c:beginBaseTaskWorkMove(20000) and c.state=="BASE_TASK_MOVE")
c:tick(20001)
assert(c.state=="BASE_TASK_PATROL_WAIT" and c.baseTask==task and task.patrolStopsCompleted==1)
moveResult="MOVE_FAILED BLOCKED"
assert(c:beginBaseTaskWorkMove(20300) and c.state=="BASE_SECURITY_WAIT" and task.state=="claimed")
local completed=0
c.finishBaseTask=function(self) completed=completed+1;self.baseTask=nil end
c.base.zones.yard.enabled=false
c:updateSecurityRouteWait(20400,true)
assert(c.state=="IDLE" and c.baseTask==nil and completed==1,"released areas still cancel a permanent duty")

-- Guard retries also remain orders; a player releases them explicitly.
assert(p.setCompanionDirective("watch","owner",{kind="guard",minX=2,minY=2,z=0},50))
c.companionDirective=p.getSurvivorDuty("watch").directive;c.companionOrder="hold"
local guard=c.companionDirective;current=square(8,8)
for i=1,4 do
    assert(c:beginCompanionPointDirective(21000+i*2500,guard))
    assert(c.state=="COMPANION_DUTY_WAIT" and c.companionDirective==guard)
end
assert(p.updateCompanionOrder("watch","owner","follow",51))
assert(p.getSurvivorDuty("watch").directive==nil,"Follow explicitly releases the watch")
assert(KnoxCompanionPatrol.move({},"watch",square(2,2),guard):find("REQUIRES_UPDATED_AGENT",1,true),
    "an unmatched old agent cannot silently ignore patrol bounds")
print("Security routing PASS persistent_order=true native_bounds=true actual_arrivals=true obstacle_retry=true needs=true claim=true release=true")

local small={minX=0,minY=0,maxX=1,maxY=0,z=0}
local nextSquare=KnoxCompanionPatrol.resolveWaypoint(small,"watch",0,cell,square(0,0),{},30000,false)
assert(nextSquare~=nil and nextSquare:getX()==1,"two-tile patrol areas can still move between distinct tiles")
local progress={target={x1=0,y1=0,x2=10,y2=8,z=0},patrolStep=0}
assert(not KnoxCompanionPatrol.recordTaskArrival(progress))
progress.patrolStep=2
assert(not KnoxCompanionPatrol.recordTaskArrival(progress))
progress.patrolStep=3
assert(not KnoxCompanionPatrol.recordTaskArrival(progress))
progress.patrolStep=0
assert(not KnoxCompanionPatrol.recordTaskArrival(progress),"revisiting a reached stop does not hide an unvisited one")
progress.patrolStep=1
assert(KnoxCompanionPatrol.recordTaskArrival(progress),"a lap completes after all distinct stops are physically visited")
print("Patrol progress PASS small_areas=true unique_arrivals=true")
