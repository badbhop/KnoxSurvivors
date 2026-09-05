-- Regression coverage for Build 42 items that do not publish isAmmo().
-- Loot scanning must safely treat them as ordinary items rather than stopping
-- the autonomy controller.
local rootPath = arg[1] or "."
local unknownItem
ItemTag = { AMMO = "ammo" }

KnoxSurvivorNeeds = {
    isSafeFood = function(item)
        if item == unknownItem then error("unsupported modded food check") end
        return false
    end,
    isWaterItem = function(item)
        if item == unknownItem then error("unsupported modded water check") end
        return false
    end,
}
package.preload["KS_SurvivorNeeds"] = function() return KnoxSurvivorNeeds end

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
    }
end

local plainItem = {
    IsWeapon = function() return false end,
    IsInventoryContainer = function() return false end,
    IsClothing = function() return false end,
    isCanBandage = function() return false end,
    getFullType = function() return "Base.PlainItem" end,
    getUnequippedWeight = function() return 0.1 end,
    hasTag = function() return false end,
}
unknownItem = {
    getFullType = function() return "Mod.UnknownItem" end,
    hasTag = function() return false end,
}
-- Deliberately no isAmmo method: Build 42 classifies ammunition by ItemTag.
local javaNull = setmetatable({}, { __tostring = function() return "null" end })
local inventory = {
    getItems = function() return list({ plainItem, javaNull, unknownItem }) end,
    getFreeCapacity = function() return 10 end,
}
local character = {
    getInventory = function() return inventory end,
    getWornItem = function() return nil end,
}
local container = { getItems = function() return list({ javaNull, unknownItem }) end }

local looting = dofile(rootPath .. "/mod/42/media/lua/client/KS_SurvivorLooting.lua")
local hammer = {
    getFullType = function() return "Base.Hammer" end,
    isBroken = function() return false end,
}
local brokenHammer = {
    getFullType = function() return "Base.Hammer" end,
    isBroken = function() return true end,
}
assert(looting.isEssentialTool(hammer), "usable essential tool should be recognized")
assert(not looting.isEssentialTool(brokenHammer), "broken tool should not satisfy tool order")
assert(not looting.isEssentialTool(unknownItem), "unknown modded item must fail safely")
local ok, result = pcall(function() return looting.plan(character, container, 2) end)
assert(ok, "loot planner must tolerate missing isAmmo(): " .. tostring(result))
assert(type(result) == "table" and #result == 0, "ordinary/unknown item should not be selected")

print("Survivor looting PASS item_tag_safe=true java_null_safe=true unknown_item_safe=true")
