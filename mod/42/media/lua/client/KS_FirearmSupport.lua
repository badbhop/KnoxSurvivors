-- Native firearm preparation for contained IsoPlayer survivors.
--
-- Knox never writes magazine/chamber/ammunition fields.  Build 42 owns those
-- transitions through ISReloadWeaponAction; this module only selects a real carried
-- gun, queues the vanilla reload action, and lets the normal combat controller fire it.
require "TimedActions/ISReloadWeaponAction"
require "TimedActions/ISRackFirearm"
require "TimedActions/ISTimedActionQueue"

local Firearms = rawget(_G, "KnoxFirearmSupport") or {}
_G.KnoxFirearmSupport = Firearms
local FIREARM_SWITCH_MARGIN = 1.5

local function safe(call, fallback)
    local success, value = pcall(call)
    if success then
        return value
    end
    return fallback
end

local function isFunctionalGun(item)
    return item ~= nil
        and safe(function() return item:IsWeapon() end, false)
        and safe(function() return item:isRanged() end, false)
        and not safe(function() return item:isBroken() end, true)
        and not safe(function()
            return item:isSelectFire() and item:getFireMode() == "Safe"
        end, false)
end

local function canShoot(character, gun)
    return isFunctionalGun(gun)
        and safe(function()
            return ISReloadWeaponAction.canShoot(character, gun)
        end, false)
end

local function queueFor(character)
    return ISTimedActionQueue ~= nil and ISTimedActionQueue.queues ~= nil
        and ISTimedActionQueue.queues[character] or nil
end

local function firearmActionActive(character, gun)
    local queue = queueFor(character)
    if queue == nil or type(queue.queue) ~= "table" then
        return false
    end
    local magazineType = safe(function() return gun:getMagazineType() end, nil)
    for _, action in ipairs(queue.queue) do
        if action ~= nil and (action.gun == gun or action.reloading == true) then
            return true
        end
        if action ~= nil and action.magazine ~= nil and magazineType ~= nil
            and safe(function()
                return action.magazine:getFullType() == magazineType
            end, false) then
            return true
        end
    end
    return false
end

local function items(character)
    if character == nil then
        return nil
    end
    return safe(function() return character:getInventory():getItems() end, nil)
end

local function gunScore(item)
    return safe(function() return item:getMaxRange() end, 0)
        + safe(function() return item:getMaxDamage() end, 0) * 8
        + safe(function() return item:getCondition() end, 0) * 0.1
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
            local score = gunScore(item)
            if score > bestScore then
                best = item
                bestScore = score
            end
        end
    end
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    if canShoot(character, primary) and best ~= nil
        and gunScore(primary) + FIREARM_SWITCH_MARGIN >= bestScore then
        return primary
    end
    return best
end

local function bestReloadableGun(character)
    local inventoryItems = items(character)
    if inventoryItems == nil then
        return nil
    end
    local best, bestScore = nil, -math.huge
    for index = 0, inventoryItems:size() - 1 do
        local item = inventoryItems:get(index)
        if isFunctionalGun(item) then
            local needsRack = safe(function()
                return ISReloadWeaponAction.canRack(item)
            end, false)
            local hasLoadedMagazine = safe(function()
                local magazine = item:getBestMagazine(character)
                return magazine ~= nil and magazine:getCurrentAmmoCount() > 0
            end, false)
            local hasAmmo = safe(function()
                local ammoType = item:getAmmoType()
                return ammoType ~= nil
                    and character:getInventory():getItemCountRecurse(ammoType:getItemKey()) > 0
            end, false)
            if needsRack or hasLoadedMagazine or hasAmmo then
                local score = gunScore(item)
                if score > bestScore then
                    best, bestScore = item, score
                end
            end
        end
    end
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    if primary ~= nil and isFunctionalGun(primary) and best ~= nil
        and gunScore(primary) + FIREARM_SWITCH_MARGIN >= bestScore then
        return primary
    end
    return best
end

local function equip(id, character, bridge, gun)
    if safe(function() return character:getPrimaryHandItem() == gun end, false) then
        return true, "EQUIPMENT_STABLE " .. tostring(gun:getFullType())
    end
    local result = tostring(bridge:equipNpcOwnedWeapon(id, gun:getFullType()))
    return string.find(result, "EQUIPPED_WEAPON", 1, true) == 1, result
end

local function equipMeleeFallback(id, bridge)
    if bridge.equipBestNpc == nil then
        return "NO_MELEE_BRIDGE"
    end
    return tostring(bridge:equipBestNpc(id))
end

function Firearms.preferenceFor(id)
    local persistence = rawget(_G, "KnoxPersistence")
    local policies = persistence ~= nil and persistence.getSurvivorPolicies ~= nil
        and persistence.getSurvivorPolicies(id) or nil
    local preference = policies ~= nil and policies.weaponPreference or "auto"
    return (preference == "melee" or preference == "ranged") and preference or "auto"
end

local function hasUsableMelee(character)
    local carried = items(character)
    if carried == nil then return false end
    for index = 0, carried:size() - 1 do
        local item = carried:get(index)
        if safe(function() return item:IsWeapon() and not item:isRanged() and not item:isBroken() end, false) then
            return true
        end
    end
    return false
end

-- This decides preference, never firearm viability. Native ammo/reload checks
-- still decide whether a ranged choice can actually be used.
function Firearms.wantsRanged(id, character, target)
    local preference = Firearms.preferenceFor(id)
    if preference == "ranged" then return true, "ordered_ranged" end
    if not hasUsableMelee(character) then return true, "no_usable_melee" end
    if preference == "melee" then return false, "ordered_melee" end
    local aiming = safe(function() return character:getPerkLevel(Perks.Aiming) end, 0)
    local distance = safe(function()
        if target == nil or character:getZ() ~= target:getZ() then return 0 end
        return (character:getX() - target:getX()) ^ 2 + (character:getY() - target:getY()) ^ 2
    end, 0)
    -- Novices normally keep noise down. A trained shot with room to aim may
    -- choose a gun; close-pressure fallback remains owned by native combat.
    return aiming >= 4 and distance >= 9, "survivor_choice"
end

function Firearms.cancelPreparation(character)
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    local active = safe(function() return primary:IsWeapon() and primary:isRanged() end, false)
        and firearmActionActive(character, primary)
    local queue = queueFor(character)
    -- A player inventory operation may have removed/swapped the primary while
    -- the old gun still owns a queued reload. Do not depend only on the hand slot.
    for _, action in ipairs(queue ~= nil and queue.queue or {}) do
        if action.reloading == true or (action.gun ~= nil and safe(function()
            return action.gun:IsWeapon() and action.gun:isRanged()
        end, false)) then active = true break end
    end
    if active then
        ISTimedActionQueue.clear(character)
        return true
    end
    return false
end

local function queueNativePreparation(character, gun)
    if safe(function() return ISReloadWeaponAction.canRack(gun) end, false) then
        ISTimedActionQueue.add(ISRackFirearm:new(character, gun))
        if firearmActionActive(character, gun) then
            return true, "native_rack_queued " .. tostring(gun:getFullType())
        end
    end
    ISReloadWeaponAction.BeginAutomaticReload(character, gun)
    if firearmActionActive(character, gun) then
        return true, "native_reload_queued " .. tostring(gun:getFullType())
    end
    return false, "native_preparation_unavailable " .. tostring(gun:getFullType())
end

-- Returns ready, reloading, or melee.  Reloading deliberately yields combat ownership
-- for the native timed action; a later threat scan resumes once the actual weapon can fire.
function Firearms.prepareForThreat(id, character, bridge, target)
    if character == nil or bridge == nil or bridge.equipNpcOwnedWeapon == nil then
        return "melee", "bridge_unavailable"
    end
    local primary = safe(function() return character:getPrimaryHandItem() end, nil)
    if isFunctionalGun(primary) and firearmActionActive(character, primary) then
        return "reloading", "native_action_active"
    end

    local ranged, preferenceReason = Firearms.wantsRanged(id, character, target)
    if not ranged then
        return "melee", preferenceReason .. " " .. equipMeleeFallback(id, bridge)
    end

    local ready = bestReadyGun(character)
    if ready ~= nil then
        local equipped, result = equip(id, character, bridge, ready)
        return equipped and "ready" or "melee", result
    end

    local reloadable = bestReloadableGun(character)
    if reloadable == nil then
        return "melee", "no_usable_firearm " .. equipMeleeFallback(id, bridge)
    end
    local equipped, result = equip(id, character, bridge, reloadable)
    if not equipped then
        return "melee", result
    end
    local queued, preparation = queueNativePreparation(character, reloadable)
    if queued then
        return "reloading", preparation
    end
    return "melee", preparation .. " " .. equipMeleeFallback(id, bridge)
end

function Firearms.isReady(character, gun)
    return canShoot(character, gun)
end

function Firearms.fallbackToMelee(id, bridge)
    return equipMeleeFallback(id, bridge)
end

-- Observes the currently equipped weapon without changing inventory, actions, or
-- combat ownership. The autonomy controller uses this before each bounded ranged
-- combat refresh so an emptied/jammed firearm yields to native preparation.
function Firearms.currentCombatState(character)
    local gun = safe(function() return character:getPrimaryHandItem() end, nil)
    if not isFunctionalGun(gun) then
        return "melee", "primary_not_functional_firearm"
    end
    if firearmActionActive(character, gun) then
        return "reloading", "native_action_active"
    end
    if canShoot(character, gun) then
        return "ready", tostring(gun:getFullType())
    end
    return "needs_preparation", tostring(gun:getFullType())
end

-- This is the exact Build 42 firing hook used by local player input. It owns
-- gunshot audio/world sound and calls DoAttack; later vanilla callbacks own
-- ballistics, damage, chamber, magazine, condition, and ammunition changes.
function Firearms.fireNative(character)
    local gun = safe(function() return character:getPrimaryHandItem() end, nil)
    if firearmActionActive(character, gun) then
        return false, "native_action_active"
    end
    if not canShoot(character, gun) then
        return false, "firearm_not_ready"
    end
    local success, failure = pcall(
        ISReloadWeaponAction.attackHook,
        character,
        0,
        gun
    )
    if not success then
        return false, "native_attack_hook_failed " .. tostring(failure)
    end
    return true, "native_attack_hook " .. tostring(gun:getFullType())
end

return Firearms
