local StartingGear = rawget(_G, "KnoxSurvivorStartingGear") or {}
_G.KnoxSurvivorStartingGear = StartingGear

local SIMPLE_WEAPONS = {
    "Base.RollingPin",
    "Base.Pan",
    "Base.KitchenKnife",
    "Base.Hammer",
    "Base.PipeWrench",
    "Base.BaseballBat",
}

local SIMPLE_FOOD = {
    "Base.Crisps",
}

local MEDICAL = {
    "Base.RippedSheets",
    "Base.Bandage",
}

local function addRandom(inventory, choices, added)
    local fullType = choices[ZombRand(#choices) + 1]
    local success, item = pcall(function()
        return inventory:AddItem(fullType)
    end)
    if success and item ~= nil then
        added[#added + 1] = fullType
        return true
    end
    return false
end

-- Character creation supplies clothing and the occasional bag. This adds only a
-- restrained pocket-sized start: many people remain poorly prepared, while some
-- arrive with the sort of ordinary item a new player might reasonably carry.
function StartingGear.initialize(id, character, bridge)
    if character == nil or character:getInventory() == nil then
        return false, "inventory_unavailable"
    end
    local inventory = character:getInventory()
    local added = {}
    if ZombRand(100) < 72 then
        addRandom(inventory, SIMPLE_WEAPONS, added)
    end
    if ZombRand(100) < 45 then
        addRandom(inventory, { "Base.WaterBottle" }, added)
    end
    if ZombRand(100) < 35 then
        addRandom(inventory, SIMPLE_FOOD, added)
    end
    if ZombRand(100) < 30 then
        addRandom(inventory, MEDICAL, added)
    end

    local equipped = "not_requested"
    if bridge ~= nil and bridge.equipBestNpc ~= nil then
        local success, result = pcall(function()
            return bridge:equipBestNpc(id)
        end)
        equipped = success and tostring(result) or "failed=" .. tostring(result)
    end
    return true,
        "items=" .. tostring(#added)
            .. " types=" .. table.concat(added, ",")
            .. " equipment=" .. equipped
end

return StartingGear
