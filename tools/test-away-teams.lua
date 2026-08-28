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

local valid, validation = persistence.validateAwayTeam(
    "player", "player-1", { "one", "two" }, "scout",
    { x = 110, y = 220, z = 0 }
)
assert(valid and validation == "valid", "dispatch must validate before body handoff")
local invalid, invalidReason = persistence.validateAwayTeam(
    "player", "wrong-owner", { "one" }, "scout", { x = 110, y = 220 }
)
assert(not invalid and invalidReason == "invalid_member=one",
    "invalid ownership must be rejected before body removal")
local team, result = persistence.createAwayTeam(
    "player", "player-1", { "one", "two" }, "scout",
    { x = 110, y = 220, z = 0, label = "Riverside" }, 10, 12
)
assert(team ~= nil and result == "created")
assert(team.state == "outbound" and #team.memberIds == 2)
local progress = persistence.getAwayTeamProgress(team.id, 11)
assert(progress.state == "outbound" and progress.statusLabel == "En route"
    and progress.remainingHours == 1 and progress.progress == 0.5,
    "mission progress snapshot derives durable outbound timing")
assert(persistence.getSurvivorDuty("one").mode == "away")
assert(persistence.getAwayTeamForSurvivor("two").id == team.id)

local populationSource = assert(io.open(rootPath
    .. "/mod/42/media/lua/client/KS_WorldPopulation.lua", "r")):read("*a")
assert(populationSource:find('return nil, "away_mission"', 1, true),
    "nearby population activation must leave assigned away-team members unloaded")

local autonomySource = assert(io.open(rootPath
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomy.lua", "r")):read("*a")
assert(autonomySource:find("function Autonomy.dispatchDeveloperScout", 1, true),
    "developer dispatch must use the same autonomy lifecycle owner")
assert(autonomySource:find("controller:shutdown()", 1, true)
    and autonomySource:find("bridge:removeNpc(id)", 1, true),
    "dispatch must capture and remove bodies before marking a team away")
assert(autonomySource:find("validateAwayTeam", 1, true),
    "dispatch must validate a mission before taking down its active bodies")
assert(autonomySource:find("function Autonomy.dispatchBaseScout", 1, true),
    "player base command must have a non-developer scout handoff")
local baseMenuSource = assert(io.open(rootPath
    .. "/mod/42/media/lua/client/KS_BaseContextMenu.lua", "r")):read("*a")
assert(baseMenuSource:find("Send Available Resident to Scout Here", 1, true),
    "player base menu must expose scouting")

assert(persistence.advanceAwayTeams(11) == 0)
assert(persistence.advanceAwayTeams(12) == 1)
local completed = persistence.getAwayTeam(team.id)
assert(completed.state == "complete" and completed.result.kind == "scouted")
local returned = persistence.getAwayTeamProgress(team.id, 12)
assert(returned.statusLabel == "Returned" and returned.remainingHours == 0
    and returned.progress == 1,
    "completed mission reports returned status without mutation")
assert(persistence.getSurvivorDuty("one").mode == "base")
assert(persistence.getSurvivorDuty("two").mode == "companion")

local supplyTeam = assert(persistence.createAwayTeam(
    "player", "player-1", { "one" }, "food",
    { x = 130, y = 240, z = 0, label = "Corner store" }, 20, 21
))
assert(persistence.advanceAwayTeams(21) == 1)
local arrived = persistence.getAwayTeam(supplyTeam.id)
assert(arrived.state == "awaiting_collection"
    and arrived.result.kind == "awaiting_live_collection"
    and persistence.getSurvivorDuty("one").mode == "away",
    "resource teams wait for real live collection without restoring duty or generating loot")
local collecting = assert(persistence.beginAwayTeamCollection(supplyTeam.id, 21.1))
assert(collecting.state == "collecting")
local collection, collectionResult = persistence.recordAwayTeamCollection(
    supplyTeam.id, "one", { "Base.CannedSoup", "Base.CannedSoup", "Base.WaterBottleFull" }, 21.2
)
assert(collectionResult == "recorded" and collection.resources["Base.CannedSoup"] == 2
    and collection.resources["Base.WaterBottleFull"] == 1,
    "only executor-reported item types enter the durable resource result")
local resolved, resolveResult = persistence.completeAwayTeamMember(
    supplyTeam.id, "one", true, "returned_to_owner", 22
)
assert(resolveResult == "complete" and resolved.state == "complete"
    and resolved.result.kind == "resource_run"
    and resolved.result.resources["Base.CannedSoup"] == 2
    and persistence.getSurvivorDuty("one").mode == "base",
    "team completion restores prior duty only after recorded return")

print("Away teams PASS validation=true persistence=true duty_restore=true scout_no_resources=true resource_ledger=true")
