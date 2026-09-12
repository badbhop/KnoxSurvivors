-- Original Knox routing on loaded, physically clear ground. Routes are plain
-- coordinates; native vehicle physics owns all movement. No teleporting or
-- character-sized path is used to certify clearance for a vehicle.
local Navigation={MAX_DISTANCE=160,MAX_NODES=384}
KnoxVehicleNavigation=Navigation
local scratch=nil

function Navigation.forward(vehicle)
    if Vector3f==nil or vehicle.getForwardVector==nil then return nil end
    scratch=scratch or Vector3f.new()
    local v=vehicle:getForwardVector(scratch)
    local x,y=v:x(),v:z() -- Bullet's horizontal X/Z becomes world X/Y.
    local length=math.sqrt(x*x+y*y)
    if length<0.1 then return nil end
    return x/length,y/length
end

function Navigation.geometry(vehicle)
    local script=vehicle.getScript~=nil and vehicle:getScript() or nil
    local extents=script~=nil and script:getExtents() or nil
    if extents==nil then return nil end
    local width,length=tonumber(extents:x()),tonumber(extents:z())
    if width==nil or length==nil or width<=0 or length<=0 or width>8 or length>18 then return nil end
    return {halfWidth=width/2+0.4,halfLength=length/2+0.5}
end

function Navigation.context(vehicle,geometry,driver)
    local cell=getCell()
    if cell==nil then return nil end
    local others={}
    local vehicles=cell.getVehicles~=nil and cell:getVehicles() or nil
    local function add(other)
        if other~=vehicle and other~=nil then others[#others+1]=other end
    end
    if vehicles~=nil then
        if vehicles.iterator~=nil then
            local iterator=vehicles:iterator()
            while iterator:hasNext() do add(iterator:next()) end
        else
            for i=0,vehicles:size()-1 do add(vehicles:get(i)) end
        end
    end
    return {vehicle=vehicle,driver=driver,geometry=geometry,cell=cell,others=others,squares={}}
end

local function tile(context,x,y,z)
    x,y=math.floor(x),math.floor(y)
    local key=x..":"..y..":"..z
    local cached=context.squares[key]
    if cached~=nil then return cached~=false and cached or nil end
    local square=context.cell:getGridSquare(x,y,z)
    local free=square~=nil and square:canStand() and square:isOutside()
        and not square:isSolid() and not square:isSolidTrans() and not square:HasTree()
    if free then
        local moving=square:getMovingObjects()
        for i=0,moving:size()-1 do
            local object=moving:get(i)
            if object~=context.driver and instanceof(object,"IsoGameCharacter") and not object:isDead()
                and object:getVehicle()~=context.vehicle then free=false;break end
        end
    end
    if free then
        for _,other in ipairs(context.others) do
            if math.abs(other:getX()-x)<=20 and math.abs(other:getY()-y)<=20
                and other:isIntersectingSquare(x,y,z) then free=false;break end
        end
    end
    context.squares[key]=free and square or false
    return free and square or nil
end

function Navigation.clear(context,ax,ay,bx,by,z)
    if context==nil then return false end
    local dx,dy=bx-ax,by-ay
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance<0.01 then return tile(context,ax,ay,z)~=nil end
    local px,py=-dy/distance,dx/distance
    local steps=math.ceil(distance*2)
    local radius=context.geometry.halfWidth
    local lanes=math.ceil(radius*4)
    local previous={}
    -- Half-tile sampling plus continuous square-edge checks across the width
    -- catches walls/fences between otherwise standable tiles, including turns.
    for step=0,steps do
        local row={}
        for lane=0,lanes do
            local offset=-radius+2*radius*lane/lanes
            local square=tile(context,ax+dx*step/steps+px*offset,ay+dy*step/steps+py*offset,z)
            if square==nil then return false end
            local before=previous[lane]
            if before~=nil and before~=square and before:isBlockedTo(square) then return false end
            local beside=row[lane-1]
            if beside~=nil and beside~=square and beside:isBlockedTo(square) then return false end
            row[lane]=square
        end
        previous=row
    end
    return true
end

local directions={{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}
local function distance(ax,ay,bx,by) return math.sqrt((ax-bx)^2+(ay-by)^2) end
function Navigation.plan(vehicle,x,y,z,geometry,driver)
    local origin=vehicle:getSquare()
    x,y,z=tonumber(x),tonumber(y),tonumber(z)
    if origin==nil or x==nil or y==nil or z==nil or x~=x or y~=y or z~=z
        or z~=origin:getZ() then return nil,"destination_unavailable" end
    local ax,ay=vehicle:getX(),vehicle:getY()
    local total=distance(ax,ay,x,y)
    if total>Navigation.MAX_DISTANCE then return nil,"destination_too_far" end
    if total<4 then return nil,"destination_too_close" end
    local fx,fy=Navigation.forward(vehicle)
    if fx==nil then return nil,"vehicle_heading_unavailable" end
    local context=Navigation.context(vehicle,geometry,driver)
    if context==nil or tile(context,x,y,z)==nil then return nil,"destination_unavailable" end
    local function ahead(nx,ny)
        local d=distance(ax,ay,nx,ny)
        return d>0 and ((nx-ax)*fx+(ny-ay)*fy)/d>=0.6
    end
    local start={x=ax,y=ay,g=0,key="0:0",ix=0,iy=0}
    local open={start};local best={[start.key]=start};local closed={}
    local final=nil
    for expanded=1,Navigation.MAX_NODES do
        if #open==0 then break end
        local index,score=1,math.huge
        for i,node in ipairs(open) do
            local f=node.g+distance(node.x,node.y,x,y)
            if f<score then index,score=i,f end
        end
        local node=table.remove(open,index)
        closed[node.key]=true
        if (node~=start or ahead(x,y)) and Navigation.clear(context,node.x,node.y,x,y,z) then
            final={x=x,y=y,parent=node};break
        end
        for _,dir in ipairs(directions) do
            local ix,iy=node.ix+dir[1],node.iy+dir[2]
            local key=ix..":"..iy
            local nx,ny=ax+ix*4,ay+iy*4
            if not closed[key] and math.abs(nx-ax)<=Navigation.MAX_DISTANCE
                and math.abs(ny-ay)<=Navigation.MAX_DISTANCE and (node~=start or ahead(nx,ny)) then
                local cost=node.g+distance(node.x,node.y,nx,ny)
                if best[key]==nil or cost<best[key].g then
                    if Navigation.clear(context,node.x,node.y,nx,ny,z) then
                        local nextNode=best[key]
                        if nextNode==nil then
                            nextNode={key=key,ix=ix,iy=iy,x=nx,y=ny}
                            best[key]=nextNode;open[#open+1]=nextNode
                        end
                        nextNode.g,nextNode.parent=cost,node
                    end
                end
            end
        end
    end
    if final==nil then return nil,"drive_route_unavailable" end
    local reversed={}
    while final~=start do reversed[#reversed+1]={x=final.x,y=final.y,z=z};final=final.parent end
    local raw={}
    for i=#reversed,1,-1 do raw[#raw+1]=reversed[i] end
    -- Remove redundant grid zigzags only when the full-width shortcut is clear.
    local route={};local fromX,fromY,index=ax,ay,1
    while index<=#raw do
        local chosen=index
        for i=#raw,index,-1 do
            if (#route>0 or ahead(raw[i].x,raw[i].y))
                and Navigation.clear(context,fromX,fromY,raw[i].x,raw[i].y,z) then chosen=i;break end
        end
        route[#route+1]=raw[chosen]
        fromX,fromY,index=raw[chosen].x,raw[chosen].y,chosen+1
    end
    return route
end

function Navigation.controls(speed,distance,dot,cross,limit)
    local stoppingGap=2
    local desired=math.min(limit,math.sqrt(math.max(0,distance-stoppingGap)*2*2)*3.6)
    if dot<0.9 then desired=math.min(desired,8) end
    if dot<=0 then desired=0 end
    return {steering=math.max(-1,math.min(1,cross*3)),
        forward=desired>0 and speed<desired-1, backward=false,
        brake=desired<=0 or speed>desired+1,shift=false}
end
return Navigation
