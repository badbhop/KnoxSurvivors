local root = arg[1] or "."
require = function() return true end
local enabled, now, capacity = false, 1000, 1000
KnoxSettings = {ignoreJobResourceRequirements=function() return enabled end}
getTimestampMs=function() return now end
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local stored = {}
local nextId = 0
local function makeItem(full)
    nextId = nextId + 1
    return {id=nextId, getFullType=function() return full end,getCount=function() return full=="Base.Nails" and 5 or 1 end,
        isBroken=function() return false end,IsInventoryContainer=function() return false end,
        water=full=="Base.BucketWaterDebug" and 100 or 0}
end
local inventory = {
    getItems=function() return list(stored) end,
    getItemCount=function(_,full)
        local count=0
        for _,item in ipairs(stored) do if item:getFullType()==full then count=count+item:getCount() end end
        return count
    end,
    hasRoomFor=function() return #stored<capacity end,
    isItemAllowed=function() return true end,
    -- Strict vanilla emulation: every stored item owns a unique id, adding a
    -- pre-created instance whose id is already present is rejected, and the
    -- string overload mints a fresh engine id. Deliberately NO item factory
    -- or script manager: live clients may expose neither, and engine-minted
    -- stock must not depend on them.
    AddItem=function(_,value)
        if type(value) == "string" then
            local minted = makeItem(value)
            stored[#stored+1]=minted
            return minted
        end
        for _,existing in ipairs(stored) do
            if existing.id == value.id then return nil end
        end
        stored[#stored+1]=value
        return value
    end,
    contains=function(_,item) for _,value in ipairs(stored) do if value==item then return true end end return false end,
}
local available = true
KnoxBaseStorage = {policies=function() return {{key="tools",storageRole="tools"},{key="food",storageRole="food"}} end,
    resolvePolicy=function(policy) assert(policy.key=="tools", "test tools use typed storage"); return available and {container=inventory} or nil end}
ISFarmingMenu = {getWaterUsesInteger=function(item) return item.water or 0 end}
assert(rawget(_G, "InventoryItemFactory") == nil and rawget(_G, "getScriptManager") == nil,
    "harness must prove factory-free stocking")
dofile(root.."/mod/42/media/lua/client/KS_BaseSupplyPlanner.lua")
local supplies=dofile(root.."/mod/42/media/lua/client/KS_JobTestSupplies.lua")
local base,worker={id="test-base"},{}
assert(supplies.ensure(base,worker,true)==0 and #stored==0, "normal play never creates job supplies")
enabled=true
local count,result=supplies.ensure(base,worker)
assert(count>0 and result=="test_stock_ready")
assert(inventory:getItemCount("Base.Nails")==40, "native multi-count items cannot overfill the kit")
assert(inventory:getItemCount("Base.Hammer")==2 and inventory:getItemCount("Base.BucketWaterDebug")==2)
local stockSize=#stored
assert(supplies.ensure(base,worker)==0, "autofill has a per-base cooldown")
now=11001
assert(supplies.ensure(base,worker)==0 and #stored==stockSize, "full stock does not duplicate supplies")
table.remove(stored)
assert(supplies.ensure(base,worker,true)==1, "manual test top-up replaces only missing stock")
available=false
assert(select(2,supplies.ensure(base,worker,true))=="assign_typed_storage_first")
available=true
stored={}
capacity=1
count,result=supplies.ensure(base,worker,true)
assert(count==1 and result=="cupboard_full_or_item_restricted", "test supplies respect real storage capacity")
enabled=false
stored={{real=true}}
assert(supplies.ensure(base,worker,true)==0 and #stored==1, "disabling the option preserves existing real items")

-- Ignore-mode worker top-up: real carried stock for native actions with no
-- fetch trips. Tools persist once carried; only consumed stock is replaced.
enabled=true
local satchel = {}
local satchelInventory = {
    getItems=function() return list(satchel) end,
    getItemCount=function(_,full)
        local count=0
        for _,item in ipairs(satchel) do if item:getFullType()==full then count=count+item:getCount() end end
        return count
    end,
    AddItem=function(_,value)
        if type(value) ~= "string" then return nil end
        local minted = makeItem(value)
        satchel[#satchel+1]=minted
        return minted
    end,
}
local handy = { getInventory=function() return satchelInventory end }
local topped, topResult = supplies.topUp(handy, { items = { ["Base.Hammer"] = 1, ["Base.Plank"] = 1, ["Base.Nails"] = 2 } })
assert(topped == 3 and topResult == "topped_up", "top-up must mint every missing requirement")
topped = supplies.topUp(handy, { items = { ["Base.Hammer"] = 1, ["Base.Plank"] = 1, ["Base.Nails"] = 2 } })
assert(topped == 0, "top-up must not duplicate carried tools")
enabled=false
assert(supplies.topUp(handy, { items = { ["Base.Plank"] = 1 } }) == 0, "top-up stays off without the option")
print("Job test supplies PASS dev_only=true bounded=true real_stock=true counts=true capacity=true factory_free=true topup=true")

enabled=true
satchel={}
supplies.prepareDiscovery({zones={wood={type="woodcutting"}, garden={type="farming",enabled=false}}}, handy)
assert(satchelInventory:getItemCount("Base.HandAxe")==1)
assert(satchelInventory:getItemCount("Base.Log")==0, "wood worker must not receive eight test logs")
assert(satchelInventory:getItemCount("Base.HandShovel")==0, "disabled zones do not create kit items")
assert(supplies.prepareDiscovery({zones={wood={type="woodcutting"}}}, handy)==0)
enabled=false
satchel={}
assert(supplies.prepareDiscovery({zones={}}, handy)==0 and #satchel==0)
enabled=true
satchelInventory.AddItem=function() return nil end
assert(select(2,supplies.topUp(handy,{items={["Base.Hammer"]=1}}))=="unavailable_items=Base.Hammer",
    "unavailable native items must not report top-up success")
