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
    minX = 8, minY = 18, maxX = 12, maxY = 22,
}, 12)
assert(camp ~= nil and result == "created")
assert(#camp.memberIds == 2 and camp.memberIds[1] == "one" and camp.memberIds[2] == "two",
    "camp membership should be copied from the durable faction")
assert(persistence.getCampForSurvivor("one") == camp
        and persistence.getCampForSurvivor("two") == camp,
    "save data should resolve each member back to the same camp")
assert(#persistence.syncFactionCampMembers("faction-1").memberIds == 2,
    "camp reconciliation must not duplicate membership")
assert(persistence.getFactionCamp("faction-1").id == camp.id)
assert(persistence.createFactionCamp("faction-1", { x = 10, y = 20 }, 13) == camp,
    "one faction should retain one temporary shelter")
assert(persistence.clearFactionCamp("faction-1", "moved", 14))
assert(persistence.getFactionCamp("faction-1") == nil)

local replacement = assert(persistence.createFactionCamp("faction-1", {
    x = 11, y = 21, z = 0, buildingId = "building-2",
}, 15))
assert(replacement ~= camp, "a deliberately cleared shelter may be replaced")
data.factions["faction-1"].homeBase = { buildingId = "permanent-home" }
assert(persistence.syncFactionCampMembers("faction-1") == nil
        and persistence.getFactionCamp("faction-1") == nil,
    "conversion to a permanent home must clear the temporary camp link")

print("Faction camps PASS persistent=true members=true one_per_faction=true cleanup=true")
