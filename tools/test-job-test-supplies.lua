local root = arg[1] or "."
require = function() return true end
local enabled, now, capacity = false, 1000, 1000
KnoxSettings = {developerJobSuppliesEnabled=function() return enabled end}
getTimestampMs=function() return now end
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local stored = {}
local inventory = {
    getItems=function() return list(stored) end,
    getItemCount=function(_,full)
        local count=0
        for _,item in ipairs(stored) do if item:getFullType()==full then count=count+item:getCount() end end
        return count
    end,
    hasRoomFor=function() return #stored<capacity end,
    isItemAllowed=function() return true end,
    AddItem=function(_,item) stored[#stored+1]=item end,
    contains=function(_,item) for _,value in ipairs(stored) do if value==item then return true end end return false end,
}
local available = true
KnoxBaseStorage = {policies=function() return {{key="food",storageRole="food"},{key="central",toolCupboard=true}} end,
    resolvePolicy=function(policy) assert(policy.key=="central", "test tools must never be created in a fridge"); return available and {container=inventory} or nil end}
ISFarmingMenu = {getWaterUsesInteger=function(item) return item.water or 0 end}
local created=0
InventoryItemFactory = {CreateItem=function(full)
    created=created+1
    return {getFullType=function() return full end,getCount=function() return full=="Base.Nails" and 5 or 1 end,
        isBroken=function() return false end,IsInventoryContainer=function() return false end,
        water=full=="Base.BucketWaterDebug" and 100 or 0}
end}
dofile(root.."/mod/42/media/lua/client/KS_BaseSupplyPlanner.lua")
local supplies=dofile(root.."/mod/42/media/lua/client/KS_JobTestSupplies.lua")
local base,worker={id="test-base"},{}
assert(supplies.ensure(base,worker,true)==0 and created==0, "normal play never creates job supplies")
enabled=true
local count,result=supplies.ensure(base,worker)
assert(count>0 and result=="test_stock_ready")
assert(inventory:getItemCount("Base.Nails")==40, "native multi-count items cannot overfill the kit")
assert(inventory:getItemCount("Base.Hammer")==2 and inventory:getItemCount("Base.BucketWaterDebug")==2)
local before=created
assert(supplies.ensure(base,worker)==0 and created==before, "autofill has a per-base cooldown")
now=11001
assert(supplies.ensure(base,worker)==0 and created==before, "full stock does not duplicate supplies")
table.remove(stored)
assert(supplies.ensure(base,worker,true)==1, "manual test top-up replaces only missing stock")
available=false
assert(select(2,supplies.ensure(base,worker,true))=="set_a_loaded_central_cupboard_first")
available=true
stored={}
capacity=1
count,result=supplies.ensure(base,worker,true)
assert(count==1 and result=="cupboard_full_or_item_restricted", "test supplies respect real storage capacity")
enabled=false
assert(supplies.ensure(base,worker,true)==0 and #stored==1, "disabling the option preserves existing real items")
print("Job test supplies PASS dev_only=true bounded=true real_stock=true counts=true capacity=true")
