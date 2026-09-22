local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController
KnoxFirearmSupport = {}

local function characterAt(x, y, z, primary)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        getPrimaryHandItem = function() return primary end,
    }
end
local function targetAt(x, y, z)
    return { getX = function() return x end, getY = function() return y end, getZ = function() return z end }
end
local function controller(character)
    return setmetatable({ id = "fighter", character = character, reloadYieldStreak = 0 }, Controller)
end

-- Repeated checks must not exhaust a native animation-driven reload budget.
local c = controller(characterAt(0, 0, 0))
local far = targetAt(10, 0, 0)
assert(c:reloadYieldDecision(100, far, "reloading") == nil)
assert(c:reloadYieldDecision(200, far, "reloading") == nil)
assert(c:reloadYieldDecision(300, far, "reloading") == nil)
for index = 1, 100 do
    assert(c:reloadYieldDecision(300, far, "reloading") == nil,
        "duplicate checks do not consume preparation time")
end
assert(c:reloadYieldDecision(1899, far, "reloading") == nil)
assert(c:reloadYieldDecision(1900, far, "reloading") == "reload_stalled",
    "a reload that never resolves must fall back to melee")
-- A ready gun resets the streak.
assert(c:reloadYieldDecision(2000, far, "ready") == nil)
assert(c.reloadYieldStreak == 0)
assert(c.reloadPreparationStartedAt == nil)
assert(c:reloadYieldDecision(3000, far, "needs_preparation") == nil)
assert(c:reloadYieldDecision(3000, far, "reloading") == nil,
    "preparation and reload checks within one tick share one budget")
assert(c:reloadYieldDecision(4800, far, "reloading") == "reload_stalled")

-- A point-blank zombie never waits through a reload.
c = controller(characterAt(0, 0, 0))
local near = targetAt(1, 1, 0)
assert(c:reloadYieldDecision(100, near, "reloading") == "close_threat")
assert(c.reloadYieldStreak == 0, "close-threat fallback must not consume the stall budget")
-- Different floors are never close.
local above = targetAt(1, 1, 1)
assert(c:reloadYieldDecision(100, above, "reloading") == nil)

-- Armed hands pass the gate; empty hands with no equip bridge fail loudly.
local bat = {
    IsWeapon = function() return true end,
    isRanged = function() return false end,
    isBroken = function() return false end,
}
c = controller(characterAt(0, 0, 0, bat))
local armed, reason = c:ensureMeleeHands(far)
assert(armed == true and reason == "already_armed")
c = controller(characterAt(0, 0, 0, nil))
armed, reason = c:ensureMeleeHands(far)
assert(armed == false and reason == "melee_pull_unavailable",
    "a carried-but-unequipped blade must block empty-handed combat, got " .. tostring(reason))
c = controller({})
armed, reason = c:ensureMeleeHands(far)
assert(armed == true and reason == "primary_unverifiable")

print("Combat reload PASS stall_fallback=true close_fallback=true melee_gate=true")
