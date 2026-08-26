local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["TimedActions/ISChopTreeAction"] = true
package.loaded["TimedActions/ISCraftAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
ItemTag = { CHOP_TREE = "CHOP_TREE", SAW = "SAW" }
ISChopTreeAction = {
    new = function(_, character, tree)
        return { kind = "chop_tree", character = character, tree = tree }
    end,
}
ISCraftAction = {
    new = function(_, character, item, recipe, container, containers)
        return { kind = "saw_logs", character = character, item = item,
            recipe = recipe, container = container, containers = containers }
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

local axe = { full = "Base.Axe", broken = false }
function axe:getFullType() return self.full end
function axe:hasTag(tag) return tag == ItemTag.CHOP_TREE end
function axe:isBroken() return self.broken end
local log = { full = "Base.Log", id = 17, container = true }
function log:getFullType() return self.full end
function log:getID() return self.id end
function log:getContainer() return self.container and {} or nil end
local saw = { full = "Base.Saw", broken = false }
function saw:getFullType() return self.full end
function saw:hasTag(tag) return tag == ItemTag.SAW end
function saw:isBroken() return self.broken end
local inventory = {}
local inventoryItems = { axe }
function inventory:getItems() return list(inventoryItems) end
local character = {}
function character:getInventory() return inventory end
function character:setPrimaryHandItem(item) self.primary = item end

ArrayList = { new = function()
    local values = {}
    return {
        add = function(_, value) values[#values + 1] = value end,
        values = values,
    }
end }
local recipe = { name = "Base.SawLogs" }
getScriptManager = function()
    return { getRecipe = function(_, name) return name == recipe.name and recipe or nil end }
end
RecipeManager = {
    IsRecipeValid = function(value, owner, selected, containers)
        return value == recipe and owner == character and selected == log
            and containers ~= nil
    end,
}

local tree = { objectIndex = 4 }
function tree:getObjectIndex() return self.objectIndex end
local square = { x = 10, y = 20, z = 0 }
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end
function square:HasTree() return tree.objectIndex >= 0 end
function square:getTree() return tree end

getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            return x == 10 and y == 20 and z == 0 and square or nil
        end,
    }
end

local base = {
    id = "base-woodcutting",
    zones = {
        timber = {
            id = "timber",
            type = "woodcutting",
            x1 = 10, y1 = 20, x2 = 10, y2 = 20, z = 0,
            enabled = true,
        },
    },
}

local woodcutting = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseWoodcutting.lua")
assert(woodcutting.findAxe(character) == axe)
local target, result = woodcutting.findTask(base, character)
assert(target ~= nil and result == "found")
assert(target.action == "chop_tree" and target.objectIndex == 4)
local resolved = assert(woodcutting.resolveTarget(base, target, character))
local action = assert(woodcutting.queueAction(character, resolved))
assert(action.kind == "chop_tree" and queuedAction == action)
assert(character.primary == axe)
tree.objectIndex = -1
assert(woodcutting.isComplete(resolved), "removed tree should complete the task")
table.insert(inventoryItems, log)
table.insert(inventoryItems, saw)

local sawTarget, sawResult = woodcutting.findTask(base, character)
assert(sawTarget ~= nil and sawResult == "saw_logs")
local sawResolved = assert(woodcutting.resolveTarget(base, sawTarget, character))
local sawAction = assert(woodcutting.queueAction(character, sawResolved))
assert(sawAction.kind == "saw_logs" and queuedAction == sawAction)
log.container = false
assert(woodcutting.isComplete(sawResolved), "consumed log should complete sawing")

print("Base woodcutting PASS axe_gate=true target_discovery=true chop=true saw_logs=true completion=true")
