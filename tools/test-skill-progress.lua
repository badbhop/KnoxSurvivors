local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local data = {}
ModData = { getOrCreate = function(key) data[key] = data[key] or {} return data[key] end }
Events = {
    OnSave = { Add = function() end },
    OnGameStart = { Add = function() end },
    OnPostSave = { Add = function() end },
}
getGameTime = function() return { getWorldAgeHours = function() return 24 end } end

-- One tracked perk; level/XP driven by the fake body like native earn.
local bodyLevel, bodyXp = 1, 10
local fakePerk = {
    getParent = function() return "parent" end,
    getId = function() return "Woodwork" end,
}
Perks = {
    None = "none",
    getMaxIndex = function() return 1 end,
    fromIndex = function() return "woodwork" end,
}
PerkFactory = { getPerk = function() return fakePerk end }
local character = {
    getPerkLevel = function() return bodyLevel end,
    getXp = function()
        return { getXP = function() return bodyXp end }
    end,
}

require "KS_Persistence"
local Capabilities = require "KS_SurvivorCapabilities"

local fed = {}
KnoxActivityFeed = { event = function(text) fed[#fed + 1] = text end }

assert(KnoxPersistence.setRecord("skilled-1", "record-skilled-1"))
assert(KnoxPersistence.setSurvivorCapabilities("skilled-1", {
    version = 1, professionId = "unemployed", traitIds = {},
    skills = { Woodwork = { level = 1, xp = 10 } },
}))
assert(Capabilities.capture("skilled-1", character))
assert(#fed == 0, "no level-up, no announcement")

bodyLevel, bodyXp = 2, 40
assert(Capabilities.capture("skilled-1", character))
assert(#fed == 1 and string.find(fed[1], "Woodwork 2", 1, true),
    "level-up must announce the perk and level, got: " .. tostring(fed[1]))

local stored = KnoxPersistence.getSurvivorCapabilities("skilled-1")
assert(stored.skills.Woodwork.level == 2 and stored.skills.Woodwork.xp == 40,
    "capture must persist the progressed level and xp")

print("Skill progress PASS capture=true levelup_feed=true persist=true")
