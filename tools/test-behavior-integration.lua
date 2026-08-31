local rootPath = arg[1] or "."

require = function() return true end
assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"))()
local Controller = assert(KnoxAutonomyController)

local currentSquare = { getX = function() return 1 end, getY = function() return 1 end,
    getZ = function() return 0 end }
local actions = { empty = true, cleared = 0 }
local character = {
    getCurrentSquare = function() return currentSquare end,
    getCharacterActions = function()
        return {
            isEmpty = function() return actions.empty end,
        }
    end,
    isSitOnGround = function() return false end,
    isSittingOnFurniture = function() return false end,
    setVariable = function() end,
    setIsResting = function() end,
    setBed = function() end,
}
ISTimedActionQueue = { clear = function() actions.cleared = actions.cleared + 1 end }
KnoxSurvivorNeeds = { wakeForDanger = function() return false end }

local bridge = {
    cancelNpcMove = function() end,
    resetNpcCombat = function() end,
}
local controller = setmetatable({
    id = "integration",
    character = character,
    bridge = bridge,
    state = "DETACHED",
    activeDecision = "drink",
    selfCareIntent = { kind = "drink" },
    selfCareRetryAt = {},
    companionOrder = "follow",
    companionOwnerId = "player",
    groupLeaderId = "leader",
    campId = "camp",
    baseId = "base",
    formationMovementPace = "run",
    nextThink = 0,
    reservations = { threats = {}, items = {}, containers = {}, restSpots = {} },
    counts = { failures = 0 },
    abandonBaseTask = function(self, reason) self.abandoned = reason end,
}, Controller)

assert(controller:recoverFromDetached(100), "loaded detached shell normalizes once")
assert(controller.state == "IDLE" and controller.activeDecision == nil
    and controller.selfCareIntent == nil, "stale transient decision is cleared")
assert(controller.selfCareRetryAt.drink ~= nil, "interrupted self-care gets bounded retry")
assert(controller.companionOrder == "follow" and controller.companionOwnerId == "player"
    and controller.groupLeaderId == "leader" and controller.campId == "camp"
    and controller.baseId == "base", "persistent duty and social/home ownership survive recovery")
assert(controller.formationMovementPace == nil and controller.abandoned == "detached_recovered",
    "temporary movement/task owners are released")
assert(not controller:recoverFromDetached(101), "normalization cannot thrash every tick")

print("Behavior integration PASS detached_recovery=true persistent_intent=true transient_cleanup=true")
