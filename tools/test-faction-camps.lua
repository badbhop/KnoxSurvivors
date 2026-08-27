local rootPath = arg[1] or "."
local data = {}
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }

dofile(rootPath .. "/mod/42/media/lua/client/KS_Persistence.lua")
local persistence = KnoxPersistence
data.survivors = {
    one = { id = "one", alive = true, affiliation = { kind = "faction", factionId = "faction-1" }, duty = { mode = "autonomous" } },
    two = { id = "two", alive = true, affiliation = { kind = "faction", factionId = "faction-1" }, duty = { mode = "autonomous" } },
}
data.factions = {
    ["faction-1"] = { id = "faction-1", kind = "npc", leaderId = "one", memberIds = { "one", "two" } },
}

local camp, result = persistence.createFactionCamp("faction-1", {
    x = 10, y = 20, z = 0, buildingId = "building-1",
}, 12)
assert(camp ~= nil and result == "created")
assert(persistence.getFactionCamp("faction-1").id == camp.id)
assert(persistence.createFactionCamp("faction-1", { x = 10, y = 20 }, 13) == camp,
    "one faction should retain one temporary shelter")
assert(persistence.clearFactionCamp("faction-1", "moved", 14))
assert(persistence.getFactionCamp("faction-1") == nil)

print("Faction camps PASS persistent=true one_per_faction=true clearable=true")
