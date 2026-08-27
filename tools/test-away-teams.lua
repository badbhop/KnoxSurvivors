local rootPath = arg[1] or "."
local data = {}
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }

dofile(rootPath .. "/mod/42/media/lua/client/KS_Persistence.lua")
local persistence = KnoxPersistence
data.survivors = {
    one = {
        id = "one", alive = true,
        affiliation = { kind = "player", ownerId = "player-1" },
        duty = { mode = "base", order = "available", baseId = "base-1", revision = 4 },
    },
    two = {
        id = "two", alive = true,
        affiliation = { kind = "player", ownerId = "player-1" },
        duty = { mode = "companion", order = "hold", ownerId = "player-1", revision = 2 },
    },
}

local team, result = persistence.createAwayTeam(
    "player", "player-1", { "one", "two" }, "scout",
    { x = 110, y = 220, z = 0, label = "Riverside" }, 10, 12
)
assert(team ~= nil and result == "created")
assert(team.state == "outbound" and #team.memberIds == 2)
assert(persistence.getSurvivorDuty("one").mode == "away")
assert(persistence.getAwayTeamForSurvivor("two").id == team.id)

assert(persistence.advanceAwayTeams(11) == 0)
assert(persistence.advanceAwayTeams(12) == 1)
local completed = persistence.getAwayTeam(team.id)
assert(completed.state == "complete" and completed.result.kind == "scouted")
assert(persistence.getSurvivorDuty("one").mode == "base")
assert(persistence.getSurvivorDuty("two").mode == "companion")

print("Away teams PASS persistence=true duty_restore=true scout_no_resources=true")
