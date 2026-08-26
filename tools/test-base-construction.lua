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
