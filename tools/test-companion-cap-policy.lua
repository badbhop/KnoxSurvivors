local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path
for _, module in ipairs({ "KS_Persistence", "KS_SurvivorRuntime", "KS_ActivityFeed", "KS_CompanionVehicles" }) do
    package.preload[module] = function() return true end
end
SandboxVars = { KnoxSurvivors = { CompanionLimit = 1 } }
local trust, grouped, alive, cooldown, refusalPlayer = 60, false, true, 0, nil
local square = { getX = function() return 1 end, getY = function() return 1 end,
    getZ = function() return 0 end }
local character = { getCurrentSquare = function() return square end }
KnoxPersistence = {
    ensurePlayerId = function() return "player" end,
    isSurvivorAlive = function() return alive end,
    isSurvivorHostileToPlayer = function() return false end,
    isIndependentSurvivor = function() return true end,
    getTravelGroupFor = function() return grouped and {} or nil end,
    getFactionForSurvivor = function() return nil end,
    getCompanionIds = function() return { "existing" } end,
    getPlayerRelationship = function() return { trust = trust, nextRecruitHours = cooldown } end,
    recordPlayerRecruitRefusal = function(playerId)
        refusalPlayer = playerId
        return {}
    end,
}
KnoxSurvivorRuntime = { getCharacter = function() return character end }
KnoxActivityFeed = { speak = function() end }
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
local service = require "KS_CompanionService"
local ok, reason = service.canRecruit(character, "candidate")
assert(not ok and reason == "companion_limit", "existing configured follower limit enforced")
SandboxVars.KnoxSurvivors.DisableSurvivorCaps = true
assert(service.canRecruit(character, "candidate"), "cap opt-out reaches actual recruitment gate")
trust = 5
assert(service.canRecruit(character, "candidate"),
    "low trust does not block recruitment under the default sandbox policy")
SandboxVars.KnoxSurvivors.RequireTrustForRecruitment = true
ok, reason = service.canRecruit(character, "candidate")
assert(not ok and reason == "needs_trust", "trust requirement remains available as an opt-in")
assert(not service.recruit(character, "candidate") and refusalPlayer == "player",
    "trust refusal records against the resolved player identity")
trust, grouped = 60, true
ok, reason = service.canRecruit(character, "candidate")
assert(not ok and reason == "already_with_group", "disabling caps does not steal faction/group members")
grouped, cooldown = false, 11
ok, reason = service.canRecruit(character, "candidate")
assert(not ok and reason == "recruit_cooldown", "refusal cooldown preserved")
cooldown, alive = 0, false
ok, reason = service.canRecruit(character, "candidate")
assert(not ok and reason == "character_dead", "caps do not bypass death")
print("Companion cap policy PASS configured=true disabled=true relationship_rules=true")
