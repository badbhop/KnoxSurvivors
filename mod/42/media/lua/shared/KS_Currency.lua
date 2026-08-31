-- Physical barter goods, not an account balance or an item-generation service.
local Currency = {}
_G.KnoxCurrency = Currency
local GOODS = {
    ["Base.Money"] = { kind = "cash", quantity = 1, unitValue = .25 },
    -- Native 42.20.3 UnbundleMoney produces exactly 100 Base.Money.
    ["Base.MoneyBundle"] = { kind = "cash", quantity = 100, unitValue = .25 },
    ["Base.SilverCoin"] = { kind = "silver", quantity = 1, unitValue = 2 },
    ["Base.GoldCoin"] = { kind = "gold", quantity = 1, unitValue = 8 },
}

function Currency.describe(item)
    if item == nil or tostring(item) == "null" or item.getFullType == nil then return nil end
    local ok, full = pcall(item.getFullType, item)
    local goods = ok and GOODS[full] or nil
    if goods == nil then return nil end
    return { kind = goods.kind, quantity = goods.quantity, value = goods.unitValue * goods.quantity }
end

return Currency
