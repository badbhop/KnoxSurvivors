local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController
instanceof = function(object, class)
    return class == "IsoZombie" and type(object) == "table" and object.__zombie == true
end
getNumActivePlayers = function() return 0 end
getSpecificPlayer = function() return nil end

local function tile(x, y)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return 0 end }
end
-- Nine tiles out: past ordinary notice, inside a dawn sweep.
local zombie = {
    __zombie = true,
    isDead = function() return false end,
    getCurrentSquare = function() return tile(9, 0, 0) end,
    getTarget = function() return nil end,
    CanSee = function() return true end,
}
local character = {
    getCurrentSquare = function() return tile(0, 0, 0) end,
    CanSee = function() return true end,
}
local function controller()
    return setmetatable({
        id = "sweeper",
        character = character,
        currentTicks = 5000,
        combatTarget = nil,
        companionOrder = nil,
        groupMembers = {},
        reservations = { threats = {}, items = {}, restSpots = {} },
        failedThreats = {},
        perceivedThreats = {},
    }, Controller)
end

local c = controller()
assert(c:evaluateCombatThreat(zombie, 5000) == nil,
    "a distant yard zombie must not interrupt the routine")

c = controller()
c.nightSweepUntil = 6000
local awareness = c:evaluateCombatThreat(zombie, 5000)
assert(awareness ~= nil, "a dawn sweep must clear the gathered yard first")

c = controller()
c.nightSweepUntil = 4000
assert(c:evaluateCombatThreat(zombie, 5000) == nil, "expired sweeps must not linger")

print("Dawn sweep PASS quiet=true sweep=true expiry=true")
