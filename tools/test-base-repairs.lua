local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["Moveables/ISMoveableSpriteProps"] = true
package.loaded["Moveables/ISMoveablesAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
package.loaded["TimedActions/ISWearClothing"] = true
package.loaded["Util/AdjacentFreeTileFinder"] = true
package.loaded["ISUI/ISWorldObjectContextMenu"] = true
package.loaded["KS_SurvivorInventoryActions"] = true

local queued = nil
ISTimedActionQueue = { add = function(action) queued = action end }
ISMoveablesAction = {
    new = function(_, character, square, mode, spriteName, object)
        return { kind = mode, character = character, square = square,
            spriteName = spriteName, object = object }
    end,
}
local wearQueued = 0
ISWearClothing = { new = function()
    wearQueued = wearQueued + 1
    return { kind = "wear" }
end }
local equipped = {}
ISWorldObjectContextMenu = {
    equip = function(_, _, tool, primary)
        equipped[primary and "primary" or "secondary"] = tool
        return tool
    end,
}
local transferQueued = 0
KnoxInventoryActions = { queueTransfer = function()
    transferQueued = transferQueued + 1
    return {}, "queued"
end }
AdjacentFreeTileFinder = {
    Find = function(square) return square.approach end,
}
instanceof = function(object, className)
    return object ~= nil and object.className == className
end

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function item(fullType)
    local value = { fullType = fullType }
    function value:getFullType() return self.fullType end
    return value
end

local hammer = item("Base.Hammer")
local screwdriver = item("Base.Screwdriver")
local secondaryTool = screwdriver
local inventory = {}
local inventoryItems={hammer,screwdriver,item("Base.Plank"),item("Base.Plank"),
    item("Base.Nails"),item("Base.Nails"),item("Base.Nails"),item("Base.Nails")}
function inventory:getItems() return list(inventoryItems) end
function inventory:getItemCount(full)
    local count=0
    for _,value in ipairs(inventoryItems) do if value:getFullType()==full then count=count+1 end end
    return count
end
local character = {}
function character:getInventory() return inventory end
function character:getPrimaryHandItem() return nil end
function character:getSecondaryHandItem() return nil end

local approach = { x = 9, y = 10, z = 0 }
function approach:getX() return self.x end
function approach:getY() return self.y end
function approach:getZ() return self.z end

local square = { x = 10, y = 10, z = 0, approach = approach }
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end

local sprite = { name = "fixtures_doors_01_2" }
function sprite:getName() return self.name end

local props = {
    canRepairObject = function(self, worker)
        return { canRepair = worker ~= nil and self.object.health >= 20
            and self.object.health <= 95 }
    end,
    hasRepairTool = function(_, worker, second)
        return second and secondaryTool or hammer
    end,
    getAllRepairParts = function()
        return {
            { itemType = "Base.Plank", amount = 2, required = true },
            { itemType = "Base.Nails", amount = 4, required = false },
            { itemType = "Base.Screws", amount = 4, required = false },
        }
    end,
    checkForRepairPart = function(_, _, itemType)
        return itemType == "Base.Nails"
    end,
    walkToAndEquip = function(_, worker, targetSquare, mode, spriteName)
        return worker == character and targetSquare == square and mode == "repair"
            and spriteName == sprite.name
    end,
}

local door = {
    className = "IsoDoor",
    health = 50,
    maxHealth = 100,
    objectIndex = 2,
    square = square,
    sprite = sprite,
}
props.object = door
function door:getHealth() return self.health end
function door:getMaxHealth() return self.maxHealth end
function door:getObjectIndex() return self.objectIndex end
function door:getSquare() return self.square end
function door:getSprite() return self.sprite end
square.objects = list({ door })
function square:getObjects() return self.objects end

ISMoveableSpriteProps = {
    fromObjectForRepair = function(object)
        return object == door and props or nil
    end,
}

function character:getCurrentSquare() return approach end

getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            if x == 10 and y == 10 and z == 0 then return square end
            return nil
        end,
    }
end

local base = {
    id = "base-repair",
    territory = { minX = 8, minY = 8, maxX = 12, maxY = 12, z = 0 },
    zones = {},
}

local repairs = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseRepairs.lua")
local target, result = repairs.findTask(base, character)
assert(target ~= nil and result == "found")
assert(target.action == "repair" and target.objectIndex == 2)
assert(target.requiredItems["Base.Hammer"] == 1)
assert(target.requiredItems["Base.Screwdriver"] == 1)
assert(target.requiredItems["Base.Plank"] == 2)
assert(target.requiredItems["Base.Nails"] == 4)
assert(target.requiredItems["Base.Screws"] == nil)

local resolved = assert(repairs.resolveTarget(base, target, character))
assert(resolved.object == door and resolved.approach == approach)
local before = repairs.snapshot(resolved)
local action = assert(repairs.queueAction(character, resolved))
assert(action.kind == "repair" and queued == action)
assert(equipped.primary == hammer and equipped.secondary == screwdriver)

local maskContainer = {}
local mask = item("Base.WeldingMask")
mask.className = "Clothing"
function mask:getContainer() return maskContainer end
secondaryTool = mask
function character:isEquippedClothing() return false end
local metalAction = assert(repairs.queueAction(character, resolved))
assert(metalAction.kind == "repair" and wearQueued == 1 and transferQueued == 1,
    "off-slot welding mask should use character-bound transfer and wear actions")
secondaryTool = screwdriver
door.health = 100
assert(repairs.isComplete(resolved, before))

local none, noneResult = repairs.findTask(base, character)
assert(none == nil and noneResult == "no_repair_ready")
door.health = 10
none, noneResult = repairs.findTask(base, character)
assert(none == nil and noneResult == "no_repair_ready")

print("Base repairs PASS structure_scan=true vanilla_validation=true requirements=true action=true offslot_welding_mask=true health_verification=true")

door.health=50
assert(repairs.findTask(base,character,function() return false end)==nil)
local otherDoor=setmetatable({objectIndex=3},{__index=door})
ISMoveableSpriteProps.fromObjectForRepair=function(object)
    if object==door or object==otherDoor then return props end
end
square.objects=list({door,otherDoor})
local alternate=assert(repairs.findTask(base,character,function(candidate) return candidate.objectIndex~=2 end))
assert(alternate.objectIndex==3,"occupied repair object cannot hide another valid repair")
square.objects=list({otherDoor})
assert(repairs.resolveTarget(base,target,character)==nil,
    "a removed target must not silently substitute another object with the same sprite")
print("Repair crew selection PASS exclusion=true alternate_object=true stale_identity=true")

-- Discover from actual stock without lending a virtual inventory to native validation.
square.objects=list({door});door.objectIndex=2;door.health=50
inventoryItems={}
local stock={hammer,screwdriver,item("Base.Plank"),item("Base.Plank"),
    item("Base.Screws"),item("Base.Screws"),item("Base.Screws"),item("Base.Screws")}
local definitions={tools={"Base.Hammer"},tools2={"Base.Screwdriver"}}
ISMoveableDefinitions={getInstance=function() return {getRepairDefinition=function(material)
    assert(material=="Wood");return definitions
end} end}
props.material="Wood"
function props:hasRepairTool(worker,second)
    local choices=second and definitions.tools2 or definitions.tools
    if #choices==0 then return true end
    for _,value in ipairs(inventoryItems) do
        for _,full in ipairs(choices) do
            if value:getFullType()==full then return value end
        end
    end
    return false
end
local structurallyValid=true
function props:canRepairObject(worker)
    assert(worker==character and worker:getInventory()==inventory,
        "discovery must not replace or fabricate the worker inventory")
    return {craftValid=structurallyValid,canRepair=structurallyValid
        and self:hasRepairTool(worker,false)~=false and self:hasRepairTool(worker,true)~=false
        and inventory:getItemCount("Base.Plank")>=2
        and (inventory:getItemCount("Base.Nails")>=4 or inventory:getItemCount("Base.Screws")>=4)}
end
local planner=KnoxBaseSupplyPlanner
KnoxBaseStorage={findItemType=function(owner,predicate)
    assert(owner==base)
    for _,value in ipairs(stock) do if predicate(value) then return value:getFullType(),value end end
end,requirementsAvailable=function(owner,worker,requirements)
    assert(owner==base and worker==character)
    for full,count in pairs(requirements.items) do
        local have=planner.inventoryCount(inventory,full,requirements)
        for _,value in ipairs(stock) do
            if value:getFullType()==full and planner.matchesRequirement(value,requirements) then have=have+1 end
        end
        if have<count then return false end
    end
    return true
end}
local stored=assert(repairs.findTask(base,character))
assert(stored.requiredItems["Base.Hammer"]==1 and stored.requiredItems["Base.Screwdriver"]==1)
assert(stored.requiredItems["Base.Plank"]==2 and stored.requiredItems["Base.Screws"]==4
    and stored.requiredItems["Base.Nails"]==nil,"choose one fully stocked optional recipe alternative")
assert(stored.requiredItemRules["Base.Hammer"].usable and #inventoryItems==0)
assert(repairs.resolveTarget(base,stored,character)==nil,"remote stock cannot authorize native work")
local previous=queued
assert(repairs.queueAction(character,resolved)==nil and queued==previous,
    "a cached target must still validate current carried supplies")
local removed=table.remove(stock)
assert(repairs.findTask(base,character)==nil,"partial optional stock cannot start a repair")
stock[#stock+1]=removed
structurallyValid=false
assert(repairs.findTask(base,character)==nil,"stock never overrides native structural invalidity")
structurallyValid=true
-- Model the result of native delivery; discovery itself leaves these lists unchanged.
inventoryItems=stock;stock={}
local delivered=assert(repairs.resolveTarget(base,stored,character))
assert(repairs.queueAction(character,delivered),"the actual repair is allowed after real supplies arrive")

-- Drainable parts require one sufficiently charged item, not several empty copies.
inventoryItems={}
local resin=item("Base.Resin");resin.uses=3
function resin:getCurrentUses() return self.uses end
local torch=item("Base.BlowTorch");torch.fuel=0.2
function torch:getCurrentUsesFloat() return self.fuel end
stock={torch,resin}
definitions.tools,definitions.tools2={"Base.BlowTorch"},{}
ScriptManager={instance={FindItem=function(_,full)
    return full=="Base.Resin" and {className="DrainableComboItem"} or nil
end}}
props.getAllRepairParts=function() return {{itemType="Base.Resin",amount=3,required=true}} end
stored=assert(repairs.findTask(base,character))
assert(stored.requiredItems["Base.Resin"]==1 and stored.requiredItemRules["Base.Resin"].minUses==3)
assert(stored.requiredItemRules["Base.BlowTorch"].minUsesFloat==0.1)
resin.uses=2
assert(repairs.findTask(base,character)==nil,"insufficient charge is not a complete repair part")
resin.uses=3;torch.fuel=0.05
assert(repairs.findTask(base,character)==nil,"depleted welding tools cannot satisfy repair supplies")
torch.fuel=0.2;torch.isBroken=function() return true end
assert(repairs.findTask(base,character)==nil,"broken stored tools are rejected")
print("Repair cupboard supplies PASS native_inventory_unchanged=true physical_delivery=true alternative_parts=true shortages=true drainable=true usable_torch=true native_validation=true")

local goodTorch=item("Base.BlowTorch")
function goodTorch:getCurrentUsesFloat() return 0.3 end
torch.isBroken=function() return false end;torch.fuel=0.01
inventoryItems={torch,goodTorch};stock={resin}
assert(repairs.findTask(base,character),"a depleted first match must not hide another usable carried tool")
props.canRepairObject=function() return {craftValid=true,canRepair=true} end
local torchTarget={object=door,props=props,square=square,spriteName=sprite.name}
assert(repairs.queueAction(character,torchTarget) and equipped.primary==goodTorch,
    "execution equips the usable carried alternative, never the first depleted duplicate")
print("Repair duplicate tools PASS usable_carried_alternative=true")
