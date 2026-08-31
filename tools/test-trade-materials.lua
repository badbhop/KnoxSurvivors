local root = arg[1] or "."
local f = dofile(root .. "/tools/test-trade-valuation.lua")
local player, npc = f.actor(), f.actor()
KnoxPersistence.ensurePlayerId(player)
assert(KnoxPersistence.setRecord("priced", "record"))
getSpecificPlayer = function(n) if n == 0 then return player end end
KnoxSurvivorRuntime.getCharacter = function(id) if id == "priced" then return npc end end
local shirt = f.item("Base.Shirt", { clothing = true })
npc.inventory = f.container({ shirt })
local function medicine(uses)
    local item = f.item("Base.Pills")
    item.IsDrainable = function() return true end
    item.getCurrentUsesFloat = function() return uses * .1 end
    item.getUseDelta = function() return .1 end
    return item
end
local full, partial = medicine(10), medicine(5)
player.inventory = f.container({ full, partial })
local function quote(give, take) return KnoxTradeValuation.quote(player, "priced", give, take or { shirt }) end
local fullQuote, partialQuote = assert(quote({ full })), assert(quote({ partial }))
assert(fullQuote.offeredValue > partialQuote.offeredValue, "real remaining doses affect price")
npc.inventory = f.container({ partial })
player.inventory = f.container({ full })
local result, reason = quote({ full }, { partial })
assert(result ~= nil, "replacing medicine preserves a carried reserve: " .. tostring(reason))
local gift = f.item("Base.Bag_DuffelBag", { bag = f.container() })
player.inventory = f.container({ gift })
result, reason = quote({ gift }, { partial })
assert(result == nil and reason == "medical_reserve", "last medicine cannot be sold for unrelated gear")
npc.inventory = f.container({ shirt })
local large = f.item("Base.SheetMetal")
local small = { f.item("Base.SmallSheetMetal"), f.item("Base.SmallSheetMetal"),
    f.item("Base.SmallSheetMetal"), f.item("Base.SmallSheetMetal") }
player.inventory = f.container({ large, small[1], small[2], small[3], small[4] })
assert(math.abs(assert(quote({ large })).offeredValue - assert(quote(small)).offeredValue) < .00001,
    "equivalent native sheet units use the same price and saturation")
ProceduralDistributions = { list = { a = { items = { "Pills", .1, "Nails", 10, "Invalid", 0/0 },
    junk = { items = { "Base.Pills", .2 } } } } }
assert(KnoxTradeAvailability.refresh())
assert(KnoxTradeAvailability.factor("Base.Pills") > KnoxTradeAvailability.factor("Base.Nails"))
assert(KnoxTradeAvailability.factor("Mod.Unknown") == 1 and KnoxTradeAvailability.factor("Base.Invalid") == 1)
local before = KnoxTradeAvailability.factor("Base.Pills")
ProceduralDistributions.list.a.items[2] = 99
assert(KnoxTradeAvailability.factor("Base.Pills") == before, "quotes use stable session cache")
ProceduralDistributions = nil
assert(not KnoxTradeAvailability.refresh() and KnoxTradeAvailability.factor("Base.Pills") == 1)
print("Trade materials PASS remaining_doses=true medical_reserve=true native_units=true bounded_rarity=true")
