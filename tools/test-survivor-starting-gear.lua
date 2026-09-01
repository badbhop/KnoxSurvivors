local rolls = { 0, 5, 0, 0, 0, 0, 0, 0 }
local rollIndex = 0
ZombRand = function(limit)
    rollIndex = rollIndex + 1
    return rolls[rollIndex] % limit
end

local added = {}
local inventory = {
    AddItem = function(_, fullType)
        added[#added + 1] = fullType
        return { fullType = fullType }
    end,
}
local character = {
    getInventory = function() return inventory end,
}
local bridge = {
    equipBestNpc = function(_, id)
        assert(id == "ks-world-1")
        return "EQUIPPED weapon=Base.BaseballBat"
    end,
}

local gear = dofile("mod/42/media/lua/client/KS_SurvivorStartingGear.lua")
local ok, evidence = gear.initialize("ks-world-1", character, bridge)
assert(ok)
assert(#added == 4, evidence)
assert(added[1] == "Base.BaseballBat")
assert(added[2] == "Base.WaterBottle")
assert(added[3] == "Base.Crisps")
assert(added[4] == "Base.RippedSheets")
assert(string.find(evidence, "items=4", 1, true) ~= nil)

rolls = { 0, 0, 0, 0, 0, 0, 0, 0 }
rollIndex = 0
added = {}
local policeOk, policeEvidence = gear.initialize("ks-world-1", character, bridge, "police")
assert(policeOk, policeEvidence)
assert(#added == 5, policeEvidence)
assert(added[1] == "Base.Nightstick" and added[2] == "Base.WalkieTalkie4",
    "police kit must use real restrained officer equipment")
assert(added[3] == "Base.WaterBottle" and added[4] == "Base.Crisps"
    and added[5] == "Base.RippedSheets")
assert(string.find(policeEvidence, "theme=police", 1, true) ~= nil)

print("survivor starting gear tests passed")
