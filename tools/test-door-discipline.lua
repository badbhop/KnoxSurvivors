local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

local toggled = 0
local function door(open)
    return {
        IsOpen = function() return open end,
        getSquare = function() return {} end,
        ToggleDoor = function() toggled = toggled + 1 end,
    }
end
KnoxBaseManager = { containsSquare = function() return false end }

local function controller(fields)
    fields.id = "walker"
    fields.character = {}
    fields.openedDoors = { [door(true)] = true }
    return setmetatable(fields, Controller)
end

-- Companions close doors behind the party even outside owned territory.
toggled = 0
local c = controller({ base = {}, companionOrder = "follow", groupLeaderId = nil })
c:closeOpenedDoors()
assert(toggled == 1, "companions must close doors they opened")

-- Pair/group members behave the same.
toggled = 0
c = controller({ base = {}, companionOrder = nil, groupLeaderId = "leader" })
c:closeOpenedDoors()
assert(toggled == 1, "group members must close doors they opened")

-- Independents keep the old territory-only rule outside a base.
toggled = 0
c = controller({ base = {}, companionOrder = nil, groupLeaderId = nil })
c:closeOpenedDoors()
assert(toggled == 0, "independents must not trap others outside territory")

-- Without base context the historical default still closes.
toggled = 0
c = controller({ base = nil, companionOrder = nil, groupLeaderId = nil })
c:closeOpenedDoors()
assert(toggled == 1, "unowned context keeps closing")

print("Door discipline PASS companion=true group=true independent=true")
