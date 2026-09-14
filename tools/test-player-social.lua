local root = arg[1] or "."
package.path = root .. "/mod/42/media/lua/client/?.lua;" .. package.path
for _, module in ipairs({ "KS_Persistence", "KS_SurvivorRuntime", "KS_ActivityFeed", "KS_Settings",
    "KS_CompanionVehicles", "KS_OrderCatalog", "KS_OrderSignals" }) do
    package.preload[module] = function() return true end
end

local social = "join"
local relation = { meetings = 0, lureAttempts = 0, recruitmentAttempts = 0, trust = 30 }
local hostile, robberies, joined = false, 0, 0
local square = { getX = function() return 1 end, getY = function() return 1 end,
    getZ = function() return 0 end }
local character = { getCurrentSquare = function() return square end,
    isDead = function() return false end }
local player = { getCurrentSquare = function() return square end,
    isDead = function() return false end }

KnoxSettings = { enabled = function() return true end,
    companionLimit = function() return 8 end }
KnoxPersistence = {
    ensurePlayerId = function() return "player" end,
    isSurvivorAlive = function() return true end,
    isSurvivorHostileToPlayer = function() return hostile end,
    setSurvivorHostileToPlayer = function(_, _, value) hostile = value == true; return true end,
    isIndependentSurvivor = function() return true end,
    getTravelGroupFor = function() return nil end,
    getFactionForSurvivor = function() return nil end,
    getCompanionIds = function() return {} end,
    getPlayerSocialDisposition = function() return social end,
    getPlayerRelationship = function() return relation end,
    recordPlayerSocialEvent = function(_, _, event)
        if event == "recruit_attempt" then relation.recruitmentAttempts = relation.recruitmentAttempts + 1 end
        if event == "lure_attempt" then relation.lureAttempts = relation.lureAttempts + 1 end
    end,
    setPlayerCompanion = function() joined = joined + 1; return true, "saved" end,
    getSurvivorIdentity = function() return { forename = "Test", surname = "Person" } end,
}
KnoxSurvivorRuntime = {
    getCharacter = function() return character end,
    notifyDutyChanged = function() end,
    beginRobbery = function() robberies = robberies + 1; return true end,
}
KnoxActivityFeed = { speak = function() end, event = function() end }
KnoxOrderCatalog = { isPrimaryOrder = function() return true end, normalize = function(value) return value end }
KnoxOrderSignals = { order = function() end }
getGameTime = function() return { getWorldAgeHours = function() return 8 end } end

local service = dofile(root .. "/mod/42/media/lua/client/KS_CompanionService.lua")

social = "warm_up"
local ok, reason = service.canRecruit(player, "candidate")
assert(not ok and reason == "needs_time", "guarded survivors can require time without trust gating")
assert(service.recruit(player, "candidate") == false and relation.recruitmentAttempts == 1)
relation.meetings = 2
assert(service.canRecruit(player, "candidate"), "warm-up survivor becomes recruitable after contact")
assert(service.recruit(player, "candidate") and joined == 1)

social, relation.meetings = "independent", 0
ok, reason = service.canRecruit(player, "candidate")
assert(not ok and reason == "prefers_alone", "independent survivors can decline permanently")

social, hostile, relation.lureAttempts = "lure", false, 0
ok, reason = service.canRecruit(player, "candidate")
assert(not ok and reason == "lure", "opportunists begin with a lure response")
service.recruit(player, "candidate")
assert(relation.lureAttempts == 1 and not hostile)
ok, reason = service.canRecruit(player, "candidate")
assert(not ok and reason == "dangerous", "a repeated lure becomes dangerous")
service.recruit(player, "candidate")
assert(hostile and robberies == 1, "lure response turns hostile and can rob through the existing owner")

social, hostile = "volatile", false
assert(service.canRecruit(player, "candidate"), "volatile survivor can appear recruitable before the turn")
assert(not service.recruit(player, "candidate") and hostile, "volatile survivor can attack after the offer")

print("Player social PASS warm_up=true independent=true lure=true volatile=true")
