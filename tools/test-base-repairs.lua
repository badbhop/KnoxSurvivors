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
