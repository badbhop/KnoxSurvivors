local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

package.loaded["KS_Persistence"] = true
package.loaded["KS_SurvivorNeeds"] = true
package.loaded["KS_SurvivorInventoryActions"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
package.loaded["Util/AdjacentFreeTileFinder"] = true
KnoxSurvivorNeeds = {
    isSafeFood = function(item) return item:getFullType() == "Base.TinnedSoup" end,
    isWaterItem = function(item) return item:getFullType() == "Base.WaterBottleFull" end,
}
KnoxInventoryActions = {
    queueTransfer = function() return {}, "queued" end,
}

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
        contains = function(_, target)
            for _, value in ipairs(values) do
                if value == target then return true end
            end
            return false
        end,
    }
end

local function item(full)
    return {
        getFullType = function() return full end,
        IsWeapon = function() return false end,
        IsClothing = function() return false end,
        IsInventoryContainer = function() return false end,
        isCanBandage = function() return false end,
        getContainer = function(self) return self._container end,
    }
end

local function container(kind, values)
    local result = { values = values or {} }
    for _, value in ipairs(result.values) do value._container = result end
    function result:getItems() return list(self.values) end
    function result:isExistYet() return true end
    function result:getType() return kind end
    function result:getParent() return nil end
    function result:hasRoomFor(character, candidate)
        assert(candidate ~= nil, "native capacity check requires character plus item")
        return not self.full
    end
    function result:isItemAllowed() return true end
    function result:contains(target)
        for _, value in ipairs(self.values) do
            if value == target then return true end
        end
        return false
    end
    function result:AddItem(value)
        local previous = value ~= nil and value._container or nil
        if previous ~= nil and previous.values ~= nil then
            for index = #previous.values, 1, -1 do
                if previous.values[index] == value then table.remove(previous.values, index) end
            end
        end
        self.values[#self.values + 1] = value
        value._container = self
        return value
    end
    return result
end

local function square(x, y, z, object)
    local result = { x = x, y = y, z = z, object = object }
    function result:getX() return self.x end
    function result:getY() return self.y end
    function result:getZ() return self.z end
    function result:getObjects() return list({ self.object }) end
    return result
end

local depotItem = item("Base.Plank")
local foodItem = item("Base.TinnedSoup")
local misplacedItem = item("Base.HandAxe")
local depot = container("crate", { depotItem, foodItem })
local destination = container("crate", {})
local storedBag = item("Base.Bag")
local storedBagInventory = container("bag", { item("Base.TinnedSoup") })
storedBag.IsInventoryContainer = function() return true end
storedBag.getInventory = function() return storedBagInventory end
depot.values[#depot.values + 1] = storedBag
local depotObject = {}
function depotObject:getObjectIndex() return 1 end
function depotObject:getContainerByIndex(index) return index == 0 and depot or nil end
function depotObject:getContainerCount() return 1 end
local destinationObject = {}
function destinationObject:getObjectIndex() return 2 end
function destinationObject:getContainerByIndex(index) return index == 0 and destination or nil end
function destinationObject:getContainerCount() return 1 end
local squares = {
    ["10:20:0"] = square(10, 20, 0, depotObject),
    ["12:20:0"] = square(12, 20, 0, destinationObject),
}
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            return squares[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)]
        end,
    }
end

local base = {
    id = "base-storage",
    storage = {
        depot = {
            key = "depot",
            x = 10, y = 20, z = 0, objectIndex = 1, containerIndex = 0,
            containerType = "crate", category = "depot", depot = true,
        },
        building = {
            key = "building",
            x = 12, y = 20, z = 0, objectIndex = 2, containerIndex = 0,
            containerType = "crate", category = "building", depot = false,
        },
    },
}

local storage = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseStorage.lua")
local policies = storage.policies(base)
assert(#policies == 2 and base.storage.building ~= nil,
    "typed plus legacy assignments persist without moving real items")
assert(base.storage.building ~= nil and #depot.values == 3 and #destination.values == 0,
    "categorized assignments persist without moving or deleting real items")
assert(storage.findTransfer(base) == nil, "central storage has no sorting job")
local summary = storage.summarize(base)
assert(summary.loadedPolicies == 2 and summary.totals.building == 1
    and summary.totals.food == 2,
    "assigned storage summaries must include real food inside stored containers")
local origin = square(11, 20, 0, {})
function origin:isSomethingTo() return self.blocked == true end
local worker = { getCurrentSquare = function() return origin end,
    getInventory = function() return container("inventory", {}) end }
local nearby = assert(storage.findNearbyDeposit(base, worker, depotItem))
assert(nearby.policy.key == "building", "typed storage is preferred for matching materials")
origin.blocked = true
assert(not storage.findNearbyDeposit(base, worker, depotItem), "no transfer through walls")
origin.blocked = false
depot.full = true
destination.full = true
assert(not storage.findNearbyDeposit(base, worker, depotItem), "full assigned storage cannot accept another deposit")
depot.full = false
destination.full = false
local approach = square(11, 20, 0, {})
function approach:isSomethingTo() return self.blocked == true end
AdjacentFreeTileFinder = { Find = function() return approach end }
origin.x = 50
assert(not storage.findNearbyDeposit(base, worker, depotItem))
assert(storage.findDepositTrip(base, worker, depotItem, {}, 100).policy.key == "building")
assert(storage.findDepositTrip(base, worker, depotItem, { building = 200 }, 100).policy.key == "depot")
assert(storage.findDepositTrip(base, worker, depotItem, { depot = 200 }, 201).policy.key == "building")
approach.blocked = true
assert(not storage.findDepositTrip(base, worker, depotItem))
approach.blocked = false
origin.x = 200
assert(not storage.findDepositTrip(base, worker, depotItem))
origin.x, origin.z = 50, 1
assert(storage.findDepositTrip(base, worker, depotItem), "native deposit routes can reach another loaded floor")
assert(not storage.findNearbyDeposit(base, worker, depotItem), "cross-floor transfers require walking first")
origin.z = 3
assert(not storage.findDepositTrip(base, worker, depotItem), "cross-floor search remains bounded")
origin.x, origin.z = 11, 0
assert(storage.findNearbyDeposit(base, worker, depotItem, "building").policy.key == "building",
    "typed policy can be selected directly")
local generalBase = { id = "general-fallback", storage = {
    general = { key = "general", x = 12, y = 20, z = 0, objectIndex = 2,
        containerIndex = 0, containerType = "crate", category = "general",
        storageRole = "general" },
} }
local unclassifiedItem = item("Mod.UnclassifiedSupply")
local generalDeposit = assert(storage.findNearbyDeposit(generalBase, worker, unclassifiedItem))
assert(generalDeposit.policy.key == "general"
    and storage.acceptsDeposit(generalDeposit.policy, unclassifiedItem),
    "an explicitly assigned General Storage accepts an otherwise unclassified real item")
for _, fullType in ipairs({ "Base.Log", "Base.TreeBranch", "Base.Twigs", "Base.Firewood" }) do
    assert(storage.classifyItem(item(fullType)) == "logs",
        "raw timber and firewood route to Logs & Lumber: " .. fullType)
end
local function nativeItem(full, display)
    local result = item(full)
    result.getDisplayCategory = function() return display end
    return result
end
for _, fullType in ipairs({ "Base.NormalTire1", "Base.CarBattery1", "Base.NormalBrake1",
        "Base.SmallGasTank1" }) do
    local part = nativeItem(fullType, "VehicleMaintenance")
    assert(storage.classifyItem(part) == "building",
        "native vehicle parts route to Materials: " .. fullType)
    assert(storage.matchesCategory(part, "building"),
        "VehicleMaintenance matches the building role: " .. fullType)
    assert(not storage.matchesCategory(part, "logs")
        and not storage.matchesCategory(part, "tools")
        and not storage.matchesCategory(part, "medical")
        and not storage.matchesCategory(part, "food"),
        "vehicle parts do not leak into unrelated typed roles: " .. fullType)
end
assert(storage.classifyItem(nativeItem("Base.SheetMetal", "Material")) == "building",
    "native Material sheets stay on the Materials shelf")
assert(storage.classifyItem(item("Mod.UnclassifiedSupply")) == "other",
    "genuinely unclassified items still fall through to General Storage")
local required = assert(storage.findRequiredTransfer(base, worker, { items = { ["Base.Plank"] = 1 } }))
assert(required.sourcePolicy.key == "depot")
assert(storage.requirementsAvailable(base, worker, { items = { ["Base.Plank"] = 1 } }))
assert(not storage.requirementsAvailable(base, worker, { items = { ["Base.Nails"] = 1 } }))
local nestedFood = storage.findItemType(base, function(candidate)
    return candidate == storedBagInventory.values[1]
end, worker)
assert(nestedFood == "Base.TinnedSoup",
    "assigned storage item discovery must inspect stored containers")
local stableKey = "base:container:10:20:0:1:0"
local stablePolicy = { key = stableKey, x = 10, y = 20, z = 0, objectIndex = 99,
    containerIndex = 0, containerType = "crate" }
depotObject.getModData = function() return { KnoxSurvivors = { storageIds = { original = stableKey } } } end
assert(storage.resolvePolicy(stablePolicy).container == depot,
    "stable identity survives tile object reordering")
depotObject.getModData = function() return {} end
stablePolicy.objectIndex = 1
assert(storage.resolvePolicy(stablePolicy) == nil, "replacement object cannot inherit assignment")
base.toolCupboardKey = "missing"
assert(storage.mainPolicy(base) ~= nil and #storage.policies(base) == 2
    and base.storage.building ~= nil,
    "legacy main retained without silent promotion")
base.toolCupboardKey = nil
local coldOnly = { storage = { fridge = { key = "fridge", containerType = "fridge" } } }
assert(#storage.policies(coldOnly) == 0, "legacy fridge is not silently enlarged into a dry cupboard")
assert(coldOnly.storage.fridge ~= nil, "migration preserves old physical-container references when no dry storage exists")
print("Central storage PASS migration=true single=true capacity=true route=true reserves=true identity=true")

-- Readiness, cupboard withdrawal and local supply searches must agree on usable stock.
base.toolCupboardKey = "depot"
local brokenAxe, goodAxe = item("Base.HandAxe"), item("Base.HandAxe")
brokenAxe.isBroken = function() return true end
goodAxe.isBroken = function() return false end
local emptyWater, fullWater = item("Base.WaterBottle"), item("Base.WaterBottle")
emptyWater.uses, fullWater.uses = 0, 4
ISFarmingMenu = { getWaterUsesInteger = function(candidate) return candidate.uses or 0 end }
local carried = container("inventory", {brokenAxe, emptyWater})
carried.getItemCount = function(_, fullType)
    return (fullType == "Base.HandAxe" or fullType == "Base.WaterBottle") and 1 or 0
end
worker.getInventory = function() return carried end
local axeRequirement = { items = { ["Base.HandAxe"] = 1 },
    itemRules = { ["Base.HandAxe"] = { usable = true } } }
local waterRequirement = { items = { ["Base.WaterBottle"] = 1 },
    itemRules = { ["Base.WaterBottle"] = { water = true } } }
depot.values = {brokenAxe, emptyWater}
assert(not storage.requirementsAvailable(base, worker, axeRequirement),
    "broken carried and stored tools cannot make a job ready")
assert(not storage.requirementsAvailable(base, worker, waterRequirement),
    "empty bottles cannot make watering ready")
depot.values = {brokenAxe, emptyWater, goodAxe, fullWater}
assert(storage.requirementsAvailable(base, worker, axeRequirement))
assert(storage.findRequiredTransfer(base, worker, axeRequirement).item == goodAxe,
    "worker replaces a broken tool with the usable stored instance")
assert(storage.findRequiredTransfer(base, worker, waterRequirement).item == fullWater,
    "worker skips empty bottles when gathering crop water")
local planner = KnoxBaseSupplyPlanner
assert(not planner.matchesMissingRequirement(brokenAxe, axeRequirement, carried)
    and planner.matchesMissingRequirement(goodAxe, axeRequirement, carried),
    "world resupply uses the same usable-tool requirement")
assert(not planner.matchesMissingRequirement(emptyWater, waterRequirement, carried)
    and planner.matchesMissingRequirement(fullWater, waterRequirement, carried),
    "world resupply uses the same nonempty-water requirement")
local bag = item("Base.Bag")
bag.IsInventoryContainer = function() return true end
bag.getInventory = function() return container("bag", {goodAxe, fullWater}) end
carried.values = {brokenAxe, emptyWater, bag}
local transfer, status = storage.findRequiredTransfer(base, worker, axeRequirement)
assert(transfer == nil and status == "requirements_ready", "usable nested tools prevent duplicate withdrawals")
transfer, status = storage.findRequiredTransfer(base, worker, waterRequirement)
assert(transfer == nil and status == "requirements_ready", "usable nested water prevents duplicate withdrawals")
print("Job supply usability PASS broken_tools=true empty_water=true nested=true world_search=true")

-- Kitchen assignments preserve raw ingredients and prefer food deposits, without
-- making unsafe food edible or changing native refrigerator capacity.
local rawFood = item("Base.RawChicken")
rawFood.IsFood = function() return true end
foodItem.IsFood = function() return true end
local waterItem = item("Base.WaterBottleFull")
-- Replace the legacy building assignment with the explicit kitchen assignment;
-- one physical container has one player-facing category.
base.storage.building = nil
local pantry = {key="pantry", x=12,y=20,z=0,objectIndex=2,containerIndex=0,
    containerType="crate",category="food",storageRole="food"}
base.storage.pantry = pantry
origin.x,origin.y,origin.z=11,20,0
carried.values = {}
depot.values, destination.values = {}, {foodItem,rawFood,waterItem,goodAxe}
assert(#storage.policies(base)==2 and base.storage.pantry==pantry)
assert(storage.findNearbyDeposit(base,worker,rawFood).policy.key=="pantry", "raw food belongs in kitchen storage")
assert(storage.findNearbyDeposit(base,worker,foodItem).policy.key=="pantry")
assert(storage.findNearbyDeposit(base,worker,waterItem).policy.key=="pantry")
assert(storage.findNearbyDeposit(base,worker,depotItem).policy.key=="depot", "building supplies stay out of food storage")
destination.full=true
assert(storage.findNearbyDeposit(base,worker,foodItem).policy.key=="depot", "full kitchen falls back to legacy supplies")
destination.full=false
summary=storage.summarize(base)
assert(summary.loadedPolicies==2 and summary.totals.food==1 and summary.totals.water==1
    and summary.totals.other==1 and summary.misplacedItems==1, "raw food is stored but not counted as ready-to-eat meals")
assert(storage.requirementsAvailable(base,worker,axeRequirement)
    and storage.findRequiredTransfer(base,worker,axeRequirement).item==goodAxe,
    "actual supplies can be recovered even if the player puts a tool in food storage")
local foodOnly={storage={pantry=pantry}}
assert(#storage.policies(foodOnly)==1 and storage.mainPolicy(foodOnly)==nil and not pantry.toolCupboard,
    "food-only bases never silently enlarge a pantry")
local capacityChanges=0
local originalApply=KnoxToolCupboard.apply
KnoxToolCupboard.apply=function() capacityChanges=capacityChanges+1;return true end
storage.resolvePolicy(pantry)
assert(capacityChanges==0, "food storage never reapplies an old cupboard capacity marker")
KnoxToolCupboard.apply=originalApply
print("Kitchen storage PASS persistence=true food=true raw_ingredients=true fallback=true capacity=true withdrawal=true")

-- Native hand tools also satisfy IsWeapon, unlike the older lightweight mocks.
local hammer = item("Base.Hammer")
hammer.IsWeapon = function() return true end
assert(storage.classifyItem(hammer) == "tools")
assert(storage.acceptsDeposit({storageRole="weapons"}, hammer), "explicit weapon storage still accepts tools")
depot.values = {hammer}
local toolStore = {key="tools", x=10,y=20,z=0,objectIndex=1,containerIndex=0,
    containerType="crate",category="tools",storageRole="tools"}
local stock = storage.summarize({storage={tools=toolStore}})
assert(stock.loadedPolicies == 1 and stock.totals.tools == 1 and stock.totals.weapons == 0,
    "real weapon-capable tools are counted once as tools")
local bat = item("Base.BaseballBat")
bat.IsWeapon = function() return true end
assert(storage.classifyItem(bat) == "weapons", "ordinary weapons retain their category")

-- Hibernation provisioning transfers real instances from assigned storage into
-- the resident inventory once, stops at the bounded reserve, and is idempotent.
local storedFood = {
    item("Base.TinnedSoup"), item("Base.TinnedSoup"),
    item("Base.TinnedSoup"), item("Base.TinnedSoup"),
}
local storedWater = {
    item("Base.WaterBottleFull"), item("Base.WaterBottleFull"),
    item("Base.WaterBottleFull"),
}
local provisionSource = container("crate", {
    storedFood[1], storedFood[2], storedFood[3], storedFood[4],
    storedWater[1], storedWater[2], storedWater[3],
})
local provisionObject = {}
function provisionObject:getObjectIndex() return 3 end
function provisionObject:getContainerByIndex(index)
    return index == 0 and provisionSource or nil
end
squares["30:30:0"] = square(30, 30, 0, provisionObject)
local provisionBase = { storage = { supplies = {
    key = "supplies", x = 30, y = 30, z = 0, objectIndex = 3,
    containerIndex = 0, containerType = "crate", category = "food",
    storageRole = "food",
} } }
local carriedFood = item("Base.TinnedSoup")
local provisionInventory = container("inventory", { carriedFood })
local provisionCharacter = {
    getInventory = function() return provisionInventory end,
    getCurrentSquare = function() return square(30, 31, 0, {}) end,
}
local provisioned, provisionReport = storage.provisionSurvivalSupplies(
    provisionBase, provisionCharacter, { food = 4, water = 3 }
)
assert(provisioned and provisionReport.transferred.food == 3
        and provisionReport.transferred.water == 3
        and provisionReport.after.food == 4 and provisionReport.after.water == 3,
    "base provisioning must fill only the bounded carried reserve from real stock")
assert(#provisionSource.values == 1 and #provisionInventory.values == 7,
    "provisioned instances must leave assigned storage and enter personal inventory")
local sourceAfterFirst = #provisionSource.values
local _, repeatedReport = storage.provisionSurvivalSupplies(
    provisionBase, provisionCharacter, { food = 4, water = 3 }
)
assert(#provisionSource.values == sourceAfterFirst
        and repeatedReport.transferred.food == 0 and repeatedReport.transferred.water == 0,
    "repeated hibernation preparation must not withdraw duplicate reserves")
squares["30:30:0"] = nil
local _, unavailableReport = storage.provisionSurvivalSupplies(
    provisionBase, { getInventory = function() return container("inventory", {}) end,
        getCurrentSquare = provisionCharacter.getCurrentSquare },
    { food = 1, water = 1 }
)
assert(unavailableReport.shortages.food ~= nil and unavailableReport.shortages.water ~= nil,
    "unloaded assigned storage must remain an explicit shortage, not fabricated stock")
local rollbackFood = item("Base.TinnedSoup")
local rollbackSource = container("crate", { rollbackFood })
provisionObject.getContainerByIndex = function(_, index)
    return index == 0 and rollbackSource or nil
end
squares["30:30:0"] = square(30, 30, 0, provisionObject)
local rollbackInventory = container("inventory", {})
local normalAdd = rollbackInventory.AddItem
rollbackInventory.AddItem = function(self, value)
    normalAdd(self, value)
    return false
end
local _, rollbackReport = storage.provisionSurvivalSupplies(
    provisionBase,
    { getInventory = function() return rollbackInventory end,
        getCurrentSquare = provisionCharacter.getCurrentSquare },
    { food = 1, water = 0 }
)
assert(rollbackSource:contains(rollbackFood) and not rollbackInventory:contains(rollbackFood)
        and rollbackReport.shortages.food ~= nil,
    "failed provisioning transfer must restore the real item to base storage")
print("Unloaded base provisioning PASS real=true bounded=true idempotent=true shortage=true rollback=true")

-- RimWorld priorities: rank helpers, persistence shape, deposit order.
-- Isolated shelves so earlier sections cannot disturb the fixture.
assert(storage.priorityRank(nil) == 2, "missing policy reads normal")
assert(storage.priorityRank({}) == 2, "missing priority reads normal")
assert(storage.priorityRank({ priority = "critical" }) == 0, "critical sorts first")
assert(storage.priorityRank({ priority = "preferred" }) == 1)
assert(storage.priorityRank({ priority = "normal" }) == 2)
assert(storage.priorityRank({ priority = "low" }) == 3, "low sorts last")
assert(storage.priorityRank({ priority = "penthouse" }) == 2, "unknown reads normal")
assert(storage.priorityLabel({ priority = "critical" }) == "Critical")
assert(storage.priorityLabel(nil) == "Normal")
local shelfACrate = container("crate", {})
local shelfBCrate = container("crate", {})
local shelfAObject, shelfBObject = {}, {}
function shelfAObject:getObjectIndex() return 11 end
function shelfAObject:getContainerByIndex(index) return index == 0 and shelfACrate or nil end
function shelfAObject:getContainerCount() return 1 end
function shelfBObject:getObjectIndex() return 12 end
function shelfBObject:getContainerByIndex(index) return index == 0 and shelfBCrate or nil end
function shelfBObject:getContainerCount() return 1 end
squares["10:30:0"] = square(10, 30, 0, shelfAObject)
squares["12:30:0"] = square(12, 30, 0, shelfBObject)
local shelfBase = { id = "base-shelves", storage = {
    ["shelf-a"] = { key = "shelf-a", x = 10, y = 30, z = 0, objectIndex = 11,
        containerIndex = 0, containerType = "crate", category = "food", storageRole = "food" },
    ["shelf-b"] = { key = "shelf-b", x = 12, y = 30, z = 0, objectIndex = 12,
        containerIndex = 0, containerType = "crate", category = "food", storageRole = "food" },
} }
local shelfWorker = { getCurrentSquare = function() return square(11, 30, 0, {}) end,
    getInventory = function() return container("inventory", {}) end }
local soupProbe = item("Base.TinnedSoup")
-- The shared approach stub sits by the old y=20 fixtures; trip deposits
-- near the y=30 shelves need an adjacent tile to prove reachability.
local shelfApproach = square(11, 30, 0, {})
function shelfApproach:isSomethingTo() return false end
local previousFinder = AdjacentFreeTileFinder
AdjacentFreeTileFinder = { Find = function() return shelfApproach end }
shelfBase.storage["shelf-a"].priority = "critical"
local ranked = assert(storage.findDepositTrip(shelfBase, shelfWorker, soupProbe, {}, 100))
assert(ranked.policy.key == "shelf-a", "critical shelf wins the deposit")
shelfBase.storage["shelf-a"].priority = nil
local unranked = assert(storage.findDepositTrip(shelfBase, shelfWorker, soupProbe, {}, 100))
assert(unranked.policy.key == "shelf-a",
    "unranked shelves keep distance-then-key order")
print("Storage priorities PASS ranks=true order=true legacy_default=true")
AdjacentFreeTileFinder = previousFinder

-- Ambient re-shelving: a stray meal in a non-accepting crate moves to
-- supplies through real native transfers, never fabricated or lost.
local organize = dofile(rootPath .. "/mod/42/media/lua/client/KS_BaseOrganize.lua")
local stray = item("Base.TinnedSoup")
stray.getID = function() return 4242 end
stray._container = destination
destination.values[#destination.values + 1] = stray
local organizerInventory = container("inventory", {})
local organizerSquare = squares["12:20:0"]
local organizer = {
    getCurrentSquare = function() return organizerSquare end,
    getInventory = function() return organizerInventory end,
    getCharacterActions = function() return { isEmpty = function() return true end } end,
}
local organizerQueue = { current = nil,
    indexOf = function() return -1 end }
ISTimedActionQueue = {
    add = function() end,
    getTimedActionQueue = function() return organizerQueue end,
    clear = function() organizerQueue.current = nil end,
}
KnoxInventoryActions.queueTransfer = function(_, item, source, dest)
    if source ~= nil and dest ~= nil and source.contains ~= nil and source:contains(item) then
        dest:AddItem(item)
        return {}, "queued"
    end
    return nil, "transfer_failed"
end
local organizerBridge = {
    moveNpc = function() return "MOVE_STARTED" end,
    tickNpc = function() return "Succeeded" end,
}
local plan = assert(organize.find(base, organizer,
    function() return true end, function() return false end))
assert(plan.item == stray, "misplaced meal is nominated")
assert(plan.destinationPolicy.key == "depot", "supplies is the accepting shelf")
local outcome, reason = "working", nil
for _ = 1, 20 do
    outcome, reason = organize.step(plan, organizer, base, organizerBridge, "tidy-1", 200)
    if plan.phase == "borrow_move" then organizerSquare = squares["12:20:0"] end
    if plan.phase == "deposit_move" then organizerSquare = squares["10:20:0"] end
    if outcome ~= "working" then break end
end
assert(outcome == "done" and reason == "organize_completed",
    "shelving completes end to end: " .. tostring(reason))
assert(depot:contains(stray) and not destination:contains(stray)
    and not organizerInventory:contains(stray),
    "the real item moves shelf to shelf with nothing left behind")
-- Settled shelves stay settled: nothing else qualifies right now.
assert(organize.find(base, organizer, function() return true end,
    function() return false end) == nil, "no reshuffle once everything is shelved")
print("Base organize PASS nominate=true transfer=true settled=true")
