local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["TimedActions/ISBarricadeAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
package.loaded["Util/AdjacentFreeTileFinder"] = true
ISBarricadeAction = {
    new = function(_, character, object, isMetal, isMetalBar)
        return {
            character = character,
            object = object,
            isMetal = isMetal,
            isMetalBar = isMetalBar,
            isValid = function() return true end,
        }
    end,
}
ISTimedActionQueue = {
    add = function(action) _G.queuedAction = action end,
}

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function item(full)
    local value = { full = full }
function value:getFullType() return self.full end
function value:IsInventoryContainer() return false end
function value:isBroken() return false end
function value:hasTag(tag)
    return (tag == "hammer" or (ItemType ~= nil and tag == ItemType.HAMMER)
        or (ItemTag ~= nil and tag == ItemTag.HAMMER))
        and (self.full == "Base.Hammer" or self.full == "Base.HammerForged")
end
    return value
end

local items = { item("Base.Hammer"), item("Base.Plank"), item("Base.Nails"), item("Base.Nails") }
local inventory = {}
function inventory:getItems() return list(items) end
function inventory:getItemCount(full)
    local count = 0
    for _, value in ipairs(items) do
        if value:getFullType() == full then count = count + 1 end
    end
    return count
end
local character = { primary = nil, secondary = nil }
function character:getInventory() return inventory end
function character:setPrimaryHandItem(value) self.primary = value end
function character:setSecondaryHandItem(value) self.secondary = value end

local barricade = nil
local object = {}
function object:getObjectIndex() return 4 end
function object:getBarricadeForCharacter() return barricade end
function object:IsOpen() return false end
local square = {}
function square:getX() return 10 end
function square:getY() return 20 end
function square:getZ() return 0 end
function square:getObjects() return list({ object }) end
local approachSquare = { id = "window-side" }
AdjacentFreeTileFinder = {
    FindWindowOrDoor = function(targetSquare, targetObject, actor)
        assert(targetSquare == square and targetObject == object and actor == character,
            "barricade approach must use the exact native window/door arguments")
        return approachSquare
    end,
}
local base = {
    id = "base-1",
    home = { z = 0 },
    territory = { minX = 10, minY = 20, maxX = 10, maxY = 20 },
}
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        return x == 10 and y == 20 and z == 0 and square or nil
    end }
end

local barricades = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseBarricades.lua")
assert(barricades.canPrepare(character), "carried hammer, plank, and nails should be sufficient")
local target, targetResult = barricades.findTarget(base, character)
assert(target ~= nil and targetResult == "found")
assert(target.objectIndex == 4 and target.zoneType == "barricade")
local resolved, resolvedResult = barricades.resolveTarget(base, target, character)
assert(resolved ~= nil and resolvedResult == "resolved")
assert(barricades.isTargetValid(resolved, character), "resolved opening should remain valid")
local cachedApproach, cachedApproachResult = barricades.approachResolved(resolved, character)
assert(cachedApproach == approachSquare and cachedApproachResult == "resolved",
    "cached target must preserve the native side-aware approach")
local approach, approachResult = barricades.approachSquare(base, target, character)
assert(approach == approachSquare and approachResult == "resolved",
    "barricade movement must use the native side-aware window approach")
assert(barricades.plankCount(resolved, character) == 0)
local action, actionResult = barricades.queueAction(character, resolved)
assert(action ~= nil and actionResult == "queued" and queuedAction == action)
assert(character.primary == items[1] and character.secondary == items[2])

-- The native timed action accepts tagged hammers. It rejects some blunt tools
-- that the old Knox allow-list incorrectly admitted, so they must never be
-- selected for a wooden window barricade.
local mallet = item("Base.WoodenMallet")
assert(not barricades.findHammer({ getInventory = function()
    return { getItems = function() return list({ mallet }) end }
end }), "non-native hammer tools must not be selected")

barricade = { getNumPlanks = function() return 1 end, canAddPlank = function() return true end }
assert(barricades.isComplete(resolved, character, 0), "new plank should be observable")
assert(barricades.isTargetComplete(base, target, character),
    "a window secured while another worker traveled must satisfy its stale claim")

function object:getObjectIndex() return -1 end
assert(not barricades.isTargetValid(resolved, character), "removed opening must invalidate cached target")
function object:getObjectIndex() return 4 end

-- A streamed object update may allocate a new index. The saved sprite
-- fingerprint still resolves the sole eligible opening instead of blocking it.
local streamedObject = setmetatable({}, { __index = object })
function streamedObject:getObjectIndex() return 17 end
function streamedObject:getSprite() return { getName = function() return "fixtures/window" end } end
function object:getSprite() return { getName = function() return "fixtures/window" end } end
function square:getObjects() return list({ streamedObject }) end
target.objectIndex, target.spriteName = 4, "fixtures/window"
barricade = nil
local streamed = assert(barricades.resolveTarget(base, target, character))
assert(streamed.object == streamedObject, "sprite fingerprint must survive object-index churn")
function square:getObjects() return list({ object }) end

-- Automatic defense must not board the only usable door and strand every
-- other base job behind it.
local door = setmetatable({}, { __index = object })
function door:getObjectIndex() return 6 end
function door:isDoor() return true end
instanceof = function(value, class)
    return class == "BarricadeAble" or (value == door and class == "IsoThumpable")
end
function square:getObjects() return list({ door, object }) end
local windowOnly = assert(barricades.findTarget(base, character))
assert(windowOnly.objectIndex == 4, "automatic barricades must leave doors usable")
instanceof = nil
function square:getObjects() return list({ object }) end

-- Door classification must remain fail-closed even during an early/modded
-- load order where the global instanceof helper is temporarily unavailable.
function square:getObjects() return list({ door, object }) end
local fallbackWindow = assert(barricades.findTarget(base, character))
assert(fallbackWindow.objectIndex == 4,
    "door predicate must exclude doors without instanceof")
function square:getObjects() return list({ object }) end

print("Base barricades PASS target_discovery=true native_approach=true cached_target=true material_gate=true vanilla_action=true completion=true door-filter=true")

local cupboardItems = items
items = {}
KnoxBaseStorage = {
    findItemType = function(owner, predicate)
        assert(owner == base)
        for _, value in ipairs(cupboardItems) do
            if predicate(value) then return value:getFullType(), value end
        end
    end,
    requirementsAvailable = function(owner, actor, required)
        assert(owner == base and actor == character and required.itemRules["Base.Hammer"].usable)
        local counts = {}
        for _, value in ipairs(cupboardItems) do
            local full = value:getFullType()
            counts[full] = (counts[full] or 0) + 1
        end
        for full, count in pairs(required.items) do
            if (counts[full] or 0) < count then return false end
        end
        return true
    end,
}
assert(barricades.canPrepare(character, base), "stored materials enable barricade discovery")
assert(barricades.findHammer(character, base) == cupboardItems[1])
local previousAction = queuedAction
local _, queueReason = barricades.queueAction(character, resolved, base)
assert(queuedAction == previousAction and queueReason == "missing_carried_hammer_or_plank",
    "execution needs carried items even when storage holds them")
table.remove(cupboardItems)
assert(not barricades.canPrepare(character, base), "one nail cannot satisfy the two-nail recipe")
print("Cupboard barricades PASS discovery=true native_delivery_required=true material_counts=true")

barricade=nil
local secondObject=setmetatable({},{__index=object})
function secondObject:getObjectIndex() return 5 end
function square:getObjects() return list({object,secondObject}) end
local nextTarget=assert(barricades.findTarget(base,character,function(candidate) return candidate.objectIndex~=4 end))
assert(nextTarget.objectIndex==5,"busy opening must not hide another barricade target")
assert(barricades.findTarget(base,character,function() return false end)==nil)
print("Barricade crew selection PASS alternate_opening=true exclusion=true")

-- A fully barricaded opening must resolve as no-longer-valid (not workable)
-- so callers take the already-secured path instead of failing the task.
barricade = { getNumPlanks = function() return 4 end, canAddPlank = function() return false end }
function square:getObjects() return list({ object }) end
local completeTarget = { id = "barricade:base-1:10:20:0:4", x = 10, y = 20, z = 0, objectIndex = 4, spriteName = "" }
assert(barricades.resolveTarget(base, completeTarget, character) == nil,
    "fully barricaded window must not resolve as workable")
assert(barricades.isTargetComplete(base, completeTarget, character),
    "fully barricaded window must satisfy its stale claim")
barricade = nil

KnoxSettings = { ignoreJobResourceRequirements = function() return true end }
items, cupboardItems = {}, {}
assert(barricades.canPrepare(character, base), "free mode discovers work without stocked storage")
assert(not barricades.canPrepare(character), "native execution still requires carried supplies")
assert(select(2, barricades.queueAction(character, resolved, base)) == "missing_carried_hammer_or_plank")
