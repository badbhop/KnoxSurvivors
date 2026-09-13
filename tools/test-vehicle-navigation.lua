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
local route=assert(nav.plan(w.vehicle,0,30,0,geometry));assert(route[#route].y==30)
for _,point in ipairs(route) do assert(point.curvature==0 and math.abs(point.x)<0.000001) end
w.blocked['0:12']=true
route=assert(nav.plan(w.vehicle,0,30,0,geometry))
assert(#route>1 and route.length>30, "an obstruction produces actual turns around it")
local x,y=0,0
for _,point in ipairs(route) do
    assert(nav.poseClear(nav.context(w.vehicle,geometry),point.x,point.y,point.heading,0))
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

-- Complete body caps and turning continuity, including a goal behind the car.
w.people={};w.blocked={}
w.blocked['0:12']=true
assert(not nav.clear(nav.context(w.vehicle,geometry),0,0,0,10,0),"the stopped nose is part of destination clearance")
w.blocked={};w.blocked['0:-2']=true
assert(not nav.poseClear(nav.context(w.vehicle,geometry),0,0,math.pi/2,0),"the rear body cannot be ignored")
w.blocked={}
local loop=assert(nav.plan(w.vehicle,0,-30,0,geometry))
assert(loop.length>30 and #loop>3,"a behind destination requires a real forward turning route")
local previous=loop.origin
for _,point in ipairs(loop) do
    assert(math.abs(point.heading-previous.heading)<0.5,"no instantaneous heading reversal")
    assert((point.x-previous.x)*math.cos(previous.heading)+(point.y-previous.y)*math.sin(previous.heading)>0,
        "every short route step is forward in its preceding orientation")
    previous=point
end
local follow=nav.follow(loop,1,0,0,8)
assert(follow.remaining>30)
local command=nav.controls(4,follow.remaining,1,0,20,geometry,4,0)
assert(command.forward and not command.brake,"an intermediate waypoint is not a stopping destination")
local gentle=nav.controls(5,100,1,0.04,20,geometry,4,0)
assert(gentle.steering>0.1 and gentle.steering<0.2,"gentle corrections must cross native recentering deadband without normalized oversteer")
local coasting=nav.controls(5,100,1,0.001,20,geometry,4,0)
assert(coasting.steering==0)

-- Scaled native dimensions/axles and an offset body are used as returned.
local function vec(x,y,z) return {x=function() return x end,y=function() return y end,z=function() return z end} end
local original=w.script
w.script={getExtents=function() return vec(4,2,8) end,getModelScale=function() error("already scaled") end,
    getCenterOfMassOffset=function() return vec(2,0,3) end,getModelOffset=function() return vec(1,0,0.5) end,
    getWheelCount=function() return 4 end,getSteeringClamp=function() return 0.6 end,
    getWheel=function(_,i) return {getOffset=function() return vec(i%2==0 and -1.5 or 1.5,0,i<2 and 2.6 or -2.6) end} end}
local offset=assert(nav.geometry(w.vehicle))
assert(offset.halfWidth==2.4 and offset.halfLength==4.5 and offset.wheelbase==5.2 and offset.rearX==1 and offset.rearZ==-2.1)
w.blocked['2:7']=true
assert(not nav.poseClear(nav.context(w.vehicle,offset),0,0,math.pi/2,0),"COM shifts the whole physical body")
w.blocked={};w.blocked['-4:0']=true
assert(nav.poseClear(nav.context(w.vehicle,offset),0,0,math.pi/2,0),"the body is not reflected to the wrong side")
w.blocked={}
local shifted=assert(nav.plan(w.vehicle,30,30,0,offset))
assert(math.abs(shifted[#shifted].x-30)<0.00001 and math.abs(shifted[#shifted].y-30)<0.00001)
w.script=original
w.vehicle.getUpVectorDot=function() return -1 end
assert(nav.forward(w.vehicle)==nil,"an overturned car cannot be certified with yaw-only geometry")
w.vehicle.getUpVectorDot=nil
print("Vehicle turn geometry PASS nose=true rear=true curved_loop=true continuity=true deadband=true scale=true COM=true rear_axle=true upright=true")

-- Native chassis and additional box/sphere shapes can extend beyond rendering.
local shapes={}
w.script.hasPhysicsChassisShape=function() return true end
w.script.useChassisPhysicsCollision=function() return true end
w.script.getPhysicsChassisShape=function() return vec(4,1,6) end
w.script.getPhysicsShapeCount=function() return #shapes end
w.script.getPhysicsShape=function(_,i) return shapes[i+1] end
local chassis=assert(nav.geometry(w.vehicle))
assert(chassis.halfWidth==2.4 and chassis.halfLength==3.5)
shapes[1]={getTypeString=function() return "box" end,getOffset=function() return vec(4,0,0) end,
    getExtents=function() return vec(2,1,2) end,getRotate=function() return vec(0,0,0) end}
local extended=assert(nav.geometry(w.vehicle))
w.blocked['4:0']=true
assert(not nav.poseClear(nav.context(w.vehicle,extended),0,0,math.pi/2,0),"an offset physical part beyond the render body blocks departure")
w.blocked={}
shapes[2]={getTypeString=function() return "sphere" end,getOffset=function() return vec(-4,0,0) end,getRadius=function() return 1.5 end}
local sphere=assert(nav.geometry(w.vehicle))
w.blocked['-5:0']=true
assert(not nav.poseClear(nav.context(w.vehicle,sphere),0,0,math.pi/2,0))
w.blocked={}
shapes[1].getRotate=function() return vec(0,45,0) end
assert(nav.geometry(w.vehicle).halfWidth>sphere.halfWidth,"rotated custom parts have a conservative containing bound")
shapes[1].getTypeString=function() return "mesh" end
assert(nav.geometry(w.vehicle)==nil,"unknown mesh collision cannot be certified from its picture")
w.blocked['3:0']=true
assert(not nav.poseClear(nav.context(w.vehicle,geometry),0.4,0,math.pi/4,0),"rotated body corner grazing a tile is checked")
w.blocked={};w.blocked['3:-1']=true
assert(nav.poseClear(nav.context(w.vehicle,geometry),0.4,0,math.pi/4,0),"empty corners of the axis-aligned bounds do not block a rotated body")
w.blocked={}
print("Vehicle collision shapes PASS native_chassis=true custom_box=true sphere=true rotated_part=true mesh_unverified=true tile_intersection=true")
