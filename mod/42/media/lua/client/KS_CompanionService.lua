require "KS_Persistence"
require "KS_SurvivorRuntime"
require "KS_ActivityFeed"
require "KS_Settings"
require "KS_CompanionVehicles"
require "KS_OrderCatalog"

local CompanionService = rawget(_G, "KnoxCompanionService") or {}
_G.KnoxCompanionService = CompanionService

local RECRUIT_TRUST = 50
local TALK_GAIN = 8
local TALK_COOLDOWN_HOURS = 0.5
local RECRUIT_REFUSAL_COOLDOWN_HOURS = 0.5
local INTERACTION_DISTANCE_SQUARED = 16
local syncCache = {}

local TALK_LINES = {
    "Been keeping out of trouble?",
    "Found anywhere safe yet?",
    "Keep your voice down. Sound carries.",
    "If you find clean water, remember where it was.",
    "I haven't seen many living people lately.",
    "We should check our supplies before we move on.",
    "Doors first. Windows only if we have to.",
    "I could use a quiet night for once.",
    "Let me know if you need me to carry anything.",
    "We should keep an eye out for medicine.",
    "This place still feels too exposed.",
    "I'm good to keep moving when you are.",
}

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

-- Search-style orders are useful from more than the ground-selection menu
-- (Notebook, party shortcuts, and future controller callers may only provide
-- the order name).  Give those orders a small, bounded area around the person
-- instead of making every caller duplicate square/radius construction.  Point
-- and guard orders still require an explicit destination so an accidental
-- click cannot send a survivor somewhere arbitrary.
local SEARCH_DIRECTIVES = {
    loot_area = true, loot_corpses = true, find_food = true, find_water = true,
    find_medical = true, find_weapon = true, find_tools = true,
    clean_inventory = true,
}

local BASE_SUPPLY_ORDERS = {
    find_food = true,
    find_water = true,
    find_medical = true,
    find_weapon = true,
    find_tools = true,
}

local function isPlayerCompanion(player, survivorId)
    if player == nil or survivorId == nil then return false end
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or KnoxPersistence.getCompanionIds == nil then return false end
    for _, id in ipairs(KnoxPersistence.getCompanionIds(playerId) or {}) do
        if tostring(id) == tostring(survivorId) then return true end
    end
    return false
end

local function defaultCompanionArea(player, survivorId, kind)
    if kind ~= "guard" and kind ~= "patrol_area" and kind ~= "patrol" then
        return nil
    end
    if not isPlayerCompanion(player, survivorId) then return nil end
    local character = KnoxSurvivorRuntime ~= nil
        and KnoxSurvivorRuntime.getCharacter ~= nil
        and KnoxSurvivorRuntime.getCharacter(survivorId) or nil
    local square = character ~= nil and character:getCurrentSquare() or nil
    square = square or (player ~= nil and player:getCurrentSquare() or nil)
    if square == nil then return nil end
    local radius = kind == "guard" and 3 or 8
    return {
        kind = kind == "patrol" and "patrol_area" or kind,
        minX = square:getX() - radius,
        minY = square:getY() - radius,
        maxX = square:getX() + radius,
        maxY = square:getY() + radius,
        z = square:getZ(),
    }
end

local function defaultSearchDirective(player, survivorId, kind)
    if not SEARCH_DIRECTIVES[kind] then return nil end
    local character = KnoxSurvivorRuntime ~= nil
        and KnoxSurvivorRuntime.getCharacter ~= nil
        and KnoxSurvivorRuntime.getCharacter(survivorId) or nil
    local square = character ~= nil and character:getCurrentSquare() or nil
    square = square or (player ~= nil and player:getCurrentSquare() or nil)
    if square == nil then return nil end
    local radius = 12
    return {
        kind = kind,
        minX = square:getX() - radius,
        minY = square:getY() - radius,
        maxX = square:getX() + radius,
        maxY = square:getY() + radius,
        z = square:getZ(),
    }
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
    if KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId) then return false, "hostile" end
    local previousRelation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    local previousTrust = previousRelation ~= nil and (tonumber(previousRelation.trust) or 30) or 30
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
    KnoxActivityFeed.event("Talked to " .. displayName(survivorId) .. ".")
    KnoxActivityFeed.speak(character, line)
    if KnoxActivityFeed.reputation ~= nil then
        KnoxActivityFeed.reputation(character, (tonumber(relation.trust) or previousTrust) - previousTrust)
    end
    print(
        "[KnoxSurvivors][Companions] talk survivor=" .. survivorId
            .. " player=" .. playerId
            .. " meetings=" .. tostring(relation.meetings)
            .. " trust=" .. tostring(relation.trust)
    )
    return true, relation
end

function CompanionService.askNeeds(player, survivorId)
    local character, availability = validateInteraction(player, survivorId)
    if character == nil then return false, availability end
    local needs = rawget(_G, "KnoxSurvivorNeeds")
    if needs == nil then
        pcall(require, "KS_SurvivorNeeds")
        needs = rawget(_G, "KnoxSurvivorNeeds")
    end
    if needs == nil then return false, "needs_unavailable" end
    local state = needs.snapshot(character)
    local line
    if state.bleedingParts > 0 then
        line = "I'm bleeding. I need something clean for it."
    elseif state.health < 65 then
        line = "I'm hurt. I could use a safe place to recover."
    elseif state.thirst >= needs.thresholds.thirst then
        line = needs.findBestWater(character, false) ~= nil
            and "I'm thirsty, but I have water." or "I need clean water."
    elseif state.hunger >= needs.thresholds.hunger then
        line = needs.findBestFood(character) ~= nil
            and "I'm hungry. I have something to eat." or "I need food."
    elseif state.fatigue >= needs.thresholds.fatigue then
        line = "I need somewhere safe to sleep."
    elseif state.endurance <= needs.thresholds.lowEndurance then
        line = "I just need a minute to catch my breath."
    else
        line = "I'm all right for now."
    end
    KnoxActivityFeed.speak(character, line)
    return true, line
end

function CompanionService.askNeedsAll(player)
    local answered = 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success = CompanionService.askNeeds(player, survivorId)
        answered = answered + (success and 1 or 0)
    end
    if answered > 0 then
        KnoxActivityFeed.event("Party needs check.")
    end
    return answered > 0, answered
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
    if KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId) then return false, "hostile" end
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
    local requiresTrust = KnoxSettings.requireTrustForRecruitment()
    if requiresTrust and relation ~= nil
        and (tonumber(relation.nextRecruitHours) or 0) > worldAge() then
        return false, "recruit_cooldown", relation.trust
    end
    if requiresTrust and (relation == nil or (tonumber(relation.trust) or 0) < RECRUIT_TRUST) then
        return false, "needs_trust", relation ~= nil and relation.trust or 0
    end
    return true, "ready", relation ~= nil and relation.trust or 0
end

function CompanionService.recruit(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    local ready, reason, trust = CompanionService.canRecruit(player, survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if not ready then
        if character ~= nil then
            local line = reason == "recruit_cooldown"
                and "Give me a little time."
                or reason == "already_with_group"
                and "I'm already travelling with people."
                or "I don't know you well enough."
            KnoxActivityFeed.speak(character, line)
        end
        if reason == "needs_trust" and playerId ~= nil then
            KnoxPersistence.recordPlayerRecruitRefusal(
                playerId,
                survivorId,
                worldAge(),
                RECRUIT_REFUSAL_COOLDOWN_HOURS
            )
        end
        return false, reason, trust
    end
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
    if playerId == nil or not KnoxOrderCatalog.isPrimaryOrder(order)
        or (order ~= "follow" and order ~= "hold" and order ~= "relax") then
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
            order == "follow" and "Right behind you."
                or (order == "relax" and "I'll take a breather." or "I'll stay here.")
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
        local messages = {
            follow = "Party order: regroup and follow.",
            hold = "Party order: hold position.",
            relax = "Party order: rest and recover.",
        }
        KnoxActivityFeed.event(messages[order] or "Party order updated.")
    end
    return changed > 0, changed
end

-- Single player-facing dispatch point.  The catalogue describes the order;
-- existing persistence/directive services still own execution and state.
-- Keeping this boundary small lets menus and future notebook controls use the
-- same validation without introducing another task manager.
function CompanionService.issueOrder(player, survivorId, kind, payload)
    local resolved, resolveResult
    if KnoxOrderCatalog.resolve ~= nil then
        resolved, resolveResult = KnoxOrderCatalog.resolve(kind)
    end
    local normalizedKind = resolved ~= nil and resolved.kind
        or KnoxOrderCatalog.normalize(kind)
    if normalizedKind == nil or (resolved == nil and not KnoxOrderCatalog.isKnown(normalizedKind)) then
        return false, resolveResult or "unknown_order"
    end
    -- Base residents use the same human-facing search labels as companions,
    -- but their request must remain a durable base duty rather than becoming
    -- a companion directive.  This branch deliberately precedes default area
    -- construction, which would otherwise route the order through the wrong
    -- ownership model.
    if BASE_SUPPLY_ORDERS[normalizedKind]
        and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.setBaseSupplyOrder ~= nil then
        local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
        if duty.mode == "base" and duty.baseId ~= nil then
            return CompanionService.setBaseSupplyOrder(player, survivorId, normalizedKind)
        end
    end
    -- `patrol` is also the resident base preference.  When a caller supplies
    -- an area payload, it is the concrete companion directive; converge that
    -- familiar label here so the payload cannot be silently discarded by the
    -- preference branch below.
    if payload ~= nil and normalizedKind == "patrol" then
        normalizedKind = "patrol_area"
    end
    if normalizedKind == "follow" or normalizedKind == "hold" or normalizedKind == "relax" then
        return CompanionService.command(player, survivorId, normalizedKind)
    end
    if normalizedKind == "return_to_base" then
        return CompanionService.sendToBase(player, survivorId)
    end
    if normalizedKind == "resume_normal_duty" then
        local duty = KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(survivorId) or {}
        if duty.mode == "base" then
            return CompanionService.clearBaseSupplyOrder(player, survivorId)
        end
        return CompanionService.clearDirective(player, survivorId)
    end
    -- Catalogue actions are thin adapters to their existing service owners.
    -- Keeping them here gives every player-facing entry point one validation
    -- boundary without introducing another executor or state store.
    if normalizedKind == "recruit" then
        return CompanionService.recruit(player, survivorId)
    end
    if normalizedKind == "dismiss" then
        return CompanionService.dismiss(player, survivorId)
    end
    if normalizedKind == "check_needs" then
        return CompanionService.askNeeds(player, survivorId)
    end
    if normalizedKind == "enter_vehicle" then
        return CompanionService.boardPlayerVehicle(player, survivorId)
    end
    if normalizedKind == "exit_vehicle" then
        return CompanionService.exitVehicle(player, survivorId)
    end
    if normalizedKind == "allow_climbing"
        or normalizedKind == "disallow_climbing" then
        return CompanionService.setClimbing(
            player,
            survivorId,
            normalizedKind == "allow_climbing"
        )
    end
    if normalizedKind == "combat_stance" then
        local stance = type(payload) == "table" and payload.stance or payload
        return CompanionService.setCombatStance(player, survivorId, stance)
    end
    if normalizedKind == "weapon_preference" then
        local preference = type(payload) == "table" and payload.preference or payload
        return CompanionService.setWeaponPreference(player, survivorId, preference)
    end
    -- A concrete task assignment is still owned by the existing task board.
    -- Route it through the same catalogue boundary as every other player
    -- order, but require the explicit base/task payload so a malformed menu
    -- call cannot silently turn into an automatic preference change.
    if normalizedKind == "assign_base_task" then
        if type(payload) ~= "table" or payload.baseId == nil or payload.taskId == nil then
            return false, "task_target_required"
        end
        local assigned, result = CompanionService.assignBaseTask(
            player, survivorId, payload.baseId, payload.taskId
        )
        return assigned ~= nil, result
    end
    if payload == nil then
        payload = defaultCompanionArea(player, survivorId, normalizedKind)
            or defaultSearchDirective(player, survivorId, normalizedKind)
    end
    if payload ~= nil and normalizedKind == "patrol" then
        normalizedKind = "patrol_area"
    end
    -- `guard` is intentionally shared by the catalogue as a base preference
    -- and as a location directive. A payload means the player selected a
    -- concrete guard post, so route it to the directive executor before the
    -- preference branch; a payload-less order still sets the resident role.
    if payload ~= nil and KnoxOrderCatalog.isDirective(normalizedKind) then
        local directive, directiveResult = KnoxOrderCatalog.makeDirective(normalizedKind, payload)
        if directive == nil then
            return false, directiveResult == "invalid_directive"
                and "directive_target_required" or directiveResult
        end
        return CompanionService.issueDirective(player, survivorId, directive)
    end
    if KnoxOrderCatalog.isBasePreference(normalizedKind) then
        return CompanionService.setBaseJobPreference(player, survivorId, normalizedKind)
    end
    -- Concrete settlement task names are valid player-facing order vocabulary,
    -- but the resident scheduler owns their execution. Route them to the
    -- matching persisted preference instead of creating a second task path.
    local taskPreference = KnoxOrderCatalog.preferenceForTask ~= nil
        and KnoxOrderCatalog.preferenceForTask(normalizedKind) or nil
    if taskPreference ~= nil then
        return CompanionService.setBaseJobPreference(player, survivorId, taskPreference)
    end
    if KnoxOrderCatalog.isDirective(normalizedKind) then
        local directive, directiveResult = KnoxOrderCatalog.makeDirective(normalizedKind, payload)
        if directive == nil then
            return false, directiveResult == "invalid_directive"
                and "directive_target_required" or directiveResult
        end
        return CompanionService.issueDirective(player, survivorId, directive)
    end
    return false, "order_not_companion_executable"
end

-- Concrete settlement work is still a task-board concern, but the player-facing
-- assignment enters through the same service boundary as every other order.
-- This keeps ownership validation and runtime refresh in one place without
-- creating a second command or scheduling system.
function CompanionService.assignBaseTask(player, survivorId, baseId, taskId)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or baseId == nil or taskId == nil or survivorId == nil then
        return nil, "invalid_assignment"
    end
    local taskBoard = rawget(_G, "KnoxBaseTaskBoard")
    if taskBoard == nil then
        taskBoard = require "KS_BaseTaskBoard"
    end
    local assigned, result = taskBoard.claimSpecific(
        baseId, taskId, survivorId, playerId
    )
    if assigned == nil then return nil, result end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, "I'll handle that job.")
    end
    return assigned, result
end

-- Group-level counterpart to issueOrder.  Party commands used to call a
-- mixture of commandAll(), issueDirectiveAll(), and direct persistence helpers,
-- which meant the visible order vocabulary and validation could diverge.  Keep
-- the same catalogue boundary for a whole party while preserving the existing
-- per-system ownership rules.
function CompanionService.issueOrderAll(player, kind, payload)
    local resolved, resolveResult
    if KnoxOrderCatalog.resolve ~= nil then
        resolved, resolveResult = KnoxOrderCatalog.resolve(kind)
    end
    local normalizedKind = resolved ~= nil and resolved.kind
        or KnoxOrderCatalog.normalize(kind)
    if normalizedKind == nil or (resolved == nil and not KnoxOrderCatalog.isKnown(normalizedKind)) then
        return false, 0, resolveResult or "unknown_order"
    end
    -- Keep payload-bearing patrol calls on the area-directive path.  Without
    -- this, the shared `patrol` label is treated as a base preference and the
    -- selected patrol area never reaches the party directive executor.
    if payload ~= nil and normalizedKind == "patrol" then
        normalizedKind = "patrol_area"
    end
    if normalizedKind == "follow" or normalizedKind == "hold" or normalizedKind == "relax" then
        local success, changed = CompanionService.commandAll(player, normalizedKind)
        return success, changed, success and "updated" or "no_companions"
    end
    if normalizedKind == "return_to_base" then
        local changed = 0
        for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
            local success = CompanionService.sendToBase(player, survivorId)
            if success then changed = changed + 1 end
        end
        return changed > 0, changed, changed > 0 and "returned" or "no_companions"
    end
    if normalizedKind == "resume_normal_duty" then
        local _, changed = CompanionService.clearDirectiveAll(player)
        local playerId = CompanionService.getPlayerId(player)
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and playerId ~= nil
            and manager.getForOwner("player", playerId) or nil
        if base ~= nil and KnoxPersistence.getBaseResidentIds ~= nil then
            for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
                local success = CompanionService.clearBaseSupplyOrder(player, residentId)
                if success then changed = changed + 1 end
            end
        end
        return changed > 0, changed, changed > 0 and "cleared" or "no_directives"
    end
    -- Party actions reuse the existing per-member service methods. Recruit and
    -- dismiss intentionally remain individual-only so a broad click cannot
    -- change ownership for the whole party accidentally.
    if normalizedKind == "check_needs" then
        local success, changed = CompanionService.askNeedsAll(player)
        return success, changed, success and "checked" or "no_companions"
    end
    if normalizedKind == "enter_vehicle" then
        local success, changed = CompanionService.boardAllPlayerVehicle(player)
        return success, changed, success and "boarded" or "no_companions"
    end
    if normalizedKind == "exit_vehicle" then
        local success, changed = CompanionService.exitAllVehicles(player)
        return success, changed, success and "exited" or "no_companions"
    end
    if normalizedKind == "allow_climbing"
        or normalizedKind == "disallow_climbing" then
        local success, changed = CompanionService.setClimbingAll(
            player,
            normalizedKind == "allow_climbing"
        )
        return success, changed, success and "updated" or "no_companions"
    end
    if normalizedKind == "combat_stance" then
        local stance = type(payload) == "table" and payload.stance or payload
        local success, changed = CompanionService.setCombatStanceAll(player, stance)
        return success, changed, success and "updated" or "no_companions"
    end
    if normalizedKind == "weapon_preference" then
        local preference = type(payload) == "table" and payload.preference or payload
        local success, changed = CompanionService.setWeaponPreferenceAll(player, preference)
        return success, changed, success and "updated" or "no_companions"
    end
    -- Without a selected area, resolve search orders per companion so each
    -- survivor searches near its own current body.  A shared player-centred
    -- directive would make a separated party converge on one stale square.
    if payload == nil and SEARCH_DIRECTIVES[normalizedKind] then
        local changed = 0
        for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
            local success = CompanionService.issueOrder(player, survivorId, normalizedKind)
            if success then changed = changed + 1 end
        end
        -- A party-wide resource order also reaches the player's base
        -- residents. Their service path persists a base supply request rather
        -- than converting them into companions, so both populations keep
        -- their existing ownership models.
        local playerId = CompanionService.getPlayerId(player)
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and playerId ~= nil
            and manager.getForOwner("player", playerId) or nil
        if base ~= nil and KnoxPersistence.getBaseResidentIds ~= nil
            and KnoxPersistence.getSurvivorDuty ~= nil then
            for _, survivorId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
                local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
                if duty.mode == "base" then
                    local success = CompanionService.issueOrder(player, survivorId, normalizedKind)
                    if success then changed = changed + 1 end
                end
            end
        end
        return changed > 0, changed, changed > 0 and "updated" or "no_companions"
    end
    -- Guard/Patrol are also valid base preferences, but a party-wide command
    -- with no selected area should still reach travelling companions. Resolve
    -- each companion locally; base residents continue through the preference
    -- path below and keep their persistent settlement duty.
    if payload == nil and (normalizedKind == "guard"
        or normalizedKind == "patrol" or normalizedKind == "patrol_area") then
        local changed = 0
        for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
            local success = CompanionService.issueOrder(player, survivorId, normalizedKind)
            if success then changed = changed + 1 end
        end
        if changed > 0 then
            return true, changed, "updated"
        end
    end
    if payload ~= nil and KnoxOrderCatalog.isDirective(normalizedKind) then
        local directive, result = KnoxOrderCatalog.makeDirective(normalizedKind, payload)
        if directive == nil then
            return false, 0, result
        end
        local success, changed = CompanionService.issueDirectiveAll(player, directive)
        return success, changed, success and "updated" or "no_companions"
    end
    if KnoxOrderCatalog.isBasePreference(normalizedKind) then
        local playerId = CompanionService.getPlayerId(player)
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and playerId ~= nil
            and manager.getForOwner("player", playerId) or nil
        if base == nil or KnoxPersistence.getBaseResidentIds == nil then
            return false, 0, "no_player_base"
        end
        local changed = 0
        for _, survivorId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
            local success = CompanionService.setBaseJobPreference(
                player, survivorId, normalizedKind
            )
            if success then changed = changed + 1 end
        end
        return changed > 0, changed, changed > 0 and "updated" or "no_residents"
    end
    local taskPreference = KnoxOrderCatalog.preferenceForTask ~= nil
        and KnoxOrderCatalog.preferenceForTask(normalizedKind) or nil
    if taskPreference ~= nil then
        local playerId = CompanionService.getPlayerId(player)
        local manager = rawget(_G, "KnoxBaseManager")
        local base = manager ~= nil and playerId ~= nil
            and manager.getForOwner("player", playerId) or nil
        if base == nil or KnoxPersistence.getBaseResidentIds == nil then
            return false, 0, "no_player_base"
        end
        local changed = 0
        for _, residentId in ipairs(KnoxPersistence.getBaseResidentIds(base.id) or {}) do
            local success = CompanionService.setBaseJobPreference(
                player, residentId, taskPreference
            )
            if success then changed = changed + 1 end
        end
        return changed > 0, changed, changed > 0 and "updated" or "no_residents"
    end
    if KnoxOrderCatalog.isDirective(normalizedKind) then
        local directive, result = KnoxOrderCatalog.makeDirective(normalizedKind, payload)
        if directive == nil then
            return false, 0, result
        end
        local success, changed = CompanionService.issueDirectiveAll(player, directive)
        return success, changed, success and "updated" or "no_companions"
    end
    return false, 0, "order_not_party_executable"
end

function CompanionService.boardAllPlayerVehicle(player)
    local boarded, waiting = 0, 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success, result = CompanionService.boardPlayerVehicle(player, survivorId)
        boarded = boarded + (success and 1 or 0)
        waiting = waiting + (result == "no_free_passenger_seat" and 1 or 0)
    end
    if boarded > 0 then
        KnoxActivityFeed.event("Party order: get in the vehicle.")
    elseif waiting > 0 then
        KnoxActivityFeed.event("No passenger seats are available.")
    end
    return boarded > 0, boarded, waiting
end

function CompanionService.exitAllVehicles(player)
    local exited = 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success = CompanionService.exitVehicle(player, survivorId)
        exited = exited + (success and 1 or 0)
    end
    if exited > 0 then
        KnoxActivityFeed.event("Party order: get out of the vehicle.")
    end
    return exited > 0, exited
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

function CompanionService.setCombatStanceAll(player, stance)
    if stance ~= "passive" and stance ~= "defensive" and stance ~= "aggressive" then
        return false, "invalid_stance"
    end
    local changed = 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success = CompanionService.setCombatStance(player, survivorId, stance)
        changed = changed + (success and 1 or 0)
    end
    if changed > 0 then
        local labels = {
            passive = "stay close",
            defensive = "protect the party",
            aggressive = "clear threats",
        }
        KnoxActivityFeed.event("Party combat stance: " .. (labels[stance] or stance) .. ".")
    end
    return changed > 0, changed
end

function CompanionService.setWeaponPreference(player, survivorId, preference)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.setCompanionWeaponPreference(
        survivorId, playerId, preference, worldAge()
    ) then return false, "invalid_companion_weapon_preference" end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    return true, preference
end

function CompanionService.setWeaponPreferenceAll(player, preference)
    if preference ~= "melee" and preference ~= "ranged" and preference ~= "auto" then
        return false, "invalid_weapon_preference"
    end
    local changed = 0
    for _, id in ipairs(CompanionService.getCompanionIds(player)) do
        if CompanionService.setWeaponPreference(player, id, preference) then changed = changed + 1 end
    end
    return changed > 0, changed
end

function CompanionService.boardPlayerVehicle(player, survivorId)
    local character, reason = validateInteraction(player, survivorId)
    if character == nil then return false, reason end
    local vehicle = player:getVehicle()
    if vehicle == nil then return false, "player_not_in_vehicle" end
    local success, result = KnoxCompanionVehicles.board(character, vehicle)
    if success then
        KnoxActivityFeed.speak(character, "I'll take a seat.")
    elseif result == "no_free_passenger_seat" then
        KnoxActivityFeed.speak(character, "I'll wait here. No more seats.")
    end
    return success, result
end

function CompanionService.exitVehicle(player, survivorId)
    local character, reason = validateInteraction(player, survivorId)
    if character == nil then return false, reason end
    local success, result = KnoxCompanionVehicles.exit(character)
    if success then KnoxActivityFeed.speak(character, "Getting out.") end
    return success, result
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
    if type(directive) ~= "table" then
        return false, "invalid_directive"
    end
    -- Keep direct callers on the same canonical boundary as issueOrder. This
    -- accepts familiar legacy labels while persisting only the current Knox
    -- directive vocabulary and preserves all caller-supplied target fields.
    local normalizedKind = KnoxOrderCatalog.normalize(directive.kind)
    if not KnoxOrderCatalog.isDirective(normalizedKind) then
        return false, "invalid_directive"
    end
    if normalizedKind ~= directive.kind then
        local canonical = {}
        for key, value in pairs(directive) do canonical[key] = value end
        canonical.kind = normalizedKind
        directive = canonical
    end
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
        local label = KnoxOrderCatalog.label(directive.kind, "New task.")
        KnoxActivityFeed.event("Party order: " .. label .. ".")
    end
    return changed > 0, changed
end

function CompanionService.clearDirective(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    if playerId == nil or not KnoxPersistence.clearCompanionDirective(
        survivorId, playerId, worldAge()
    ) then
        return false, "not_your_companion"
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil then
        KnoxActivityFeed.speak(character, "I'll get back to my usual orders.")
    end
    return true, "cleared"
end

function CompanionService.clearDirectiveAll(player)
    local changed = 0
    for _, survivorId in ipairs(CompanionService.getCompanionIds(player)) do
        local success = CompanionService.clearDirective(player, survivorId)
        changed = changed + (success and 1 or 0)
    end
    if changed > 0 then
        KnoxActivityFeed.event("Party order cleared: resume normal duty.")
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
        local autonomy = rawget(_G, "KnoxSurvivorAutonomy")
        if character ~= nil and autonomy ~= nil and autonomy.beginVirtualBaseReturn ~= nil then
            local handedOff, handoffResult = autonomy.beginVirtualBaseReturn(survivorId, base.id)
            if handedOff then
                KnoxActivityFeed.event("A companion started the trip back to base.")
                return true, handoffResult
            end
        end
    end
    return saved, result
end

function CompanionService.setBaseJobPreference(player, survivorId, preference)
    local normalizedPreference = KnoxOrderCatalog.normalizeBasePreference ~= nil
        and KnoxOrderCatalog.normalizeBasePreference(preference)
        or KnoxOrderCatalog.normalize(preference)
    if normalizedPreference == nil or not KnoxOrderCatalog.isBasePreference(normalizedPreference) then
        return false, "unknown_base_preference"
    end
    local playerId = CompanionService.getPlayerId(player)
    local manager = rawget(_G, "KnoxBaseManager")
    local base = manager ~= nil and manager.getForOwner ~= nil
        and manager.getForOwner("player", playerId) or nil
    local previousDuty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    local previousPreference = KnoxOrderCatalog.normalizeBasePreference ~= nil
        and KnoxOrderCatalog.normalizeBasePreference(previousDuty.jobPreference)
        or KnoxOrderCatalog.normalize(previousDuty.jobPreference)
    if base == nil or not KnoxPersistence.setBaseJobPreference(
        survivorId, playerId, base.id, normalizedPreference, worldAge()
    ) then
        return false, "not_your_base_resident"
    end
    if previousPreference ~= normalizedPreference
        and normalizedPreference ~= "rest"
        and KnoxPersistence.requeueAutomaticBaseTasksForSurvivor ~= nil then
        KnoxPersistence.requeueAutomaticBaseTasksForSurvivor(
            survivorId, base.id, "resident_preference_changed"
        )
    end
    if normalizedPreference == "rest"
        and KnoxPersistence.requeueAutomaticBaseTasksForSurvivor ~= nil then
        KnoxPersistence.requeueAutomaticBaseTasksForSurvivor(
            survivorId, base.id, "resident_requested_rest"
        )
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        local lines = {
            auto = "I'll help wherever the base needs me.",
            guard = "I'll keep watch.",
            patrol = "I'll patrol the area.",
            farming = "I'll take care of the garden.",
            woodwork = "I'll handle repairs and timber.",
            hauling = "I'll keep supplies moving.",
            animal_care = "I'll look after the animals.",
            repair = "I'll handle maintenance.",
            rest = "I'll rest and recover for now.",
        }
        KnoxActivityFeed.speak(character, lines[normalizedPreference]
            or ("I'll take the " .. KnoxOrderCatalog.label(normalizedPreference, "new") .. " duty."))
    end
    return true, normalizedPreference
end

function CompanionService.setBaseSupplyOrder(player, survivorId, kind)
    local normalized = KnoxOrderCatalog.normalize(kind)
    local playerId = CompanionService.getPlayerId(player)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    if not BASE_SUPPLY_ORDERS[normalized] or playerId == nil
        or duty.mode ~= "base" or duty.baseId == nil
        or KnoxPersistence.setBaseSupplyOrder == nil then
        return false, "not_your_base_resident"
    end
    local saved = KnoxPersistence.setBaseSupplyOrder(
        survivorId, playerId, duty.baseId, normalized, worldAge(), 24
    )
    if not saved then return false, "not_your_base_resident" end
    if KnoxPersistence.requeueAutomaticBaseTasksForSurvivor ~= nil then
        KnoxPersistence.requeueAutomaticBaseTasksForSurvivor(
            survivorId, duty.baseId, "resident_supply_ordered"
        )
    end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, "I'll look for "
            .. string.gsub(KnoxOrderCatalog.label(normalized), "^Find ", "") .. ".")
    end
    return true, "base_supply_ordered"
end

function CompanionService.clearBaseSupplyOrder(player, survivorId)
    local playerId = CompanionService.getPlayerId(player)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId) or {}
    if playerId == nil or duty.mode ~= "base" or duty.baseId == nil
        or KnoxPersistence.clearBaseSupplyOrder == nil then
        return false, "not_your_base_resident"
    end
    if duty.baseSupplyOrder == nil then return false, "no_supply_order" end
    local cleared = KnoxPersistence.clearBaseSupplyOrder(
        survivorId, playerId, duty.baseId, worldAge()
    )
    if not cleared then return false, "not_your_base_resident" end
    KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character ~= nil and KnoxActivityFeed ~= nil and KnoxActivityFeed.speak ~= nil then
        KnoxActivityFeed.speak(character, "I'll get back to my normal work.")
    end
    return true, "base_supply_cleared"
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
    local eventRuntime = rawget(_G, "KnoxEventRuntime")
    if eventRuntime ~= nil and controller.setEventAssignment ~= nil then
        eventRuntime.syncController(survivorId, controller)
        duty = KnoxPersistence.getSurvivorDuty(survivorId)
    end
    if controller.setWeaponPreference ~= nil then
        local policies = KnoxPersistence.getSurvivorPolicies(survivorId) or {}
        local mode = duty ~= nil and duty.mode or "independent"
        local owner = duty ~= nil and duty.ownerId or ""
        local order = duty ~= nil and duty.order or ""
        local stance = duty ~= nil and duty.combatStance or ""
        local directive = duty ~= nil and tostring(duty.directive) or ""
        local baseId = duty ~= nil and duty.baseId or ""
        local jobPreference = duty ~= nil and duty.jobPreference or ""
        local revision = duty ~= nil and duty.revision or ""
        local supplyOrder = duty ~= nil and tostring(duty.baseSupplyOrder) or ""
        local climbing = policies.allowClimbing ~= false and "1" or "0"
        local roster = ""
        if duty ~= nil and duty.mode == "companion" then
            local ids = KnoxPersistence.getCompanionIds(duty.ownerId) or {}
            local parts = {}
            for _, id in ipairs(ids) do parts[#parts + 1] = tostring(id) end
            roster = table.concat(parts, ",")
        end
        local cacheKey = table.concat({
            tostring(controller), tostring(mode), tostring(owner), tostring(order),
            tostring(stance), directive, tostring(baseId), tostring(jobPreference),
            tostring(revision), supplyOrder, roster, tostring(policies.weaponPreference or "auto"), climbing,
        }, "|")
        local previousKey = syncCache[survivorId]
        if previousKey == cacheKey then
            return
        end
        syncCache[survivorId] = cacheKey
        controller:setWeaponPreference(policies.weaponPreference)
    else
        syncCache[survivorId] = nil
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge ~= nil and bridge.setNpcPartyVisible ~= nil then
        bridge:setNpcPartyVisible(survivorId, duty ~= nil and duty.mode == "companion")
    end
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
