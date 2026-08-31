local root = arg[1] or "."
local game = arg[2] or "C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid"
local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a") file:close() return text
end
local nativeContainers = read(game .. "/media/scripts/generated/items/container.txt")
for _, name in ipairs({ "Wallet", "Wallet_Female", "Wallet_Male", "Wallet_Hide" }) do
    local definition = assert(nativeContainers:match("item " .. name .. "%s*{(.-)}"))
    assert(definition:find("AcceptItemFunction = AcceptItemFunction.Wallet", 1, true)
        and definition:find("Capacity = 1,", 1, true) and definition:find("MaxItemSize = 0.2,", 1, true),
        "native wallet restrictions changed")
end
local recipes = read(game .. "/media/scripts/generated/recipes/recipes_packing.txt")
local unbundle = assert(recipes:match("craftRecipe UnbundleMoney(.-)craftRecipe"))
assert(unbundle:find("item 1 [Base.MoneyBundle]", 1, true) and unbundle:find("item 100 Base.Money", 1, true),
    "native cash denomination changed")
local fixture = dofile(root .. "/tools/test-trade-action.lua")
local currency = dofile(root .. "/mod/42/media/lua/shared/KS_Currency.lua")

-- Registry and script setup use only the exact native signatures inspected in
-- 42.20.3. Loading twice may reapply one property, never replace an item script.
local location = {}
ItemBodyLocation = { register = function(name)
    assert(name == "knoxsurvivors:wallet") return location
end }
dofile(root .. "/mod/42/media/registries.lua")
local locations = {}
BodyLocations = { getGroup = function(name)
    assert(name == "Human")
    return { getOrCreateLocation = function(_, value) locations[value] = true end }
end }
ItemType = { CONTAINER = "container" }
local scripts = {}
for _, name in ipairs({ "Wallet", "Wallet_Female", "Wallet_Male", "Wallet_Hide", "KeyRing", "Bag_Schoolbag" }) do
    scripts["Base." .. name] = { full = "Base." .. name, updates = 0,
        getItemType = function() return ItemType.CONTAINER end,
        DoParam = function(self, param)
            assert(param == "CanBeEquipped = knoxsurvivors:wallet")
            self.location, self.updates = location, self.updates + 1
        end }
end
ScriptManager = { instance = { getItem = function(_, name) return scripts[name] end } }
local wallets = dofile(root .. "/mod/42/media/lua/shared/KS_Wallets.lua")
assert(locations[location] and scripts["Base.Wallet"].location == location)
assert(scripts["Base.KeyRing"].updates == 0 and scripts["Base.Bag_Schoolbag"].updates == 0)
assert(wallets.install() and scripts["Base.Wallet"].updates == 2)
scripts["Base.Wallet_Hide"] = nil
scripts["Base.Wallet_Male"].getItemType = function() return "normal" end
assert(wallets.install() and scripts["Base.Wallet_Male"].updates == 2, "skip removed or replaced noncontainer definitions")
KnoxWalletLocation = nil
assert(not wallets.install(), "missing registry does not invent a body slot")
KnoxWalletLocation = location

local bill, bundle = fixture.item("Base.Money"), fixture.item("Base.MoneyBundle")
local gold, silver = fixture.item("Base.GoldCoin"), fixture.item("Base.SilverCoin")
assert(currency.describe(bundle).quantity == 100)
assert(currency.describe(bundle).value == currency.describe(bill).value * 100)
assert(currency.describe(gold).kind == "gold" and currency.describe(silver).kind == "silver")
assert(currency.describe(fixture.item("Other.Money")) == nil and currency.describe({}) == nil)
assert(currency.describe(fixture.item("Base.GoldBar")) == nil, "no unresearched gold-bar exchange rate")
local changed = currency.describe(bill) changed.quantity = 900
assert(currency.describe(bill).quantity == 1, "callers cannot mutate the currency definitions")

-- Native acceptance is unchanged. Cash/coins fit; a bundle or large gold bar
-- must remain in normal inventory until vanilla allows it (e.g. unbundle cash).
ItemTag.FITS_WALLET = "wallet"
dofile(game .. "/media/lua/server/Items/AcceptItemFunction.lua")
local function walletGood(full)
    local result = fixture.item(full)
    function result:IsMap() return false end
    function result:IsLiterature() return false end
    function result:hasTag(tag)
        return tag == ItemTag.FITS_WALLET and (full == "Base.Money" or full == "Base.GoldCoin" or full == "Base.SilverCoin")
    end
    return result
end
assert(AcceptItemFunction.Wallet(nil, walletGood("Base.Money")))
assert(AcceptItemFunction.Wallet(nil, walletGood("Base.GoldCoin")))
assert(AcceptItemFunction.Wallet(nil, walletGood("Base.SilverCoin")))
assert(not AcceptItemFunction.Wallet(nil, walletGood("Base.MoneyBundle")))
assert(not AcceptItemFunction.Wallet(nil, walletGood("Base.GoldBar")))

-- Execute native wearing completion on the new location. No off-slot UI call is
-- needed for NPC wearing: Knox's existing Java equipment gateway owns that path.
setmetatable(ItemBodyLocation, { __index = function(_, name) return name end })
instanceof = function(item, class) return class == "InventoryContainer" and item.bag ~= nil end
dofile(game .. "/media/lua/shared/TimedActions/ISWearClothing.lua")
local player, npc, controller, giving, taking = fixture.setup()
local wallet = fixture.item("Base.Wallet", { bag = fixture.container({ bill }) })
player.inventory:AddItem(wallet)
function wallet:canBeEquipped() return location end
function wallet:getBodyLocation() return nil end
function wallet:getCategory() return "Container" end
function wallet:getCapacity() return 1 end
function wallet:getWeightReduction() return 0 end
function player:getWornItem(value) return self.worn and self.worn[value] end
function player:setWornItem(value, item) self.worn = self.worn or {} self.worn[value] = item item.equipped = true end
function player:removeFromHands() end
local wear = setmetatable({ item = wallet, character = player }, { __index = ISWearClothing })
assert(wear:complete() and player:getWornItem(location) == wallet)
assert(not wear:complete() and bill:getContainer() == wallet.bag, "wear is idempotent and preserves contents")
local equipment = dofile(root .. "/mod/42/media/lua/client/KS_EquipmentIntelligence.lua")
player.worn, wallet.equipped = {}, false
local choice = assert(equipment.choose(player, { wallet }))
assert(choice.kind == "wear" and choice.item == wallet, "existing equipment policy recognizes a carried wallet")
player:setWornItem(location, wallet)
assert(equipment.choose(player, { wallet }) == nil, "no repeated wallet equip")

-- Spend real cash from a worn wallet through the actual trade action; the wallet
-- and its remaining coins are neither unequipped nor replaced.
local money = {}
for i = 1, 20 do money[i] = fixture.item("Base.Money") wallet.bag:AddItem(money[i]) end
wallet.bag:AddItem(gold)
local action = assert(KnoxTradeActions.queue(player, "exchange", money, { taking }))
action:perform()
assert(action.success and player:getWornItem(location) == wallet and gold:getContainer() == wallet.bag)
for _, item in ipairs(money) do assert(item:getContainer() == npc.inventory) end
assert(taking:getContainer() == player.inventory and controller.tradeAction == nil)

player, npc, controller, giving, taking = fixture.setup()
player.inventory:AddItem(bundle)
local quote = assert(KnoxTradeValuation.quote(player, "exchange", { bundle }, { taking }))
assert(quote.acceptable, "bundled cash uses the same existing barter acceptance path")
local equivalentStock = {}
for i = 1, 100 do equivalentStock[i] = fixture.item("Base.Money") end
npc.inventory:AddItem(fixture.item("Base.MoneyBundle"))
local bundledStock = assert(KnoxTradeValuation.quote(player, "exchange", { bundle }, { taking })).offeredValue
npc.inventory = fixture.container({ taking })
for _, item in ipairs(equivalentStock) do npc.inventory:AddItem(item) end
local unpackedStock = assert(KnoxTradeValuation.quote(player, "exchange", { bundle }, { taking })).offeredValue
assert(math.abs(bundledStock - unpackedStock) < .000001, "unpacking does not erase stock saturation")
local reverse = assert(KnoxTradeValuation.quote(player, "exchange", { bundle }, { npc.inventory.values[2] }))
assert(reverse.requestedValue > currency.describe(bill).value, "currency selling retains the reputation spread")
print("wallet/currency PASS native-wear=true native-restrictions=true cash-ratio=true real-trade=true stable-equipment=true")
