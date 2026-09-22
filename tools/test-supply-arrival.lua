local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

-- A supply move that arrives must queue the native transfer. This regressed
-- when BASE_TASK_SUPPLY_MOVE fell out of the movement-polling block: every
-- fetch timed out instead of arriving, and residents looped cupboards forever.
local item = {}
local source = { contains = function(_, candidate) return candidate == item end }
local actorSquare = {
    getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
}
local actor = {
    getCurrentSquare = function() return actorSquare end,
    getCharacterActions = function() return { isEmpty = function() return true end } end,
    getInventory = function() return {} end,
}
local queued = 0
KnoxInventoryActions = { queueTransfer = function() queued = queued + 1 return {}, "queued" end }
KnoxActivityFeed = { speak = function() end, event = function() end }
local c = setmetatable({
    id = "worker",
    character = actor,
    state = "BASE_TASK_SUPPLY_MOVE",
    stateStartedAt = 0,
    nextThink = 0,
    nextThreatScan = 100000,
    base = {},
    baseTask = { id = "task-1", type = "barricade", state = "claimed", claimedBy = "worker" },
    baseTaskSupplyTransfer = { source = { container = source }, item = item },
    counts = { failures = 0 },
    failureReasons = {},
    recoverFromDetached = function() return false end,
    releaseBaseCooking = function() end,
    releaseSupply = function() end,
    releaseGroupSupport = function() end,
    releaseAmbientMovement = function() end,
    bridge = {
        cancelNpcMove = function() end,
        moveNpc = function() return "MOVE_STARTED" end,
        tickNpc = function() return "Succeeded" end,
    },
    finishBaseTask = function(self) self.baseTask = nil end,
    finishDecision = function(self) self.state = "IDLE" end,
}, Controller)

c:tick(10)
assert(queued == 1, "an arrived supply move must queue the native transfer")
assert(c.state == "BASE_TASK_SUPPLY_TRANSFER", "supply arrival must stage the transfer, got " .. tostring(c.state))

-- Structural guard: every state with a Succeeded-arrival branch must be
-- polled by the movement block, or its trips can only ever time out.
local source = assert(io.open(
    root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r")):read("*a")
local pollStart, pollEnd = string.find(source, "or self.state == \"BASE_TASK_SUPPLY_MOVE\"", 1, true)
assert(pollStart ~= nil, "supply moves must be movement-polled")

print("Supply arrival PASS transfer=true polled=true")
