local root = arg[1] or "."
require = function() return true end
local function square(x, y)
    return {getX=function() return x end, getY=function() return y end, getZ=function() return 0 end}
end
local current, post = square(0,0), square(0,0)
local need = "roam"
local body = {getCurrentSquare=function() return current end,
    getCharacterActions=function() return {isEmpty=function() return true end} end}
getCell = function() return {getZombieList=function() return {size=function() return 0 end} end} end
getGameTime = function() return {getWorldAgeHours=function() return 24 end} end
getNumActivePlayers = function() return 0 end
KnoxSettings = {}
KnoxSurvivorNeeds = {decide=function() return {kind=need} end}
KnoxActivityFeed = {speak=function() end}
KnoxBaseCorpseHandling = {isDragging=function() return false end}
KnoxBaseJobs = {workDuration=function() return 240 end, resolveTaskSquare=function() return post end}
KnoxCompanionPatrol = dofile(root .. "/mod/42/media/lua/client/KS_CompanionPatrol.lua")
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local completions, moved = 0, 0
local guard = setmetatable({id="guard", character=body, state="BASE_TASK_WORK", observedState="BASE_TASK_WORK",
    stateStartedAt=0, baseTaskStartedAt=0, nextThink=0, nextThreatScan=10000,
    base={zones={post={enabled=true}}}, baseTask={id="watch", type="guard", state="claimed", claimedBy="guard",
        target={autoZoneId="post",x1=0,y1=0,x2=0,y2=0,z=0}},
    bridge={cancelNpcMove=function() end}, releaseSupply=function() end,
    finishBaseTask=function(self) completions=completions+1; self.baseTask=nil end,
    finishDecision=function(self) self.state="IDLE" end,
    beginBaseTaskWorkMove=function(self) moved=moved+1; self.state="BASE_TASK_MOVE"; return true end,
}, KnoxAutonomyController)
guard:tick(300)
assert(completions==0 and guard.state=="BASE_TASK_WORK", "guard duty must not expire after four seconds")
guard:tick(2000)
assert(completions==0 and guard.state=="BASE_TASK_WORK", "guard is exempt from finite job timeout")
local claimed = guard.baseTask
need="drink"
guard:tick(2090)
assert(guard.state=="IDLE" and guard.baseTask==claimed and claimed.claimedBy=="guard",
    "needs temporarily interrupt guard duty without losing the post")
need="roam"
guard.state="BASE_TASK_WORK"
current=square(4,0)
guard:tick(2180)
assert(moved==1 and guard.state=="BASE_TASK_MOVE", "a displaced guard returns to the actual post")
current=post
guard.state="BASE_TASK_WORK"
guard.base.zones.post.enabled=false
guard:tick(2270)
assert(guard.baseTask==nil and guard.state=="IDLE", "disabling a guard area releases its controller")
print("Base security duty PASS persistent=true needs=true displacement=true release=true")

local patrolTask = {id="patrol",type="patrol",state="claimed",claimedBy="guard",
    target={x1=0,y1=0,x2=10,y2=10,z=0},patrolStep=3,patrolStopsCompleted=3}
guard.baseTask,guard.state=patrolTask,"BASE_TASK_MOVE"
guard.resetMovementRecovery=function() end
guard.bridge.tickNpc=function() return "Succeeded" end
guard.observedState,guard.stateStartedAt="BASE_TASK_MOVE",2300
local before=completions
guard:tick(2301)
assert(guard.baseTask==patrolTask and patrolTask.patrolLaps==1 and completions==before,
    "finishing one patrol circuit retains the duty for another lap")
assert(guard.state=="BASE_TASK_PATROL_WAIT")
guard:tick(2481)
assert(guard.state=="BASE_TASK_MOVE" and moved==2, "patrol resumes walking after its observation pause")
need="eat"
guard.state="BASE_TASK_PATROL_WAIT"
guard:tick(2571)
assert(guard.state=="IDLE" and guard.baseTask==patrolTask, "patrol retains its claim while handling needs")
print("Repeating patrol duty PASS laps=true pause=true needs=true")

patrolTask.state,patrolTask.claimedBy="cancelled",nil
guard.state="BASE_TASK_MOVE"
guard:tick(2572)
assert(guard.baseTask==nil and guard.state=="IDLE", "removing a security area cancels an in-flight patrol immediately")

-- Companion post orders must pass through real needs handling too.
local companion=setmetatable({id="companion",character=body,state="COMPANION_HOLD",
    observedState="COMPANION_HOLD",stateStartedAt=3000,nextThink=3000,nextThreatScan=10000,
    companionOrder="hold",bridge={cancelNpcMove=function() end}},KnoxAutonomyController)
need="roam"
companion:tick(3000)
assert(companion.state=="COMPANION_HOLD" and companion.companionOrder=="hold")
need="eat"
companion:tick(3090)
assert(companion.state=="IDLE" and companion.nextThink==3090 and companion.companionOrder=="hold",
    "holding survivors must handle carried needs without deleting their order")
local directive={kind="guard",target={x=0,y=0,z=0}}
companion.state,companion.companionDirective="COMPANION_GUARD",directive
need="drink"
companion:tick(3180)
assert(companion.state=="IDLE" and companion.companionDirective==directive,
    "guard needs yield and retain the destination")
local postChecks=0
companion.state="COMPANION_GUARD"
companion.beginCompanionPointDirective=function(self,ticks,order)
    assert(order==directive);postChecks=postChecks+1;return true
end
need="roam"
companion:tick(3270)
assert(postChecks==1, "a resting guard rechecks its actual post after displacement")
print("Companion security needs PASS persistent_order=true needs=true post_recovery=true")
