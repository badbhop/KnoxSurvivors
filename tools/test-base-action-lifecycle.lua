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
KnoxBaseAnimalCare={queueAction=function()
    queued=queued+1;local action={};queue.queue={action};return action,"queued"
end,isComplete=function() checked=checked+1;return true end}
local function controller(state,kind)
    return setmetatable({id="worker",character=actor,state=state,nextThreatScan=100000,
        baseTask={type=kind or "animal_water",state="claimed",claimedBy="worker"},
        baseTaskAnimalTarget={},baseTaskAnimalBefore={},
        recoverFromDetached=function() return false end,
        releaseBaseCooking=function() end,releaseSupply=function() end,
        bridge={cancelNpcMove=function() end},
        finishBaseTask=function(self,success,reason)
            finished=finished+1;self.result=success;self.reason=reason;self.baseTask=nil
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
    "chop_tree","saw_logs","haul_corpse","animal_water","animal_feed","repair","construct_defense"}) do
    for _,alreadyQueued in ipairs({false,true}) do
        c=controller("BASE_TASK_ACTION",kind);c.baseTaskActionQueued=alreadyQueued
        queue.queue={{}};local previous=finished;c:tick(10)
        assert(c.state=="BASE_TASK_ACTION" and finished==previous,
            kind.." cannot dispatch or finish over pending Lua work")
    end
end

-- Cupboard transfers cannot immediately send a still-empty-handed worker away.
c=controller("BASE_TASK_SUPPLY_TRANSFER");c.baseTaskSupplyTransfer={}
local resumed=0
c.beginBaseTaskSupplyOrWork=function() resumed=resumed+1 end
queue.queue={{}};c:tick(20);assert(resumed==0 and c.baseTaskSupplyTransfer)
queue.queue={};c:tick(21);assert(resumed==1 and c.baseTaskSupplyTransfer==nil)

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
print("Base action lifecycle PASS lua_wait=true native_wait=true all_jobs=true supply_handoff=true needs=true interrupt=true timeout=true")
