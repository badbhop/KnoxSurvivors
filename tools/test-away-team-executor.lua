local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path
local data = {}
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }

dofile(rootPath .. "/mod/42/media/lua/client/KS_Persistence.lua")
dofile(rootPath .. "/mod/42/media/lua/client/KS_AwayTeamExecutor.lua")

data.survivors = {
    one = {
        id = "one", alive = true,
        affiliation = { kind = "player", ownerId = "player-1" },
        duty = { mode = "base", baseId = "base-1" },
    },
}
data.bases = {
    ["base-1"] = { id = "base-1", territory = { minX = 10, minY = 10, width = 6, height = 6, z = 0 } },
}

local team = assert(KnoxPersistence.createAwayTeam(
    "player", "player-1", { "one" }, "food",
    { x = 100, y = 120, z = 0, label = "Store" }, 1, 2,
    { x = 12, y = 13, z = 0, label = "Home" }
))
assert(KnoxAwayTeamExecutor.destinationDirective(team).minX == 82,
    "destination directive uses bounded search radius")
assert(KnoxAwayTeamExecutor.destinationDirective(team).maxY == 138,
    "destination directive retains destination bounds")
assert(KnoxPersistence.advanceAwayTeams(2) == 1,
    "resource mission reaches the live collection boundary")
assert(KnoxAwayTeamExecutor.beginCollection(team.id, 2).state == "collecting",
    "executor enters collection through persistence")

local item = {
    getFullType = function() return "Base.CannedSoup" end,
}
local secondItem = {
    getFullType = function() return "Base.CannedSoup" end,
}
local inventory = {
    contains = function(_, candidate)
    return candidate == item or candidate == secondItem
    end,
}
local character = { getInventory = function() return inventory end }
local collection, result = KnoxAwayTeamExecutor.recordCollection(
    team.id, "one", { items = {
        { item = item },
        { item = item },
        { item = secondItem },
        { item = { getFullType = function() return "Base.WaterBottleFull" end } },
    } },
    character, 2.5
)
assert(collection ~= nil and result == "recorded"
    and collection.resources["Base.CannedSoup"] == 2
    and collection.resources["Base.WaterBottleFull"] == nil,
    "only unique real items present in the survivor inventory enter the ledger")
assert(KnoxAwayTeamExecutor.collectionReady(team.id),
    "one-member collection acknowledges after a real search")
assert(KnoxAwayTeamExecutor.beginReturn(team.id, 2.6) ~= nil,
    "executor opens the persisted return phase")
assert(KnoxAwayTeamExecutor.returnDestination(team.id).x == 12,
    "executor exposes the durable return point")

print("Away team executor PASS directive=true real_transfer=true return_gate=true")
