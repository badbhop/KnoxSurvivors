local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

-- Java must never latch forceGetUp: vanilla pulses it on discrete input, so
-- a latched flag stands every later knockdown up instantly. Both the combat
-- entry and the teardown must actively clear it.
local combat = read(root .. "/java/src/main/java/com/knoxsurvivors/npc/KnoxCombatController.java")
assert(not string.find(combat, '"forceGetUp", true', 1, true),
    "no latched get-up may remain in native combat")
assert(string.find(combat, '"forceGetUp", false', 1, true),
    "native combat must clear stale get-up latches")

-- Lua rest exit pulses then disarms on standing: the next knockdown keeps
-- the native player-like timer.
local variables = {}
local character = {
    isSitOnGround = function() return true end,
    isSittingOnFurniture = function() return false end,
    setVariable = function(_, key, value) variables[key] = value end,
    setIsResting = function() end,
    setBed = function() end,
    wakeForDanger = function() end,
}
KnoxSurvivorNeeds = { wakeForDanger = function() end }
local c = setmetatable({ id = "parity", character = character }, Controller)
c:leaveRecoveryPosture()
assert(variables.forceGetUp == true and c.forceGetUpLatched == true,
    "rest exit pulses get-up once and arms the disarm")
local source = read(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
assert(string.find(source, "forceGetUpLatched", 1, true)
    and string.find(source, "knocked_down", 1, true)
    and string.find(source, "stood_up", 1, true),
    "knockdown timing must stay observable through disarm telemetry")

print("Knockdown parity PASS no_latch=true pulse_disarm=true telemetry=true")
