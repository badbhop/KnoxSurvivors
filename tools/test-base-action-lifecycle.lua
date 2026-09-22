local root=arg[1] or "."
require=function() return true end
dofile(root.."/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller=KnoxAutonomyController
local nativeBusy=false
local actor={getCurrentSquare=function() return {} end,
    getCharacterActions=function() return {isEmpty=function() return not nativeBusy end} end}
local queue={queue={}}
local cleared,checked,queued,finished=0,0,0,0
ISTimedActionQueue={queues={[actor]=queue},clear=function(character)
    assert(character==actor);queue.queue={};nativeBusy=false;cleared=cleared+1
end}
KnoxBaseCorpseHandling={isDragging=function() return false end}
KnoxActivityFeed={speak=function() end}
KnoxBaseStorage={findRequiredTransfer=function() return nil,"requirements_ready" end}
KnoxBaseBarricades={resolveTarget=function() return {} end,
    queueAction=function()
        queued=queued+1;local action={};queue.queue={action};return action,"queued"
    end,
    isComplete=function() checked=checked+1;return true end,
    plankCount=function() return 1 end}
local function controller(state,kind)
    return setmetatable({id="worker",character=actor,state=state,nextThreatScan=100000,
        baseTask={type=kind or "barricade",state="claimed",claimedBy="worker"},
        recoverFromDetached=function() return false end,
        releaseBaseCooking=function() end,releaseSupply=function() end,
        bridge={cancelNpcMove=function() end},
        finishBaseTask=function(self,success,reason)
            finished=finished+1;self.result=success;self.reason=reason;self.baseTask=nil
            self.baseTaskSupplyTransfer=nil
        end,
        finishDecision=function(self) self.state="IDLE" end,
    },Controller)
end

-- Native waitToStart may leave Java empty while Lua still owns the job.
local c=controller("BASE_TASK_ACTION")
c:tick(1)
assert(queued==1 and c.baseTaskActionQueued and #queue.queue==1)
c:tick(2)
assert(checked==0 and finished==0 and c.state=="BASE_TASK_ACTION")
nativeBusy=true;queue.queue={};c:tick(3)
assert(checked==0,"native work also retains ownership")
nativeBusy=false;c:tick(4)
assert(checked==1 and finished==1 and c.result and c.state=="IDLE")

-- Every physical job shares the same wait boundary, including both corpse phases.
for _,kind in ipairs({"barricade","farm_water","farm_harvest","farm_plow","farm_seed",
    "chop_tree","saw_logs","haul_corpse","burn_corpse","repair"}) do
    for _,alreadyQueued in ipairs({false,true}) do
        c=controller("BASE_TASK_ACTION",kind);c.baseTaskActionQueued=alreadyQueued
        queue.queue={{}};local previous=finished;c:tick(10)
        assert(c.state=="BASE_TASK_ACTION" and finished==previous,
            kind.." cannot dispatch or finish over pending Lua work")
    end
end

-- Cupboard transfers cannot immediately send a still-empty-handed worker away.
local supplyItem = {}
local supplySource = { present = true,
    contains = function(self, item) return self.present and item == supplyItem end }
local supplyInventory = { present = false,
    contains = function(self, item) return self.present and item == supplyItem end }
actor.getInventory = function() return supplyInventory end
c=controller("BASE_TASK_SUPPLY_TRANSFER")
c.baseTaskSupplyTransfer={item=supplyItem,source={container=supplySource}}
local resumed=0
c.beginBaseTaskSupplyOrWork=function() resumed=resumed+1 end
queue.queue={{}};c:tick(20);assert(resumed==0 and c.baseTaskSupplyTransfer)
queue.queue={};c:tick(21);assert(resumed==0 and c.baseTaskSupplyTransfer==nil
    and c.reason=="assigned_supply_transfer_not_completed",
    "a completed queue without a real receipt must fail closed")

c=controller("BASE_TASK_SUPPLY_TRANSFER")
c.baseTaskSupplyTransfer={item=supplyItem,source={container=supplySource}}
supplySource.present=false;supplyInventory.present=true
 c.beginBaseTaskSupplyOrWork=function() resumed=resumed+1 end
queue.queue={{}};c:tick(22);assert(resumed==0 and c.baseTaskSupplyTransfer)
queue.queue={};c:tick(23);assert(resumed==1 and c.baseTaskSupplyTransfer==nil,
    "a real cupboard receipt may resume the job")

-- A transient native route failure gets one fresh target/route attempt, while
-- an attached corpse drop remains fail-closed instead of retrying into an
-- infinite drag.
local routeRetries, routeCancels = 0, 0
c=controller("BASE_TASK_MOVE", "barricade")
c.bridge.cancelNpcMove=function() routeCancels=routeCancels+1 end
c.beginBaseTaskWorkMove=function(self)
    routeRetries=routeRetries+1;self.state="BASE_TASK_MOVE";return true
end
assert(c:retryBaseTaskMovement(30, "FailedStuck")
    and routeRetries==1 and routeCancels==1
    and c.baseTaskMoveRetryIssued==true,
    "a failed work route gets one bounded fresh attempt")
assert(not c:retryBaseTaskMovement(31, "FailedStuck") and routeRetries==1,
    "a route failure cannot retry forever")
c=controller("BASE_TASK_MOVE", "haul_corpse")
c.baseTaskCorpsePhase="drop"
assert(not c:retryBaseTaskMovement(40, "FailedStuck"),
    "an attached corpse drop does not restart its route")

-- An armed resident may break a locked door inside its owned base and resume
-- the same claimed task. Corpse drop remains protected from this transition.
local workSquare={}
getCell=function() return {getGridSquare=function() return workSquare end} end
KnoxBaseManager={canDamageStructure=function(_,square) return square==workSquare end}
KnoxSurvivorNeeds={snapshot=function() return {endurance=1} end}
local melee={IsWeapon=function() return true end,isBroken=function() return false end,
    isRanged=function() return false end}
actor.getPrimaryHandItem=function() return melee end
c=controller("BASE_TASK_MOVE","barricade")
c.baseTask.target={x=10,y=10,z=0}
c.activeDecision="base_task_barricade"
local doorStarts=0
c.bridge.beginNpcLockedDoorCombat=function()
    doorStarts=doorStarts+1;return "COMBAT_STARTED"
end
local resumedDoorTask=0
c.beginBaseTaskWorkMove=function(self)
    resumedDoorTask=resumedDoorTask+1;self.state="BASE_TASK_MOVE";return true
end
assert(c:beginBaseTaskLockedDoorBreak(50) and doorStarts==1
    and c.state=="BREAKING_LOCKED_DOOR" and c.entryDetour.baseTask,
    "owned base work must start native locked-door combat")
assert(c:resumeAfterBaseTaskDoorBreak(51) and resumedDoorTask==1
    and c.baseTask~=nil and c.entryDetour==nil,
    "door completion must resume the original task")
c=controller("BASE_TASK_MOVE","haul_corpse")
c.baseTask.target={corpseX=10,corpseY=10,corpseZ=0}
c.baseTaskCorpsePhase="drop"
c.activeDecision="base_task_haul_corpse_drop"
assert(not c:beginBaseTaskLockedDoorBreak(52),
    "a corpse already being dragged never starts door combat")

-- The same queue gap must not fail an eat/drink verification or group support.
for _,state in ipairs({"TIMED_ACTION","GROUP_SUPPORT"}) do
    c=controller(state);queue.queue={{}};c:tick(25)
    assert(c.state==state)
end

-- A threat suspends the claim, but must cancel its old pending native/Lua work.
c=controller("BASE_TASK_ACTION");c.baseTaskActionQueued=true;queue.queue={{}}
local claim=c.baseTask
assert(c:suspendBaseTaskForThreat("test_danger"))
assert(c.baseTask==claim and claim.interruptedReason=="test_danger")
assert(#queue.queue==0 and cleared==1 and not c.baseTaskActionQueued)
-- Explicit cancellation drops the claim and clears waiting work too.
c=controller("BASE_TASK_ACTION");queue.queue={{}}
c:abandonBaseTask("released")
assert(#queue.queue==0 and cleared==2 and c.baseTask==nil and c.result==false)

-- A permanently stuck Lua action is still bounded by the state timeout.
c=controller("BASE_TASK_ACTION");queue.queue={{}};c:tick(100)
local timeout
c.abandonCurrentDecision=function(self,ticks,reason)
    timeout=reason;self:abandonBaseTask(reason);self.state="IDLE"
end
c:tick(1301)
assert(timeout=="state_timeout_BASE_TASK_ACTION" and #queue.queue==0)
print("Base action lifecycle PASS lua_wait=true native_wait=true all_jobs=true supply_handoff=true locked_entry=true needs=true interrupt=true timeout=true")
