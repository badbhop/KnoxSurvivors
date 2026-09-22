local root = arg[1] or "."
package.path = root .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["TimedActions/ISWashYourself"] = true
package.loaded["TimedActions/ISWashClothing"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
package.loaded["Util/AdjacentFreeTileFinder"] = true

local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end

local parts = { { blood = 1, dirt = 0 }, { blood = 0, dirt = 1 }, { blood = 1, dirt = 1 }, { blood = 0, dirt = 1 } }
-- Vanilla dot-call convention (no self): FromIndex(i) takes the bare index,
-- exactly like ISWashYourself. The old self-passing mock hid the static
-- dispatch bug that broke live washing.
BloodBodyPartType = {
    MAX = { index = function() return #parts end },
    FromIndex = function(index) return index end,
}
local visual = {
    getBlood = function(_, part) return parts[part + 1].blood end,
    getDirt = function(_, part) return parts[part + 1].dirt end,
}
local square = { getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end }
local actionsEmpty = true
local actor = {
    getHumanVisual = function() return visual end,
    getCurrentSquare = function() return square end,
    getCharacterActions = function() return { isEmpty = function() return actionsEmpty end } end,
}
local sink = { getFluidAmount = function() return 20 end }
local sinkSquare = {
    getX = function() return 12 end, getY = function() return 20 end, getZ = function() return 0 end,
    getObjects = function() return list({ sink }) end,
}
AdjacentFreeTileFinder = { Find = function(target) return target == sinkSquare and sinkSquare or nil end }
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        return x == 12 and y == 20 and z == 0 and sinkSquare or nil
    end }
end
local queued = nil
ISTimedActionQueue = {
    add = function(action) queued = action end,
    getTimedActionQueue = function() return { indexOf = function(_, action) return action == queued and 0 or -1 end } end,
    clear = function() queued = nil end,
}
ISWashYourself = { new = function(_, character, object) return { character = character, object = object } end }
ISWashClothing = {}

local hygiene = dofile(root .. "/mod/42/media/lua/client/KS_BaseHygiene.lua")
local base = { territory = { minX = 10, minY = 20, maxX = 12, maxY = 20, z = 0 } }
assert(hygiene.dirtyParts(actor) == 4 and hygiene.isNeeded(actor), "four dirty body parts need ambient hygiene")
local plan = assert(hygiene.find(actor, base))
assert(plan.object == sink and plan.approach == sinkSquare, "hygiene selects a reachable in-base water source")
local bridge = { moveNpc = function() return "MOVE_STARTED" end, tickNpc = function() return "Succeeded" end }
plan = assert(hygiene.begin(actor, base, bridge, "worker", 100))
assert(plan.phase == "move")
assert(hygiene.step(plan, actor, bridge, "worker", 101) == "working" and plan.phase == "washing" and queued ~= nil,
    "arrival queues the native washing action")
parts[1].blood, parts[2].dirt, parts[3].blood, parts[4].dirt = 0, 0, 0, 0
assert(hygiene.step(plan, actor, bridge, "worker", 102) == "complete", "completed native wash reduces visible dirt")
print("Base hygiene PASS threshold=true in_base_water=true native_action=true completion=true")
