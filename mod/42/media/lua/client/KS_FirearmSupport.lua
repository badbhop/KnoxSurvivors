-- Native firearm preparation for contained IsoPlayer survivors.
--
-- Knox never writes magazine/chamber/ammunition fields.  Build 42 owns those
-- transitions through ISReloadWeaponAction; this module only selects a real carried
-- gun, queues the vanilla reload action, and lets the normal combat controller fire it.
require "TimedActions/ISReloadWeaponAction"

local Firearms = rawget(_G, "KnoxFirearmSupport") or {}
_G.KnoxFirearmSupport = Firearms

local function safe(call, fallback)
    local success, value = pcall(call)
    if success then
        return value
    end
    return fallback
end

local function isUsableGun(item)
    return item ~= nil
        and safe(function() return item:IsWeapon() end, false)
        and safe(function() return item:isRanged() end, false)
        and not safe(function() return item:isBroken() end, true)
end

local function canShoot(character, gun)
    return isUsableGun(gun)
        and safe(function()
            return ISReloadWeaponAction.canShoot(character, gun)
        end, false)
end

local function items(character)
    if character == nil then
        return nil
    end
    return safe(function() return character:getInventory():getItems() end, nil)
end

local function bestReadyGun(character)
    local inventoryItems = items(character)
    if inventoryItems == nil then
        return nil
    end
    local best = nil
    local bestScore = -math.huge
    for index = 0, inventoryItems:size() - 1 do
        local item = inventoryItems:get(index)
        if canShoot(character, item) then
            local score = safe(function() return item:getMaxRange() end, 0)
                + safe(function() return item:getMaxDamage() end, 0) * 8
                + safe(function() return item:getCondition() end, 0) * 0.1
            if score > bestScore then
                best = item
                bestScore = score
            end
        end
    end
    return best
end

local function firstReloadableGun(character)
    local inventoryItems = items(character)
    if inventoryItems == nil then
        return nil
    end
    for index = 0, inventoryItems:size() - 1 do
        local item = inventoryItems:get(index)
        if isUsableGun(item) then
            local hasMagazine = safe(function()
                return item:getBestMagazine(character) ~= nil
            end, false)
            local hasAmmo = safe(function()
                local ammoType = item:getAmmoType()
                return ammoType ~= nil
                    and character:getInventory():getItemCountRecurse(ammoType:getItemKey()) > 0
            end, false)
            if hasMagazine or hasAmmo then
                return item
            end
        end
    end
    return nil
end

local function equip(id, bridge, gun)
    local result = tostring(bridge:equipNpcOwnedWeapon(id, gun:getFullType()))
    return string.find(result, "EQUIPPED_WEAPON", 1, true) == 1, result
end

-- Returns ready, reloading, or melee.  Reloading deliberately yields combat ownership
-- for the native timed action; a later threat scan resumes once the actual weapon can fire.
function Firearms.prepareForThreat(id, character, bridge)
    if character == nil or bridge == nil or bridge.equipNpcOwnedWeapon == nil then
        return "melee", "bridge_unavailable"
    end
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    if isUsableGun(primary) and not character:getCharacterActions():isEmpty() then
        return "reloading", "native_action_active"
    end

    local ready = bestReadyGun(character)
    if ready ~= nil then
        local equipped, result = equip(id, bridge, ready)
        return equipped and "ready" or "melee", result
    end

    local reloadable = firstReloadableGun(character)
    if reloadable == nil then
        return "melee", "no_loaded_firearm"
    end
    local equipped, result = equip(id, bridge, reloadable)
    if not equipped then
        return "melee", result
    end
    ISReloadWeaponAction.BeginAutomaticReload(character, reloadable)
    if not character:getCharacterActions():isEmpty() then
        return "reloading", "native_reload_queued " .. tostring(reloadable:getFullType())
    end
    return "melee", "native_reload_unavailable " .. tostring(reloadable:getFullType())
end

function Firearms.isReady(character, gun)
    return canShoot(character, gun)
end

return Firearms
