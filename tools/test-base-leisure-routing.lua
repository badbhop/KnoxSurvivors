local root=arg[1] or "."
require=function() return true end
Events={OnGameStart={Add=function() end}}
dofile(root.."/mod/42/media/lua/client/KS_BaseManager.lua")
dofile(root.."/mod/42/media/lua/client/KS_CompanionPatrol.lua")
dofile(root.."/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller=KnoxAutonomyController
local squares,room={},{}
local indoors,occupied,blocked,unloaded=false,false,false,false
local forced,requested,limit=nil,0,0
local function square(x,y,z)
    local key=x..":"..y..":"..z
    if not squares[key] then
        local s={x=x,y=y,z=z}
        function s:getX() return self.x end;function s:getY() return self.y end;function s:getZ() return self.z end
        function s:canStand() return not blocked end
        function s:getRoom() return indoors and room or nil end
        function s:getMovingObjects() return {size=function() return occupied and 1 or 0 end} end
        squares[key]=s
    end
    return squares[key]
end
local current=square(0,0,1)
local hour=12
getGameTime=function() return {getTimeOfDay=function() return hour end} end
getCell=function() return {getGridSquare=function(_,x,y,z)
    requested=requested+1
    assert(z==1,"idle movement stays on the resident's actual floor")
    return not unloaded and (forced or square(x,y,z)) or nil
end} end
local seed=17
ZombRand=function(bound)
    limit=math.max(limit,bound)
    seed=(seed*25173+13849)%65536
    return seed%bound
end
local base={id="home",home={minX=-4,minY=-4,width=9,height=9,z=0},
    territory={minX=-100,minY=-100,maxX=100,maxY=100,allFloors=true}}
local actor={getCurrentSquare=function() return current end,
    isSitOnGround=function() return false end,isSittingOnFurniture=function() return false end}
local moves=0
local bridge={moveNpcWithinArea=function(_,id,target,x1,y1,x2,y2,z)
    assert(id=="resident" and x1==-100 and y1==-100 and x2==100 and y2==100 and z==1)
    assert(KnoxBaseManager.containsSquare(base,target))
    moves=moves+1
    return "MOVE_STARTED"
end}
local c=setmetatable({id="resident",base=base,character=actor,bridge=bridge},Controller)
for i=1,40 do
    local before=requested
    local target=assert(c:findBaseMovementTarget(false,i*100))
    local d=target:getX()^2+target:getY()^2
    assert(d>=4 and d<=36 and target:getZ()==1)
    assert(requested-before<=24 and limit<=13,"a large base never expands the bounded idle scan")
end
occupied=true;assert(c:findBaseMovementTarget(false,5000)==nil);occupied=false
blocked=true;assert(c:findBaseMovementTarget(false,5000)==nil);blocked=false
unloaded=true;assert(c:findBaseMovementTarget(false,5000)==nil);unloaded=false
hour=22;assert(c:findBaseMovementTarget(false,5000)==nil,"nighttime walks do not select outdoor tiles")
indoors=true;assert(c:findBaseMovementTarget(false,5000));hour=12
local danger={getCurrentSquare=function() return current end,isDead=function() return false end}
c.perceivedThreats={[danger]={lastSeen=5000}}
assert(c:findBaseMovementTarget(false,5000)==nil,"idle residents avoid remembered danger near a destination")
c.perceivedThreats[danger].lastSeen=-10000
assert(c:findBaseMovementTarget(false,5000),"expired danger must not permanently disable base life")
c.perceivedThreats={}
forced=square(0,0,0);assert(c:findBaseMovementTarget(false,5000)==nil,"wrong-floor results are rejected")
forced=square(101,0,1);assert(c:findBaseMovementTarget(false,5000)==nil,"outside territory is never a leisure destination")
forced=square(4,0,1)
assert(c:beginBaseMovement(5000,false) and moves==1 and c.state=="BASE_PATROL")
assert(not c:beginBaseMovement(5001,false) and moves==1,"the movement cooldown is retained")
local old=current;current=forced;forced=old
assert(c:findBaseMovementTarget(false,7000)==nil,"idle walks must not immediately bounce to their previous origin")
assert(c:findBaseMovementTarget(false,13000)==old,"the previous spot becomes usable again after a bounded hold")
current=square(101,0,1);forced=nil
assert(c:findBaseMovementTarget(false,13000)==nil,"an away resident must use the real return-home decision")
current=nil;assert(c:findBaseMovementTarget(false,13000)==nil)
print("Base leisure routing PASS short_walks=true bounds=true floor=true occupancy=true darkness=true perceived_danger=true cooldown=true native_area=true")
