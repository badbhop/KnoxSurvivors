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
    local alreadyHostile = KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId)
    if KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, true)
        and not alreadyHostile then
        KnoxPersistence.recordPlayerAggression(playerId, survivorId, worldAge())
        KnoxActivityFeed.event("A survivor has turned hostile.")
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

return HumanCombat
