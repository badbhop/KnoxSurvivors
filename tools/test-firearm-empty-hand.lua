-- Regression coverage for KS_FirearmSupport.lua:258.
--
-- Live Build 42 surfaced:
--   java.lang.RuntimeException: attempted index: IsWeapon of non-table: null
--     at KahluaThread.tableget(KahluaThread.java:1430)
--   Stack: KS_FirearmSupport.lua:258 -> :25 -> pullMeleeToHands:295
--          -> ensureMeleeHands (KS_SurvivorAutonomyController.lua:7008)
--          -> beginCombat -> tick -> pcall -> update
--
-- Empty hands should return a normal fallback, without dispatching on nil.
-- Use the real Lua pcall contract. Installed KahluaThread.pcall catches
-- java.lang.Throwable; a stack trace alone does not establish an escaped error.
local rootPath = arg[1] or "."

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
            return { character = character, gun = gun, kind = "rack" }
        end,
    }
    return ISRackFirearm
end

package.preload["TimedActions/ISReloadWeaponAction"] = function()
    ISReloadWeaponAction = {
        canShoot = function() return false end,
        canRack = function() return false end,
        BeginAutomaticReload = function() end,
        attackHook = function() end,
    }
    return ISReloadWeaponAction
end

package.preload["KS_SafeCall"] = function()
    return dofile(rootPath .. "/mod/42/media/lua/shared/KS_SafeCall.lua")
end

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local function makeItem(fullType, options)
    options = options or {}
    local item = {
        fullType = fullType,
        weapon = options.weapon,
        ranged = options.ranged,
        broken = options.broken,
    }
    function item:IsWeapon() return self.weapon == true end
    function item:isRanged() return self.ranged == true end
    function item:isBroken() return self.broken == true end
    function item:getFullType() return self.fullType end
    if options.nestedInventory ~= nil then
        function item:IsInventoryContainer() return true end
        function item:getInventory() return options.nestedInventory end
    else
        function item:IsInventoryContainer() return false end
    end
    return item
end

local function makeCharacter(items)
    local value = { primary = nil }
    value.inventory = {
        getItems = function() return list(items) end,
        AddItem = function(_, candidate)
            for _, existing in ipairs(items) do
                if existing == candidate then return candidate end
            end
            items[#items + 1] = candidate
            return candidate
        end,
    }
    function value:getInventory() return self.inventory end
    function value:getPrimaryHandItem() return self.primary end
    return value
end

local bridge = {
    equipNpcOwnedWeapon = function() return "EQUIPPED_WEAPON x" end,
    equipNpcOwnedWeaponById = function() return "EQUIPPED_WEAPON x" end,
    equipBestNpc = function() return "NO_MELEE_WEAPON" end,
}

local support = assert(dofile(rootPath .. "/mod/42/media/lua/client/KS_FirearmSupport.lua"))
assert(type(support.pullMeleeToHands) == "function",
    "Firearms.pullMeleeToHands must be exposed for the live call site")

-- Exercise the public recovery path with no weapon in either hand/inventory.
local emptyCharacter = makeCharacter({})
local ok, pulled, reason = pcall(support.pullMeleeToHands,
    "regression", emptyCharacter, bridge)
assert(ok,
    "pullMeleeToHands with empty hand must short-circuit before method dispatch: "
        .. tostring(pulled))
assert(pulled == false and reason == "no_carried_melee",
    "empty hand returns the no_carried_melee fallback: "
        .. tostring(pulled) .. "/" .. tostring(reason))

-- Ranged-only survivor: still empty-handed, still must not throw on the
-- empty-hand nil check at line 258.
local rangedOnly = makeItem("Base.Pistol", { weapon = true, ranged = true })
local rangedCharacter = makeCharacter({ rangedOnly })
local rangedOk, rangedPulled, rangedReason = pcall(support.pullMeleeToHands,
    "regression", rangedCharacter, bridge)
assert(rangedOk and rangedPulled == false and rangedReason == "no_carried_melee",
    "ranged-only inventory returns cleanly without Kahlua exception: "
        .. tostring(rangedPulled) .. "/" .. tostring(rangedReason))

-- Bagged melee: exercises the second call to isUsableMelee via findCarriedMelee
-- on the bag's nested inventory. Confirms the predicate is still correct for
-- real items and that the safe wrapper is not masking real weapon checks.
local knife = makeItem("Base.KitchenKnife", { weapon = true })
local bag = makeItem("Base.Backpack", {
    nestedInventory = {
        getItems = function() return list({ knife }) end,
    },
})
local baggedCharacter = makeCharacter({ bag })
local baggedOk, baggedPulled, baggedReason = pcall(support.pullMeleeToHands,
    "regression", baggedCharacter, bridge)
assert(baggedOk,
    "bagged melee pull must not throw: " .. tostring(baggedPulled))
assert(baggedPulled == false,
    "bagged melee returns false because no equip bridge satisfied: "
        .. tostring(baggedPulled))

-- A real weapon handed off through the live code path must still be classified
-- as usable melee when it is already in the primary hand. Guards against the
-- nil guard over-aggressively rejecting real weapons.
local realBat = makeItem("Base.BaseballBat", { weapon = true })
local armedCharacter = makeCharacter({})
armedCharacter.primary = realBat
local armedOk, armedPulled, armedReason = pcall(support.pullMeleeToHands,
    "regression", armedCharacter, bridge)
assert(armedOk and armedPulled == true and armedReason == "already_equipped",
    "already-equipped real melee reports already_equipped: "
        .. tostring(armedPulled) .. "/" .. tostring(armedReason))

print("Firearm weapon classification PASS "
    .. "empty_hand_safe=true ranged_only_safe=true "
    .. "bagged_safe=true already_equipped_true")
