require "KS_Settings"
require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_ActivityFeed"

local HumanCombat = rawget(_G, "KnoxHumanCombatRelations") or {}
_G.KnoxHumanCombatRelations = HumanCombat
local creditedKills = setmetatable({}, { __mode = "k" })

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

local function localPlayerId(character)
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, count - 1) do
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and player == character then
            return KnoxPersistence.ensurePlayerId(player)
        end
    end
    return nil
end

-- Native damage remains authoritative. This hook only records the social
-- consequence after Build 42 confirms that a player actually hit a survivor.
function HumanCombat.onWeaponHitCharacter(attacker, target)
    if not KnoxSettings.allowSurvivorPlayerCombat() then return end
    local playerId = localPlayerId(attacker)
    if playerId == nil then return end
    local survivorId = KnoxSurvivorRuntime.idForCharacter(target)
    if survivorId == nil then return end
    -- The Java bridge should already have blocked protected targets. Keep the
    -- Lua consequence path defensive as well so a stale lease or native event
    -- can never turn a companion, owned resident, or ally hostile.
    if not HumanCombat.canPlayerAttack(playerId, survivorId) then return end
    local alreadyHostile = KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId)
    if KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
        and not alreadyHostile then
        KnoxPersistence.recordPlayerAggression(playerId, survivorId, worldAge())
        KnoxActivityFeed.event("A survivor has turned hostile.")
    end
end

-- Read the existing relationship state; no hostility is created by swinging or missing.
function HumanCombat.canPlayerAttack(playerId, survivorId)
    if not KnoxSettings.enabled() or not KnoxSettings.allowSurvivorPlayerCombat() then return false end
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if affiliation == nil or affiliation.kind == "player" then return false end
    if KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId) then return true end
    local faction = KnoxPersistence.getPlayerFaction(playerId)
    if faction ~= nil and affiliation.factionId ~= nil then
        if faction.id == affiliation.factionId then return false end
        local relation = KnoxPersistence.getFactionRelationship(affiliation.factionId, faction.id)
        if relation ~= nil and relation.disposition == "allied" then return false end
    end
    -- Independent and neutral survivors remain valid player combat targets.
    -- Their response is owned by the existing hostile-human controller after
    -- an actual hit; relationship history does not grant friendly-fire safety.
    return true
end

function HumanCombat.onWeaponSwing(attacker)
    local playerId = localPlayerId(attacker)
    if playerId == nil then return end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil or bridge.beginPlayerHumanAttack == nil
        or bridge.setPlayerHumanAttackTarget == nil then return end
    if not bridge:beginPlayerHumanAttack(attacker) then return end
    -- Active bodies only, at native attack events, not a world/per-frame scan.
    for _, survivorId in ipairs(KnoxSurvivorRuntime.activeIds()) do
        bridge:setPlayerHumanAttackTarget(attacker, survivorId,
            HumanCombat.canPlayerAttack(playerId, survivorId))
    end
end

-- Native onKilled emits OnZombieDead before DoDeath. Only its actual player
-- attacker and current nearby survivor target count; there is no radius-wide XP.
function HumanCombat.onZombieDead(zombie)
    if zombie == nil or creditedKills[zombie] or not KnoxSettings.enabled() then return end
    local ok, attacker, target = pcall(function()
        if not zombie:isDead() then return nil, nil end
        return zombie:getAttackedBy(), zombie:getTarget()
    end)
    if not ok or attacker == nil or target == nil then return end
    local playerId = localPlayerId(attacker)
    if playerId == nil then return end
    local survivorId = KnoxSurvivorRuntime.idForCharacter(target)
    if survivorId == nil then return end
    local relevant, close = pcall(function()
        if target:isDead() or target:getCurrentSquare() == nil or zombie:getCurrentSquare() == nil
            or attacker:getCurrentSquare() == nil or target:getZ() ~= zombie:getZ()
            or attacker:getZ() ~= target:getZ() then return false end
        local threatDistance = (target:getX() - zombie:getX()) ^ 2 + (target:getY() - zombie:getY()) ^ 2
        local playerDistance = (target:getX() - attacker:getX()) ^ 2 + (target:getY() - attacker:getY()) ^ 2
        return threatDistance <= 64 and playerDistance <= 400
    end)
    if not relevant or not close then return end
    creditedKills[zombie] = true
    local result = KnoxPersistence.recordPlayerContribution(playerId, survivorId, "defense", worldAge())
    if result ~= nil then
        KnoxActivityFeed.speak(target, "Thanks for covering me.")
        if KnoxActivityFeed.reputation ~= nil then KnoxActivityFeed.reputation(target, result.trustGain) end
    end
end

if Events.OnWeaponHitCharacter ~= nil then
    Events.OnWeaponHitCharacter.Add(HumanCombat.onWeaponHitCharacter)
end

if Events.OnZombieDead ~= nil then Events.OnZombieDead.Add(HumanCombat.onZombieDead) end

if Events.OnWeaponSwing ~= nil then Events.OnWeaponSwing.Add(HumanCombat.onWeaponSwing) end
-- Recheck immediately before native collision; recruiting/peace during the windup wins.
if Events.OnWeaponSwingHitPoint ~= nil then Events.OnWeaponSwingHitPoint.Add(HumanCombat.onWeaponSwing) end

return HumanCombat
