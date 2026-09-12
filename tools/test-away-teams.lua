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
data.bases = {
    ["base-1"] = {
        id = "base-1", name = "Riverside Home",
        territory = { minX = 10, minY = 20, maxX = 16, maxY = 24, allFloors = true },
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
    { x = 110, y = 220, z = 0, label = "Riverside" }, 10, 12,
    { x = 12, y = 14, z = 0, label = "Home" }
)
assert(team ~= nil and result == "created")
assert(team.state == "outbound" and #team.memberIds == 2)
assert(team.returnDestination ~= nil and team.returnDestination.x == 12
    and persistence.getAwayTeamReturnDestination(team.id).label == "Home",
    "away dispatch should persist a real return destination when supplied")
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
assert(populationSource:find("allowAwayMission", 1, true),
    "away activation must use an explicit mission-only exception")

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
assert(autonomySource:find("candidate.awayMission", 1, true)
    and autonomySource:find("setAwayTeam", 1, true),
    "loaded away members must restore at their mission point and bind the controller")
local controllerSource = assert(io.open(rootPath
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua", "r")):read("*a")
assert(controllerSource:find("finishAwayCollection", 1, true)
    and controllerSource:find("AWAY_RETURN", 1, true),
    "away members must record collection and return through the controller lifecycle")
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
assert(persistence.getAwayTeamReturnDestination(supplyTeam.id) ~= nil,
    "base-owned resource dispatches should derive a durable return point")
local homeDestination = persistence.getAwayTeamReturnDestination(supplyTeam.id)
assert(homeDestination.x == 13 and homeDestination.y == 22,
    "away-team return uses saved territory center instead of its first corner")
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
local collectionProgress = persistence.getAwayTeamProgress(supplyTeam.id, 21.2)
assert(collectionProgress.collectedItems == 3
    and collectionProgress.collectingMembers == 1
    and collectionProgress.memberCount == 1
    and collectionProgress.collectionProgress == 1,
    "away-team progress must expose honest collected-item/member progress")
local premature, prematureResult = persistence.completeAwayTeamMember(
    supplyTeam.id, "one", true, "still_at_destination", 21.3
)
assert(premature == nil and prematureResult == "invalid_completion"
    and persistence.getSurvivorDuty("one").mode == "away",
    "destination collection must not restore duty before return begins")
local returning = assert(persistence.beginAwayTeamReturn(supplyTeam.id, 21.5))
assert(returning.state == "returning" and returning.returnStartedAtHours == 21.5,
    "resource mission must expose an explicit return handoff")
local resolved, resolveResult = persistence.completeAwayTeamMember(
    supplyTeam.id, "one", true, "returned_to_owner", 22
)
assert(resolveResult == "complete" and resolved.state == "complete"
    and resolved.result.kind == "resource_run"
    and resolved.result.resources["Base.CannedSoup"] == 2
    and persistence.getSurvivorDuty("one").mode == "base",
    "team completion restores prior duty only after recorded return")

-- A multi-member resource run must not enter return while one member is still
-- searching. A valid empty search is still an acknowledgement.
local groupSupply = assert(persistence.createAwayTeam(
    "player", "player-1", { "one", "two" }, "food",
    { x = 132, y = 242, z = 0, label = "Group supply stop" }, 22, 23
))
assert(persistence.advanceAwayTeams(23) == 1)
assert(persistence.beginAwayTeamCollection(groupSupply.id, 23.1) ~= nil)
assert(persistence.recordAwayTeamCollection(
    groupSupply.id, "one", { "Base.CannedSoup" }, 23.2
) ~= nil)
assert(not persistence.awayTeamCollectionReady(groupSupply.id),
    "group return must wait for every member acknowledgement")
local pendingReturn, pendingResult = persistence.beginAwayTeamReturn(groupSupply.id, 23.3)
assert(pendingReturn == nil and pendingResult == "members_pending_collection",
    "partial group collection must not begin return")
local emptyCollection, emptyResult = persistence.recordAwayTeamCollection(
    groupSupply.id, "two", {}, 23.4
)
assert(emptyCollection ~= nil and emptyResult == "no_items"
    and persistence.awayTeamCollectionReady(groupSupply.id),
    "empty member search must still complete collection")
assert(persistence.beginAwayTeamReturn(groupSupply.id, 23.5) ~= nil,
    "all acknowledged members should unlock return")
assert(persistence.completeAwayTeamMember(
    groupSupply.id, "one", true, "returned_to_owner", 23.6
) ~= nil)
assert(persistence.completeAwayTeamMember(
    groupSupply.id, "two", true, "returned_to_owner", 23.7
) ~= nil)

local returnTimeoutTeam = assert(persistence.createAwayTeam(
    "player", "player-1", { "one" }, "food",
    { x = 135, y = 245, z = 0, label = "Return timeout store" }, 24, 25
))
assert(persistence.advanceAwayTeams(25) == 1)
assert(persistence.beginAwayTeamCollection(returnTimeoutTeam.id, 25.1) ~= nil)
assert(persistence.recordAwayTeamCollection(
    returnTimeoutTeam.id, "one", { "Base.CannedSoup" }, 25.2
) ~= nil)
assert(persistence.beginAwayTeamReturn(returnTimeoutTeam.id, 25.3) ~= nil)
assert(persistence.advanceAwayTeams(97.3) == 1)
local returnExpired = persistence.getAwayTeam(returnTimeoutTeam.id)
assert(returnExpired.state == "blocked"
    and returnExpired.result.kind == "resource_run_return_expired"
    and returnExpired.result.reason == "return_timeout"
    and returnExpired.result.members.one.success == false
    and persistence.getSurvivorDuty("one").mode == "base",
    "return timeout must release an unacknowledged member without losing the real ledger")

local expiringTeam = assert(persistence.createAwayTeam(
    "player", "player-1", { "one" }, "food",
    { x = 140, y = 250, z = 0, label = "Remote store" }, 30, 31
))
assert(persistence.advanceAwayTeams(31) == 1
    and persistence.getAwayTeam(expiringTeam.id).state == "awaiting_collection")
assert(persistence.advanceAwayTeams(103) == 1,
    "uncollected resource missions must reach a bounded terminal state")
local expired = persistence.getAwayTeam(expiringTeam.id)
assert(expired.state == "blocked" and expired.result.kind == "resource_run_expired"
    and expired.result.reason == "collection_timeout"
    and persistence.getSurvivorDuty("one").mode == "base",
    "collection expiry must restore the member's prior duty without creating loot")

-- A death racing mission release must remain a deceased duty, never the old
-- base/companion duty captured when the team departed.
local deadReturnTeam = assert(persistence.createAwayTeam(
    "player", "player-1", { "one" }, "food",
    { x = 136, y = 246, z = 0, label = "Death race store" }, 104, 105
))
assert(persistence.advanceAwayTeams(105) == 1)
assert(persistence.beginAwayTeamCollection(deadReturnTeam.id, 105.1) ~= nil)
assert(persistence.recordAwayTeamCollection(
    deadReturnTeam.id, "one", { "Base.CannedSoup" }, 105.15
) ~= nil)
assert(persistence.beginAwayTeamReturn(deadReturnTeam.id, 105.2) ~= nil)
assert(persistence.markSurvivorDead("one", 105.3, "mission_test") == true)
assert(persistence.advanceAwayTeams(178) == 1)
assert(persistence.getSurvivorDuty("one").mode == "deceased",
    "dead away member must not regain prior ownership during mission release")

print("Away teams PASS validation=true persistence=true duty_restore=true scout_no_resources=true resource_ledger=true")
