local root = arg[1] or "."
require = function() end
Events = { OnFillWorldObjectContextMenu = { Add = function() end } }
local fed = {}
KnoxActivityFeed = { event = function(message) fed[#fed + 1] = message end }

local zombie = { cleared = false }
function zombie:setTarget() end
function zombie:setUseless() self.cleared = true end
function zombie:setCanWalk() end
function zombie:removeFromWorld() end
function zombie:removeFromSquare() end
local friend = {}
local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end
local origin = {
    getX = function() return 100 end, getY = function() return 100 end, getZ = function() return 0 end,
}
local nearSquare = { getMovingObjects = function() return list({ zombie, friend }) end }
local farSquare = { getMovingObjects = function() return list({ zombie }) end }
getCell = function()
    return { getGridSquare = function(_, x, y, z)
        if x == 100 and y == 100 then return nearSquare end
        return nil
    end }
end
instanceof = function(object, class) return object == zombie and class == "IsoZombie" end
local actor = { getCurrentSquare = function() return origin end }
getSpecificPlayer = function() return actor end

local tools = dofile(root .. "/mod/42/media/lua/client/KS_DeveloperTools.lua")
tools.calmTestScene(0)
assert(zombie.cleared == true, "zombies near the player must be cleared")
assert(fed[#fed] ~= nil and string.find(fed[#fed], "cleared 1 zombies", 1, true) ~= nil,
    "calm scene must report its clearing, got: " .. tostring(fed[#fed]))

print("Calm test scene PASS cleared=true reported=true")
