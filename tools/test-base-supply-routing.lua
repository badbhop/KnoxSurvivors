local root=arg[1] or "."
require=function() return true end
dofile(root.."/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local C=KnoxAutonomyController
local function list(t) return {size=function() return #t end,get=function(_,i) return t[i+1] end} end
local grid={}
local function square(x,y,z)
    local s={x=x,y=y,z=z,objects={}}
    function s:getX() return self.x end
    function s:getY() return self.y end
    function s:getZ() return self.z end
    function s:getRoom() return nil end
    function s:getBuilding() return nil end
    function s:getObjects() return list(self.objects) end
    grid[x..":"..y..":"..z]=s
    return s
end
local origin=square(0,0,0)
local outside=square(1,0,0)
local home=square(8,0,0)
local kitchen=square(10,0,1)
local function container(s,kind)
    local food={getFullType=function() return "Base.TestMeal" end,safe=true}
    local c={food=food,values={food},kind=kind}
    function c:getItems() return list(self.values) end
    function c:isExistYet() return true end
    function c:getSourceGrid() return s end
    s.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return c end}}
    return c
end
local outsideFood,mainFood,kitchenFood=container(outside,"world"),container(home,"main"),container(kitchen,"food")
getCell=function() return {getGridSquare=function(_,x,y,z) return grid[x..":"..y..":"..z] end} end
local actor={getCurrentSquare=function() return origin end}
local base={id="home",tasks={}}
local foodPolicy={key="food",storageRole="food",x=10,y=0,z=1}
local mainPolicy={key="main",toolCupboard=true,x=8,y=0,z=0}
local resolved={food={container=kitchenFood,square=kitchen},main={container=mainFood,square=home}}
KnoxBaseStorage={policies=function(b) assert(b==base);return {mainPolicy,foodPolicy} end,
    resolvePolicy=function(p) return resolved[p.key] end}
KnoxSurvivorNeeds={isSafeFood=function(item) return item.safe end}
AdjacentFreeTileFinder={Find=function(s) return s end}
local moved
local c=setmetatable({id="resident",character=actor,base=base,baseId=base.id,
    inspectedContainers={},blockedAreas={},nextWorldSearch=0,reservations={items={}},
    bridge={moveNpc=function(_,id,s) moved=s;return "MOVE_STARTED" end}},C)
local function search(t)
    c.nextWorldSearch=0
    c.pendingSupply=nil
    moved=nil
    return c:beginWorldSearch("find_food",t)
end
assert(search(1) and moved==kitchen and c.pendingSupply.item==kitchenFood.food,
    "a personal meal uses the assigned kitchen on a loaded upstairs floor before a closer outside house")
c.reservations.items[kitchenFood.food]="another-resident"
assert(search(2) and moved==home, "reserved kitchen food falls back to main supplies")
c.inspectedContainers[mainFood]=100
assert(not search(3) and moved==nil, "base residents do not leave home for personal needs")
c.inspectedContainers={}
c.reservations.items={}
kitchenFood.food.safe=false
assert(search(4) and moved==home, "assigned food storage does not make unsafe food edible")
kitchenFood.food.safe=true
c.baseSupplyTrip=true
assert(search(5) and moved==outside, "restocking never withdraws from the base's own storage")
outsideFood.values={}
assert(not search(6) and moved==nil, "an empty neighborhood cannot be reported as newly recovered supplies")
c.baseSupplyTrip=false
resolved.food=nil
assert(search(7) and moved==home, "unloaded food storage falls back without abandoning the base")
print("Home supply search PASS kitchen=true floors=true reservations=true unsafe_food=true no_restock_loop=true")
