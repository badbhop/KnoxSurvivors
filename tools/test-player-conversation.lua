local root = arg[1] or "."
require = function() return true end
local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z end }
end
local npcSquare, playerSquare = square(0, 0, 0), square(1, 0, 0)
local busy, dead, danger, need = false, false, false, "roam"
local player = { getCurrentSquare = function() return playerSquare end,
    isDead = function() return dead end }
local body = { getCurrentSquare = function() return npcSquare end,
    getCharacterActions = function() return { isEmpty = function() return not busy end } end,
    CanSee = function() return true end, faceThisObject = function() end }
getCell = function() return { getZombieList = function() return {
    size = function() return 0 end } end } end
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
getSpecificPlayer = function() return player end
getNumActivePlayers = function() return 1 end
KnoxSettings = { allowSurvivorFleeing = function() return false end }
local conversations = 0
KnoxPersistence = {
    isSurvivorHostileToPlayer = function() return danger end,
    ensurePlayerId = function() return "player" end,
    getPlayerRelationship = function() return {trust = 30} end,
    recordPlayerConversation = function()
        conversations = conversations + 1
        return { trust = 38, meetings = conversations }, "recorded"
    end,
    getSurvivorIdentity = function() return {forename = "Morgan", surname = "Reed"} end,
}
KnoxSurvivorNeeds = { decide = function() return {kind = need} end }
KnoxActivityFeed = { speak = function() end, event = function() end }
local runtime = dofile(root .. "/mod/42/media/lua/client/KS_SurvivorRuntime.lua")
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController
local cancellations = 0
local c = setmetatable({ id = "npc", character = body, state = "ROAMING", currentTicks = 100,
    companionOrder = "follow", groupMembers = {}, failedThreats = {},
    reservations = { threats = {} },
    bridge = { cancelNpcMove = function() cancellations = cancellations + 1 end },
    releaseSupply = function() end, leaveRecoveryPosture = function() end,
    releaseRestSpot = function() end, abandonBaseTask = function() end,
}, Controller)
assert(runtime.register("npc", c))
local service = dofile(root .. "/mod/42/media/lua/client/KS_CompanionService.lua")
assert(service.talk(player, "npc"))
assert(c.state == "PLAYER_CONVERSATION" and cancellations == 1 and conversations == 1,
    "successful talk owns attention and cancels the old route once")
assert(c.companionOrder == "follow", "conversation preserves underlying order")
c:updatePlayerConversation(101)
assert(c.state == "PLAYER_CONVERSATION", "safe conversation remains stable")
assert(not runtime.endPlayerConversation("npc", {}), "unrelated actor cannot release attention")
c:updatePlayerConversation(700)
assert(c.state == "IDLE" and c.playerConversation == nil, "attention expires without a stuck owner")
assert(runtime.beginPlayerConversation("npc", player))
need = "bandage"
c:updatePlayerConversation(701)
assert(c.state == "IDLE", "medical needs release conversation")
need = "roam"
assert(runtime.beginPlayerConversation("npc", player))
playerSquare = square(1, 0, 1)
c:updatePlayerConversation(701)
assert(c.state == "IDLE", "player floor change ends conversation")
playerSquare = square(1, 0, 0)
assert(runtime.beginPlayerConversation("npc", player))
playerSquare = square(10, 0, 0)
c:updatePlayerConversation(701)
assert(c.state == "IDLE", "player departure ends conversation")
playerSquare = square(1, 0, 0)
c.baseTask = { id = "active-work" }
assert(not service.talk(player, "npc") and conversations == 1,
    "active job refuses talk before granting trust")
c.baseTask, busy = nil, true
assert(not service.talk(player, "npc") and conversations == 1, "native work retains ownership")
busy = false
c.state = "COMBAT"
assert(not runtime.beginPlayerConversation("npc", player), "combat cannot be interrupted for talk")
c.state = "IDLE"
assert(runtime.beginPlayerConversation("npc", player))
assert(c:interruptForDirective() and c.state == "IDLE" and c.playerConversation == nil,
    "new player order immediately releases attention")
assert(runtime.snapshot("npc").activity == "idle")
c.currentTicks = 1000
assert(runtime.beginPlayerConversation("npc", player))
c:tick(1001)
assert(c.state == "PLAYER_CONVERSATION", "full tick preserves safe attention after scanning danger")
need = "drink"
c:tick(1061)
assert(c.state == "IDLE", "full tick releases attention for thirst")
need = "roam"
body.CanSee = function() return false end
assert(not runtime.beginPlayerConversation("npc", player), "walls prevent remote conversation")
print("Player conversation PASS pause=true expiry=true needs=true departure=true ownership=true")

local cleared, stood = 0, 0
ISTimedActionQueue = { clear = function(actor)
    assert(actor == body)
    cleared, busy = cleared + 1, false
end }
c.leaveRecoveryPosture = function() stood = stood + 1 end
c.state, c.activeDecision, busy = "BASE_AMBIENT_REST", "base_ambient_rest", true
assert(c:interruptForMeeting() and cleared == 1 and stood == 1,
    "a resident releases native rest and furniture before a social approach")
c.state, c.activeDecision, busy = "ROAMING", "roam", true
assert(not c:canInterruptForMeeting() and not c:interruptForMeeting() and cleared == 1,
    "social requests cannot cancel unrelated native actions")
busy = false
body.getCurrentStateName = function() return "ClimbOverFenceState" end
body.getCurrentActionContextStateName = function() return "climbfence" end
assert(not c:canInterruptForMeeting(), "social requests wait for native traversal")
body.getCurrentStateName, body.getCurrentActionContextStateName = nil, nil
c.baseTask = {id = "retained-job"}
assert(not c:canInterruptForMeeting(), "retained job claims block idle social takeover")
c.baseTask = nil
print("Native social ownership PASS rest_cleanup=true action_guard=true traversal_guard=true claim_guard=true")

c.state, c.activeDecision = "IDLE", nil
body.CanSee = function() return true end
c.currentTicks = 2000
assert(runtime.beginPlayerConversation("npc", player))
local attacker = { getCurrentSquare = function() return square(1, 0, 0) end,
    isDead = function() return false end, getTarget = function() return body end }
getCell = function() return { getZombieList = function() return {
    size = function() return 1 end, get = function() return attacker end } end } end
c.beginCombat = function(self, target)
    assert(target == attacker)
    self.state = "COMBAT"
    return true
end
c:tick(2001)
assert(c.state == "COMBAT", "danger preempts player attention through the full controller tick")
print("Player attention danger handoff PASS")
