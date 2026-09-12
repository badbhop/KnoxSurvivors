local root=arg[1] or "."
require=function() return true end
local function list(t) return {size=function() return #t end,get=function(_,i) return t[i+1] end} end
local function inventory(values)
    local c={values=values or {}}
    function c:getItems() return list(self.values) end
    function c:contains(item) for _,v in ipairs(self.values) do if v==item then return true end end return false end
    return c
end
local function square(x,z)
    return {getX=function() return x end,getY=function() return 0 end,getZ=function() return z or 0 end,
        isSomethingTo=function(self) return self.blocked==true end}
end
local current=square(0)
local storeSquare=square(4)
local dark,illiterate,need=false,false,"roam"
local queue={queue={}}
function queue:indexOf(action) for i,a in ipairs(self.queue) do if a==action then return i end end return -1 end
function queue:removeFromQueue(action) local i=self:indexOf(action);if i~=-1 then table.remove(self.queue,i) end; self.current=self.queue[1] end
local carried=inventory({})
local actor={nativeReads=0,getInventory=function() return carried end,getCurrentSquare=function() return current end,
    getVehicle=function() return nil end,tooDarkToRead=function() return dark end,
    hasTrait=function() return illiterate end,getAlreadyReadPages=function() return 0 end,
    getPerkLevel=function() return 0 end,isLiteratureRead=function() return false end,
    getCharacterActions=function() return {isEmpty=function() return #queue.queue==0 end} end}
ISReadABook={}
function ISReadABook:derive(name) local c={Type=name};c.__index=c;setmetatable(c,{__index=self});return c end
function ISReadABook:new(character,item) return setmetatable({character=character,item=item},self) end
function ISReadABook:perform() self.character.nativeReads=self.character.nativeReads+1;queue:removeFromQueue(self) end
ISTimedActionQueue={getTimedActionQueue=function() return queue end,
    add=function(action) queue.queue[#queue.queue+1]=action;queue.current=queue.queue[1] end,
    clear=function() queue.queue={};queue.current=nil end}
CharacterTrait={ILLITERATE="illiterate"}
ItemTag={PICTUREBOOK="picture",UNINTERESTING="uninteresting"}
SkillBook={Woodwork={perk="wood"}}
instanceof=function(item,kind) return item~=nil and item.kind==kind end
local book={kind="Literature",data={},pages=-1,tags={},skill="",low=-1,high=-1}
function book:getModData() return self.data end
function book:getFullType() return "Base.Book" end
function book:getNumberOfPages() return self.pages end
function book:hasTag(tag) return self.tags[tag]==true end
function book:getSkillTrained() return self.skill end
function book:getLvlSkillTrained() return self.low end
function book:getMaxLevelTrained() return self.high end
local stored=inventory({book})
local policy={key="library",x=4,y=0,z=0}
local store={container=stored,square=storeSquare}
local base={id="home"}
local assigned=true
KnoxBaseStorage={policies=function() return assigned and {policy} or {} end,
    resolvePolicy=function() return store end,mainPolicy=function() return assigned and policy or nil end}
KnoxBaseManager={containsSquare=function() return true end}
AdjacentFreeTileFinder={Find=function() return square(3) end}
KnoxInventoryActions={queueTransfer=function(character,item,source,dest)
    assert(character==actor and source:contains(item))
    local action={item=item,source=source,dest=dest,forceCancel=function() end}
    ISTimedActionQueue.add(action)
    return action,"queued"
end}
local moved,cancelled=0,0
local bridge={moveNpc=function() moved=moved+1;return "MOVE_STARTED" end,
    tickNpc=function() return "Succeeded" end,cancelNpcMove=function() cancelled=cancelled+1 end}
local function transfer()
    local a=assert(queue.current)
    for i,v in ipairs(a.source.values) do if v==a.item then table.remove(a.source.values,i);break end end
    a.dest.values[#a.dest.values+1]=a.item
    queue:removeFromQueue(a)
end
local r=dofile(root.."/mod/42/media/lua/client/KS_BaseRecreation.lua")
assert(r.readable(actor,book))
dark=true;assert(not r.readable(actor,book));dark=false
illiterate=true;assert(not r.readable(actor,book));book.tags.picture=true;assert(r.readable(actor,book))
illiterate=false;book.tags={uninteresting=true};assert(not r.readable(actor,book));book.tags={}
book.data.printMedia={id="picture"};assert(not r.readable(actor,book), "NPC reading must never open another player's print-media UI")
book.data={};book.pages=100;book.skill="Woodwork";book.low=3;book.high=4
assert(not r.readable(actor,book), "inappropriate skill tiers are not repeatedly selected")
book.low=1;book.high=2;assert(r.readable(actor,book));book.pages=-1;book.skill=""
assert(r.find(actor,base,function() return false end)==nil, "claimed books are unavailable")
local plan=assert(r.find(actor,base,function() return true end))
assert(r.step(plan,actor,base,bridge,"reader",0)=="working" and plan.phase=="borrow_move" and moved==1)
current=square(3)
r.step(plan,actor,base,bridge,"reader",1)
r.step(plan,actor,base,bridge,"reader",2)
assert(plan.phase=="borrowing" and stored:contains(book) and not carried:contains(book), "queueing does not fabricate possession")
transfer()
r.step(plan,actor,base,bridge,"reader",3)
assert(plan.phase=="reading" and queue.current.Type=="KnoxNpcReadAction" and book.data.KnoxBaseBookLoan.storageKey=="library")
assert(actor.nativeReads==0, "selection does not fabricate a completed read")
queue.current:perform()
r.step(plan,actor,base,bridge,"reader",4)
r.step(plan,actor,base,bridge,"reader",5)
assert(plan.phase=="returning" and carried:contains(book), "reading returns a borrowed book through another real transfer")
transfer()
local outcome,reason=r.step(plan,actor,base,bridge,"reader",6)
assert(outcome=="done" and reason=="reading_completed" and actor.nativeReads==1
    and stored:contains(book) and book.data.KnoxBaseBookLoan==nil)

-- The controller's native action ownership yields to needs and preserves the
-- physical borrowed item for return after a save/load or later idle decision.
dofile(root.."/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
KnoxSurvivorNeeds={decide=function() return {kind=need} end}
KnoxSettings={baseReadingEnabled=function() return true end}
local c=setmetatable({id="reader",character=actor,base=base,bridge=bridge,state="IDLE",reservations={items={}},
    finishDecision=function(self) self.state="IDLE" end,recordFailure=function() end},KnoxAutonomyController)
assert(c:beginBaseRecreation(100))
c:updateBaseRecreation(101)
transfer()
c:updateBaseRecreation(102)
assert(c.pendingRecreation.phase=="reading")
need="drink"
c:updateBaseRecreation(200)
assert(c.state=="IDLE" and c.pendingRecreation==nil and queue.current==nil and carried:contains(book)
    and c.reservations.items[book]==nil and book.data.KnoxBaseBookLoan~=nil,
    "need interruption releases the reading action and claim without losing the borrowed book")
need="roam";dark=true
local resumed=assert(r.find(actor,base,function() return true end))
assert(resumed.phase=="return" and resumed.borrowed, "saved item loan returns even after dark")
r.step(resumed,actor,base,bridge,"reader",201)
transfer()
assert(r.step(resumed,actor,base,bridge,"reader",202)=="done" and book.data.KnoxBaseBookLoan==nil)
dark=false
c.baseTask={id="work"}
assert(not c:beginBaseRecreation(5000), "recreation never takes a claimed job")
c.baseTask=nil
assert(c:beginBaseRecreation(5000))
c:updateBaseRecreation(5001);transfer();c:updateBaseRecreation(5002)
assert(c:interruptSelfCareForDanger(5003) and c.pendingRecreation==nil and carried:contains(book),
    "danger releases real reading before combat owns actions")
local retry=assert(r.find(actor,base,function() return true end))
assigned=false
assert(r.step(retry,actor,base,bridge,"reader",5004)=="done" and carried:contains(book),
    "removed storage never deletes or teleports the book")
print("Base reading PASS native_action=true borrowing=true return=true darkness=true literacy=true levels=true interruption=true")

-- Loan ownership survives a book being put into a carried bag.
assigned=true
local bagInventory=inventory({book})
local bag={IsInventoryContainer=function() return true end,getInventory=function() return bagInventory end}
carried.values={bag}
local nested=assert(r.find(actor,base,function() return true end))
assert(nested.phase=="return" and nested.source==bagInventory)
r.step(nested,actor,base,bridge,"reader",5010)
assert(queue.current.source==bagInventory and queue.current.dest==stored,
    "return transfers name the physical bag container")
transfer()
assert(r.step(nested,actor,base,bridge,"reader",5011)=="done" and book.data.KnoxBaseBookLoan==nil)
assert(not bagInventory:contains(book) and stored:contains(book))
KnoxSettings.baseReadingEnabled=function() return false end
assert(not c:beginBaseRecreation(9000), "sandbox switch disables voluntary reading")
print("Book loan recovery PASS nested_inventory=true disabled_option=true")
