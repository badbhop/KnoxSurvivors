local d=dofile((arg[1] or ".").."/mod/42/media/lua/client/KS_ZombieDiscovery.lua")
local x,y,sneak,running,mod=4,0,false,false,0.5
local fx,fy=1,0
local npc={getX=function() return x end,getY=function() return y end,
    isSneaking=function() return sneak end,isRunning=function() return running end,
    getSneakSpotMod=function() return mod end}
local observer={getX=function() return 0 end,getY=function() return 0 end,
    getLookDirectionX=function() return fx end,getLookDirectionY=function() return fy end}
local function spot(t,clear) return d.canAcquire(observer,npc,d.snapshot(npc),t,x*x+y*y,clear~=false) end
assert(spot(0), "an upright person four tiles directly ahead is obvious")
x=-4
assert(not spot(15), "geometric LOS behind the zombie is not visual discovery")
x=-1
assert(spot(30), "physical contact is dangerous even behind a zombie")
x=8;sneak=true
for t=45,135,15 do assert(not spot(t), "crouching and distance delay visual discovery") end
assert(spot(150), "sustained exposure eventually reveals a crouching survivor")
assert(not spot(165,false), "solid cover clears exposure")
assert(not spot(180), "a glimpse after cover starts fresh")
assert(not spot(600), "an unloaded or unsampled interval cannot count as continuous exposure")
x=4;sneak=false;fx=0;fy=1
assert(not spot(900) and not spot(915) and spot(930), "peripheral sight takes longer than looking directly")
fx=1;fy=0;x=8;running=true
assert(spot(960), "running makes a person easier to notice")
running=false;sneak=true;mod=0
assert(d.snapshot(npc).sneakMod==0.1, "extreme sneak modifiers remain bounded")
assert(not d.canAcquire({},npc,d.snapshot(npc),1000,16,true), "missing native facing cannot invent a sighting")
print("Zombie discovery PASS facing=true exposure=true sneak=true contact=true cover=true sampling=true")
