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

rolls = { 0, 0, 0, 0, 0, 0, 0, 0 }
rollIndex = 0
added = {}
local renamed = nil
local baseAdd = inventory.AddItem
inventory.AddItem = function(self, fullType)
    local item = baseAdd(self, fullType)
    item.setCustomName = function(_, name) renamed = name end
    return item
end
local scienceOk, scienceEvidence = gear.initialize("ks-world-1", character, bridge, "science")
assert(scienceOk, scienceEvidence)
assert(#added == 7, scienceEvidence)
assert(added[1] == "Base.Clipboard" and added[2] == "Base.Pen"
    and added[3] == "Base.Scalpel", "science kit must use real ordinary field items")
assert(added[4] == "Base.AntibioticsBox" and renamed == "Knox Cure",
    "scientists can carry the renamed cure")
assert(added[5] == "Base.WaterBottle" and added[6] == "Base.Crisps"
    and added[7] == "Base.RippedSheets")
assert(string.find(scienceEvidence, "theme=science", 1, true) ~= nil)

rolls = { 50, 0, 0, 0, 0, 0, 0, 0 }
rollIndex = 0
added = {}
renamed = nil
local plainOk, plainEvidence = gear.initialize("ks-world-1", character, bridge, "science")
assert(plainOk, plainEvidence)
assert(#added == 6, plainEvidence)
for _, fullType in ipairs(added) do
    assert(fullType ~= "Base.AntibioticsBox", "the cure stays rare")
end
assert(renamed == nil, "no cure, no rename")

rolls = { 0, 0, 0, 0, 0, 0, 0, 0 }
rollIndex = 0
added = {}
local militaryOk, militaryEvidence = gear.initialize("ks-world-1", character, bridge, "military")
assert(militaryOk, militaryEvidence)
assert(#added == 10, militaryEvidence)
assert(added[1] == "Base.HuntingKnife" and added[2] == "Base.Pistol"
    and added[3] == "Base.9mmClip", "Military kit uses real weapon and magazine items")
assert(added[4] == "Base.Bullets9mm" and added[5] == "Base.Bullets9mm"
    and added[6] == "Base.Bullets9mm" and added[7] == "Base.WalkieTalkie5",
    "Military kit carries exactly three native five-round stacks and one radio")
assert(added[8] == "Base.WaterBottle" and added[9] == "Base.Crisps"
    and added[10] == "Base.RippedSheets")
assert(string.find(militaryEvidence, "theme=military", 1, true) ~= nil)

print("survivor starting gear tests passed")
