-- Focused non-engine regression coverage for the firearm planner. Native reload/fire
-- behavior remains a required live Build 42 test; this only verifies that Knox does not
-- invent ammunition or bypass the native reload action.
local rootPath = arg[1] or "."

package.preload["TimedActions/ISReloadWeaponAction"] = function()
    ISReloadWeaponAction = {
        canShoot = function(_, gun)
            return gun.ready == true
        end,
        BeginAutomaticReload = function(character, gun)
            gun.reloadRequested = true
            character.actions.empty = false
        end,
    }
    return ISReloadWeaponAction
end

local function item(fullType, options)
    options = options or {}
    return {
        ready = options.ready,
        ranged = options.ranged,
        broken = options.broken,
        ammo = options.ammo,
        magazine = options.magazine,
        fullType = fullType,
        IsWeapon = function(self) return self.ranged ~= nil end,
        isRanged = function(self) return self.ranged == true end,
        isBroken = function(self) return self.broken == true end,
        getMaxRange = function() return options.range or 0 end,
        getMaxDamage = function() return options.damage or 0 end,
        getCondition = function() return 10 end,
        getFullType = function(self) return self.fullType end,
        getBestMagazine = function(self) return self.magazine and self or nil end,
        getAmmoType = function(self) return self.ammo and { getItemKey = function() return "Base.Bullets9mm" end } or nil end,
        getMaxAmmo = function() return options.magazine and 15 or 0 end,
        isAmmo = function(self) return self.ammo == true end,
    }
end

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function character(values)
    local character = { actions = { empty = true } }
    character.inventory = {
        getItems = function() return list(values) end,
        getItemCountRecurse = function() return 24 end,
    }
    character.getInventory = function(self) return self.inventory end
    character.getPrimaryHandItem = function() return nil end
    character.getVariableBoolean = function() return false end
    character.getCharacterActions = function(self)
        return { isEmpty = function() return self.actions.empty end }
    end
    return character
end

local support = dofile(rootPath .. "/mod/42/media/lua/client/KS_FirearmSupport.lua")
local equipped = {}
local bridge = {
    equipNpcOwnedWeapon = function(_, id, fullType)
        equipped[#equipped + 1] = id .. ":" .. fullType
        return "EQUIPPED_WEAPON " .. fullType
    end,
}

local readyGun = item("Base.Pistol", { ranged = true, ready = true, range = 15, damage = 1 })
local readyCharacter = character({ readyGun })
local state = support.prepareForThreat("ks-test", readyCharacter, bridge)
assert(state == "ready", "a genuinely ready gun should be selected")
assert(#equipped == 1 and equipped[1] == "ks-test:Base.Pistol", "selected gun must be owned")

local unloadedGun = item("Base.Pistol", { ranged = true, ready = false, magazine = true })
local reloadCharacter = character({ unloadedGun })
state = support.prepareForThreat("ks-reload", reloadCharacter, bridge)
assert(state == "reloading", "reloadable gun must yield to the native reload action")
assert(unloadedGun.reloadRequested == true, "reload must be requested through native action")

local emptyCharacter = character({ item("Base.Hammer", { ranged = false }) })
state = support.prepareForThreat("ks-melee", emptyCharacter, bridge)
assert(state == "melee", "no firearm inventory must preserve melee fallback")

print("Firearm support PASS native_reload=true ready_selection=true melee_fallback=true")
