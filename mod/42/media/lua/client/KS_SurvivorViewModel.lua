require "KS_CompanionService"
require "KS_Persistence"
require "KS_SurvivorCapabilities"
require "KS_SurvivorNeeds"
require "KS_SurvivorRuntime"
require "KS_OrderCatalog"
local SurvivorNames = require "KS_SurvivorNames"

local ViewModel = rawget(_G, "KnoxSurvivorViewModel") or {}
_G.KnoxSurvivorViewModel = ViewModel

local ACTIVITY_LABELS = {
    fighting = "Fighting",
    looting = "Looting",
    searching = "Searching",
    seeking_supplies = "Looking for supplies",
    exploring = "On the move",
    resting = "Resting",
    busy = "Busy",
    travelling = "Travelling",
    following = "Following",
    holding = "Waiting here",
    returning_home = "Returning to base",
    working_at_base = "Working at base",
    at_base = "At base",
    scouting_base = "Looking for a base",
    meeting = "Talking",
    stopped = "Stopped",
    waiting = "Waiting",
    idle = "Taking a moment",
    trading = "Trading",
    returning_to_shelter = "Returning to shelter",
    at_shelter = "At shelter",
    riding = "In vehicle",
    boarding = "Using vehicle",
}

local ROLE_LABELS = {
    companion = "Companion",
    resident = "Base resident",
    faction = "Faction survivor",
    independent = "Independent",
}

local LIFE_INTENT_LABELS = {
    find_food = "Looking for food",
    find_water = "Looking for water",
    find_medical = "Looking for medical supplies",
    scavenge = "Scavenging",
    investigate_building = "Checking a building",
    travel_area = "Travelling onward",
}

local function clamp01(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function cleanNamePart(value)
    return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
end

local function identityFor(id, character)
    local stored = KnoxPersistence.getSurvivorIdentity(id) or {}
    return SurvivorNames.resolve(id, stored, character)
end

local function liveCharacter(id)
    local success, character = pcall(function()
        return KnoxSurvivorRuntime.getCharacter(id)
    end)
    if not success or character == nil then
        return nil
    end
    local squareOk, square = pcall(function()
        return character:getCurrentSquare()
    end)
    return squareOk and square ~= nil and character or nil
end

local function physicalState(character, id)
    local fallback = {
        hunger = 0,
        thirst = 0,
        fatigue = 0,
        endurance = 1,
        bleedingParts = 0,
        health = 100,
    }
    if character == nil then
        local stored = KnoxPersistence.getUnloadedSurvivalState ~= nil
            and KnoxPersistence.getUnloadedSurvivalState(id) or nil
        local known = type(stored) == "table" and stored.pendingMaterialization ~= true
        return known and stored or fallback, known
    end
    local success, state = pcall(function()
        return KnoxSurvivorNeeds.snapshot(character)
    end)
    if success and type(state) == "table" then
        return state, true
    end
    return fallback, false
end

local function weaponName(character)
    if character == nil then
        return "Unarmed"
    end
    local success, item = pcall(function()
        return character:getPrimaryHandItem() or character:getSecondaryHandItem()
    end)
    if not success or item == nil then
        return "Unarmed"
    end
    local nameOk, name = pcall(function()
        return item:getDisplayName()
    end)
    return nameOk and cleanNamePart(name) ~= "" and tostring(name) or "Unarmed"
end

local function roleFor(affiliation, duty)
    if affiliation.kind == "player" then
        return duty.mode == "companion" and "companion" or "resident"
    end
    if affiliation.kind == "faction" then
        return "faction"
    end
    return "independent"
end

local function worldAgeHours()
    local gameTime = getGameTime ~= nil and getGameTime() or nil
    return gameTime ~= nil and tonumber(gameTime:getWorldAgeHours()) or 0
end

local function wholeDaysSince(startedAtHours, nowHours)
    local started = tonumber(startedAtHours)
    if started == nil then
        return nil
    end
    return math.floor(math.max(0, (tonumber(nowHours) or 0) - started) / 24)
end

local function liveNumber(character, getterName)
    if character == nil or character[getterName] == nil then
        return nil
    end
    local success, value = pcall(function()
        return character[getterName](character)
    end)
    return success and tonumber(value) or nil
end

local function existingPlayerId(player)
    if player == nil or player.getModData == nil then
        return nil
    end
    local success, modData = pcall(function()
        return player:getModData()
    end)
    local knox = success and type(modData) == "table" and modData.KnoxSurvivors or nil
    local playerId = type(knox) == "table" and knox.playerId or nil
    return type(playerId) == "string" and playerId ~= "" and playerId or nil
end

local function professionLabelFor(id)
    local success, label = pcall(function()
        local profile = KnoxPersistence.getSurvivorCapabilities(id)
        return KnoxSurvivorCapabilities.professionLabel(profile)
    end)
    return success and cleanNamePart(label) ~= "" and tostring(label) or "Survivor"
end

-- Base duty is persisted separately from the loaded controller.  Projecting an
-- active claim here keeps the Notebook/Card truthful after a reload or while
-- the controller is between ticks, without creating another order owner.
local function claimedBaseTaskFor(id, duty)
    if id == nil or type(duty) ~= "table" or duty.mode ~= "base"
        or duty.baseId == nil or KnoxPersistence.getBase == nil then
        return nil
    end
    local base = KnoxPersistence.getBase(duty.baseId)
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if type(task) == "table" and task.state == "claimed"
            and tostring(task.claimedBy or "") == tostring(id) then
            return task
        end
    end
    return nil
end

local function orderLabelFor(duty, survivorId)
    -- A stale companion directive may survive a delayed duty refresh.  Base
    -- ownership is authoritative, so never let that transient field mask the
    -- resident's real claimed work in the player-facing status.
    local directive = duty.mode ~= "base"
        and type(duty.directive) == "table" and duty.directive or nil
    local directiveLabel = directive ~= nil and KnoxOrderCatalog.statusLabel(
        tostring(directive.kind or ""), nil
    ) or nil
    if directiveLabel ~= nil then
        return directiveLabel
    end
    if duty.mode == "base" then
        local task = claimedBaseTaskFor(survivorId, duty)
        if task ~= nil then
            return KnoxOrderCatalog.label(
                KnoxOrderCatalog.normalizeTaskType(task.type) or task.type,
                "Working at base"
            )
        end
        if duty.lastJobType ~= nil then
            return "Available at base (last: " .. KnoxOrderCatalog.label(
                KnoxOrderCatalog.normalizeTaskType(duty.lastJobType) or duty.lastJobType,
                tostring(duty.lastJobType)
            ) .. ")"
        end
        return "Available at base"
    end
    if duty.mode == "companion" then
        local directive = type(duty.directive) == "table" and duty.directive or nil
        if directive ~= nil then
            local label = KnoxOrderCatalog.statusLabel(tostring(directive.kind or ""), nil)
            if label ~= nil then return label end
        end
        return duty.order == "hold" and "Holding here"
            or (duty.order == "relax" and "Relaxing" or "Following")
    end
    if duty.order == "return" or duty.order == "return_to_base" then
        return "Returning to base"
    end
    return ACTIVITY_LABELS[tostring(duty.order or "")] or "Surviving"
end

local function locationLabelFor(duty, character, distance, sameLevel)
    if duty.mode == "base" and type(duty.baseId) == "string" then
        local base = KnoxPersistence.getBase(duty.baseId)
        local name = tostring(base ~= nil and base.name or "Home Base")
        local manager = rawget(_G, "KnoxBaseManager")
        if character ~= nil and manager ~= nil and manager.containsSquare ~= nil then
            local ok, inside = pcall(function()
                return manager.containsSquare(base, character:getCurrentSquare())
            end)
            if ok and inside then return "At " .. name end
        end
        return (character == nil and "Away - assigned to " or "Outside ") .. name
    end
    if character == nil then
        return "Away"
    end
    if distance == nil then
        return "Nearby"
    end
    if not sameLevel then
        return "Nearby, another floor"
    end
    return "With you - " .. tostring(math.floor(distance + 0.5)) .. " tiles"
end

local function runtimeActivity(id)
    local success, snapshot = pcall(function()
        return KnoxSurvivorRuntime.snapshot(id)
    end)
    if not success or type(snapshot) ~= "table" or snapshot.loaded == false then
        local intent = KnoxPersistence.getSurvivorLifeIntent ~= nil
            and KnoxPersistence.getSurvivorLifeIntent(id) or nil
        local intentLabel = intent ~= nil
            and LIFE_INTENT_LABELS[tostring(intent.kind or "")] or nil
        local stored = KnoxPersistence.getUnloadedSurvivalState ~= nil
            and KnoxPersistence.getUnloadedSurvivalState(id) or nil
        local labels = {
            base_life = "Living at base",
            group_travel = "Travelling with group",
            group_waiting = "Waiting for group",
            group_regrouping = "Regrouping",
            surviving = "Surviving offscreen",
            exploring = "Exploring",
            seeking_supplies = "Looking for supplies",
            sleeping = "Sleeping",
            resting = "Resting",
            sheltering = "Staying nearby",
            returning_to_base = "Returning to base",
            waiting_for_leader = "Waiting for leader",
            away_mission = "On a mission",
        }
        return intentLabel or (stored ~= nil and labels[stored.activity] or nil)
    end
    return ACTIVITY_LABELS[tostring(snapshot.activity or "")]
end

local function activityFor(duty, state, loaded, alive, currentActivity)
    if not alive then
        return "Dead"
    end
    if not loaded then
        return currentActivity or "Away"
    end
    if (tonumber(state.bleedingParts) or 0) > 0 or (tonumber(state.health) or 100) < 75 then
        return "Hurt"
    end
    if currentActivity ~= nil then
        return currentActivity
    end
    if (tonumber(state.thirst) or 0) >= KnoxSurvivorNeeds.thresholds.thirst then
        return "Needs water"
    end
    if (tonumber(state.hunger) or 0) >= KnoxSurvivorNeeds.thresholds.hunger then
        return "Needs food"
    end
    if (tonumber(state.endurance) or 1) <= KnoxSurvivorNeeds.thresholds.lowEndurance then
        return "Catching breath"
    end
    if (tonumber(state.fatigue) or 0) >= KnoxSurvivorNeeds.thresholds.fatigue then
        return "Tired"
    end
    if duty.mode == "companion" then
        local directive = type(duty.directive) == "table" and duty.directive or nil
        if directive ~= nil then
            if directive.kind == "guard" then
                return "Guarding"
            end
            if directive.kind == "go_to" then
                return "Moving"
            end
        end
        return duty.order == "hold" and "Waiting here"
            or (duty.order == "relax" and "Relaxing" or "Following")
    end
    if duty.mode == "base" then
        return "At base"
    end
    return "Surviving"
end

local function playerDistance(player, character)
    if player == nil or character == nil then
        return nil, false
    end
    local success, distance, sameLevel = pcall(function()
        local dx = player:getX() - character:getX()
        local dy = player:getY() - character:getY()
        return math.sqrt(dx * dx + dy * dy), player:getZ() == character:getZ()
    end)
    return success and distance or nil, success and sameLevel or false
end

function ViewModel.resolveLiveCharacter(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    return liveCharacter(id)
end

function ViewModel.getSurvivor(id, playerNum)
    if type(id) ~= "string" or id == "" then
        return nil
    end

    local player = getSpecificPlayer(tonumber(playerNum) or 0)
    local character = liveCharacter(id)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {
        kind = "independent",
    }
    local duty = KnoxPersistence.getSurvivorDuty(id) or {
        mode = "autonomous",
        order = "survive",
    }
    local state, vitalsAvailable = physicalState(character, id)
    local forename, surname, displayName = identityFor(id, character)
    local distance, sameLevel = playerDistance(player, character)
    local currentActivity = runtimeActivity(id)
    local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
    local nowHours = worldAgeHours()
    local ageYears = tonumber(identity.ageYears) or liveNumber(character, "getAge")
    local daysSurvived = wholeDaysSince(identity.createdAtHours, nowHours)
    if daysSurvived == nil then
        local survivedHours = liveNumber(character, "getHoursSurvived")
        daysSurvived = survivedHours ~= nil and math.floor(math.max(0, survivedHours) / 24) or nil
    end
    local playerId = existingPlayerId(player)
    local relationship = playerId ~= nil
        and KnoxPersistence.getPlayerRelationshipSnapshot(playerId, id)
        or nil
    local capabilities = KnoxPersistence.getSurvivorCapabilities(id) or {}
    local lifeIntent = KnoxPersistence.getSurvivorLifeIntent ~= nil
        and KnoxPersistence.getSurvivorLifeIntent(id) or nil
    local faction = affiliation.factionId ~= nil and KnoxPersistence.getFaction ~= nil
        and KnoxPersistence.getFaction(affiliation.factionId) or nil
    local knownSince = relationship ~= nil and relationship.firstMetHours
        or affiliation.joinedAtHours
    local role = roleFor(affiliation, duty)
    local alive = KnoxPersistence.isSurvivorAlive == nil
        or KnoxPersistence.isSurvivorAlive(id) ~= false
    if character ~= nil then
        local success, dead = pcall(function()
            return character:isDead()
        end)
        alive = alive and not (success and dead == true)
    end

    return {
        version = 2,
        id = id,
        forename = forename,
        surname = surname,
        displayName = displayName,
        role = role,
        roleLabel = ROLE_LABELS[role] or "Survivor",
        professionLabel = professionLabelFor(id),
        traits = capabilities.traitIds or {},
        skills = capabilities.skills or {},
        trust = relationship ~= nil and tonumber(relationship.trust) or nil,
        relationshipMeetings = relationship ~= nil and tonumber(relationship.meetings) or nil,
        factionName = faction ~= nil and tostring(faction.name or faction.id or "") or nil,
        ageYears = ageYears ~= nil and math.floor(ageYears) or nil,
        daysSurvived = daysSurvived,
        daysKnown = wholeDaysSince(knownSince, nowHours),
        locationLabel = alive and locationLabelFor(duty, character, distance, sameLevel) or "Deceased",
        orderLabel = orderLabelFor(duty, id),
        order = tostring(duty.order or "survive"),
        activity = activityFor(duty, state, character ~= nil, alive, currentActivity),
        lifeIntent = lifeIntent ~= nil and {
            kind = lifeIntent.kind,
            phase = lifeIntent.phase,
            label = LIFE_INTENT_LABELS[tostring(lifeIntent.kind or "")],
        } or nil,
        loaded = character ~= nil,
        alive = alive,
        health = clamp01((tonumber(state.health) or 100) / 100),
        bleedingParts = math.max(0, tonumber(state.bleedingParts) or 0),
        needs = {
            food = 1 - clamp01(state.hunger),
            water = 1 - clamp01(state.thirst),
            rest = 1 - clamp01(state.fatigue),
            endurance = clamp01(state.endurance),
        },
        vitals = {
            available = vitalsAvailable == true,
            health = vitalsAvailable and clamp01((tonumber(state.health) or 100) / 100) or nil,
            hunger = vitalsAvailable and clamp01(state.hunger) or nil,
            thirst = vitalsAvailable and clamp01(state.thirst) or nil,
            fatigue = vitalsAvailable and clamp01(state.fatigue) or nil,
        },
        weaponName = weaponName(character),
        distanceTiles = distance,
        sameLevel = sameLevel,
        affiliation = {
            kind = tostring(affiliation.kind or "independent"),
            ownerId = affiliation.ownerId,
            factionId = affiliation.factionId,
            joinedAtHours = tonumber(affiliation.joinedAtHours),
        },
        duty = {
            mode = tostring(duty.mode or "autonomous"),
            order = tostring(duty.order or "survive"),
            ownerId = duty.ownerId,
            baseId = duty.baseId,
            jobPreference = KnoxOrderCatalog.normalizeBasePreference ~= nil
                and KnoxOrderCatalog.normalizeBasePreference(duty.jobPreference)
                or duty.jobPreference,
            directiveKind = type(duty.directive) == "table"
                and tostring(duty.directive.kind or "")
                or nil,
        },
        portraitKey = character ~= nil and tostring(character) or "unloaded",
    }
end

function ViewModel.getForPlayer(playerNum)
    local playerIndex = tonumber(playerNum) or 0
    local player = getSpecificPlayer(playerIndex)
    if player == nil then
        return {}
    end

    local snapshots = {}
    local ids = KnoxCompanionService.getCompanionIds(player)
    for _, id in ipairs(ids or {}) do
        local snapshot = ViewModel.getSurvivor(id, playerIndex)
        if snapshot ~= nil and snapshot.alive and snapshot.role == "companion" then
            snapshots[#snapshots + 1] = snapshot
        end
    end
    table.sort(snapshots, function(first, second)
        local firstName = string.lower(first.displayName or first.id)
        local secondName = string.lower(second.displayName or second.id)
        if firstName == secondName then
            return first.id < second.id
        end
        return firstName < secondName
    end)
    return snapshots
end

return ViewModel
