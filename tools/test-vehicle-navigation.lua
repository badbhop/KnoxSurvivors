local root=arg[1] or "."
local w=dofile(root.."/tools/vehicle-test-world.lua")
local nav=dofile(root.."/mod/42/media/lua/client/KS_VehicleNavigation.lua")
local geometry=assert(nav.geometry(w.vehicle))
w.vehicle.fx,w.vehicle.fy=1,0
local fx,fy=nav.forward(w.vehicle);assert(fx==1 and fy==0)
w.vehicle.fx,w.vehicle.fy=0,1
local function clear() return nav.clear(nav.context(w.vehicle,geometry),0,0,0,12,0) end
assert(clear())
w.blocked['1:5']=true;assert(not clear(), "obstacles beside the centreline collide with vehicle width")
w.blocked={};w.blocked['0:5']='tree';assert(not clear())
w.blocked={};w.wall=function(ax,ay,bx,by) return math.min(ay,by)<5 and math.max(ay,by)>=5 end
assert(not clear(), "a wall between standable squares cannot be driven through")
w.wall=nil
w.people['0:5']={{kind="IsoGameCharacter",isDead=function() return false end,getVehicle=function() return nil end}}
assert(not clear(), "living people in a lane require braking")
w.people={};w.otherVehicles={{getX=function() return 0 end,getY=function() return 5 end,
    isIntersectingSquare=function(_,x,y,z) return x==0 and y==5 end}}
assert(not clear(), "other vehicle bodies block a route")
w.otherVehicles={};w.unloaded=function(x,y) return y==5 end
assert(not clear(), "unloaded ground cannot certify a safe route")
w.unloaded=nil
local route=assert(nav.plan(w.vehicle,0,30,0,geometry));assert(#route==1 and route[1].y==30)
w.blocked['0:12']=true
route=assert(nav.plan(w.vehicle,0,30,0,geometry))
assert(#route>1, "an obstruction produces actual waypoints around it")
local x,y=0,0
for _,point in ipairs(route) do
    assert(nav.clear(nav.context(w.vehicle,geometry),x,y,point.x,point.y,0))
    x,y=point.x,point.y
end
local rejected,reason=nav.plan(w.vehicle,0,1000,0,geometry)
assert(rejected==nil and reason=="destination_too_far")
assert(nav.plan(w.vehicle,0,30,1,geometry)==nil)
local overspeed=nav.controls(25,100,1,0,20)
assert(overspeed.brake and not overspeed.forward)
local corner=nav.controls(12,10,0.7,0.7,20)
assert(corner.brake and not corner.forward and corner.steering>0)
assert(nav.controls(2,1,1,0,20).brake)
print("Vehicle navigation PASS footprint=true walls=true people=true vehicles=true loaded_ground=true routes=true limits=true")

w.blocked={};w.people['0:0']={w.character}
assert(nav.plan(w.vehicle,0,30,0,geometry,w.character)~=nil,
    "the assigned driver about to board does not block their own planned route")
assert(nav.plan(w.vehicle,0,30,0,geometry)==nil,
    "a different person occupying the vehicle corridor still blocks departure")
