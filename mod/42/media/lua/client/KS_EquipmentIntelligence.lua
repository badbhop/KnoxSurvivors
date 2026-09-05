-- Small, inventory-only equipment policy for loaded survivors.  It does not search
-- the world, create items, consume supplies, or maintain a parallel gear record.
-- Build 42 inventory/worn state remains the authority.
local Equipment = rawget(_G, "KnoxEquipmentIntelligence") or {}
_G.KnoxEquipmentIntelligence = Equipment

local EVALUATION_TICKS = 300
local MELEE_SWITCH_MARGIN = 1.25
local CLOTHING_SWITCH_MARGIN = 0.50
local BAG_SWITCH_MARGIN = 1.00
local states = setmetatable({}, { __mode = "k" })

-- A Java ArrayList can briefly expose a Java null sentinel while an item is
-- removed by combat, looting, or corpse transfer. Kahlua does not always
-- compare that sentinel equal to Lua nil, but indexing it emits an error.
local function usableItem(item)
    return item ~= nil and tostring(item) ~= "null"
end

local function safe(call, fallback)
    local success, value = pcall(call)
    if success then return value end
    return fallback
end

local function fullType(item)
    if not usableItem(item) then return nil end
    return safe(function() return tostring(item:getFullType()) end, nil)
end

local function isMelee(item)
    return usableItem(item)
        and safe(function() return item:IsWeapon() end, false)
        and not safe(function() return item:isRanged() end, true)
        and not safe(function() return item:isBroken() end, true)
end

local function meleeScore(item)
    if not isMelee(item) then return nil end
    local conditionMax = safe(function() return item:getConditionMax() end, 0)
    local condition = conditionMax > 0
        and safe(function() return item:getCondition() end, 0) / conditionMax or 0
    return (safe(function() return item:getMinDamage() end, 0)
            + safe(function() return item:getMaxDamage() end, 0)) * 5
        + condition * 5
        + safe(function() return item:getMaxRange() end, 0)
        + safe(function() return item:getBaseSpeed() end, 0)
        + safe(function() return item:getCriticalChance() end, 0) * 0.02
end

function Equipment.isUsableMelee(item)
    return meleeScore(item) ~= nil
end

function Equipment.isMeaningfulMeleeUpgrade(character, item)
    local candidateScore = meleeScore(item)
    if candidateScore == nil then return false end
    local primary = character ~= nil and safe(function()
        return character:getPrimaryHandItem()
    end, nil) or nil
    local primaryIsUsableGun = safe(function()
        return primary ~= nil and primary:IsWeapon() and primary:isRanged()
            and not primary:isBroken()
    end, false)
    if primaryIsUsableGun then return false end
    local primaryScore = meleeScore(primary)
    return primary == nil or candidateScore >= (primaryScore or -math.huge) + MELEE_SWITCH_MARGIN
end

-- Explicit weapon orders may also accept a firearm, but only when Build 42
-- says the carried gun is ready. Ammo, magazine and chamber state stay native.
function Equipment.isMeaningfulWeaponUpgrade(character, item)
    if Equipment.isMeaningfulMeleeUpgrade(character, item) then return true end
    if not usableItem(item) or not safe(function() return item:IsWeapon() end, false)
        or not safe(function() return item:isRanged() end, false)
        or safe(function() return item:isBroken() end, true) then
        return false
    end
    local firearms = rawget(_G, "KnoxFirearmSupport")
    if firearms == nil or firearms.isReady == nil
        or not safe(function() return firearms.isReady(character, item) end, false) then
        return false
    end
    local primary = character ~= nil and safe(function()
        return character:getPrimaryHandItem()
    end, nil) or nil
    if primary == item then return false end
    local score = function(gun)
        return safe(function() return gun:getMaxRange() end, 0)
            + safe(function() return gun:getMaxDamage() end, 0) * 8
            + safe(function() return gun:getCondition() end, 0) * 0.1
    end
    local currentReady = primary ~= nil and safe(function()
        return firearms.isReady(character, primary)
    end, false) or false
    return not currentReady or score(item) >= score(primary) + 1.5
end

local function wearableLocation(item)
    if not usableItem(item) then return nil end
    local location = safe(function() return item:getBodyLocation() end, nil)
    if location ~= nil then return location end
    return safe(function() return item:canBeEquipped() end, nil)
end

local function isContainer(item)
    if not usableItem(item) then return false end
    return safe(function() return item:IsInventoryContainer() end, false)
end

local function isClothing(item)
    if not usableItem(item) then return false end
    return safe(function() return item:IsClothing() end, false)
end

local function bagScore(item)
    if not isContainer(item) then return nil end
    return safe(function() return item:getCapacity() end, 0)
        + safe(function() return item:getWeightReduction() end, 0) * 0.15
end

local function clothingScore(item)
    if not isClothing(item) then return nil end
    local conditionMax = safe(function() return item:getConditionMax() end, 0)
    local condition = conditionMax > 0
        and safe(function() return item:getCondition() end, 0) / conditionMax or 0
    return safe(function() return item:getBiteDefense() end, 0) * 0.08
        + safe(function() return item:getScratchDefense() end, 0) * 0.04
        + safe(function() return item:getInsulation() end, 0) * 2
        + condition * 3
end

local function rootItems(character)
    local inventory = safe(function() return character:getInventory() end, nil)
    local items = inventory ~= nil and safe(function() return inventory:getItems() end, nil) or nil
    if items == nil then return {} end
    local result = {}
    local size = safe(function() return items:size() end, 0)
    for index = 0, size - 1 do
        local item = safe(function() return items:get(index) end, nil)
        if usableItem(item) then result[#result + 1] = item end
    end
    return result
end

local function actionActive(character)
    return not safe(function() return character:getCharacterActions():isEmpty() end, true)
end

local function replacedWearScore(character, location, scoreItem)
    local wornItems = character.getWornItems ~= nil and character:getWornItems() or nil
    if wornItems == nil then
        return scoreItem(safe(function() return character:getWornItem(location) end, nil))
    end
    -- Match vanilla doWearClothingTooltip: different locations can be
    -- mutually exclusive (shorts/trousers, for example).
    local group = wornItems:getBodyLocationGroup()
    local total, found = 0, false
    for index = 0, wornItems:size() - 1 do
        local worn = wornItems:get(index)
        if location == worn:getLocation() or group:isExclusive(location, worn:getLocation()) then
            total = total + (scoreItem(worn:getItem()) or 0)
            found = true
        end
    end
    return found and total or nil
end

function Equipment.choose(character)
    if character == nil then return nil end
    local candidates = rootItems(character)
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    local primaryIsUsableGun = safe(function()
        return primary ~= nil and primary:IsWeapon() and primary:isRanged() and not primary:isBroken()
    end, false)
    local bestMelee, bestMeleeScore = nil, -math.huge
    local bestWear, bestWearGain = nil, 0

    for _, item in ipairs(candidates) do
        local score = meleeScore(item)
        if score ~= nil and score > bestMeleeScore then
            bestMelee, bestMeleeScore = item, score
        end
        local location = wearableLocation(item)
        if location ~= nil then
            local worn = safe(function() return character:getWornItem(location) end, nil)
            local candidate, current, margin
            if isContainer(item) then
                candidate, current, margin = bagScore(item),
                    safe(function() return replacedWearScore(character, location, bagScore) end, math.huge),
                    BAG_SWITCH_MARGIN
            elseif isClothing(item) then
                candidate, current, margin = clothingScore(item),
                    safe(function() return replacedWearScore(character, location, clothingScore) end, math.huge),
                    CLOTHING_SWITCH_MARGIN
            end
            local gain = candidate ~= nil and candidate - (current or -1) or nil
            if gain ~= nil and gain >= margin and item ~= worn and gain > bestWearGain then
                bestWear, bestWearGain = item, gain
            end
        end
    end

    local primaryScore = meleeScore(primary)
    if not primaryIsUsableGun and bestMelee ~= nil and bestMelee ~= primary
        and bestMeleeScore >= (primaryScore or -math.huge) + MELEE_SWITCH_MARGIN then
        return { kind = "melee", item = bestMelee, score = bestMeleeScore }
    end
    if bestWear ~= nil then
        return { kind = "wear", item = bestWear, gain = bestWearGain }
    end
    return nil
end

function Equipment.reconsider(id, character, bridge, ticks, force)
    if character == nil or bridge == nil then return false, "equipment_unavailable" end
    local state = states[character] or { nextAt = 0 }
    states[character] = state
    if not force and (ticks or 0) < (state.nextAt or 0) then
        return false, "equipment_cooldown"
    end
    if actionActive(character) then
        state.nextAt = (ticks or 0) + 30
        return false, "equipment_action_active"
    end
    state.nextAt = (ticks or 0) + EVALUATION_TICKS
    local decision = Equipment.choose(character)
    if decision == nil then return false, "equipment_stable" end
    local typeName = fullType(decision.item)
    if typeName == nil then return false, "equipment_unknown_item" end
    if decision.kind == "melee" and bridge.equipNpcOwnedWeapon ~= nil then
        local result = tostring(bridge:equipNpcOwnedWeapon(id, typeName))
        return string.find(result, "EQUIPPED_WEAPON", 1, true) == 1, result
    end
    if decision.kind == "wear" and bridge.wearNpcOwnedItem ~= nil then
        local result = tostring(bridge:wearNpcOwnedItem(id, typeName))
        return string.find(result, "WORN_OWNED", 1, true) == 1, result
    end
    return false, "equipment_bridge_unavailable"
end

function Equipment.resetRuntime()
    states = setmetatable({}, { __mode = "k" })
end

return Equipment
