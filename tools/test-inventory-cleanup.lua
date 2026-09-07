local root = arg[1] or "."
package.path = root .. "/mod/42/media/lua/client/?.lua;" .. package.path
package.preload.KS_SurvivorNeeds = function() return true end
KnoxSurvivorNeeds = {
    isSafeFood = function(item) return item.food == true end,
    isWaterItem = function(item) return item.water == true end,
}
ItemTag = { AMMO = "ammo" }
local function list(values)
    return { size = function() return #values end, get = function(_, index) return values[index + 1] end }
end
local inventory = { values = {} }
function inventory:getItems() return list(self.values) end
function inventory:contains(item)
    for _, entry in ipairs(self.values) do if entry == item then return true end end
    return false
end
local function item(full, values)
    local result = values or {}
    result.full = full
    function result:getFullType() return self.full end
    function result:hasTag(tag) return tag == "ammo" and self.ammo == true end
    function result:IsWeapon() return self.weapon == true end
    function result:IsInventoryContainer() return self.contents ~= nil end
    function result:IsClothing() return self.clothing == true end
    function result:getInventory() return self.contents end
    function result:getContainer() return self.container or inventory end
    function result:getBodyLocation() return self.slot end
    function result:canBeEquipped() return self.slot end
    function result:getDisplayCategory() return self.category or "" end
    function result:isFavorite() return self.favorite == true end
    function result:isBroken() return self.broken == true end
    function result:isRanged() return self.ranged == true end
    function result:isCanBandage() return self.bandage == true end
    function result:getConditionMax() return 10 end
    function result:getCondition() return self.broken and 0 or 10 end
    function result:getMinDamage() return self.damage or 1 end
    function result:getMaxDamage() return self.damage or 1 end
    function result:getMaxRange() return 1 end
    function result:getBaseSpeed() return 1 end
    function result:getUnequippedWeight() return self.weight or 1 end
    return result
end
local character = { weight = 11 }
function character:getInventory() return inventory end
function character:getInventoryWeight() return self.weight end
function character:getMaxWeight() return 10 end
function character:isEquipped(item) return item.equipped == true end
function character:isHandItem(item) return item.hand == true end
function character:isAttachedItem(item) return item.attached == true end
function character:getWornItem() return nil end
local broken = item("Base.BaseballBat", { weapon = true, broken = true })
local junk = item("Base.TinCanEmpty", { category = "Junk", weight = 2 })
local best = item("Base.Crowbar", { weapon = true, damage = 3 })
local weak = item("Base.RollingPin", { weapon = true })
local med = item("Base.Bandage", { bandage = true })
local ammo = item("Base.Bullets9mm", { ammo = true })
local valuable = item("Base.Necklace_Gold", { clothing = true, category = "Accessory" })
local favorite = item("Base.FavoriteJunk", { category = "Junk", favorite = true })
local modded = item("Mod.QuestObject", { category = "Junk" })
local taskItem = item("Base.RequiredJunk", { category = "Junk" })
local equipped = item("Base.Equipped", { category = "Junk", equipped = true })
local attached = item("Base.AttachedGear", { category = "Junk", attached = true })
local hammer = item("Base.Hammer", { weapon = true })
inventory.values = { broken, junk, best, weak, med, ammo, valuable, favorite, modded, taskItem, equipped, attached, hammer }
local looting = require "KS_SurvivorLooting"
for _, full in ipairs({ "Base.MoneyBundle", "Base.GoldCoin", "Base.SilverCoin", "Base.SmallGoldBar" }) do
    local value, reason = looting.itemUtility(character, item(full, { category = "Junk" }), {}, {})
    assert(value == nil and reason == "valuable", "cleanup must retain physical currency: " .. full)
end
local plan = looting.cleanupPlan(character, { ["Base.RequiredJunk"] = 1 })
assert(#plan == 3 and plan[1].item == broken and plan[2].item == junk and plan[3].item == weak,
    "cleanup ranks low utility first and preserves essential/equipped/valuable/unknown/task items")
character.weight = 8.5
assert(#looting.cleanupPlan(character, {}, false) == 0, "comfortable load does not start cleanup")
assert(#looting.cleanupPlan(character, {}, true) > 0, "active cleanup has lower stopping threshold")
character.weight = 7.9
assert(#looting.cleanupPlan(character, {}, true) == 0, "cleanup stops below preferred load")
assert(#looting.cleanupPlan(character, {}, false, true) > 0,
    "routine home deposits do not wait for encumbrance")
character.weight = 11
inventory.values = {}
for i = 1, 4 do inventory.values[i] = item("Base.Apple", { food = true }) end
assert(#looting.cleanupPlan(character, {}) == 0, "near-term food reserve is not discarded")
assert(#looting.cleanupPlan(character, {}, false, true) == 0,
    "routine home deposits retain four meals")
inventory.values[5] = item("Base.Apple", { food = true })
plan = looting.cleanupPlan(character, {})
assert(#plan == 5 and plan[1].canDrop == false, "surplus food can be deposited but not thrown away")
KnoxBaseStorage = { matchesCategory = function(candidate, category)
    return candidate:getFullType() == "Base.Plank" and category == "building"
end }
inventory.values = { item("Base.Plank") }
plan = looting.cleanupPlan(character, {})
assert(#plan == 1 and plan[1].canDrop == false and plan[1].reason == "base_material",
    "useful surplus base materials are deposited, not thrown away")
assert(#looting.cleanupPlan(character, { ["Base.Plank"] = 1 }) == 0,
    "queued work retains required materials instead of depositing them in a loop")
KnoxBaseStorage = nil
inventory.values = {}
for i = 1, 5 do inventory.values[i] = item("Base.Bandage", { bandage = true }) end
assert(#looting.cleanupPlan(character, {}, false, true) > 0, "extra medical supplies go to cupboard")
table.remove(inventory.values)
assert(#looting.cleanupPlan(character, {}, false, true) == 0, "medical reserve survives repeated deposits")
local bagContents = { values = {} }
function bagContents:getItems() return list(self.values) end
local bag = item("Base.Bag_DuffelBag", { contents = bagContents, favorite = true })
function bagContents:getContainingItem() return bag end
bagContents.values = { item("Base.Junk", { category = "Junk", container = bagContents }) }
inventory.values = { bag }
assert(#looting.cleanupPlan(character, {}) == 0, "favorite bag protects its contents")
bag.favorite = false
assert(#looting.cleanupPlan(character, {}) == 1, "nonempty bag remains but disposable contents are considered")
bagContents.values[#bagContents.values + 1] = bag
assert(pcall(looting.cleanupPlan, character, {}), "cyclic modded bag data cannot recurse indefinitely")

-- Controller ownership and native transfer adapter selection, without invoking a game UI.
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController
local square = { getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end }
local actions, queued = false, 0
function character:getCurrentSquare() return square end
function character:getCharacterActions() return { isEmpty = function() return not actions end } end
local base = { id = "owned-base", tasks = {} }
KnoxPersistence = { getSurvivorDuty = function() return { mode = "companion" } end,
    getSurvivorAffiliation = function() return { kind = "player", ownerId = "player-1" } end,
    getBaseForOwner = function(kind, id) assert(kind == "player" and id == "player-1") return base end,
    captureActiveSurvivor = function() return true end }
local destination = { contains = function(_, candidate) return candidate.deposited == true end }
local storageAvailable = true
KnoxBaseStorage = { findNearbyDeposit = function(owned)
    assert(owned == base, "storage search is restricted to canonical owner base")
    return storageAvailable and { container = destination } or nil
end }
KnoxInventoryActions = {
    queueTransfer = function(_, candidate, source, dest)
        assert(source == inventory and dest == destination)
        queued = queued + 1 actions = true return {}, "queued"
    end,
    queueDrop = function() queued = queued + 1 actions = true return {}, "queued" end,
}
ISTimedActionQueue = { clear = function() actions = false end }
inventory.values = { junk }
local controller = setmetatable({ id = "test", character = character, state = "IDLE",
    companionOrder = "hold", counts = { failures = 0 }, nextThink = 0 }, Controller)
assert(controller:beginInventoryCleanup(0) and controller.activeDecision == "deposit_surplus",
    "nearby owned deposit is preferred to dropping")
assert(not controller:beginInventoryCleanup(1) and queued == 1, "no duplicate cleanup action")
assert(controller:interruptSelfCareForDanger(2) and not actions and controller.pendingCleanup == nil
    and controller.companionOrder == "hold", "danger cancels cleanup but preserves command")
storageAvailable = false
assert(controller:beginInventoryCleanup(603) and controller.activeDecision == "drop_surplus",
    "known low-value item uses native drop adapter when no owned storage is available")
controller:interruptSelfCareForDanger(604)
controller.nextCleanupAt = 0
controller.baseTask = { id = "claimed-job" }
assert(not controller:beginInventoryCleanup(2000), "claimed base job is not interrupted for cleanup")
controller.baseTask = nil
controller.failureReasons = {}
ZombRand = function() return 0 end
storageAvailable = true
assert(controller:beginInventoryCleanup(2100))
actions = false
controller:updateInventoryCleanup(2101)
assert(controller.counts.failures == 1 and controller.pendingCleanup == nil
    and controller.state == "IDLE" and controller.nextCleanupAt == 2701,
    "empty action queue without real transfer fails cleanly with bounded retry")
assert(not controller:beginInventoryCleanup(2150), "failed action cannot immediately retry")
assert(controller:beginInventoryCleanup(2800))
junk.deposited = true
inventory.values = {}
actions = false
controller:updateInventoryCleanup(2801)
assert(controller.counts.failures == 1 and controller.pendingCleanup == nil
    and controller.state == "IDLE" and controller.companionOrder == "hold",
    "real destination receipt completes once and preserves underlying Hold")
inventory.values = { junk }
junk.deposited = false
storageAvailable = false
assert(controller:beginInventoryCleanup(3200))
function junk:getWorldItem() return self.worldItem end
inventory.values = {}
junk.worldItem = {}
actions = false
controller:updateInventoryCleanup(3201)
assert(controller.counts.failures == 1 and controller.state == "IDLE",
    "ground drop succeeds only after source removal and a real world item")

-- Useful surplus can travel to owned storage without taking over companion or
-- group movement. Native routing and transfer remain separate ownership stages.
inventory.values = { best, weak }
local moves, cancels = 0, 0
local moveResult = "MOVE_STARTED"
controller.bridge = {
    moveNpc = function(_, id, target)
        assert(id == "test" and target == square) moves = moves + 1 return moveResult
    end,
    cancelNpcMove = function() cancels = cancels + 1 end,
}
controller.leaveRecoveryPosture = function() end
KnoxBaseStorage.findDepositTrip = function(owned, actor, candidate, excluded, ticks)
    assert(owned == base and actor == character and candidate == weak)
    if excluded ~= nil and (excluded.storage or 0) > ticks then return nil end
    return { policy = { key = "storage" }, approach = square }
end
controller.nextCleanupAt = 0
assert(not controller:canMakeDepositTrip(nil), "Hold never permits an autonomous deposit detour")
controller.companionOrder = nil
assert(controller:canMakeDepositTrip({ mode = "autonomous" }), "independent duty may use its faction's owned storage")
assert(not controller:canMakeDepositTrip({ mode = "companion" }), "persisted companion duty protects orders before runtime refresh")
assert(not controller:canMakeDepositTrip({ mode = "away" }))
controller.groupLeader = {}
assert(not controller:canMakeDepositTrip(nil), "storage cleanup cannot split a travelling group")
controller.groupLeader = nil
controller.groupMembers = { {}, {} }
assert(not controller:canMakeDepositTrip(nil))
controller.groupMembers = {}
KnoxPersistence.getSurvivorDuty = function() return { mode = "base" } end
assert(controller:beginInventoryCleanup(4000) and controller.state == "MOVING_TO_DEPOSIT" and moves == 1)
local queuedBefore = queued
assert(not controller:beginInventoryCleanup(4400) and moves == 1 and queued == queuedBefore,
    "active travel cannot be replaced by another cleanup decision even after refresh cooldown")
storageAvailable = true
assert(controller:completeDepositTrip(4500) and controller.state == "INVENTORY_CLEANUP"
    and queued == queuedBefore + 1, "arrival queues real transfer, not inventory mutation")
weak.deposited = true
inventory.values = { best }
actions = false
controller:updateInventoryCleanup(4501)
assert(controller.pendingDepositTrip == nil and controller.state == "IDLE")

local function startTrip(ticks)
    inventory.values = { best, weak }
    weak.deposited, weak.favorite = false, false
    storageAvailable = false
    controller.nextCleanupAt, controller.depositRetryAt = 0, {}
    assert(controller:beginInventoryCleanup(ticks) and controller.state == "MOVING_TO_DEPOSIT")
end
startTrip(5000)
weak.favorite = true
storageAvailable = true
queuedBefore = queued
assert(not controller:completeDepositTrip(5100) and queued == queuedBefore,
    "item protected during travel cannot be deposited using a stale plan")
assert(controller.depositRetryAt.storage == 6900 and controller.nextCleanupAt == 5700)
startTrip(6000)
base.id = "relocated-base"
assert(not controller:completeDepositTrip(6100), "base replacement invalidates old trip")
base.id = "owned-base"
startTrip(7000)
assert(not controller:completeDepositTrip(7100), "removed/full/unreachable container fails arrival without transfer")
startTrip(8000)
controller.companionOrder = "hold"
storageAvailable = true
assert(not controller:completeDepositTrip(8100), "new Hold invalidates autonomous trip at arrival")
controller.companionOrder = nil
startTrip(9000)
assert(controller:interruptSelfCareForDanger(9100) and controller.pendingDepositTrip == nil
    and controller.state == "IDLE" and cancels > 0, "combat cancels travel ownership and keeps carried loot")
controller.abandonBaseTask, controller.releaseSupply, controller.releaseRestSpot = function() end, function() end, function() end
startTrip(10000)
assert(controller:interruptForDirective() and controller.pendingDepositTrip == nil and controller.state == "IDLE",
    "replacement command cancels trip immediately")
storageAvailable = false
moveResult = "Failed:blocked"
controller.nextCleanupAt = 0
assert(controller:beginInventoryCleanup(11000), "eligible droppable spare still has native floor fallback after failed trip")
assert(controller.pendingDepositTrip == nil and controller.depositRetryAt.storage == 12800)
controller:interruptSelfCareForDanger(11001)
for index = 1, 30 do
    controller.pendingDepositTrip = { policyKey = "storage-" .. index }
    controller:deferDepositTrip(12000 + index)
end
local remembered = 0
for _ in pairs(controller.depositRetryAt) do remembered = remembered + 1 end
assert(remembered <= 16, "failure memory is bounded")
controller.pendingDepositTrip = nil

-- Exercise the actual tick dispatch as well as the arrival policy above.
moveResult = "MOVE_STARTED"
controller.nextThreatScan = math.huge
controller.bridge.tickNpc = function() return "Succeeded" end
startTrip(14000)
storageAvailable = true
controller.movementFailureCount = 3
controller:tick(14001)
assert(controller.state == "INVENTORY_CLEANUP" and controller.movementFailureCount == 0,
    "native success reaches deposit completion and resets movement backoff")
controller:interruptSelfCareForDanger(14002)
startTrip(15000)
controller.bridge.tickNpc = function() return "Failed:blocked" end
controller:tick(15001)
assert(controller.state == "IDLE" and controller.pendingDepositTrip == nil
    and controller.depositRetryAt.storage == 16801, "native failure releases trip and suppresses failed storage")
startTrip(16000)
controller.observedState = controller.state
controller.stateStartedAt = 14000
controller.bridge.resetNpcCombat = function() end
controller.releaseCombat = function() end
controller:tick(16001)
assert(controller.state == "IDLE" and controller.pendingDepositTrip == nil
    and controller.depositRetryAt.storage == 17801, "timeout uses common abandonment and retains failure memory")
startTrip(18000)
controller.state = "DETACHED"
assert(controller:recoverFromDetached(18001) and controller.pendingDepositTrip == nil
    and controller.state == "IDLE", "streaming interruption discards transient trip without losing carried inventory")

-- The drop adapter must create its own floor container and use the same native
-- transfer subclass, never getSpecificPlayer or the local player's loot panel.
local function derive(self)
    local child = {} child.__index = child setmetatable(child, { __index = self }) return child
end
ISBaseTimedAction = { derive = derive }
ISInventoryTransferAction = { derive = derive, new = function(self, actor, candidate, source, dest)
    return { character = actor, item = candidate, srcContainer = source, destContainer = dest }
end }
local floor
ItemContainer = { new = function(kind, square, parent)
    assert(kind == "floor" and square == nil and parent == nil)
    floor = { setExplored = function() end } return floor
end }
local lastAction
ISTimedActionQueue.add = function(action) lastAction = action end
KnoxInventoryActions = nil
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorInventoryActions.lua")
function character:getVehicle() return nil end
local drop = assert(KnoxInventoryActions.queueDrop(character, junk))
assert(lastAction == drop and drop.character == character and drop.destContainer == floor,
    "native floor action belongs to the off-slot survivor, not player index zero")
function character:getVehicle() return {} end
assert(not KnoxInventoryActions.queueDrop(character, junk), "vehicle drop requires its separate native interaction")
print("Inventory cleanup PASS protection=true utility=true hysteresis=true nested=true deposit=true interruption=true")
