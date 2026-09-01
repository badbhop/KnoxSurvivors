local root = arg[1] or "."
local data, now = {}, 24
ModData = { getOrCreate = function() return data end }
local callbacks = {}
Events = {}
for _, name in ipairs({ "OnSave", "OnPostSave", "OnGameStart", "OnWeaponHitCharacter", "OnZombieDead" }) do
    Events[name] = { Add = function(callback) callbacks[name] = callback end }
end
getGameTime = function() return { getWorldAgeHours = function() return now end } end
dofile(root .. "/mod/42/media/lua/client/KS_Persistence.lua")
local function actor(x, y, z)
    local value = { x = x or 0, y = y or 0, z = z or 0, data = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getCurrentSquare() return self.detached and nil or self end
    function value:isDead() return self.dead == true end
    function value:getModData() return self.data end
    return value
end
local player, secondPlayer = actor(), actor()
local playerId = KnoxPersistence.ensurePlayerId(player)
local secondId = KnoxPersistence.ensurePlayerId(secondPlayer)
for _, id in ipairs({ "a", "b", "c", "neutral" }) do assert(KnoxPersistence.setRecord(id, "record-" .. id)) end
local group = assert(KnoxPersistence.createTravelGroup({ "a", "b", "c" }, now))
local faction = assert(KnoxPersistence.promoteTravelGroupToFaction(group.id, now))
assert(not KnoxPersistence.recordPlayerContribution(playerId, "missing", "defense", now))
assert(data.survivors.missing == nil, "invalid contribution cannot create identity")
assert(not KnoxPersistence.recordPlayerContribution("unknown-player", "a", "defense", now))
assert(not KnoxPersistence.recordPlayerContribution(playerId, "a", "invented", now))
assert(not KnoxPersistence.recordPlayerContribution(playerId, "a", "defense", math.huge))
assert(not KnoxPersistence.recordPlayerContribution(playerId, "a", "defense", 0/0))
local result = assert(KnoxPersistence.recordPlayerContribution(playerId, "a", "defense", now))
assert(result.trustGain == 4 and result.reputationGain == 2)
assert(KnoxPersistence.getPlayerRelationship(playerId, "a").trust == 34)
assert(not KnoxPersistence.recordPlayerContribution(playerId, "a", "defense", now), "same-time spam receives no credit")
assert(KnoxPersistence.recordPlayerContribution(playerId, "a", "defense", 25))
assert(KnoxPersistence.recordPlayerContribution(playerId, "a", "defense", 26))
assert(not KnoxPersistence.recordPlayerContribution(playerId, "a", "gift", 27), "different reward kinds share daily trust cap")
assert(not KnoxPersistence.recordPlayerContribution(playerId, "a", "defense", 23), "clock rollback cannot refill reward budget")
assert(KnoxPersistence.recordPlayerContribution(playerId, "b", "defense", 26))
result = assert(KnoxPersistence.recordPlayerContribution(playerId, "c", "defense", 26))
assert(result.reputationGain == 0, "faction reward budget is shared across members")
local playerFaction = KnoxPersistence.getPlayerFaction(playerId)
local relationship = KnoxPersistence.getFactionRelationship(faction.id, playerFaction.id)
assert(relationship.reputation == 8 and relationship.disposition == "neutral", "help does not manufacture an alliance")
relationship.contributions.earned = -100
assert(KnoxPersistence.getFactionRelationship(faction.id, playerFaction.id).contributions.earned == 8,
    "read-only faction snapshot cannot mutate nested reward budgets")
dofile(root .. "/mod/42/media/lua/client/KS_Persistence.lua")
assert(not KnoxPersistence.recordPlayerContribution(playerId, "a", "defense", 27), "reload preserves cooldown/budget")
assert(KnoxPersistence.recordPlayerContribution(playerId, "a", "defense", 48), "new reward window eventually permits help")
assert(KnoxPersistence.getPlayerRelationship(secondId, "a").trust == 30, "split-screen player trust is separate")

require = function() return true end
local survivor = actor(2, 0, 0)
local bodyIds = { [survivor] = "neutral" }
KnoxSettings = { enabled = function() return true end, allowSurvivorPlayerCombat = function() return true end,
    companionLimit = function() return 4 end, requireTrustForRecruitment = function() return false end }
KnoxSurvivorRuntime = { idForCharacter = function(body) return bodyIds[body] end,
    getCharacter = function() return survivor end }
local acknowledgements, hostilityNotices, reputationNotices = 0, 0, {}
KnoxActivityFeed = { speak = function(body) assert(body == survivor) acknowledgements = acknowledgements + 1 end,
    event = function() hostilityNotices = hostilityNotices + 1 end,
    reputation = function(body, delta)
        assert(body == survivor) reputationNotices[#reputationNotices + 1] = delta
    end }
getNumActivePlayers = function() return 2 end
getSpecificPlayer = function(index) return index == 0 and player or secondPlayer end
local human = dofile(root .. "/mod/42/media/lua/client/KS_HumanCombatRelations.lua")
assert(callbacks.OnZombieDead == human.onZombieDead and callbacks.OnWeaponHitCharacter == human.onWeaponHitCharacter)
local function zombie(target, attacker)
    local body = actor(3, 0, 0)
    body.dead, body.target, body.attacker = true, target, attacker
    function body:getTarget() return self.target end
    function body:getAttackedBy() return self.attacker end
    return body
end
now = 50
local threat = zombie(survivor, player)
human.onZombieDead(threat)
assert(KnoxPersistence.getPlayerRelationship(playerId, "neutral").trust == 34 and acknowledgements == 1,
    "native player kill of survivor's immediate threat grants personal credit")
assert(reputationNotices[1] == 4, "defense displays actual earned reputation")
now = 51
human.onZombieDead(threat)
assert(acknowledgements == 1, "duplicate death callback cannot reward again after cooldown")
human.onZombieDead(zombie(player, player))
human.onZombieDead(zombie(survivor, survivor))
local distant = zombie(survivor, player) distant.x = 100
human.onZombieDead(distant)
local upstairs = zombie(survivor, player) upstairs.z = 1
human.onZombieDead(upstairs)
local alive = zombie(survivor, player) alive.dead = false
human.onZombieDead(alive)
human.onZombieDead({})
assert(acknowledgements == 1, "unrelated/NPC/distant/other-floor/live/invalid targets cannot farm credit")
human.onZombieDead(zombie(survivor, secondPlayer))
assert(KnoxPersistence.getPlayerRelationship(secondId, "neutral").trust == 34,
    "credit goes to the actual split-screen killer")

bodyIds[survivor] = "b"
human.onWeaponHitCharacter(player, survivor)
assert(KnoxPersistence.isSurvivorHostileToPlayer("b", playerId) and hostilityNotices == 1)
assert(KnoxPersistence.getPlayerRelationship(playerId, "b").trust == 4, "unprovoked hit costs existing trust")
relationship = KnoxPersistence.getFactionRelationship(faction.id, playerFaction.id)
assert(relationship.disposition == "hostile" and relationship.reputation == -10,
    "faction attack has durable reputation and hostility consequences")
human.onWeaponHitCharacter(player, survivor)
assert(KnoxPersistence.getPlayerRelationship(playerId, "b").trust == 4 and hostilityNotices == 1,
    "continued fight with existing hostile does not repeat unprovoked penalty")
assert(not KnoxPersistence.recordPlayerContribution(playerId, "b", "gift", 99),
    "gifts/help cannot erase active hostility through trust farming")
local service = dofile(root .. "/mod/42/media/lua/client/KS_CompanionService.lua")
local ok, reason = service.talk(player, "b")
assert(not ok and reason == "hostile", "hostile survivors cannot be farmed through talk")
ok, reason = service.canRecruit(player, "b")
assert(not ok and reason == "hostile", "recruitment refuses hostility before other eligibility")
dofile(root .. "/mod/42/media/lua/client/KS_Persistence.lua")
assert(KnoxPersistence.isSurvivorHostileToPlayer("b", playerId))
assert(KnoxPersistence.getFactionRelationship(faction.id, playerFaction.id).reputation == -10)
bodyIds[survivor] = "neutral"
local conversation = KnoxPersistence.getPlayerRelationship(playerId, "neutral")
conversation.trust, conversation.nextTalkHours = 99, 0
now = 60
assert(service.talk(player, "neutral"))
assert(reputationNotices[#reputationNotices] == 1, "conversation shows actual capped gain, not promised gain")
local noticeCount = #reputationNotices
assert(not service.talk(player, "neutral"))
assert(#reputationNotices == noticeCount, "conversation cooldown gives no reputation spam")
print("Player reputation PASS verified_defense=true aggression=true bounded=true persistent=true faction=true split_screen=true")
