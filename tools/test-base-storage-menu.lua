local root=arg[1] or "."
require=function() return true end
Events={OnGameStart={Add=function() end},OnFillWorldObjectContextMenu={Add=function() end}}
KnoxSettings={enabled=function() return true end,toolCupboardCapacity=function() return 500 end}
local base={id="home",storage={},territory={minX=0,minY=0,maxX=10,maxY=10,allFloors=true}}
local writes=0
KnoxPersistence={getBase=function(id) assert(id==base.id);return base end,
    getBaseForOwner=function() return base end,ensurePlayerId=function() return "player" end,
    setBaseStoragePolicy=function(id,reference,category)
        assert(id==base.id)
        if category=="depot" then return nil,"main_supplies_retired" end
        assert(category=="food" or category=="tools")
        writes=writes+1
        reference.category,reference.storageRole=category,category
        reference.toolCupboard=false
        reference.depot=false
        base.storage[reference.key]=reference
        return reference,"saved"
    end,
    removeBaseStoragePolicy=function(id,key) assert(id==base.id);base.storage[key]=nil;return true,"removed" end}
KnoxActivityFeed={event=function() end}
local refreshed=0
KnoxBaseHighlights={refresh=function() refreshed=refreshed+1 end}
local player={getPlayerNum=function() return 0 end}
getSpecificPlayer=function() return player end
local sq={x=3,getX=function(self) return self.x end,getY=function() return 3 end,getZ=function() return 1 end,
    getBuilding=function() return nil end}
local kinds={"fridge","freezer"}
local capacity={40,20}
local customNames={}
local containers={}
for i=1,2 do
    containers[i]={getType=function() return kinds[i] end,getCapacity=function() return capacity[i] end,
        setCapacity=function(_,v) capacity[i]=v end,
        getCustomName=function() return customNames[i] end,
        setCustomName=function(_,v) customNames[i]=v end}
end
local data={}
local object={getSquare=function() return sq end,getContainerCount=function() return #containers end,
    getContainerByIndex=function(_,i) return containers[i+1] end,getObjectIndex=function() return 0 end,
    getModData=function() return data end,transmitModData=function() end}
dofile(root.."/mod/42/media/lua/client/KS_ToolCupboard.lua")
dofile(root.."/mod/42/media/lua/client/KS_BaseStorage.lua")
dofile(root.."/mod/42/media/lua/client/KS_BaseManager.lua")
local menus={}
local function menu()
    local m={options={}}
    function m:addOption(name,target,callback,...)
        local option={name=name,target=target,callback=callback,args={...}}
        self.options[#self.options+1]=option
        return option
    end
    function m:addSubMenu(option,child) option.menu=child end
    menus[#menus+1]=m
    return m
end
ISContextMenu={getNew=function() return menu() end}
local ui=dofile(root.."/mod/42/media/lua/client/KS_BaseContextMenu.lua")
local function optionsNamed(name)
    local result={}
    for _,m in ipairs(menus) do for _,o in ipairs(m.options) do if o.name==name then result[#result+1]=o end end end
    return result
end
local function open(objects) menus={};ui.onFill(0,menu(),objects or {object},false) end
local function click(o) assert(o and not o.notAvailable and o.callback);return o.callback(o.target,unpack(o.args)) end
open()
local assign=optionsNamed("Use for Food & Drink")
assert(#assign==2, "fridge and freezer have separate storage assignments")
assert(#optionsNamed("Use as Main Supplies (100)")==0, "main supplies retired: no main option")
-- Duplicate worldobjects (multi-square crate) must not double the menu.
open({object, object})
local rootMenus=0
for _,m in ipairs(menus) do for _,o in ipairs(m.options) do
    if o.name=="Set Storage Containers" then rootMenus=rootMenus+1 end
end end
assert(rootMenus==1, "crates have a single set-storage menu")
open()
click(optionsNamed("Use for Food & Drink")[2])
local reference=KnoxBaseManager.containerReference(object,1,base.id)
assert(base.storage[reference.key].storageRole=="food" and base.storage[reference.key].containerIndex==1)
assert(capacity[2]==100 and refreshed==1, "assigned storage gets infinite (native max) capacity")
assert(customNames[2]=="Food & Drink", "container renamed to storage type")
open()
assert(#optionsNamed("Assigned: Food & Drink")==1)
click(optionsNamed("Stop Using for Food & Drink")[1])
assert(base.storage[reference.key]==nil and refreshed==2)
assert(customNames[2]=="" or customNames[2]==nil, "container name cleared on removal")
sq.x=20
local before=writes
assert(not KnoxBaseManager.setStoragePolicy(base.id,object,"food",0) and writes==before,
    "a stale menu cannot assign containers moved outside the base")
sq.x=3
kinds[1]="corpse"
assert(not KnoxBaseManager.setStoragePolicy(base.id,object,"food",0))
kinds[1]="crate"
assert(not KnoxBaseManager.setStoragePolicy(base.id,object,"depot",0), "main supplies retired")
print("Storage menu PASS callback_indices=true fridge=true capacity=true removal=true bounds=true main_retired=true dedupe=true rename=true")
