local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["TimedActions/ISChopTreeAction"] = true
package.loaded["Entity/TimedActions/ISHandcraftAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
ItemTag = { CHOP_TREE = "CHOP_TREE", SAW = "SAW" }
ISChopTreeAction = {
    new = function(_, character, tree)
        return { kind = "chop_tree", character = character, tree = tree }
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
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
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
print("Base woodcutting PASS axe_gate=true target_discovery=true native_chop=true completion=true")

-- A loaded log-processing zone can produce a real native handcraft job.
getScriptManager = function() return { getCraftRecipe = function(_, name)
    return name == "Base.SawLogs" and recipe or nil end } end
local craftValid = true
HandcraftLogic = { new = function()
    return { setContainers = function() end, setRecipe = function() end,
        canPerformCurrentRecipe = function() return craftValid end }
end }
ISHandcraftAction = { new = function(_, owner, selectedRecipe, containers)
    assert(owner == character and selectedRecipe == recipe and containers ~= nil)
    return { craftStarted = false, character = owner }
end }
function square:canStand() return true end
inventoryItems = { log, saw }
target = assert(woodcutting.findTask(base, character))
assert(target.action == "saw_logs", "carried log and saw discover processing work")
resolved = assert(woodcutting.resolveTarget(base, target, character))
action = assert(woodcutting.queueAction(character, resolved))
assert(not woodcutting.isComplete(resolved), "queue acceptance is not log consumption")
local directAction = assert(woodcutting.queueSawLogs(character))
assert(directAction.character == character and queuedAction == directAction,
    "an explicit saw-logs order must queue the survivor as the action owner")
action.craftStarted = true
assert(not woodcutting.isComplete(resolved), "started crafting alone is not completion")
inventoryItems = { saw }
assert(not woodcutting.isComplete(resolved), "a missing log alone does not prove crafting")
action.logic = { getCreatedOutputItems = function(_, output)
    output:add({ getFullType = function() return "Base.Plank" end })
end }
assert(woodcutting.isComplete(resolved), "native output and log consumption prove processing")
inventoryItems = { log, saw }
craftValid = false
assert(woodcutting.resolveTarget(base, target, character) == nil,
    "invalid native recipe never executes")

base.zones.processing = { id = "processing", type = "log_processing",
    x1 = 9, y1 = 20, x2 = 10, y2 = 20, z = 0 }
local offsetTask = assert(woodcutting.findTask(base, character))
assert(offsetTask.zoneId == "processing" and offsetTask.x == 10,
    "unloaded or blocked first corner does not hide usable processing tiles")
print("Processing area fallback PASS")

tree.objectIndex=4
inventoryItems={axe}
local nextSquare=setmetatable({x=11,y=20,z=0},{__index=square})
getCell=function() return {getGridSquare=function(_,x,y,z)
    if y~=20 or z~=0 then return nil end
    if x==10 then return square elseif x==11 then return nextSquare end
end} end
base.zones.timber.x2=11
local nextTree=assert(woodcutting.findTask(base,character,function(candidate) return candidate.x~=10 end))
assert(nextTree.action=="chop_tree" and nextTree.x==11,"an unavailable tree cannot hide the next tree")
assert(woodcutting.findTask(base,character,function() return false end)==nil)
inventoryItems={log,saw,axe}
local sawSkipped=assert(woodcutting.findTask(base,character,function(candidate)
    return candidate.action~="saw_logs"
end))
assert(sawSkipped.action=="chop_tree","busy log processing must not hide available tree work")
print("Woodwork selection PASS next_tree=true unavailable=true other_work=true")
