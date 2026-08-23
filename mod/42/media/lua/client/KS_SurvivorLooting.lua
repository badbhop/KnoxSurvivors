require "KS_SurvivorNeeds"

local Looting = rawget(_G, "KnoxSurvivorLooting") or {}
_G.KnoxSurvivorLooting = Looting

local ESSENTIAL_TOOLS = {
    ["Base.Axe"] = true,
    ["Base.HandAxe"] = true,
    ["Base.Hammer"] = true,
    ["Base.Saw"] = true,
    ["Base.Screwdriver"] = true,
    ["Base.Wrench"] = true,
    ["Base.LugWrench"] = true,
    ["Base.Jack"] = true,
    ["Base.TirePump"] = true,
}

local MEDICAL_TYPES = {
    ["Base.AlcoholWipes"] = true,
    ["Base.BottleDisinfectant"] = true,
    ["Base.Pills"] = true,
    ["Base.PillsAntiDep"] = true,
    ["Base.PillsBeta"] = true,
    ["Base.PillsSleepingTablets"] = true,
    ["Base.SutureNeedle"] = true,
    ["Base.Tweezers"] = true,
}

local function walkInventory(container, visitor)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        visitor(item)
        if item:IsInventoryContainer() then
            walkInventory(item:getInventory(), visitor)
        end
    end
end

local function weaponScore(item)
    if item == nil or not item:IsWeapon() or item:isRanged() or item:isBroken() then
        return nil
    end
    local condition = item:getConditionMax() > 0
        and item:getCondition() / item:getConditionMax()
        or 0
    return ((item:getMinDamage() + item:getMaxDamage()) * 5)
        + condition * 5
        + item:getMaxRange()
        + item:getBaseSpeed()
end

local function clothingScore(item)
    if item == nil or not item:IsClothing() or item:getBodyLocation() == nil then
        return nil
    end
    local condition = item:getConditionMax() > 0
        and item:getCondition() / item:getConditionMax()
        or 0
    return item:getBiteDefense() * 0.08
        + item:getScratchDefense() * 0.04
        + item:getInsulation() * 2
        + condition * 3
end

local function bagScore(item)
    if item == nil or not item:IsInventoryContainer() then
        return nil
    end
    return item:getCapacity() + item:getWeightReduction() * 0.15
end

local function inventoryFacts(character)
    local facts = {
        bestWeapon = -math.huge,
        food = 0,
        water = 0,
        bandages = 0,
        medical = 0,
        fullTypes = {},
    }
    walkInventory(character:getInventory(), function(item)
        facts.fullTypes[item:getFullType()] = true
        local score = weaponScore(item)
        if score ~= nil then
            facts.bestWeapon = math.max(facts.bestWeapon, score)
        end
        if KnoxSurvivorNeeds.isSafeFood(item) then
            facts.food = facts.food + 1
        end
        if KnoxSurvivorNeeds.isWaterItem(item, true) then
            facts.water = facts.water + 1
        end
        if item:isCanBandage() then
            facts.bandages = facts.bandages + 1
        end
        if MEDICAL_TYPES[item:getFullType()] then
            facts.medical = facts.medical + 1
        end
    end)
    return facts
end

local function candidateScore(character, facts, item)
    local weapon = weaponScore(item)
    if weapon ~= nil and weapon > facts.bestWeapon + 0.25 then
        return 100 + weapon - math.max(0, facts.bestWeapon), "weapon_upgrade"
    end
    if item:IsClothing() and item:getBodyLocation() ~= nil then
        local worn = character:getWornItem(item:getBodyLocation())
        local current = clothingScore(worn) or -1
        local candidate = clothingScore(item)
        if candidate ~= nil and candidate > current + 0.5 then
            return 70 + candidate - math.max(0, current), "clothing_upgrade"
        end
    end
    if item:IsInventoryContainer() and item:getBodyLocation() ~= nil then
        local worn = character:getWornItem(item:getBodyLocation())
        local candidate = bagScore(item)
        local current = bagScore(worn) or -1
        if candidate ~= nil and candidate > current + 1 then
            return 65 + candidate - math.max(0, current), "bag_upgrade"
        end
    end
    if item:isCanBandage() and facts.bandages < 3 then
        return 60 + item:getBandagePower(), "medical_stock"
    end
    if MEDICAL_TYPES[item:getFullType()] and facts.medical < 4
        and not facts.fullTypes[item:getFullType()] then
        return 55, "medical_stock"
    end
    if KnoxSurvivorNeeds.isWaterItem(item, false) and facts.water < 2 then
        return 50, "water_stock"
    end
    if KnoxSurvivorNeeds.isSafeFood(item) and facts.food < 4 then
        return 45 + math.abs(item:getHungerChange()), "food_stock"
    end
    if ESSENTIAL_TOOLS[item:getFullType()] and not facts.fullTypes[item:getFullType()] then
        return 40, "tool_stock"
    end
    return nil, nil
end

local function applySelectedFacts(facts, item)
    local weapon = weaponScore(item)
    if weapon ~= nil then
        facts.bestWeapon = math.max(facts.bestWeapon, weapon)
    end
    if KnoxSurvivorNeeds.isSafeFood(item) then
        facts.food = facts.food + 1
    end
    if KnoxSurvivorNeeds.isWaterItem(item, true) then
        facts.water = facts.water + 1
    end
    if item:isCanBandage() then
        facts.bandages = facts.bandages + 1
    end
    if MEDICAL_TYPES[item:getFullType()] then
        facts.medical = facts.medical + 1
    end
    facts.fullTypes[item:getFullType()] = true
end

function Looting.plan(character, container, maximumItems)
    if character == nil or container == nil then
        return {}
    end
    local facts = inventoryFacts(character)
    local candidates = {}
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local score, reason = candidateScore(character, facts, item)
        if score ~= nil then
            candidates[#candidates + 1] = { item = item, score = score, reason = reason }
        end
    end
    table.sort(candidates, function(first, second)
        return first.score > second.score
    end)
    local selected = {}
    local categoryCounts = {}
    local limit = math.max(1, math.min(4, maximumItems or 3))
    local remainingCapacity = math.max(
        0,
        character:getInventory():getFreeCapacity(character)
    )
    for _, candidate in ipairs(candidates) do
        local currentScore, currentReason = candidateScore(
            character,
            facts,
            candidate.item
        )
        local weight = math.max(0, candidate.item:getUnequippedWeight())
        if currentScore ~= nil and currentReason == candidate.reason
            and weight <= remainingCapacity + 0.001 then
            local category = candidate.reason
            local categoryLimit = (category == "weapon_upgrade"
                or category == "bag_upgrade"
                or category == "clothing_upgrade") and 1 or limit
            local alreadySelected = categoryCounts[category] or 0
            if alreadySelected < categoryLimit then
                selected[#selected + 1] = candidate
                categoryCounts[category] = alreadySelected + 1
                remainingCapacity = math.max(0, remainingCapacity - weight)
                applySelectedFacts(facts, candidate.item)
                if #selected >= limit then
                    break
                end
            end
        end
    end
    return selected
end

function Looting.equipUpgrade(character, item)
    if character == nil or item == nil then
        return false
    end
    if item:IsInventoryContainer() and item:getBodyLocation() ~= nil then
        local current = character:getWornItem(item:getBodyLocation())
        local candidateScoreValue = bagScore(item)
        local currentScoreValue = bagScore(current)
        if current == nil or (candidateScoreValue ~= nil
            and candidateScoreValue > (currentScoreValue or -1) + 1) then
            character:setWornItem(item:getBodyLocation(), item)
            character:resetModelNextFrame()
            return true
        end
    elseif item:IsClothing() and item:getBodyLocation() ~= nil then
        local current = character:getWornItem(item:getBodyLocation())
        local candidateScoreValue = clothingScore(item)
        local currentScoreValue = clothingScore(current)
        if current == nil or (candidateScoreValue ~= nil
            and candidateScoreValue > (currentScoreValue or -1) + 0.5) then
            character:setWornItem(item:getBodyLocation(), item)
            character:resetModelNextFrame()
            return true
        end
    end
    return false
end
