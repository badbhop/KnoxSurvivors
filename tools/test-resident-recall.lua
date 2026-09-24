local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

for _, module in ipairs({ "KS_Persistence", "KS_SurvivorRuntime", "KS_ActivityFeed",
    "KS_CompanionVehicles", "KS_OrderCatalog", "KS_OrderSignals" }) do
    package.preload[module] = function() return true end
end

SandboxVars = { KnoxSurvivors = { CompanionLimit = 2 } }
local roster, alive, owner, duty = { "existing" }, true, "player", {
    mode = "base", ownerId = "player", baseId = "home",
}
local transitions, notifications, signals, events = 0, 0, 0, 0
local player = {}
KnoxPersistence = {
    ensurePlayerId = function() return "player" end,
    getSurvivorAffiliation = function() return { kind = "player", ownerId = owner } end,
    getSurvivorDuty = function() return duty end,
    isSurvivorAlive = function() return alive end,
    getCompanionIds = function() return roster end,
    getSurvivorIdentity = function() return { forename = "Alex", surname = "Reed" } end,
    setPlayerCompanion = function(_, playerId, order)
        assert(playerId == "player" and order == "follow")
        transitions = transitions + 1
        duty = { mode = "companion", ownerId = playerId, order = order }
        roster[#roster + 1] = "resident"
        return true, "companion"
    end,
}
KnoxSurvivorRuntime = {
    notifyDutyChanged = function() notifications = notifications + 1 end,
    getCharacter = function() return nil end,
}
KnoxActivityFeed = { event = function() events = events + 1 end }
KnoxOrderSignals = { order = function() signals = signals + 1 return true end }
getGameTime = function() return { getWorldAgeHours = function() return 48 end } end

local service = require "KS_CompanionService"
local ok, reason = service.recallToParty(player, "resident")
assert(ok and reason == "joined_party" and transitions == 1 and notifications == 1
    and events == 1 and signals == 0, "resident recall transitions through persistence without teleporting")

duty = { mode = "base", ownerId = "other", baseId = "home" }
ok, reason = service.recallToParty(player, "resident")
assert(not ok and reason == "not_base_resident", "another player's base resident is rejected")

duty = { mode = "base", ownerId = "player", baseId = "home" }
owner = "other"
ok, reason = service.recallToParty(player, "resident")
assert(not ok and reason == "not_your_survivor", "ownership is checked before duty transition")
owner = "player"

alive = false
ok, reason = service.recallToParty(player, "resident")
assert(not ok and reason == "character_dead", "dead residents cannot rejoin")
alive = true

roster = { "one", "two" }
ok, reason = service.recallToParty(player, "resident")
assert(not ok and reason == "companion_limit", "resident recall obeys party capacity")

local notebook = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_SurvivorNotebook.lua", "r")):read("*a")
assert(notebook:find('"Join Party"', 1, true)
    and notebook:find("KnoxCompanionService.recallToParty(player, id)", 1, true)
    and notebook:find("self.joinPartyBtn:setEnable(resident)", 1, true),
    "resident notebook action routes only through recall service and is resident-gated")
assert(notebook:find("Idle after ", 1, true) == nil
    and notebook:find("currentStatus", 1, true)
    and notebook:find("currentLocation", 1, true),
    "resident rows prioritize current view-model status and location over stale idle task text")

print("Resident recall PASS ownership=true capacity=true transition=true notebook=true status=true")
