require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_ActivityFeed"
require "KS_Settings"

local CompanionService = rawget(_G, "KnoxCompanionService") or {}
_G.KnoxCompanionService = CompanionService

local RECRUIT_TRUST = 50
local TALK_GAIN = 8
local TALK_COOLDOWN_HOURS = 0.5
local INTERACTION_DISTANCE_SQUARED = 16

local TALK_LINES = {
    "Been keeping out of trouble?",
    "Found anywhere safe yet?",
    "Keep your voice down. Sound carries.",
    "If you find clean water, remember where it was.",
    "I haven't seen many living people lately.",
}

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

local function displayName(id)
    local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
    local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
    name = string.gsub(name, "^%s*(.-)%s*$", "%1")
    return name ~= "" and name or "Survivor"
end

local function validateInteraction(player, survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    local playerSquare = player ~= nil and player:getCurrentSquare() or nil
    local survivorSquare = character ~= nil and character:getCurrentSquare() or nil
    if player == nil or playerSquare == nil then
        return nil, "player_unavailable"
    end
    if character == nil or survivorSquare == nil then
        return nil, "survivor_unavailable"
    end
    if (character.isDead ~= nil and character:isDead())
        or (player.isDead ~= nil and player:isDead()) then
        return nil, "character_dead"
    end
    if playerSquare:getZ() ~= survivorSquare:getZ() then
        return nil, "too_far_away"
    end
    local dx = playerSquare:getX() - survivorSquare:getX()
    local dy = playerSquare:getY() - survivorSquare:getY()
    if dx * dx + dy * dy > INTERACTION_DISTANCE_SQUARED then
        return nil, "too_far_away"
    end
    return character, "ready"
end

function CompanionService.getPlayerId(player)
    return KnoxPersistence.ensurePlayerId(player)
end

function CompanionService.resolvePlayer(playerId)
    if type(playerId) ~= "string" or playerId == "" then
        return nil
    end
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, count - 1) do
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and CompanionService.getPlayerId(player) == playerId then
            return player
        end
    end
    return nil
end

function CompanionService.getCompanionIds(player)
    local playerId = CompanionService.getPlayerId(player)
    return playerId ~= nil and KnoxPersistence.getCompanionIds(playerId) or {}
end

function CompanionService.talk(player, survivorId)
    local character, availability = validateInteraction(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    if character == nil or playerId == nil then
        return false, availability
    end
    local relation, result = KnoxPersistence.recordPlayerConversation(
        playerId,
        survivorId,
        TALK_GAIN,
        worldAge(),
        TALK_COOLDOWN_HOURS
    )
    if relation == nil then
        return false, result
    end
    if result == "cooldown" then
        KnoxActivityFeed.speak(character, "Give me a minute.")
        return false, result
    end
    local line = TALK_LINES[((relation.meetings - 1) % #TALK_LINES) + 1]
    KnoxActivityFeed.speak(character, line)
    print(
        "[KnoxSurvivors][Companions] talk survivor=" .. survivorId
            .. " player=" .. playerId
            .. " meetings=" .. tostring(relation.meetings)
            .. " trust=" .. tostring(relation.trust)
    )
    return true, relation
end

function CompanionService.canRecruit(player, survivorId)
    if not KnoxSettings.enabled() then
        return false, "mod_disabled"
    end
    local playerId = CompanionService.getPlayerId(player)
    local character, availability = validateInteraction(player, survivorId)
    if not KnoxPersistence.isSurvivorAlive(survivorId) then
        return false, "character_dead"
    end
    if playerId == nil then
        return false, "player_unavailable"
    end
    if character == nil then
        return false, availability
    end
    if not KnoxPersistence.isIndependentSurvivor(survivorId) then
        return false, "not_independent"
    end
    if KnoxPersistence.getTravelGroupFor(survivorId) ~= nil
        or KnoxPersistence.getFactionForSurvivor(survivorId) ~= nil then
        return false, "already_with_group"
    end
    if #KnoxPersistence.getCompanionIds(playerId) >= KnoxSettings.companionLimit() then
        return false, "companion_limit"
    end
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if relation == nil or (tonumber(relation.trust) or 0) < RECRUIT_TRUST then
        return false, "needs_trust", relation ~= nil and relation.trust or 0
    end
    return true, "ready", relation.trust
end

function CompanionService.recruit(player, survivorId)
    local ready, reason, trust = CompanionService.canRecruit(player, survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if not ready then
        if character ~= nil then
            local line = reason == "already_with_group"
                and "I'm already travelling with people."
                or "I don't know you well enough."
            KnoxActivityFeed.speak(character, line)
        end
        return false, reason, trust
    end
    local playerId = CompanionService.getPlayerId(player)
    local saved, result = KnoxPersistence.setPlayerCompanion(
        survivorId,
        playerId,
        "follow",
        worldAge()
    )
    if not saved then
        return false, result
    end
    if character ~= nil then
        KnoxActivityFeed.speak(character, "All right. I'll come with you.")
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    KnoxActivityFeed.event(displayName(survivorId) .. " joined you.")
    print(
        "[KnoxSurvivors][Companions] recruited survivor=" .. survivorId
            .. " player=" .. playerId
    )
    return true, "recruited"
end

function CompanionService.command(player, survivorId, order)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or (order ~= "follow" and order ~= "hold") then
        return false, "invalid_command"
    end
    if not KnoxPersistence.updateCompanionOrder(
        survivorId,
        playerId,
        order,
        worldAge()
    ) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil then
        KnoxActivityFeed.speak(
            character,
            order == "follow" and "Right behind you." or "I'll stay here."
        )
    end
    return true, order
end

function CompanionService.commandAll(player, order)
    local ids = CompanionService.getCompanionIds(player)
    local changed = 0
    for _, survivorId in ipairs(ids) do
        local success = CompanionService.command(player, survivorId, order)
        changed = changed + (success and 1 or 0)
    end
    if changed > 0 then
        KnoxActivityFeed.event(order == "follow"
            and "Party order: regroup and follow."
            or "Party order: hold position.")
    end
    return changed > 0, changed
end

function CompanionService.setCombatStance(player, survivorId, stance)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionCombatStance(
        survivorId, playerId, stance, worldAge()
    ) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil then
        local lines = {
            passive = "I'll stay close and keep my head down.",
            defensive = "I'll cover us, but I won't chase them.",
            aggressive = "I'll clear anything I see.",
        }
        KnoxActivityFeed.speak(character, lines[stance] or "I'll adjust.")
    end
    return true, stance
end

function CompanionService.setClimbing(player, survivorId, allowed)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionClimbing(
        survivorId,
        playerId,
        allowed,
        worldAge()
    ) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    return true, allowed == true and "climbing_allowed" or "climbing_disabled"
end

function CompanionService.setClimbingAll(player, allowed)
    local changed = 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success = CompanionService.setClimbing(player, survivorId, allowed)
        changed = changed + (success and 1 or 0)
    end
    if changed > 0 then
        KnoxActivityFeed.event(allowed
            and "Party traversal: vaulting and climbing allowed."
            or "Party traversal: vaulting and climbing disabled.")
    end
    return changed > 0, changed
end

function CompanionService.issueDirective(player, survivorId, directive)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionDirective(
        survivorId,
        playerId,
        directive,
        worldAge()
    ) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    return true, tostring(directive.kind)
end

function CompanionService.issueDirectiveAll(player, directive)
    local changed = 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success = CompanionService.issueDirective(player, survivorId, directive)
        changed = changed + (success and 1 or 0)
    end
    if changed > 0 then
        local labels = {
            loot_area = "Loot the marked area.",
            loot_building = "Search and loot this building.",
            loot_corpses = "Search the bodies nearby.",
            go_to = "Move to the marked location.",
            guard = "Hold and guard this location.",
        }
        KnoxActivityFeed.event("Party order: " .. (labels[directive.kind] or "new task."))
    end
    return changed > 0, changed
end

function CompanionService.sendToBase(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    local manager = rawget(_G, "KnoxBaseManager")
    local base = manager ~= nil and manager.getForOwner ~= nil
        and manager.getForOwner("player", playerId)
        or nil
    if base == nil then
        return false, "no_player_base"
    end
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    local saved, result = KnoxPersistence.setPlayerBaseResident(
        survivorId,
        playerId,
        base.id,
        worldAge()
    )
    if saved then
        KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
        if character ~= nil then
            KnoxActivityFeed.speak(character, "I'll head back and help out there.")
        end
    end
    return saved, result
end

function CompanionService.setBaseJobPreference(player, survivorId, preference)
    local playerId = CompanionService.getPlayerId(player)
    local manager = rawget(_G, "KnoxBaseManager")
    local base = manager ~= nil and manager.getForOwner ~= nil
        and manager.getForOwner("player", playerId) or nil
    if base == nil or not KnoxPersistence.setBaseJobPreference(
        survivorId, playerId, base.id, preference, worldAge()
    ) then
        return false, "not_your_base_resident"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    return true, preference
end

function CompanionService.activateFromBase(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if playerId == nil or affiliation == nil or affiliation.kind ~= "player"
        or affiliation.ownerId ~= playerId then
        return false, "not_your_survivor"
    end
    local saved, result = KnoxPersistence.setPlayerCompanion(
        survivorId,
        playerId,
        "follow",
        worldAge()
    )
    if saved then
        KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    end
    return saved, result
end

function CompanionService.dismiss(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    if playerId == nil or affiliation == nil or affiliation.kind ~= "player"
        or affiliation.ownerId ~= playerId then
        return false, "not_your_survivor"
    end
    local saved = KnoxPersistence.setSurvivorIndependent(
        survivorId,
        "dismissed",
        worldAge()
    )
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if saved and character ~= nil then
        KnoxActivityFeed.speak(character, "Understood. Take care of yourself.")
    end
    if saved then
        KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    end
    return saved, saved and "dismissed" or "save_failed"
end

function CompanionService.syncController(survivorId, controller)
    if controller == nil then
        return
    end
    local duty = KnoxPersistence.getSurvivorDuty(survivorId)
    if duty ~= nil and duty.mode == "companion" then
        if controller.clearBaseAssignment ~= nil then
            controller:clearBaseAssignment()
        end
        local formationSlot = 1
        for index, companionId in ipairs(KnoxPersistence.getCompanionIds(duty.ownerId)) do
            if companionId == survivorId then
                formationSlot = index
                break
            end
        end
        controller:setCompanionOrder(
            duty.ownerId,
            CompanionService.resolvePlayer(duty.ownerId),
            duty.order,
            formationSlot
        )
        if controller.setCompanionCombatStance ~= nil then
            controller:setCompanionCombatStance(duty.combatStance)
        end
        local policies = KnoxPersistence.getSurvivorPolicies(survivorId) or {}
        if controller.setCompanionPolicy ~= nil then
            controller:setCompanionPolicy(policies.allowClimbing ~= false)
        end
        if controller.setCompanionDirective ~= nil then
            controller:setCompanionDirective(duty.directive)
        end
    elseif duty ~= nil and duty.mode == "base" then
        if controller.clearCompanionOrder ~= nil then
            controller:clearCompanionOrder()
        end
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and manager.get ~= nil
            and manager.get(duty.baseId)
            or nil
        if controller.setBaseAssignment ~= nil then
            controller:setBaseAssignment(duty.baseId, base)
        end
    else
        if controller.clearCompanionOrder ~= nil then
            controller:clearCompanionOrder()
        end
        if controller.clearBaseAssignment ~= nil then
            controller:clearBaseAssignment()
        end
        if controller.setCompanionDirective ~= nil then
            controller:setCompanionDirective(nil)
        end
    end
end

return CompanionService
