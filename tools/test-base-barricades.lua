local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["TimedActions/ISBarricadeAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
ISBarricadeAction = {
    new = function(_, character, object, isMetal, isMetalBar)
        return {
            character = character,
            object = object,
            isMetal = isMetal,
            isMetalBar = isMetalBar,
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
assert(barricades.plankCount(resolved, character) == 0)
local action, actionResult = barricades.queueAction(character, resolved)
assert(action ~= nil and actionResult == "queued" and queuedAction == action)
assert(character.primary == items[1] and character.secondary == items[2])

barricade = { getNumPlanks = function() return 1 end, canAddPlank = function() return true end }
assert(barricades.isComplete(resolved, character, 0), "new plank should be observable")

print("Base barricades PASS target_discovery=true material_gate=true vanilla_action=true completion=true")
