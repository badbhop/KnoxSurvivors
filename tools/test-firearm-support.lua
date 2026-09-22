-- Focused firearm planning/ownership coverage. Native ballistics remain a live
-- Build 42 gate; these checks ensure Knox delegates reload, rack, and firing to
-- the installed game's action/hook boundaries without inventing ammunition.
local rootPath = arg[1] or "."

local reloadAttempts = 0
local nextItemId = 0
ISTimedActionQueue = { queues = {} }
function ISTimedActionQueue.add(action)
    local queue = ISTimedActionQueue.queues[action.character]
    if queue == nil then
        queue = { queue = {} }
        ISTimedActionQueue.queues[action.character] = queue
    end
    queue.queue[#queue.queue + 1] = action
end

package.preload["TimedActions/ISTimedActionQueue"] = function()
    return ISTimedActionQueue
end

package.preload["TimedActions/ISRackFirearm"] = function()
    ISRackFirearm = {
        new = function(_, character, gun)
            gun.rackRequested = true
            return { character = character, gun = gun, kind = "rack" }
        end,
    }
    return ISRackFirearm
end

package.preload["TimedActions/ISReloadWeaponAction"] = function()
    ISReloadWeaponAction = {
        canShoot = function(_, gun)
            if gun.safeMode or gun.jammed then return false end
            if gun.haveChamberValue then return gun.chambered == true end
            return (gun.ammoCount or 0) > 0
        end,
        canRack = function(gun)
            return gun.jammed == true
                or (gun.haveChamberValue and (gun.chambered == true
                    or gun.spent == true or (gun.ammoCount or 0) > 0))
        end,
        BeginAutomaticReload = function(character, gun)
            reloadAttempts = reloadAttempts + 1
            gun.reloadRequested = true
            if gun.reloadable then
                ISTimedActionQueue.add({
                    character = character,
                    gun = gun,
                    reloading = true,
                    kind = "reload",
                })
            end
        end,
        attackHook = function(character, _, gun)
            assert(ISReloadWeaponAction.canShoot(character, gun),
                "native attack hook may only receive a ready firearm")
            character.nativeShots = character.nativeShots + 1
            character.gunshotSounds = character.gunshotSounds + 1
            character.worldSounds = character.worldSounds + 1
            character.attackStarted = true
        end,
    }
    return ISReloadWeaponAction
end

local function item(fullType, options)
    options = options or {}
    nextItemId = nextItemId + 1
    local storedMagazine = options.magazine
    return {
        id = options.id or nextItemId,
        ranged = options.ranged,
        broken = options.broken,
        safeMode = options.safeMode,
        jammed = options.jammed,
        haveChamberValue = options.haveChamber,
        chambered = options.chambered,
        spent = options.spent,
        ammoCount = options.ammoCount or 0,
        reloadable = options.reloadable,
        fullType = fullType,
        IsWeapon = function(self) return self.ranged ~= nil end,
        isRanged = function(self) return self.ranged == true end,
        isBroken = function(self) return self.broken == true end,
        isSelectFire = function(self) return self.safeMode ~= nil end,
        getFireMode = function(self) return self.safeMode and "Safe" or "Single" end,
        isJammed = function(self) return self.jammed == true end,
        haveChamber = function(self) return self.haveChamberValue == true end,
        isRoundChambered = function(self) return self.chambered == true end,
        isSpentRoundChambered = function(self) return self.spent == true end,
        getCurrentAmmoCount = function(self) return self.ammoCount end,
        getMaxAmmo = function() return options.maxAmmo or 15 end,
        getAmmoPerShoot = function() return 1 end,
        getMaxRange = function() return options.range or 0 end,
        getMaxDamage = function() return options.damage or 0 end,
        getCondition = function() return options.condition or 10 end,
        getFullType = function(self) return self.fullType end,
        getID = function(self) return self.id end,
        IsInventoryContainer = function() return options.nestedInventory ~= nil end,
        getInventory = function() return options.nestedInventory end,
        getMagazineType = function() return options.magazineType end,
        getBestMagazine = function() return storedMagazine end,
        getAmmoType = function()
            return options.ammoType and {
                getItemKey = function() return options.ammoType end,
            } or nil
        end,
    }
end

local function magazine(fullType, rounds)
    return {
        getFullType = function() return fullType end,
        getCurrentAmmoCount = function() return rounds end,
    }
end

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function character(values, ammoCounts)
    local value = {
        primary = nil,
        nativeShots = 0,
        gunshotSounds = 0,
        worldSounds = 0,
        attackStarted = false,
    }
    value.inventory = {
        getItems = function() return list(values) end,
        AddItem = function(_, candidate)
            for _, existing in ipairs(values) do
                if existing == candidate then return candidate end
            end
            values[#values + 1] = candidate
            return candidate
        end,
        getItemCountRecurse = function(_, itemKey)
            return (ammoCounts or {})[itemKey] or 0
        end,
    }
    value.getInventory = function(self) return self.inventory end
    value.getPrimaryHandItem = function(self) return self.primary end
    value.getCharacterActions = function(self)
        local queue = ISTimedActionQueue.queues[self]
        return { isEmpty = function() return queue == nil or #queue.queue == 0 end }
    end
    return value
end

local activeCharacter = nil
local firearmEquips = 0
local bridge = {
    equipNpcOwnedWeapon = function(_, _, fullType)
        for index = 0, activeCharacter.inventory:getItems():size() - 1 do
            local candidate = activeCharacter.inventory:getItems():get(index)
            if candidate:getFullType() == fullType then
                activeCharacter.primary = candidate
                firearmEquips = firearmEquips + 1
                return "EQUIPPED_WEAPON " .. fullType
            end
        end
        return "EQUIP_FAILED"
    end,
    equipNpcOwnedWeaponById = function(_, _, fullType, itemId)
        for index = 0, activeCharacter.inventory:getItems():size() - 1 do
            local candidate = activeCharacter.inventory:getItems():get(index)
            if candidate:getFullType() == fullType and candidate:getID() == itemId then
                activeCharacter.primary = candidate
                firearmEquips = firearmEquips + 1
                return "EQUIPPED_WEAPON " .. fullType
            end
        end
        return "EQUIP_FAILED"
    end,
    equipBestNpc = function()
        for index = 0, activeCharacter.inventory:getItems():size() - 1 do
            local candidate = activeCharacter.inventory:getItems():get(index)
            if candidate.ranged == false then
                activeCharacter.primary = candidate
                return "EQUIPPED " .. candidate:getFullType()
            end
        end
        activeCharacter.primary = nil
        return "NO_MELEE_WEAPON"
    end,
}

local support = dofile(rootPath .. "/mod/42/media/lua/client/KS_FirearmSupport.lua")

local loaded = item("Base.Pistol", {
    ranged = true, haveChamber = true, chambered = true,
    ammoCount = 6, range = 15, damage = 1,
})
activeCharacter = character({ loaded })
local state = support.prepareForThreat("loaded", activeCharacter, bridge)
assert(state == "ready" and activeCharacter.primary == loaded,
    "loaded firearm is selected from real carried items")
assert(support.currentCombatState(activeCharacter) == "ready",
    "partially loaded firearm remains authoritative and ready")
local equipsAfterReady = firearmEquips
state = support.prepareForThreat("loaded", activeCharacter, bridge)
assert(state == "ready" and firearmEquips == equipsAfterReady,
    "current viable firearm remains equipped instead of being reequipped every refresh")

-- A ready gun inside a backpack must be selected as the same real item. The
-- root inventory contains another pistol with the same type, so a type-only
-- bridge would equip the wrong weapon and then falsely report ranged readiness.
local nestedReady = item("Base.Pistol", {
    ranged = true, haveChamber = true, chambered = true, ammoCount = 6,
    range = 18, damage = 2,
})
local bag = item("Base.Backpack", { nestedInventory = { getItems = function() return list({ nestedReady }) end } })
local sameTypeButDry = item("Base.Pistol", {
    ranged = true, haveChamber = true, chambered = false, ammoCount = 0,
    range = 8, damage = 1,
})
activeCharacter = character({ sameTypeButDry, bag })
state = support.prepareForThreat("nested", activeCharacter, bridge)
assert(state == "ready" and activeCharacter.primary == nestedReady,
    "bagged ready gun is moved and equipped by exact real item identity")

local spare = magazine("Base.9mmClip", 8)
local empty = item("Base.Pistol", {
    ranged = true, haveChamber = true, chambered = false,
    ammoCount = 0, magazineType = "Base.9mmClip", magazine = spare,
    ammoType = "Base.Bullets9mm", reloadable = true,
})
activeCharacter = character({ empty }, { ["Base.Bullets9mm"] = 12 })
state = support.prepareForThreat("reload", activeCharacter, bridge)
assert(state == "reloading" and empty.reloadRequested,
    "empty firearm queues Build 42 automatic reload")
local attemptsAfterQueue = reloadAttempts
state = support.prepareForThreat("reload", activeCharacter, bridge)
assert(state == "reloading" and reloadAttempts == attemptsAfterQueue,
    "active reload owns preparation and cannot be queued twice")

ISTimedActionQueue.queues[activeCharacter] = nil
empty.ammoCount = 7
empty.chambered = true
assert(support.currentCombatState(activeCharacter) == "ready",
    "completed native reload returns the firearm to ranged readiness")

local rack = item("Base.Pistol", {
    ranged = true, haveChamber = true, chambered = false,
    ammoCount = 5, magazineType = "Base.9mmClip",
})
activeCharacter = character({ rack })
state = support.prepareForThreat("rack", activeCharacter, bridge)
assert(state == "reloading" and rack.rackRequested,
    "loaded magazine with empty chamber queues native rack action")

local hammer = item("Base.Hammer", { ranged = false })
local dry = item("Base.Pistol", {
    ranged = true, haveChamber = true, chambered = false,
    ammoCount = 0, magazineType = "Base.9mmClip",
    ammoType = "Base.Bullets9mm",
})
activeCharacter = character({ dry, hammer })
local attemptsBeforeDry = reloadAttempts
state = support.prepareForThreat("dry", activeCharacter, bridge)
assert(state == "melee" and activeCharacter.primary == hammer,
    "no compatible ammunition falls back to a real melee weapon")
assert(reloadAttempts == attemptsBeforeDry,
    "no-ammo fallback does not enter a reload loop")
assert(string.find(support.fallbackToMelee("close", bridge), "EQUIPPED", 1, true) == 1
        and activeCharacter.primary == hammer,
    "blocked close-range reposition can explicitly fall back to melee")

local safeGun = item("Base.Pistol", {
    ranged = true, safeMode = true, haveChamber = true,
    chambered = true, ammoCount = 6,
})
activeCharacter = character({ safeGun, hammer })
state = support.prepareForThreat("safe", activeCharacter, bridge)
assert(state == "melee" and activeCharacter.primary == hammer,
    "safe-mode firearm is not treated as usable")

activeCharacter = character({ loaded })
activeCharacter.primary = loaded
local fired, result = support.fireNative(activeCharacter)
assert(fired and string.find(result, "native_attack_hook", 1, true) == 1,
    "ready firearm fires through the native Build 42 attack hook")
assert(activeCharacter.nativeShots == 1 and activeCharacter.gunshotSounds == 1
        and activeCharacter.worldSounds == 1,
    "native hook owns attack, gunshot sound, and world noise")
assert(support.nativeShotCount(activeCharacter) == 1,
    "native hook telemetry records only a successful real hook invocation")

print("Firearm support PASS readiness=true stable=true reload=true rack=true noAmmo=true nativeFire=true")

local preference = "auto"
KnoxPersistence = { getSurvivorPolicies = function() return { weaponPreference = preference } end }
Perks = { Aiming = "Aiming" }
local aimingAssist = 1
KnoxSettings = { survivorAimingAssist = function() return aimingAssist end }
local target = { x = 8, z = 0, getX = function(self) return self.x end,
    getY = function() return 0 end, getZ = function(self) return self.z end }
activeCharacter = character({ loaded, hammer })
activeCharacter.aiming = 0
function activeCharacter:getPerkLevel(perk) assert(perk == Perks.Aiming) return self.aiming end
function activeCharacter:getX() return 0 end
function activeCharacter:getY() return 0 end
function activeCharacter:getZ() return 0 end
assert(not support.wantsRanged("preference", activeCharacter, target), "novice with melee keeps noise down by default")
assert(support.prepareForThreat("preference", activeCharacter, bridge, target) == "melee"
    and activeCharacter.primary == hammer)
activeCharacter.aiming = 5
local nativeSettle = support.aimSettleTicks("preference", activeCharacter)
assert(nativeSettle == 18, "native skill five keeps the established aim settle time")
assert(support.prepareForThreat("preference", activeCharacter, bridge, target) == "ready"
    and activeCharacter.primary == loaded, "trained shooter with room may select a viable gun")
target.x = 1
assert(not support.wantsRanged("preference", activeCharacter, target), "close pressure does not favor automatic ranged choice")
target.x, target.z = 8, 1
assert(not support.wantsRanged("preference", activeCharacter, target), "different floor is not assumed useful shooting distance")
target.z = 0
preference = "melee"
assert(support.prepareForThreat("preference", activeCharacter, bridge, target) == "melee",
    "explicit melee overrides firearm skill")
preference = "ranged"
activeCharacter.aiming = 0
assert(support.prepareForThreat("preference", activeCharacter, bridge, target) == "ready",
    "explicit ranged can select a usable gun for a novice")
activeCharacter = character({ dry, hammer })
local reloadBefore = reloadAttempts
assert(support.prepareForThreat("preference", activeCharacter, bridge, target) == "melee"
    and activeCharacter.primary == hammer and reloadAttempts == reloadBefore,
    "ranged order cannot manufacture ammunition or loop reload")
activeCharacter = character({ loaded, hammer })
activeCharacter.primary = loaded
activeCharacter.aiming = 2
function activeCharacter:getPerkLevel(perk) assert(perk == Perks.Aiming) return self.aiming end
function activeCharacter:getX() return 0 end
function activeCharacter:getY() return 0 end
function activeCharacter:getZ() return 0 end
preference = "auto"
aimingAssist = 1
assert(not support.wantsRanged("assist", activeCharacter, target),
    "native skills keep a low-skill survivor conservative")
local nativeLowSettle = support.aimSettleTicks("assist", activeCharacter)
aimingAssist = 2
assert(support.wantsRanged("assist", activeCharacter, target),
    "basic sandbox assistance improves firearm decision readiness")
local assistedSettle = support.aimSettleTicks("assist", activeCharacter)
aimingAssist = 3
local strongSettle = support.aimSettleTicks("assist", activeCharacter)
assert(assistedSettle < nativeLowSettle and strongSettle < assistedSettle,
    "assistance shortens aim settle without replacing native skill")
assert(activeCharacter.aiming == 2,
    "aiming assistance does not rewrite the survivor's native skill")
activeCharacter.aiming = 10
assert(support.aimSettleTicks("assist", activeCharacter) == 8,
    "high native aiming remains bounded at the fast settle floor")
preference = "ranged"
activeCharacter = character({ empty, hammer })
empty.chambered, empty.ammoCount = false, 0
assert(support.prepareForThreat("preference", activeCharacter, bridge, target) == "reloading")
ISTimedActionQueue.clear = function(actor) ISTimedActionQueue.queues[actor] = nil end
preference = "melee"
assert(support.cancelPreparation(activeCharacter) and not support.cancelPreparation(activeCharacter),
    "changed preference cancels native reload once")
ISTimedActionQueue.add({ character = activeCharacter, gun = empty, reloading = true })
activeCharacter.primary = hammer
assert(support.cancelPreparation(activeCharacter), "reload cancellation still finds the old gun after a hand-slot change")
ISTimedActionQueue.add({ character = activeCharacter, kind = "bandage" })
local nativePcall, caughtErrors = pcall, 0
pcall = function(...)
    local ok, value = nativePcall(...)
    if not ok then caughtErrors = caughtErrors + 1 end
    return ok, value
end
assert(not support.cancelPreparation(activeCharacter), "weapon preference does not cancel unrelated self-care")
pcall = nativePcall
assert(caughtErrors == 0, "unrelated action with no gun must not throw even inside pcall (Kahlua logs it)")
activeCharacter.primary = nil
pcall = function(...)
    local ok, value = nativePcall(...)
    if not ok then caughtErrors = caughtErrors + 1 end
    return ok, value
end
assert(not support.cancelPreparation(activeCharacter), "empty hand is not an active firearm")
assert(not support.fireNative(activeCharacter), "empty hand cannot fire or inspect magazine metadata")
pcall = nativePcall
assert(caughtErrors == 0, "empty hand must not throw inside Kahlua pcall")
ISTimedActionQueue.clear(activeCharacter)
assert(support.prepareForThreat("preference", activeCharacter, bridge, target) == "melee")
preference = "auto"
activeCharacter = character({ loaded, item("Base.BrokenBat", { ranged = false, broken = true }) })
assert(support.prepareForThreat("preference", activeCharacter, bridge, target) == "ready",
    "broken melee does not prevent usable firearm survival fallback")
print("Weapon choice PASS defaults=true skill=true orders=true ammo=true reload_cancellation=true")
