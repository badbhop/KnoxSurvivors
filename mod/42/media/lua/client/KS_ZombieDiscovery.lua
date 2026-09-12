-- Initial visual discovery for contained NPC shells. CanSee is a geometry
-- check, not a spotting roll; using it alone revealed crouching survivors even
-- behind a zombie. Native spotted(false) also reads a local-player lighting
-- channel that these shells cannot own. Keep this small Knox exposure policy
-- separate from native hearing, existing targets and attack/health processing.
local Discovery = {}
KnoxZombieDiscovery = Discovery
local exposures = setmetatable({}, { __mode = "k" })
local SAMPLE_TICKS = 15

local function value(object,name,fallback)
    local ok,result=pcall(function() return object[name](object) end)
    if ok and result~=nil then return result end
    return fallback
end

function Discovery.snapshot(character)
    local sneaking=value(character,"isSneaking",false)
    local sneakMod=tonumber(value(character,"getSneakSpotMod",1)) or 1
    return { x=value(character,"getX",nil), y=value(character,"getY",nil),
        sneaking=sneaking, running=value(character,"isRunning",false)
            or value(character,"isSprinting",false),
        sneakMod=math.max(0.1,math.min(1,sneakMod)) }
end

function Discovery.canAcquire(observer,character,snapshot,ticks,distanceSquared,clearSight)
    local targets=exposures[observer]
    if not clearSight then
        if targets~=nil then targets[character]=nil end
        return false
    end
    if targets==nil then
        targets=setmetatable({}, { __mode = "k" })
        exposures[observer]=targets
    end
    -- Actual contact remains dangerous even when the zombie faces away.
    if distanceSquared<=1.5*1.5 then targets[character]=nil;return true end
    local ox,oy=value(observer,"getX",nil),value(observer,"getY",nil)
    local fx,fy=value(observer,"getLookDirectionX",nil),value(observer,"getLookDirectionY",nil)
    if ox==nil or oy==nil or fx==nil or fy==nil or snapshot.x==nil or snapshot.y==nil then
        targets[character]=nil
        return false
    end
    local dx,dy=snapshot.x-ox,snapshot.y-oy
    local distance=math.sqrt(dx*dx+dy*dy)
    local length=math.sqrt(fx*fx+fy*fy)
    if distance<=0 or length<=0 then targets[character]=nil;return false end
    local dot=(dx*fx+dy*fy)/(distance*length)
    if dot < -0.25 then targets[character]=nil;return false end
    -- A nearby upright person is obvious. Distance, peripheral vision and
    -- crouching require sustained exposure; crouching never grants immunity.
    local threshold=SAMPLE_TICKS*math.max(1,distance/4)
    if dot<0.5 then threshold=threshold*3 end
    if snapshot.sneaking then threshold=threshold*2/snapshot.sneakMod
    elseif snapshot.running then threshold=math.max(SAMPLE_TICKS,threshold/2) end
    local previous=targets[character]
    local elapsed=previous~=nil and ticks-previous.ticks or SAMPLE_TICKS
    local exposure=previous~=nil and elapsed>=0 and elapsed<=SAMPLE_TICKS*2 and previous.exposure or 0
    exposure=exposure+math.max(0,math.min(SAMPLE_TICKS,elapsed))
    targets[character]={ticks=ticks,exposure=exposure}
    return exposure>=threshold
end
return Discovery
