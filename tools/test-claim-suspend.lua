local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

local square = {
    getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
}
local actor = {
    getCurrentSquare = function() return square end,
    getCharacterActions = function() return { isEmpty = function() return true end } end,
    getInventory = function() return {} end,
}
KnoxSurvivorNeeds = { decide = function() return { kind = "find_water" } end }
KnoxActivityFeed = { speak = function() end, event = function() end }
KnoxEquipmentIntelligence = { reconsider = function() end }
KnoxBaseCorpseHandling = { isDragging = function() return false end }
getCell = function() return nil end

local function controller(taskType)
    local c = setmetatable({
        id = "worker",
        character = actor,
        state = "IDLE",
        nextThink = 0,
        nextThreatScan = 100000,
        baseTask = { id = "task-1", type = taskType, state = "claimed", claimedBy = "worker" },
        baseTaskSupplyTransfer = {},
        baseTaskActionQueued = true,
        selfCareRetryAt = {},
        groupMembers = {},
        lifeIntent = nil,
        recoverFromDetached = function() return false end,
        hasNeedEscort = function() return false end,
        bridge = { cancelNpcMove = function() end },
    }, Controller)
    c.searched = false
    c.beginWorldSearch = function(self) self.searched = true return true end
    return c
end

-- Thirst mid-barricade suspends the claim instead of orphaning it: the route
-- is cancelled once, caches cleared, and the same task resumes after a drink.
local c = controller("barricade")
c:tick(100)
assert(c.searched == true, "thirst must still be answered")
assert(c.baseTask ~= nil and c.baseTask.type == "barricade",
    "the claim must survive personal needs")
assert(c.baseTask.interruptedReason == "needs_interrupt",
    "needs must suspend through the threat machinery, not orphan")
assert(c.baseTaskActionQueued == false and c.baseTaskStartedAt == nil,
    "suspend must clear stale phase caches")

-- Cook claims stay owned by the cooking update, never suspended.
c = controller("cook")
c:tick(200)
assert(c.baseTask ~= nil and c.baseTask.interruptedReason == nil,
    "cook claims must not be touched by generic needs handling")

print("Claim suspend PASS needs=true cook_exempt=true resume_intact=true")
