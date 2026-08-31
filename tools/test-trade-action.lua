local root = arg[1] or "."
local game = arg[2] or "C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid"
local fixture = dofile(root .. "/tools/test-trade-valuation.lua")
local native = game .. "/media/lua/"
ISBaseObject = {}
function ISBaseObject:derive(name)
    local value = { Type = name }
    value.__index = value
    return setmetatable(value, { __index = self })
end
-- Execute the installed native transfer implementation, not a second imitation
-- of its floor/TradeUI/container branches inside the test.
dofile(native .. "shared/TimedActions/ISBaseTimedAction.lua")
dofile(native .. "shared/TimedActions/ISTransferAction.lua")
isClient = function() return false end
isServer = function() return false end
instanceof = function() return false end
ISLogSystem = { logAction = function() end }
ISInventoryPage = {}
local nextId, transferCalls, captured, rewardCalls = 100, 0, 0, 0
local failCapture, failCaptureFrom, failAdd, failAfterAdd, failReward, failQueue
local function item(full, options)
    local value = fixture.item(full, options)
    nextId = nextId + 1 value.id = nextId
    function value:getID() return self.id end
    function value:getType() return self.full:sub(6) end
    function value:getUnequippedWeight() return self.weight or 1 end
    return value
end
local function container(values)
    local value = fixture.container(values)
    value.capacity = 50
    function value:getItems()
        local result = fixture.list(self.values)
        function result:contains(target)
            for _, entry in ipairs(value.values) do if target == entry then return true end end
            return false
        end
        return result
    end
    function value:containsID(id)
        for _, entry in ipairs(self.values) do if entry:getID() == id then return true end end
        return false
    end
    function value:isInside() return false end
    function value:isItemAllowed() return not self.disallow end
    function value:isRemoveItemAllowed() return not self.disallowRemove end
    function value:getType() return "inventory" end
    function value:getParent() return nil end
    function value:hasRoomFor(_, weight)
        local current = 0
        for _, entry in ipairs(self.values) do current = current + entry:getUnequippedWeight() end
        return current + weight <= self.capacity
    end
    function value:DoRemoveItem(target)
        for i, entry in ipairs(self.values) do if entry == target then table.remove(self.values, i) break end end
        target.container = nil
    end
    function value:AddItem(target)
        assert(type(target) == "table", "exchange/rollback must use the same object, never spawn by type")
        transferCalls = transferCalls + 1
        if failAdd == transferCalls then error("injected_add_failure") end
        if target.container then target.container:DoRemoveItem(target) end
        self.values[#self.values + 1] = target target.container = self
        if failAfterAdd == transferCalls then error("injected_post_add_failure") end
        return target
    end
    return value
end
local function actor()
    local value = fixture.actor()
    value.inventory = container()
    function value:getVehicle() return self.vehicle end
    function value:isSomethingTo(other) return self.blocked or other.blocked or false end
    function value:hasHitReaction() return self.hit == true end
    function value:getSurroundingAttackingZombies() return self.attackers or 0 end
    function value:isAttacking() return false end
    function value:isAiming() return self.aiming == true end
    function value:getCharacterActions() return { isEmpty = function() return not self.busy end } end
    function value:removeAttachedItem() end
    function value:setIsFarming() end
    function value:faceThisObject() end
    function value:shouldBeTurning() return false end
    function value:getCurrentStateName() return self.nativeState or "idle" end
    function value:getCurrentActionContextStateName() return "idle" end
    return value
end
getCell = function() return nil end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorRuntime.lua")
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Runtime, Controller = KnoxSurvivorRuntime, KnoxAutonomyController
local realCapture, realReward = KnoxPersistence.captureActiveSurvivor, KnoxPersistence.recordPlayerContribution
KnoxPersistence.captureActiveSurvivor = function(id)
    captured = captured + 1
    if captured == failCapture or (failCaptureFrom and captured >= failCaptureFrom) then return false end
    return KnoxPersistence.setRecord(id, "snapshot-" .. captured)
end
KnoxPersistence.recordPlayerContribution = function(...)
    if failReward then error("injected_reward_failure") end
    rewardCalls = rewardCalls + 1
    return realReward(...)
end
local player, npc, controller, giving, taking
ISTimedActionQueue = { queues = {} }
function ISTimedActionQueue.getTimedActionQueue(character)
    local queue = ISTimedActionQueue.queues[character]
    if queue == nil then
        queue = { queue = {}, onCompleted = function(self) self.queue = {} end,
            resetQueue = function(self) self.queue = {} end }
        ISTimedActionQueue.queues[character] = queue
    end
    return queue
end
function ISTimedActionQueue.add(action)
    if failQueue then error("injected_queue_failure") end
    ISTimedActionQueue.getTimedActionQueue(action.character).queue = { action }
end
local trade = dofile(root .. "/mod/42/media/lua/client/KS_TradeAction.lua")
local wallTime = 0
getTimestampMs = function() return wallTime end
local function setup()
    transferCalls, captured, rewardCalls = 0, 0, 0
    failCapture, failCaptureFrom, failAdd, failAfterAdd, failReward, failQueue = nil, nil, nil, nil, nil, nil
    player, npc = actor(), actor()
    getSpecificPlayer = function(index) return index == 0 and player or nil end
    KnoxPersistence.ensurePlayerId(player)
    assert(KnoxPersistence.setRecord("exchange", "initial"))
    fixture.data.survivors.exchange.affiliation = { kind = "independent" }
    fixture.data.survivors.exchange.alive = true
    giving = item("Base.Bag_DuffelBag", { bag = container() })
    taking = item("Base.Shirt", { clothing = true })
    player.inventory, npc.inventory = container({ giving }), container({ taking })
    controller = setmetatable({ id = "exchange", character = npc, state = "ROAMING",
        nextThreatScan = 0, groupLeaderId = "leader", campId = "shelter",
        reservations = { threats = {}, items = {}, containers = {}, restSpots = {} },
        bridge = { cancelNpcMove = function() end },
        leaveRecoveryPosture = function() end,
    }, Controller)
    Runtime.register("exchange", controller)
    return player, npc
end
local function queue() return trade.queue(player, "exchange", { giving }, { taking }) end
local function unchanged()
    assert(giving:getContainer() == player.inventory and taking:getContainer() == npc.inventory)
    assert(player.inventory:getItems():contains(giving) and npc.inventory:getItems():contains(taking))
    assert(not player.inventory:getItems():contains(taking) and not npc.inventory:getItems():contains(giving))
end
setup()
local action = assert(queue())
assert(controller.state == "TRADING" and Runtime.ownsTrade("exchange", action))
assert(not queue(), "second action cannot duplicate lease or queued exchange")
unchanged()
action:perform()
assert(action.success and action.result == "completed" and captured == 2 and rewardCalls == 1)
assert(giving:getContainer() == npc.inventory and taking:getContainer() == player.inventory)
assert(controller.state == "IDLE" and controller.groupLeaderId == "leader" and controller.campId == "shelter")
action:perform()
assert(transferCalls == 2 and rewardCalls == 1, "completion callback cannot exchange/reward twice")

setup() action = assert(queue()) action:stop() unchanged()
assert(controller.state == "IDLE" and not action.success and captured == 0)
setup() action = assert(queue()) action:forceCancel() unchanged()
assert(not Runtime.ownsTrade("exchange", action))
setup() failQueue = true assert(not queue()) unchanged()
assert(controller.tradeAction == nil and controller.state == "IDLE")
setup() npc.blocked = true assert(not queue()) unchanged()
setup() npc.x = 2 assert(not queue()) unchanged()
setup() npc.nativeState = "ClimbOverFence" assert(not queue()) unchanged()
setup() npc.busy = true assert(not queue()) unchanged()
setup() player.busy = true assert(not queue()) unchanged()
setup() npc.inventory.capacity = 0 assert(not queue()) unchanged()
setup() giving.weight, taking.weight = 5, 5 player.inventory.capacity, npc.inventory.capacity = 5, 5
action = assert(queue()) action:perform()
assert(action.success, "root outgoing weight permits an equal-weight swap at full capacity")
setup() npc.inventory.disallow = true assert(not queue()) unchanged()
setup() player.inventory.disallowRemove = true assert(not queue()) unchanged()
setup() taking.id = giving.id assert(not queue()) unchanged()
setup() isClient = function() return true end assert(not queue()) unchanged() isClient = function() return false end

for _, mutation in ipairs({
    function() npc.x = 2 end,
    function() npc.dead = true end,
    function() npc.detached = true end,
    function() npc.attackers = 1 end,
    function() player.hit = true end,
    function() player.aiming = true end,
    function() npc.inventory.capacity = 0 end,
    function() giving.favorite = true end,
    function() giving.condition = 0 end,
    function() fixture.data.survivors.exchange.affiliation.kind = "player" end,
    function() KnoxPersistence.setSurvivorHostileToPlayer("exchange", player:getModData().KnoxSurvivors.playerId, true) end,
    function() player:getModData().KnoxSurvivors.playerId = "different" end,
}) do
    setup() action = assert(queue()) mutation() action:perform() unchanged()
    assert(not action.success and transferCalls == 0 and rewardCalls == 0, "completion must revalidate before any transfer")
end

setup() action = assert(queue()) failCapture = 1 action:perform() unchanged()
assert(transferCalls == 0 and action.result == "capture_unavailable")
for _, transferIndex in ipairs({ 1, 2 }) do
    setup() action = assert(queue()) failAdd = transferIndex action:perform() unchanged()
    assert(action.result == "exchange_rolled_back" and rewardCalls == 0 and trade.failedExchange == nil)
    setup() action = assert(queue()) failAfterAdd = transferIndex action:perform() unchanged()
    assert(action.result == "exchange_rolled_back" and rewardCalls == 0)
end
setup() action = assert(queue()) failCapture = 2 action:perform() unchanged()
assert(action.result == "exchange_rolled_back" and captured == 3 and rewardCalls == 0)
setup() action = assert(queue()) failCaptureFrom = 2 action:perform() unchanged()
assert(action.result == "exchange_rolled_back" and KnoxPersistence.getRecord("exchange") == "snapshot-1",
    "when recapture remains unavailable, restored items retain their verified before-record")
setup() action = assert(queue()) failReward = true action:perform()
assert(action.success and giving:getContainer() == npc.inventory and taking:getContainer() == player.inventory,
    "reward errors cannot turn a verified paid trade into a failed/duplicated trade")

-- Real controller/runtime interruption and bounded lease expiry; no command data is rewritten.
setup() action = assert(queue()) controller.nextThreatScan = 999999
controller:tick(1)
assert(controller.state == "TRADING" and controller.tradeTicksRemaining == 1799)
controller.tradeTicksRemaining = 1 controller:tick(2)
assert(controller.state == "IDLE" and action.cancelled and not Runtime.ownsTrade("exchange", action))
action:perform() unchanged()
setup() action = assert(queue())
controller.abandonBaseTask = function() end
controller.releaseRestSpot = function() end
assert(controller:interruptForDirective() and action.cancelled == "directive_changed")
assert(controller.state == "IDLE" and controller.campId == "shelter" and controller.groupLeaderId == "leader")
action:perform() unchanged()
setup() action = assert(queue()) controller.state = "COMBAT" controller:releaseTrade(action)
assert(controller.state == "COMBAT", "late trade completion must not overwrite new combat ownership")
action:perform() unchanged()
setup() action = assert(queue()) Runtime.unregister("exchange", controller) action:perform() unchanged()
assert(not action.success, "unload/replacement cannot inherit transient exchange ownership")
setup() action = assert(queue()) npc.detached = true controller:tick(1)
assert(controller.state == "DETACHED" and action.cancelled and controller.tradeAction == nil)
action:perform() unchanged()

-- Unexpected rollback failure retains exact references and blocks further trades.
setup()
local session = assert(trade.beginBrowse(player, "exchange"))
assert(session:isValid() and controller.tradeTicksRemaining == 7200)
assert(not trade.beginBrowse(player, "exchange"), "second browser cannot steal the survivor")
trade.endBrowse(session, "closed") unchanged()
assert(controller.state == "IDLE")
setup() session = assert(trade.beginBrowse(player, "exchange"))
action = assert(trade.queue(player, "exchange", { giving }, { taking }, session))
assert(session.finished and Runtime.ownsTrade("exchange", action) and controller.tradeTicksRemaining == 1800,
    "browsing hands ownership to the exchange exactly once")
trade.endBrowse(session, "late_close")
assert(Runtime.ownsTrade("exchange", action), "late browser release cannot cancel a newer action")
action:perform() assert(action.success)
setup() session = assert(trade.beginBrowse(player, "exchange"))
wallTime = 120001 controller.nextThreatScan = 999999 controller:tick(1)
assert(controller.state == "IDLE" and not session:isValid(), "real-time browse deadline cannot freeze the NPC")
assert(not trade.queue(player, "exchange", { giving }, { taking }, session)) unchanged()
wallTime = 0

setup() action = assert(queue()) failAdd = 2
local nativeAdd = player.inventory.AddItem
player.inventory.AddItem = function() error("persistent container failure") end
action:perform()
assert(action.result == "recovery_required" and trade.failedExchange ~= nil and rewardCalls == 0)
assert(trade.failedExchange.journal[1].item == giving and trade.failedExchange.journal[2].item == taking)
assert(not queue())
player.inventory.AddItem = nativeAdd
print("trade action PASS native-transfer=true receipts=true rollback=true capture=true ownership=true interrupts=true")
return { setup = function()
    trade.failedExchange = nil
    setup()
    return player, npc, controller, giving, taking
end, item = item, container = container, data = fixture.data }
