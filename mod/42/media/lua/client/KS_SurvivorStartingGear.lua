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

local function add(inventory, fullType, added)
    local success, item = pcall(function()
        return inventory:AddItem(fullType)
    end)
    if success and item ~= nil then
        added[#added + 1] = fullType
        return true
    end
    return false
end

local function addRandom(inventory, choices, added)
    return add(inventory, choices[ZombRand(#choices) + 1], added)
end

local function addMany(inventory, fullType, count, added)
    for _ = 1, count do
        if not add(inventory, fullType, added) then return false end
    end
    return true
end

-- Character creation supplies clothing and the occasional bag. This adds only a
-- restrained pocket-sized start: many people remain poorly prepared, while some
-- arrive with the sort of ordinary item a new player might reasonably carry.
function StartingGear.initialize(id, character, bridge, loadoutTheme)
    if character == nil or character:getInventory() == nil then
        return false, "inventory_unavailable"
    end
    local inventory = character:getInventory()
    local added = {}
    if loadoutTheme == "police" then
        -- A restrained regular-officer kit.  Uniform clothing comes from the
        -- native policeofficer creator definition; no firearm, ammo, artificial
        -- skill or combat multiplier is granted here.
        if not add(inventory, "Base.Nightstick", added)
            or not add(inventory, "Base.WalkieTalkie4", added) then
            return false, "police_kit_item_unavailable"
        end
    elseif loadoutTheme == "science" then
        -- Build 42 has no scientist profession or magic research inventory.
        -- These are ordinary real field/medical items; the visible lab coat is
        -- applied by the creator appearance path and captured only once.
        if not add(inventory, "Base.Clipboard", added)
            or not add(inventory, "Base.Pen", added)
            or not add(inventory, "Base.Scalpel", added) then
            return false, "science_kit_item_unavailable"
        end
    elseif loadoutTheme == "military" then
        -- A real M9, compatible magazine and three five-round 9mm stacks let
        -- the existing native reload system establish weapon state. Nothing
        -- here fabricates chamber/magazine state or combat bonuses.
        if not add(inventory, "Base.HuntingKnife", added)
            or not add(inventory, "Base.Pistol", added)
            or not add(inventory, "Base.9mmClip", added)
            or not addMany(inventory, "Base.Bullets9mm", 3, added)
            or not add(inventory, "Base.WalkieTalkie5", added) then
            return false, "military_kit_item_unavailable"
        end
    elseif ZombRand(100) < 72 then
        addRandom(inventory, SIMPLE_WEAPONS, added)
    end
    local waterChance = loadoutTheme == "police" and 65
        or loadoutTheme == "science" and 60
        or loadoutTheme == "military" and 75 or 45
    if ZombRand(100) < waterChance then
        addRandom(inventory, { "Base.WaterBottle" }, added)
    end
    if ZombRand(100) < 35 then
        addRandom(inventory, SIMPLE_FOOD, added)
    end
    local medicalChance = loadoutTheme == "police" and 45
        or loadoutTheme == "science" and 55
        or loadoutTheme == "military" and 60 or 30
    if ZombRand(100) < medicalChance then
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
            .. " theme=" .. tostring(loadoutTheme or "ordinary")
            .. " equipment=" .. equipped
end

return StartingGear
