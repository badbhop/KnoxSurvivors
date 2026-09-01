local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local rolls = 0
ZombRand = function(first, second)
    rolls = rolls + 1
    if second ~= nil then return first end
    if first == 100 then return 99 end
    return 0
end

ClothingSelectionDefinitions = {
    default = { Male = { Shirt = { items = { "Base.Shirt_FormalWhite" } } } },
    doctor = { Female = { Pants = { items = { "Base.Trousers_Suit" } } } },
}
TraitClothingSelectionDefinitions = nil

local worn, dressed = {}, {}
local bridge = {
    isNpcFemale = function() return false end,
    wearNpcItem = function(_, id, fullType)
        worn[#worn + 1] = id .. ":" .. fullType
        return "WORN"
    end,
    dressNpcItem = function(_, id, fullType)
        dressed[#dressed + 1] = id .. ":" .. fullType
        return "WORN"
    end,
}

dofile("mod/42/media/lua/client/KS_CharacterAppearance.lua")
local ok, evidence = KnoxCharacterAppearance.randomizeNewSurvivor(bridge, "ks-scientist-1",
    { professionId = "base:doctor", traitIds = {} }, "Base.JacketLong_Doctor")
assert(ok, evidence)
assert(worn[1] == "ks-scientist-1:Base.Shirt_FormalWhite")
assert(dressed[1] == "ks-scientist-1:Base.Trousers_Suit"
    and dressed[2] == "ks-scientist-1:Base.JacketLong_Doctor",
    "profession clothing and explicit lab coat are applied through real wear mechanics")
assert(string.find(evidence, "worn=3", 1, true) and rolls >= 3, evidence)

print("character appearance tests passed")
