local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["BuildingObjects/ISBuildIsoEntity"] = true
package.loaded["BuildingObjects/TimedActions/ISBuildAction"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
package.loaded["Util/AdjacentFreeTileFinder"] = true

local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end

ArrayList = { new = function() return { add = function(self, value) self[#self + 1] = value end } end }
AdjacentFreeTileFinder = { Find = function(square) return square end }

local queued = nil
ISTimedActionQueue = { add = function(action) queued = action end }
ISBuildAction = { new = function(_, character, build, x, y, z, north, sprite, time)
    return { character = character, build = build, x = x, y = y, z = z,
        north = north, sprite = sprite, time = time }
end }

local infos = {}
SpriteConfigManager = { GetObjectInfo = function(name) return infos[name] end }
ISBuildIsoEntity = { new = function(character, info, nSprite)
    local logic = {
        started = false,
        startCraftAction = function(self) self.started = true end,
        canPerformCurrentRecipe = function() return true end,
        stopCraftAction = function(self) self.stopped = true end,
    }
    return {
        character = character, info = info, nSprite = nSprite, maxTime = 200,
        buildPanelLogic = logic,
        getSprite = function(self) self.north = self.nSprite == 2; return "sprite" end,
        isValid = function() return true end,
    }
end }

local squares = {}
local function square(x, y, z)
    local key = x .. ":" .. y .. ":" .. z
    if squares[key] then return squares[key] end
    local value = { x = x, y = y, z = z, objects = {}, special = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getObjects() return list(self.objects) end
    function value:getSpecialObjects() return list(self.special) end
    squares[key] = value
    return value
end
getCell = function() return { getGridSquare = function(_, x, y, z) return square(x, y, z) end } end

local function item(fullType)
    return { getFullType = function() return fullType end, isBroken = function() return false end }
end
local inventory = {
    items = { item("Base.Hammer") },
    counts = { ["Base.Plank"] = 20, ["Base.Nails"] = 40, ["Base.Hinge"] = 4, ["Base.Doorknob"] = 2 },
}
function inventory:getItems() return list(self.items) end
function inventory:getItemCount(kind) return self.counts[kind] or 0 end
local character = { inventory = inventory }
function character:getInventory() return self.inventory end
function character:setPrimaryHandItem(value) self.primary = value end

for _, entity in ipairs({ "WoodenWallFrame", "WoodenWallLvl1", "WoodDoorFrameLvl1", "WoodenDoorLvl1" }) do
    infos[entity] = { name = entity }
end

local construction = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseConstruction.lua")
local base = { id = "base-1", zones = {
    edge = { id = "edge", type = "construction", x1 = 10, y1 = 10, x2 = 14, y2 = 14, z = 0 },
} }

local task = assert(construction.findTask(base, character))
assert(task.kind == "door_frame" and task.x == 12 and task.y == 14 and task.north,
    "perimeter builds its access frame before wall segments")
local requirements = assert(construction.requirements(task, character))
assert(requirements.items["Base.Hammer"] == 1 and requirements.items["Base.Plank"] == 4
    and requirements.skills.Woodwork == 2, "door frame retains vanilla materials and skill")

local gate = square(12, 14, 0)
gate.special = { { getName = function() return "WoodDoorFrameLvl1" end,
    getNorth = function() return true end } }
task = assert(construction.findTask(base, character))
assert(task.kind == "door", "frame upgrades to a real door before perimeter walls")

gate.special = { { getName = function() return "WoodenDoorLvl1" end,
    getNorth = function() return true end } }
task = assert(construction.findTask(base, character))
assert(task.kind == "wall_frame", "sealed gate advances construction to wall frames")
local resolved = assert(construction.resolveTarget(base, task, character))
assert(resolved.approach ~= nil and resolved.info == infos.WoodenWallFrame,
    "construction target resolves through active-world entity scripts")
local action = assert(construction.queueAction(character, resolved))
assert(queued == action and character.primary:getFullType() == "Base.Hammer",
    "construction queues vanilla action with the NPC-owned hammer")
resolved.square.special = { { getName = function() return "WoodenWallFrame" end,
    getNorth = function() return resolved.target.north end } }
assert(construction.isComplete(resolved), "completion requires the actual expected world object")

print("Base construction PASS perimeter=true gate_first=true materials=true entity_action=true completion=true")

-- The intentional gate on one side must not leave a matching hole opposite it.
local function builtWall(north)
    return { getName = function() return "WoodenWallLvl1" end, getNorth = function() return north end }
end
for x = 10, 14 do
    square(x, 10, 0).special = {builtWall(true)}
    if x ~= 12 then square(x, 14, 0).special = {builtWall(true)} end
end
for y = 11, 13 do
    square(10, y, 0).special = {builtWall(false)}
    square(14, y, 0).special = {builtWall(false)}
end
square(12, 10, 0).special = {}
local gapTask = assert(construction.findTask(base, character), "perimeter must finish the wall opposite its gate")
assert(gapTask.x == 12 and gapTask.y == 10 and gapTask.kind == "wall_frame")
square(12, 10, 0).special = {builtWall(true)}
assert(not construction.findTask(base, character), "completed perimeter cannot repeatedly queue replacement frames")
square(12, 10, 0).special = {}

-- A builder must be able to start from the communal cupboard with empty hands.
inventory.items, inventory.counts = {}, {}
local storedHammer = item("Base.Hammer")
local stock = { ["Base.Hammer"] = 1, ["Base.Plank"] = 20, ["Base.Nails"] = 40,
    ["Base.Hinge"] = 2, ["Base.Doorknob"] = 1 }
local supplyChecks = 0
KnoxBaseStorage = {
    findItemType = function(owner, predicate)
        assert(owner == base)
        if stock["Base.Hammer"] > 0 and predicate(storedHammer) then return "Base.Hammer", storedHammer end
    end,
    requirementsAvailable = function(owner, actor, required)
        assert(owner == base and actor == character)
        assert(required.itemRules["Base.Hammer"].usable)
        supplyChecks = supplyChecks + 1
        for kind, count in pairs(required.items) do
            if (stock[kind] or 0) < count then return false end
        end
        return true
    end,
}
local suppliedTask = assert(construction.findTask(base, character), "cupboard materials enable an empty-handed builder")
local suppliedRequirements = assert(construction.requirements(suppliedTask, character, base))
assert(suppliedRequirements.items["Base.Hammer"] == 1)
local suppliedTarget = assert(construction.resolveTarget(base, suppliedTask, character))
local beforeQueue = queued
assert(not construction.queueAction(character, suppliedTarget) and queued == beforeQueue,
    "cupboard discovery does not skip native item delivery before building")
stock["Base.Plank"] = 0
supplyChecks = 0
assert(not construction.findTask(base, character), "insufficient real stock cannot create a construction task")
assert(supplyChecks <= 4, "unavailable materials are checked once per construction stage, not per perimeter tile")
print("Cupboard construction PASS discovery=true native_delivery_required=true shortage=true bounded=true")
