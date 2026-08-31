local root = arg[1] or "."
dofile(root .. "/mod/42/media/lua/shared/KS_Currency.lua")
local data = {}
ModData = { getOrCreate = function() return data end }
Events = {}
for _, event in ipairs({ "OnSave", "OnPostSave", "OnGameStart" }) do Events[event] = { Add = function() end } end
dofile(root .. "/mod/42/media/lua/client/KS_TradeAvailability.lua")
getGameTime = function() return { getWorldAgeHours = function() return 24 end } end
dofile(root .. "/mod/42/media/lua/client/KS_Persistence.lua")
local function list(values)
    return { size = function() return #values end, get = function(_, i) return values[i + 1] end }
end
local function container(values)
    local result = { values = values or {} }
    function result:getItems() return list(self.values) end
    for _, item in ipairs(result.values) do item.container = result end
    return result
end
local function item(full, options)
    local result = options or {}
    result.full = full
    function result:getFullType() return self.full end
    function result:getContainer() return self.container end
    function result:isFavorite() return self.favorite == true end
    function result:getConditionMax() return 10 end
    function result:getCondition() return self.condition or 10 end
    function result:IsFood() return self.food ~= nil end
    function result:IsWeapon() return self.damage ~= nil end
    function result:IsClothing() return self.clothing == true end
    function result:IsInventoryContainer() return self.bag ~= nil end
    function result:getFluidContainer() return self.water and { getAmount = function() return self.water end } end
    function result:isCanBandage() return self.bandage ~= nil end
    function result:getBandagePower() return self.bandage end
    function result:getAmmoType() return self.ammo and { getItemKey = function() return self.ammo end } end
    function result:getCurrentAmmoCount() return self.rounds or 0 end
    function result:getMaxAmmo() return self.magazine and 15 or 0 end
    function result:hasTag(tag) return tag == "ammo" and self.ammoTag == true end
    if result.food ~= nil then function result:getHungerChange() return -self.food end end
    if result.damage ~= nil then
        function result:isBroken() return self.condition == 0 end
        function result:isRanged() return self.ranged == true end
        function result:getMinDamage() return self.damage end
        function result:getMaxDamage() return self.damage end
        function result:getMagazineType() return self.magazineType end
        function result:isRoundChambered() return self.chambered == true end
    end
    if result.clothing then
        function result:getBiteDefense() return self.protection or 0 end
        function result:getScratchDefense() return self.protection or 0 end
    end
    if result.bag then
        function result:getInventory() return self.bag end
        function result:getCapacity() return 20 end
        function result:getWeightReduction() return 50 end
    end
    return result
end
local function actor()
    local result = { data = {}, inventory = container(), hunger = .1, thirst = .1, x = 0, y = 0, z = 0 }
    function result:getInventory() return self.inventory end
    function result:getModData() return self.data end
    function result:getX() return self.x end
    function result:getY() return self.y end
    function result:getZ() return self.z end
    function result:getCurrentSquare() if not self.detached then return self end end
    function result:isDead() return self.dead == true end
    function result:isEquipped(candidate) return candidate.equipped == true end
    function result:isHandItem(candidate) return candidate.hand == true end
    function result:isAttachedItem(candidate) return candidate.attached == true end
    return result
end
ItemTag = { AMMO = "ammo" }
require = function() return true end
KnoxSurvivorNeeds = {
    isSafeFood = function(candidate) return candidate.food ~= nil and candidate.food > .01 and not candidate.rotten end,
    isWaterItem = function(candidate) return candidate.water ~= nil and candidate.water > 0 and not candidate.tainted end,
    snapshot = function(character) return { hunger = character.hunger, thirst = character.thirst,
        bleedingParts = character.bleeding or 0 } end,
}
local player, npc, otherPlayer = actor(), actor(), actor()
local playerId = KnoxPersistence.ensurePlayerId(player)
KnoxPersistence.ensurePlayerId(otherPlayer)
assert(KnoxPersistence.setRecord("npc", "record"))
KnoxSurvivorRuntime = { getCharacter = function(id) return id == "npc" and not npc.unloaded and npc or nil end }
getSpecificPlayer = function(index) return index == 0 and player or (index == 1 and otherPlayer or nil) end
local trade = dofile(root .. "/mod/42/media/lua/client/KS_TradeValuation.lua")
local function quote(giving, taking) return trade.quote(player, "npc", giving, taking) end
local function rejected(giving, taking, expected)
    local result, reason = quote(giving, taking)
    assert(result == nil and reason == expected, "expected " .. expected .. ", got " .. tostring(reason))
end
local gift = item("Base.Bag_DuffelBag", { bag = container() })
local shirt = item("Base.Shirt", { clothing = true })
player.inventory, npc.inventory = container({ gift }), container({ shirt })
local q = assert(quote({ gift }, { shirt }))
assert(q.acceptable and q.margin == 1.35 and q.offeredValue > q.requestedValue)
assert(data.survivors.npc.playerRelationships[playerId] == nil, "quote does not create conversation or reward trust")
assert(gift.container == player.inventory and shirt.container == npc.inventory, "quote never moves real items")
assert(not quote({}, { shirt }) and not quote({ gift }, {}), "no empty or free trade")
rejected({ gift, gift }, { shirt }, "duplicate_or_sparse_offer")
rejected({ [2] = gift }, { shirt }, "duplicate_or_sparse_offer")
rejected({ [33] = gift }, { shirt }, "invalid_offer")
rejected({ fake = gift }, { shirt }, "invalid_offer")
rejected({ shirt }, { shirt }, "item_not_owned")
for _, field in ipairs({ "equipped", "favorite", "hand", "attached" }) do
    gift[field] = true rejected({ gift }, { shirt }, "equipped_or_favorite") gift[field] = nil
end
shirt.equipped = true rejected({ gift }, { shirt }, "equipped_or_favorite") shirt.equipped = nil
gift.container = nil rejected({ gift }, { shirt }, "inventory_unreadable_or_too_large") gift.container = player.inventory
local unknown = item("Custom.QuestItem")
player.inventory = container({ gift, unknown })
rejected({ unknown }, { shirt }, "unsupported_item")
local malicious = item("Base.UnknownThing")
function malicious:getDisplayCategory() error("classification must not infer value from a cosmetic category") end
player.inventory = container({ gift, malicious })
rejected({ malicious }, { shirt }, "unsupported_item")
assert(quote({ gift }, { shirt }), "unknown items do not block unrelated known offers")

-- Real quantities and condition, not a flat item count or a caller-supplied price.
local food = item("Base.Apple", { food = .1 })
player.inventory = container({ food, gift })
local first = assert(quote({ food }, { shirt })).offeredValue
food.food = .3
assert(assert(quote({ food }, { shirt })).offeredValue > first * 2)
food.rotten = true rejected({ food }, { shirt }, "unsupported_item") food.rotten = nil
local water = item("Base.WaterBottle", { water = .5 })
player.inventory = container({ food, water, gift })
first = assert(quote({ water }, { shirt })).offeredValue
water.water = 1
assert(assert(quote({ water }, { shirt })).offeredValue > first)
water.tainted = true rejected({ water }, { shirt }, "unsupported_item") water.tainted = nil
first = assert(quote({ gift }, { shirt })).offeredValue
gift.condition = 2
assert(assert(quote({ gift }, { shirt })).offeredValue < first / 2)
gift.condition = 10
npc.hunger = .9
local urgent = assert(quote({ food }, { shirt })).offeredValue
npc.hunger = .1
assert(assert(quote({ food }, { shirt })).offeredValue < urgent)
npc.inventory = container({ shirt, item("Base.Apple", { food = .8 }) })
local stockedValue = assert(quote({ food }, { shirt })).offeredValue
npc.inventory = container({ shirt })
assert(assert(quote({ food }, { shirt })).offeredValue > stockedValue, "available stock lowers demand")
npc.inventory = container({ shirt, item("Base.Apple", { food = .8 }) })
local secondFood = item("Base.Apple", { food = .1 })
player.inventory = container({ food, secondFood, gift })
local a = assert(quote({ food, secondFood }, { shirt }))
local b = assert(quote({ secondFood, food }, { shirt }))
assert(math.abs(a.offeredValue - b.offeredValue) < .000001, "basket order cannot change valuation")
local wholeValue = a.offeredValue
food.food = food.food + secondFood.food
assert(math.abs(assert(quote({ food }, { shirt })).offeredValue - wholeValue) < .000001,
    "splitting equivalent food quantity does not manufacture barter value")

-- Check the entire outgoing basket against remaining supplies, allowing genuine replacement.
local meals = {}
for i = 1, 6 do meals[i] = item("Base.Apple", { food = .1 }) end
npc.inventory = container(meals)
assert(quote({ gift }, { meals[1], meals[2] }))
rejected({ gift }, { meals[1], meals[2], meals[3] }, "food_reserve")
assert(quote({ food }, { meals[1], meals[2], meals[3] }), "real incoming food can replenish reserve")
local waterReserve = item("Base.WaterBottle", { water = 1 })
npc.inventory = container({ waterReserve })
rejected({ gift }, { waterReserve }, "water_reserve")
local bandage = item("Base.Bandage", { bandage = 4 })
npc.inventory = container({ bandage })
rejected({ gift }, { bandage }, "bandage_reserve")
local dirty = item("Base.BandageDirty", { bandage = 1 })
player.inventory = container({ gift, dirty })
rejected({ dirty }, { bandage }, "bandage_reserve")
local weak = item("Base.RollingPin", { damage = .5 })
local best = item("Base.Crowbar", { damage = 1.5 })
npc.inventory = container({ weak, best })
assert(quote({ gift }, { weak }))
rejected({ gift }, { best }, "best_melee_reserve")
local upgrade = item("Base.Axe", { damage = 2 })
player.inventory = container({ gift, upgrade })
assert(quote({ upgrade }, { best }))
upgrade.condition = 0 rejected({ upgrade }, { weak }, "unsupported_item") upgrade.condition = 10
local gun = item("Base.Pistol", { damage = 1, ranged = true, ammo = "Base.Bullets9mm", magazineType = "Base.9mmClip" })
local ammo = item("Base.Bullets9mm", { ammoTag = true })
local wrongAmmo = item("Base.ShotgunShells", { ammoTag = true })
local magazine = item("Base.9mmClip", { ammo = "Base.Bullets9mm", magazine = true, rounds = 5 })
npc.inventory = container({ gun, ammo, wrongAmmo, magazine })
rejected({ gift }, { ammo }, "compatible_ammunition_reserve")
rejected({ gift }, { magazine }, "compatible_ammunition_reserve")
assert(quote({ gift }, { wrongAmmo }), "unrelated ammo need not be hoarded as a weapon reserve")
player.inventory = container({ ammo, wrongAmmo, gift })
npc.inventory = container({ gun, shirt })
assert(assert(quote({ ammo }, { shirt })).offeredValue > assert(quote({ wrongAmmo }, { shirt })).offeredValue,
    "native ammo item key determines demand")

-- Nested real inventory is supported, but favorite bags, cycles, corrupt ownership
-- and unbounded scans fail safely. Nonempty bags cannot conceal an unpriced bundle.
local bag = item("Base.Bag_Schoolbag", { bag = container({ gift }) })
player.inventory = container({ bag })
npc.inventory = container({ shirt })
assert(quote({ gift }, { shirt }))
rejected({ bag }, { shirt }, "unsupported_item")
bag.favorite = true rejected({ gift }, { shirt }, "equipped_or_favorite") bag.favorite = nil
assert(#assert(trade.stock(player, "npc")).playerItems == 1, "contents of an ordinary bag are available")
function bag:isHidden() return self.hidden == true end
bag.hidden = true
assert(#assert(trade.stock(player, "npc")).playerItems == 0, "hidden bag contents are not advertised")
rejected({ gift }, { shirt }, "equipped_or_favorite")
bag.hidden = false
function gift:isHidden() return self.hidden == true end
gift.hidden = true
assert(#assert(trade.stock(player, "npc")).playerItems == 0, "hidden items are not advertised")
rejected({ gift }, { shirt }, "equipped_or_favorite")
gift.hidden = false
bag.bag.values[#bag.bag.values + 1] = bag
rejected({ gift }, { shirt }, "inventory_unreadable_or_too_large")
bag.bag.values[2] = nil
local originalItems = player.inventory.getItems
function player.inventory:getItems() return { size = function() return 5000 end } end
rejected({ gift }, { shirt }, "inventory_unreadable_or_too_large")
player.inventory.getItems = originalItems
player.inventory = container({ gift })

-- Exchanging an item cannot reward itself through stale ownership on a re-quote.
player.inventory = container({})
rejected({ gift }, { shirt }, "item_not_owned")
player.inventory = container({ gift })

-- Quotes re-read canonical relationships, life, loaded body and actual player identity.
first = assert(quote({ gift }, { shirt })).requestedValue
KnoxPersistence.getPlayerRelationship(playerId, "npc").trust = 100
assert(assert(quote({ gift }, { shirt })).requestedValue < first)
assert(KnoxPersistence.setRecord("b", "b") and KnoxPersistence.setRecord("c", "c"))
local group = assert(KnoxPersistence.createTravelGroup({ "npc", "b", "c" }, 24))
local faction = assert(KnoxPersistence.promoteTravelGroupToFaction(group.id, 24))
local beforeReputation = assert(quote({ gift }, { shirt })).requestedValue
assert(KnoxPersistence.recordPlayerContribution(playerId, "npc", "defense", 24))
local withReputation = assert(quote({ gift }, { shirt })).requestedValue
assert(withReputation < beforeReputation, "faction reputation affects terms independently of maxed personal trust")
local base = assert(KnoxPersistence.createBase("faction", faction.id,
    { minX = 0, minY = 0, width = 10, height = 10, z = 0 }, 24))
local task = assert(KnoxPersistence.queueBaseTask(base.id, "supply", { x = 1, y = 1, z = 0 },
    { items = { ["Base.Shirt"] = 1 } }, 50))
rejected({ gift }, { shirt }, "task_resource")
task.state = "completed"
assert(quote({ gift }, { shirt }), "completed work releases resource reservation")
task.state = "queued"
task.requirements.items = { ["Base.Bag_DuffelBag"] = 1 }
local needed = assert(quote({ gift }, { shirt })).offeredValue
task.state = "completed"
assert(assert(quote({ gift }, { shirt })).offeredValue < needed, "canonical faction job needs increase demand")
local playerFaction = KnoxPersistence.getPlayerFaction(playerId)
assert(KnoxPersistence.setFactionRelationshipDisposition(faction.id, playerFaction.id, "hostile", "test", 24))
rejected({ gift }, { shirt }, "hostile")
assert(KnoxPersistence.setFactionRelationshipDisposition(faction.id, playerFaction.id, "neutral", "test", 24))
data.survivors.npc.affiliation.kind = "player"
rejected({ gift }, { shirt }, "player_owned")
data.survivors.npc.affiliation.kind = "independent"
npc.x = 4 rejected({ gift }, { shirt }, "too_far") npc.x = 0
npc.z = 1 rejected({ gift }, { shirt }, "too_far") npc.z = 0
npc.detached = true rejected({ gift }, { shirt }, "too_far") npc.detached = nil
npc.dead = true rejected({ gift }, { shirt }, "not_loaded") npc.dead = nil
npc.unloaded = true rejected({ gift }, { shirt }, "not_loaded") npc.unloaded = nil
assert(not trade.quote(npc, "npc", { gift }, { shirt }), "off-slot NPC cannot impersonate the player")
data.survivors.npc.alive = false rejected({ gift }, { shirt }, "not_alive") data.survivors.npc.alive = true
assert(not trade.quote(player, "missing", { gift }, { shirt }) and data.survivors.missing == nil)
local before = assert(quote({ gift }, { shirt }))
dofile(root .. "/mod/42/media/lua/client/KS_Persistence.lua")
local after = assert(quote({ gift }, { shirt }))
assert(before.requestedValue == after.requestedValue and before.offeredValue == after.offeredValue,
    "save/module reload does not reroll prices or forget trust")
local savedInventory = npc.inventory
npc.inventory = player.inventory rejected({ gift }, { shirt }, "shared_inventory")
local sharedStock, sharedReason = trade.stock(player, "npc")
assert(sharedStock == nil and sharedReason == "shared_inventory", "browsing shares exchange ownership safeguards")
npc.inventory = savedInventory
local npcEquivalent = item("Base.Bag_DuffelBag", { bag = container() })
npc.inventory = container({ npcEquivalent })
assert(not assert(quote({ gift }, { npcEquivalent })).acceptable,
    "even maximum trust keeps a spread; equivalent item cycling cannot generate profit")
npc.inventory = savedInventory
assert(gift.container == player.inventory and shirt.container == npc.inventory,
    "all quote/rejection paths leave real inventory ownership untouched")
print("trade valuation tests passed")
return { actor = actor, item = item, container = container, list = list, data = data }
