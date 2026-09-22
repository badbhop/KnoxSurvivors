local root=arg[1] or "."
require=function() return true end
local function list(values)
    return {size=function() return #values end,get=function(_,i) return values[i+1] end,isEmpty=function() return #values==0 end}
end
local function container(values)
    local c={values=values or {},powered=true}
    function c:getItems() return list(self.values) end
    function c:contains(item) for _,v in ipairs(self.values) do if v==item then return true end end return false end
    function c:isPowered() return self.powered end
    return c
end
local function square(x,y,z)
    local s={x=x,y=y or 0,z=z or 0,objects={}}
    function s:getX() return self.x end;function s:getY() return self.y end;function s:getZ() return self.z end
    function s:getObjects() return list(self.objects) end
    function s:isSomethingTo() return self.blocked==true end
    return s
end
local current=square(0)
local kitchen,pantry=square(4),square(9)
local carried,stored,heated=container(),container(),container()
local microwave={kind="IsoStove",data={},on=false,microwave=true,broken=false,timer=0,temperature=0}
function microwave:getSquare() return kitchen end
function microwave:getObjectIndex() return 0 end
function microwave:getContainer() return heated end
function microwave:getModData() return self.data end
function microwave:isMicrowave() return self.microwave end
function microwave:isBroken() return self.broken end
function microwave:Activated() return self.on end
function microwave:PlayToggleSound() end
function microwave:Toggle() self.on=not self.on end
function microwave:setTimer(seconds) self.timer=seconds end
function microwave:setMaxTemperature(degrees) self.temperature=degrees end
kitchen.objects={microwave}
local food={cooked=false,rotten=false,poison=false,metal=0,minutes=0,replacements=nil,burnt=false,id=7}
function food:IsFood() return true end
function food:isCookable() return true end
function food:isCooked() return self.cooked end
function food:isBurnt() return self.burnt end
function food:isRotten() return self.rotten end
function food:isPoison() return self.poison end
function food:getPoisonPower() return 0 end
function food:getHungerChange() return -0.3 end
function food:getMetalValue() return self.metal end
function food:isBadInMicrowave() return true end -- native mood penalty is not a health risk
function food:getReplaceOnCooked() return self.replacements end
function food:getOnCooked() return self.callback end
function food:getMinutesToCook() return 10 end
function food:getMinutesToBurn() return 30 end
function food:getCookingTime() return self.minutes end
function food:getID() return self.id end
stored.values={food}
local queue={queue={}}
function queue:indexOf(a) for i,v in ipairs(self.queue) do if a==v then return i end end return -1 end
function queue:removeFromQueue(a) local i=self:indexOf(a);if i~=-1 then table.remove(self.queue,i) end;self.current=self.queue[1] end
ISTimedActionQueue={getTimedActionQueue=function() return queue end,
    add=function(a) queue.queue[#queue.queue+1]=a;queue.current=queue.queue[1] end,
    clear=function() queue.queue={};queue.current=nil end}
ISToggleStoveAction={}
function ISToggleStoveAction:derive(name) local t={Type=name};t.__index=t;setmetatable(t,{__index=self});return t end
function ISToggleStoveAction:new(character,object) return setmetatable({character=character,object=object},self) end
function ISToggleStoveAction:complete() self.object:Toggle();return true end
local actor={getCurrentSquare=function() return current end,getInventory=function() return carried end,
    getCharacterActions=function() return {isEmpty=function() return #queue.queue==0 end} end,faceThisObject=function() end}
AdjacentFreeTileFinder={Find=function(s) return square(s:getX()-1,s:getY(),s:getZ()) end}
instanceof=function(item,kind) return item~=nil and item.kind==kind end
local now=0
getGameTime=function() return {getWorldAgeHours=function() return now end} end
getCell=function() return {getGridSquare=function(_,x,y,z) if x==4 and y==0 and z==0 then return kitchen end end} end
local base={id="home",territory={minX=0,minY=0,maxX=10,maxY=0},zones={}}
local available=true
KnoxBaseManager={containsSquare=function(_,s) return s:getX()>=0 and s:getX()<=10 end}
KnoxBaseStorage={policies=function() return {{key="food",x=9,y=0,z=0}} end,
    resolvePolicy=function() return {container=stored,square=pantry} end,
    findDepositTrip=function() return available and {container=stored,square=pantry} or nil end}
KnoxSurvivorNeeds={isSafeFood=function(item) return item==food and food.cooked and not food.rotten and not food.burnt end}
KnoxInventoryActions={queueTransfer=function(_,item,source,destination)
    assert(source:contains(item))
    local action={item=item,source=source,destination=destination,forceCancel=function() end}
    ISTimedActionQueue.add(action);return action,"queued"
end}
local destination
local bridge={moveNpc=function(_,id,target) destination=target;return "MOVE_STARTED" end,
    tickNpc=function() current=destination;return "Succeeded" end,cancelNpcMove=function() destination=nil end}
local enabled=true
KnoxSettings={baseCookingEnabled=function() return enabled end}
local c=dofile(root.."/mod/42/media/lua/client/KS_BaseCooking.lua")
assert(c.canCook(food),"ordinary raw food remains useful even with a native microwave mood penalty")
for _,field in ipairs({"poison","rotten","burnt","cooked"}) do food[field]=true;assert(not c.canCook(food),field);food[field]=false end
food.metal=1;assert(not c.canCook(food));food.metal=0
food.replacements=list({"Base.Pot"});assert(not c.canCook(food));food.replacements=nil
food.callback="RecipeCode.onCooked";assert(not c.canCook(food));food.callback=nil
local target=assert(c.findTask(base,actor))
assert(c.resolveTaskSquare(base,target,actor):getX()==3)
microwave.broken=true;assert(c.findTask(base,actor)==nil,"broken appliances unavailable");microwave.broken=false
heated.powered=false;assert(c.findTask(base,actor)==nil);heated.powered=true
microwave.on=true;assert(c.findTask(base,actor)==nil,"player cooking is not commandeered");microwave.on=false
local plan=assert(c.begin(base,target,actor,"cook"))
assert(c.begin(base,target,actor,"second")==nil,"one cook owns an appliance and ingredient")
local ticks=0
local function step() ticks=ticks+1;return c.step(plan,actor,base,bridge,ticks) end
local function finishAction(perform)
    local a=assert(queue.current)
    if a.source~=nil then
        if perform~=false then
            for i,v in ipairs(a.source.values) do if v==a.item then table.remove(a.source.values,i);break end end
            a.destination.values[#a.destination.values+1]=a.item
        end
    else
        if perform~=false then assert(a:complete()) end
    end
    queue:removeFromQueue(a)
end
local function untilPhase(phase)
    for i=1,25 do
        if plan.phase==phase then return end
        local status,reason=step();assert(status=="working" or (status=="done" and plan.phase==phase),tostring(plan.phase)..":"..tostring(status)..":"..tostring(reason))
        if queue.current~=nil then finishAction() end
    end
    error("did not reach "..phase..", got "..tostring(plan.phase))
end
untilPhase("heat")
assert(heated:contains(food) and not food.cooked and not carried:contains(food),"real ingredient moves; no fabricated cooking")
step();if queue.current~=nil then finishAction() end
assert(microwave.on and microwave.timer==600 and microwave.temperature==100,
    "microwave cooks get a full ten-minute run instead of two-minute re-activation loops")
-- A full native timer cycle can end without a cooked meal; it is not success.
microwave.on=false;step();finishAction();assert(microwave.on and not food.cooked)
food.cooked=true
untilPhase("done")
assert(step()=="done" and stored:contains(food) and not microwave.on and microwave.data.KnoxCooking==nil)
c.cancel(plan,actor)

-- Interrupted heat retains exactly the actual item and can resume after reload.
food.cooked=false;current=square(0);plan=assert(c.begin(base,target,actor,"cook"));untilPhase("heat")
step();if queue.current~=nil then finishAction() end
c.cancel(plan,actor)
assert(not microwave.on and heated:contains(food) and microwave.data.KnoxCooking.itemId=="7")
c=dofile(root.."/mod/42/media/lua/client/KS_BaseCooking.lua")
target=assert(c.findTask(base,actor));plan=assert(c.begin(base,target,actor,"replacement"))
assert(plan.recovered and plan.item==food)
step();finishAction();current=square(30)
c.cancel(plan,actor)
assert(microwave.on and microwave.timer==1,"a displaced actor never toggles a remote appliance; the running microwave winds down instead")
microwave.on=false;current=square(3)
plan=assert(c.begin(base,target,actor,"cook"));step();finishAction()
heated.values[#heated.values+1]={metal=1}
assert(step()=="failed","player inserting another item invalidates exclusive contents")
c.cancel(plan,actor);assert(not microwave.on,"stop owned heat before yielding changed contents")
heated.values={food}
plan=assert(c.begin(base,target,actor,"cook"));food.cooked=true;plan.personal=true
untilPhase("deposit")
assert(step()=="done" and carried:contains(food) and not stored:contains(food),"hungry cook keeps the real meal for native eating")
c.cancel(plan,actor)

-- Failed transfers and power/settings/area changes never become success.
food.cooked=false;stored.values={food};carried.values={};heated.values={};microwave.data={};current=square(8)
plan=assert(c.begin(base,target,actor,"cook"));step();finishAction(false)
assert(step()=="failed");c.cancel(plan,actor)
plan=assert(c.begin(base,target,actor,"cook"));untilPhase("heat")
enabled=false;assert(step()=="failed");c.cancel(plan,actor);enabled=true
heated.values={};stored.values={food};microwave.data={}
base.zones.kitchen={id="kitchen",type="cooking",enabled=true,x1=5,x2=4,y1=1,y2=0,z=0}
KnoxBaseManager.containsSquare=function() return false end
target=assert(c.findTask(base,actor));assert(target.zoneId=="kitchen","explicit cooking areas work outside home")
plan=assert(c.begin(base,target,actor,"cook"));base.zones.kitchen.enabled=false
assert(step()=="failed");c.cancel(plan,actor)
assert(c.findTask(base,actor)==nil,"disabled explicit kitchens do not fall back to another appliance")
print("Base cooking PASS native_heat=true transfers=true storage=true recovery=true ownership=true interruption=true outside_area=true")

-- Controller keeps a claimed duty while another immediate need interrupts food
-- preparation. A persistent hunger alone must not repeatedly cancel cooking.
dofile(root.."/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
base.zones.kitchen.enabled=true;current=square(8)
local need="find_food"
KnoxSurvivorNeeds.decide=function() return {kind=need} end
local controller=setmetatable({id="cook",base=base,character=actor,bridge=bridge,
    baseTask={id="guard",type="guard"},releaseSupply=function() end,
    hasNeedEscort=function() return false end,
    finishDecision=function(self) self:releaseBaseCooking();self.state="IDLE" end},KnoxAutonomyController)
KnoxBaseCorpseHandling={isDragging=function() return false end}
KnoxBaseManager.containsSquare=function() return true end
assert(controller:beginBaseCooking(1000,nil,true))
controller:updateBaseCooking(1001)
assert(controller.pendingCooking~=nil and controller.baseTask.id=="guard")
need="drink";controller:updateBaseCooking(1200)
assert(controller.pendingCooking==nil and controller.baseTask.id=="guard" and controller.state=="IDLE")
need="roam";controller.baseTask=nil
assert(controller:beginBaseCooking(2000,target,false))
controller:updateBaseCooking(2001)
controller:suspendBaseTaskForThreat("combat_interrupt")
assert(controller.pendingCooking==nil,"even personal cooking with no board task yields to combat")
print("Cooking controller PASS hunger_response=true needs_priority=true persistent_duty=true danger_release=true")

-- Clearing assigned storage before collection revokes that source immediately.
controller:releaseBaseCooking();current=square(8);stored.values={food};carried.values={};heated.values={};microwave.data={};food.cooked=false
plan=assert(c.begin(base,target,actor,"cook"))
local policies=KnoxBaseStorage.policies
KnoxBaseStorage.policies=function() return {} end
local revoked,why=step()
assert(revoked=="failed" and why=="cooking_source_no_longer_assigned" and stored:contains(food))
c.cancel(plan,actor);KnoxBaseStorage.policies=policies
-- A player taking a previously interrupted meal must not permanently lock the empty appliance.
microwave.data.KnoxCooking={baseId=base.id,itemId="old-meal"};microwave.on=false
assert(c.findTask(base,actor)~=nil and microwave.data.KnoxCooking==nil)
plan=assert(c.begin(base,target,actor,"cook"));untilPhase("heat")
heated.powered=false;assert(step()=="failed");c.cancel(plan,actor);heated.powered=true
assert(heated:contains(food),"power interruption preserves the actual ingredient")
print("Kitchen recovery PASS revoked_storage=true player_removed_meal=true power_loss=true")

-- A Lua action can be queued before the native character action list starts.
plan=assert(c.begin(base,target,actor,"cook"));current=square(3);microwave.on=false
local characterActions=actor.getCharacterActions
actor.getCharacterActions=function() return {isEmpty=function() return true end} end
step();assert(#queue.queue==1)
step();assert(#queue.queue==1,"pending native heat action is not enqueued twice")
finishAction();actor.getCharacterActions=characterActions
c.cancel(plan,actor)
print("Kitchen action ownership PASS deferred_native_queue=true")

-- The finished meal may satisfy the worker before a pantry delivery. Count
-- verified production as successful rather than reopening an impossible job.
food.cooked=true;carried.values={food};heated.values={}
controller.pendingCooking={item=food,object=microwave,personal=false,phase="deposit"}
controller.baseTask={id="kitchen-job",type="cook"}
local completed
controller.finishBaseTask=function(self,success,reason) completed=success;self.baseTask=nil;self:releaseBaseCooking() end
need="eat";controller:updateBaseCooking(3000)
assert(completed==true and controller.pendingCooking==nil and carried:contains(food))
print("Cooked meal needs handoff PASS verified_production=true retained_food=true")
