require "KS_SurvivorAutonomyController"
require "KS_CharacterAppearance"
require "KS_Persistence"
require "KS_SurvivorRelationships"
require "KS_SurvivorRuntime"
require "KS_SurvivorCapabilities"
require "KS_CompanionService"
require "KS_Settings"
require "KS_ZombieAwareness"
require "KS_WorldPopulation"
require "KS_SurvivorStartingGear"
require "KS_SurvivorLifecyclePolicy"
require "KS_UnloadedSurvival"

local TAG = "[KnoxSurvivors][Autonomy]"
local Autonomy = rawget(_G, "KnoxSurvivorAutonomy") or {}
_G.KnoxSurvivorAutonomy = Autonomy
local activeIds = {}
local STATUS_INTERVAL_TICKS = 300
local RELATIONSHIP_INTERVAL_TICKS = 60
local POPULATION_INTERVAL_TICKS = 300
local HIBERNATION_INTERVAL_TICKS = 30
local ACTIVATION_DISTANCE = 220
local HIBERNATION_DISTANCE = 260
local HIBERNATION_DISTANCE_SQUARED = HIBERNATION_DISTANCE * HIBERNATION_DISTANCE
local DETACHED_GRACE_CHECKS = 3
local detachedGrace = {}
local DECISIONS_REQUIRED = 2
local GATE_KEY = "multi_survival_autonomy_v1"
local FACTION_BASE_GATE_KEY = "faction_base_scouting_v1"

local controllers = {}
local reservations = { threats = {}, items = {}, containers = {}, restSpots = {} }
local ticks = 0
local populationReady = false
local passReported = false
local factionBasePassReported = false
local currentScenario = "none"
local scenarioConfigured = false
local scenarioIds = {}
local nextPopulationUpdate = 0
local nextHibernationUpdate = 0
local populationStatus = nil
local update

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
    end
end

local function reportFactionBasePassIfReady()
    if factionBasePassReported then
        return
    end
    for _, id in ipairs(scenarioIds) do
        local faction = KnoxPersistence.getFactionForSurvivor(id)
        if faction ~= nil and faction.homeBase ~= nil
            and faction.engineSafehouseId ~= nil then
            factionBasePassReported = true
            KnoxPersistence.markDevGateComplete(FACTION_BASE_GATE_KEY)
            print(
                TAG .. " RESULT scenario=faction_base status=PASS"
                    .. " faction=" .. tostring(faction.id)
                    .. " leader=" .. tostring(faction.leaderId)
                    .. " members=" .. table.concat(faction.memberIds or {}, ",")
                    .. " building=" .. tostring(faction.homeBase.buildingId)
                    .. " score=" .. tostring(faction.homeBase.score)
                    .. " safehouse=" .. tostring(faction.engineSafehouseId)
            )
            return
        end
    end
end

local function squareForRecord(bridge, record)
    local success, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(record),
            bridge:getTestNpcRecordY(record),
            bridge:getTestNpcRecordZ(record)
    end)
    if not success or getCell() == nil then
        return nil, tostring(x)
    end
    return getCell():getGridSquare(x, y, z), tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function findSpawnSquare(origin)
    if origin == nil or getCell() == nil then
        return nil
    end
    local activeCharacters = {}
    for _, controller in pairs(controllers) do
        activeCharacters[#activeCharacters + 1] = controller.character
    end
    local minimumRadius = KnoxSettings.developerSpawnDistance()
    for radius = minimumRadius, math.max(minimumRadius + 8, 14) do
        local candidates = {}
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    local separated = square ~= nil and square:canStand()
                    if separated then
                        for _, character in ipairs(activeCharacters) do
                            if character:getCurrentSquare() ~= nil
                                and distanceSquared(square, character:getCurrentSquare()) < 25 then
                                separated = false
                                break
                            end
                        end
                    end
                    if separated then
                        candidates[#candidates + 1] = square
                    end
                end
            end
        end
        if #candidates > 0 then
            return candidates[ZombRand(#candidates) + 1]
        end
    end
    return nil
end

local function createSurvivorAt(bridge, id, square, developerKit)
    if square == nil then
        return nil, "no_loaded_spawn_square"
    end
    local result = tostring(bridge:spawnNpc(id, square))
    if string.find(result, "SPAWNED", 1, true) ~= 1 then
        return nil, result
    end
    local character = bridge:getNpcCharacter(id)
    if character == nil then
        bridge:removeNpc(id)
        return nil, "spawned_character_unavailable"
    end
    local capabilities, capabilityResult = KnoxSurvivorCapabilities.ensure(id, character, true)
    if capabilities == nil then
        bridge:removeNpc(id)
        return nil, "capabilities_failed=" .. tostring(capabilityResult)
    end
    local appearanceOk, appearance = KnoxCharacterAppearance.randomizeNewSurvivor(
        bridge,
        id,
        capabilities
    )
    if not appearanceOk then
        bridge:removeNpc(id)
        return nil, "appearance_failed=" .. tostring(appearance)
    end
    local equipmentOk = true
    local equipped
    if developerKit then
        equipped = tostring(bridge:seedAndEquipNpc(id))
        equipmentOk = string.find(equipped, "EQUIPPED", 1, true) == 1
    else
        equipmentOk, equipped = KnoxSurvivorStartingGear.initialize(
            id,
            character,
            bridge
        )
    end
    KnoxPersistence.ensureSurvivorIdentityFromCharacter(
        id,
        character,
        getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    )
    local saved, evidence = KnoxPersistence.captureActiveSurvivor(id)
    if not equipmentOk or not saved then
        bridge:removeNpc(id)
        return nil, "initialization_failed equipment=" .. equipped .. " save=" .. tostring(evidence)
    end
    return character,
        "SPAWNED " .. id .. " " .. tostring(appearance)
            .. " equipment=" .. tostring(equipped)
end

local function createDeveloperSurvivor(bridge, id, origin)
    local square = findSpawnSquare(origin)
    return createSurvivorAt(bridge, id, square, true)
end

local function restoreSurvivor(bridge, id, record)
    local square, location = squareForRecord(bridge, record)
    if square == nil then
        return nil, "saved_square_not_loaded=" .. tostring(location)
    end
    local result = tostring(bridge:restoreTestNpcRecord(record, square))
    if string.find(result, "RESTORED", 1, true) ~= 1 then
        return nil, result
    end
    return bridge:getNpcCharacter(id), result
end

local function addActiveId(id)
    for _, activeId in ipairs(activeIds) do
        if activeId == id then
            return
        end
    end
    activeIds[#activeIds + 1] = id
end

local function removeActiveId(id)
    local retained = {}
    for _, activeId in ipairs(activeIds) do
        if activeId ~= id then
            retained[#retained + 1] = activeId
        end
    end
    activeIds = retained
end

local function registerController(bridge, id, character, result)
    if character == nil then
        return false, "character_unavailable"
    end
    local capabilities, capabilityResult = KnoxSurvivorCapabilities.ensure(
        id,
        character
    )
    if capabilities == nil then
        bridge:removeNpc(id)
        return false, "capabilities=" .. tostring(capabilityResult)
    end
    KnoxPersistence.ensureSurvivorIdentityFromCharacter(
        id,
        character,
        getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    )
    KnoxUnloadedSurvival.applyToLoaded(id, character)
    controllers[id] = KnoxAutonomyController.new(
        id,
        character,
        bridge,
        reservations,
        ticks
    )
    addActiveId(id)
    KnoxSurvivorRuntime.register(id, controllers[id])
    if KnoxBaseManager ~= nil and KnoxBaseManager.syncStructureProtection ~= nil then
        KnoxBaseManager.syncStructureProtection()
    end
    print(TAG .. " id=" .. id .. " state=ACTIVE " .. tostring(result))
    print(
        TAG .. " id=" .. id
            .. " capabilities=" .. tostring(capabilities.professionId)
            .. " traits=" .. table.concat(capabilities.traitIds or {}, ",")
            .. " source=" .. tostring(capabilityResult)
    )
    return true, result
end

local function ensurePopulation(bridge, player, requiredIds)
    for _, id in ipairs(requiredIds or {}) do
        if controllers[id] == nil then
            local character = bridge:getNpcCharacter(id)
            local result = "ADOPTED_ACTIVE"
            if character == nil then
                local record = KnoxPersistence.getRecord(id)
                if record ~= nil then
                    character, result = restoreSurvivor(bridge, id, record)
                else
                    character, result = createDeveloperSurvivor(
                        bridge,
                        id,
                        player:getCurrentSquare()
                    )
                end
            end
            if character == nil then
                return false, "id=" .. id .. " " .. tostring(result)
            end
            local registered, registerResult = registerController(
                bridge,
                id,
                character,
                result
            )
            if not registered then
                return false, "id=" .. id .. " " .. tostring(registerResult)
            end
        end
    end
    for _, id in ipairs(requiredIds or {}) do
        if bridge:getNpcCharacter(id) == nil then
            return false, "missing=" .. tostring(id)
        end
    end
    return true,
        "active=" .. tostring(bridge:getActiveNpcCount())
            .. " ids=" .. tostring(bridge:getActiveNpcIds())
end

local function activeWorldLookup()
    local world = {}
    for _, id in ipairs(KnoxPersistence.getAllWorldSurvivorIds()) do
        world[id] = true
    end
    return world
end

local function currentPlayers()
    local players = {}
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerIndex = 0, math.max(0, tonumber(count) or 1) - 1 do
        local player = getSpecificPlayer(playerIndex)
        if player ~= nil then
            players[#players + 1] = player
        end
    end
    return players
end

local function retireDeadSurvivor(bridge, id, controller)
    pcall(function()
        controller:shutdown()
    end)
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    KnoxPersistence.markSurvivorDead(id, now, "world_death")
    local removed = tostring(bridge:removeNpc(id))
    local registryStillActive = bridge:getNpcCharacter(id) ~= nil
    if string.find(removed, "REMOVED", 1, true) == 1
        or removed == "NONE_ACTIVE" or not registryStillActive then
        KnoxSurvivorRuntime.unregister(id, controller)
        controllers[id] = nil
        removeActiveId(id)
        print(TAG .. " id=" .. tostring(id)
            .. " state=DEAD persisted=true remove=" .. tostring(removed))
        return
    end
    -- Do not silently forget a failed engine teardown. Keeping the stopped runtime
    -- registered makes the next lifecycle pass retry removal against the same shell
    -- rather than spawning a duplicate identity elsewhere.
    controller.state = "STOPPED"
    print(TAG .. " id=" .. tostring(id)
        .. " state=DEAD_REMOVE_PENDING result=" .. tostring(removed))
end

local function retireDeadControllers(bridge)
    local dead = {}
    for _, id in ipairs(activeIds) do
        local controller = controllers[id]
        if controller ~= nil and controller.character ~= nil then
            local success, isDead = pcall(function()
                return controller.character:isDead()
            end)
            if success and isDead then
                dead[#dead + 1] = { id = id, controller = controller }
            end
        end
    end
    for _, entry in ipairs(dead) do
        retireDeadSurvivor(bridge, entry.id, entry.controller)
    end
end

local function squareDescription(square)
    if square == nil then
        return "none"
    end
    return tostring(square:getX()) .. "," .. tostring(square:getY())
        .. "," .. tostring(square:getZ())
end

local function finiteNearestPlayerDistanceSquared(character, players)
    if character == nil or players == nil or #players == 0 then
        return nil
    end
    local okX, cx = pcall(function()
        return character:getX()
    end)
    local okY, cy = pcall(function()
        return character:getY()
    end)
    local okZ, cz = pcall(function()
        return character:getZ()
    end)
    if not okX or not okY or not okZ or type(cx) ~= "number" or type(cy) ~= "number" or type(cz) ~= "number" then
        return nil
    end
    if cx ~= cx or cy ~= cy or cz ~= cz or math.abs(cx) == math.huge or math.abs(cy) == math.huge or math.abs(cz) == math.huge then
        return nil
    end
    local best = nil
    for _, player in ipairs(players) do
        local okPX, px = pcall(function()
            return player:getX()
        end)
        local okPY, py = pcall(function()
            return player:getY()
        end)
        if okPX and okPY and type(px) == "number" and type(py) == "number" and px == px and py == py and math.abs(px) ~= math.huge and math.abs(py) ~= math.huge then
            local dx = cx - px
            local dy = cy - py
            local d2 = dx * dx + dy * dy
            if best == nil or d2 < best then
                best = d2
            end
        end
    end
    return best
end

local function actorXYZDescription(character)
    if character == nil then
        return "none"
    end
    local okX, x = pcall(function()
        return character:getX()
    end)
    local okY, y = pcall(function()
        return character:getY()
    end)
    local okZ, z = pcall(function()
        return character:getZ()
    end)
    if not okX or not okY or not okZ then
        return "none"
    end
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function hibernateDistantWorldSurvivors(bridge, players)
    local world = activeWorldLookup()
    local hibernate = {}
    for _, id in ipairs(activeIds) do
        local controller = controllers[id]
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        if controller ~= nil then
            local character = controller.character
            local square = character ~= nil and character:getCurrentSquare() or nil
            local distanceSquared = KnoxWorldPopulation.nearestPlayerDistanceSquared(square, players)
            local finiteDistanceSquared = finiteNearestPlayerDistanceSquared(character, players)
            local finiteDistance = finiteDistanceSquared and math.sqrt(finiteDistanceSquared) or nil
            local squareDistance = distanceSquared and math.sqrt(distanceSquared) or nil
            if square == nil then
                local grace = (detachedGrace[id] or 0) + 1
                detachedGrace[id] = grace
                local shouldHibernate, decision =
                    KnoxSurvivorLifecyclePolicy.detachedDecision(
                        finiteDistanceSquared,
                        HIBERNATION_DISTANCE_SQUARED,
                        grace,
                        DETACHED_GRACE_CHECKS
                    )
                print(TAG .. " detach-detected id=" .. tostring(id) .. " actorXYZ=" .. actorXYZDescription(character) .. " currentSquare=" .. squareDescription(square) .. " finiteDistance=" .. tostring(finiteDistance) .. " squareDistance=" .. tostring(squareDistance) .. " detachedTicks=" .. tostring(grace) .. " decision=" .. tostring(decision))
                if shouldHibernate then
                    detachedGrace[id] = nil
                    hibernate[#hibernate + 1] = {
                        id = id,
                        controller = controller,
                        reason = "detached",
                        square = nil,
                        distanceSquared = finiteDistanceSquared,
                        detachedGrace = grace,
                    }
                end
            else
                if detachedGrace[id] ~= nil then
                    print(TAG .. " detach-recovered id=" .. tostring(id) .. " actorXYZ=" .. actorXYZDescription(character) .. " square=" .. squareDescription(square) .. " finiteDistance=" .. tostring(finiteDistance))
                end
                detachedGrace[id] = nil
                -- Ordinary distance hibernation belongs only to production world
                -- survivors. A missing square is different: any shell, including a
                -- companion or developer scenario body, must leave DETACHED through
                -- the transactional capture/remove path instead of remaining an
                -- active engine object forever.
                if KnoxSurvivorLifecyclePolicy.distanceEligible(
                    world[id] == true,
                    duty.mode,
                    distanceSquared,
                    HIBERNATION_DISTANCE_SQUARED
                ) then
                    hibernate[#hibernate + 1] = {
                        id = id,
                        controller = controller,
                        reason = "distance",
                        square = square,
                        distanceSquared = distanceSquared,
                    }
                end
            end
        end
    end
    for _, entry in ipairs(hibernate) do
        local distance = entry.distanceSquared ~= nil and math.sqrt(entry.distanceSquared) or nil
        print(TAG .. " id=" .. entry.id .. " hibernate-attempt reason=" .. tostring(entry.reason) .. " square=" .. squareDescription(entry.square) .. " playerDistance=" .. tostring(distance) .. " threshold=" .. tostring(HIBERNATION_DISTANCE))
        -- shutdown() captures first. removeNpc() is intentionally not called unless
        -- persistence succeeds, so normal hibernation remains transactional.
        local success, saved, evidence = pcall(function()
            return entry.controller:shutdown()
        end)
        if success and saved then
            local removed = tostring(bridge:removeNpc(entry.id))
            local registryStillActive = bridge:getNpcCharacter(entry.id) ~= nil
            if string.find(removed, "REMOVED", 1, true) == 1
                or removed == "NONE_ACTIVE" or not registryStillActive then
                KnoxSurvivorRuntime.unregister(entry.id, entry.controller)
                controllers[entry.id] = nil
                removeActiveId(entry.id)
                print(TAG .. " id=" .. entry.id
                    .. " state=HIBERNATED reason=" .. tostring(entry.reason)
                    .. " playerDistance=" .. tostring(distance)
                    .. " save=" .. tostring(evidence)
                    .. " remove=" .. tostring(removed))
            else
                print(TAG .. " id=" .. entry.id
                    .. " hibernate-remove-failed reason=" .. tostring(entry.reason)
                    .. " result=" .. removed)
            end
        else
            print(TAG .. " id=" .. entry.id
                .. " hibernate-save-failed reason=" .. tostring(entry.reason)
                .. " square=" .. squareDescription(entry.square)
                .. " playerDistance=" .. tostring(distance)
                .. " evidence=" .. tostring(evidence))
        end
    end
end

local function activateWorldCandidate(bridge, candidate)
    local character = bridge:getNpcCharacter(candidate.id)
    local result = "ADOPTED_ACTIVE"
    if character == nil and candidate.mode == "restore" then
        character, result = restoreSurvivor(
            bridge,
            candidate.id,
            candidate.record
        )
    elseif character == nil and candidate.mode == "spawn" then
        character, result = createSurvivorAt(
            bridge,
            candidate.id,
            candidate.square,
            false
        )
    end
    if character == nil then
        return false, result
    end
    return registerController(bridge, candidate.id, character, result)
end

local function reconcileWorldPopulation(bridge)
    local players = currentPlayers()
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local awayChanged = KnoxPersistence.advanceAwayTeams ~= nil
        and KnoxPersistence.advanceAwayTeams(now) or 0
    local advanced, notable = KnoxUnloadedSurvival.advanceAll(activeIds, now)
    local summary = KnoxWorldPopulation.maintain(now)
    local remaining = math.max(0, KnoxSettings.maxActiveSurvivors() - #activeIds)
    local candidates, rejected = KnoxWorldPopulation.activationCandidates(
        bridge,
        activeIds,
        remaining,
        { players = players, maximumDistance = ACTIVATION_DISTANCE }
    )
    local activated = 0
    for _, candidate in ipairs(candidates) do
        local ready, evidence = activateWorldCandidate(bridge, candidate)
        if ready then
            activated = activated + 1
            local distance = candidate.distanceSquared ~= nil
                and math.sqrt(candidate.distanceSquared)
                or nil
            print(TAG .. " population-activated id=" .. tostring(candidate.id)
                .. " mode=" .. tostring(candidate.mode)
                .. " square=" .. tostring(candidate.x) .. ","
                    .. tostring(candidate.y) .. "," .. tostring(candidate.z)
                .. " playerDistance=" .. tostring(distance))
        else
            print(TAG .. " population-activation-failed id=" .. tostring(candidate.id)
                .. " mode=" .. tostring(candidate.mode)
                .. " evidence=" .. tostring(evidence))
        end
    end
    local statusKey = tostring(summary.status)
        .. ":" .. tostring(summary.living)
        .. ":" .. tostring(#activeIds)
    if populationStatus ~= statusKey or activated > 0 or #(summary.addedIds or {}) > 0 then
        populationStatus = statusKey
        print(TAG .. " population status=" .. tostring(summary.status)
            .. " living=" .. tostring(summary.living)
            .. "/" .. tostring(summary.target)
            .. " active=" .. tostring(#activeIds)
            .. " activated=" .. tostring(activated)
            .. " waitingSquares=" .. tostring(rejected.saved_square_not_loaded or 0))
    end
    if notable > 0 then
        print(TAG .. " unloaded-simulation advanced=" .. tostring(advanced)
            .. " notable=" .. tostring(notable))
    end
    if awayChanged > 0 then
        print(TAG .. " away-teams advanced=" .. tostring(awayChanged))
    end
end

local function completedDecisions(controller)
    return controller.counts.roam
        + controller.counts.loot
        + controller.counts.search
        + controller.counts.needs
        + controller.counts.combat
end

local function reportPassIfReady(bridge)
    if passReported or #scenarioIds == 0 then
        return
    end
    for _, id in ipairs(scenarioIds) do
        if controllers[id] == nil or completedDecisions(controllers[id]) < DECISIONS_REQUIRED then
            return
        end
    end
    local saved, evidence = KnoxPersistence.captureAllActiveSurvivors()
    if not saved then
        print(TAG .. " RESULT status=FAIL reason=capture_all_failed evidence=" .. tostring(evidence))
        return
    end
    KnoxPersistence.markDevGateComplete(GATE_KEY)
    passReported = true
    print(
        TAG
            .. " RESULT scenario=survival status=PASS"
            .. " reason=developer_autonomy_controllers"
            .. " evidence=active=" .. tostring(bridge:getActiveNpcCount())
            .. " decisions=" .. tostring(scenarioIds[1] ~= nil and completedDecisions(controllers[scenarioIds[1]]) or 0)
            .. " saved=" .. tostring(evidence)
    )
end

local function configureScenario(player, scenario, ids)
    if scenario == "single" then
        return true, "independent"
    end
    local hours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    if scenario == "companion" then
        local playerId = KnoxPersistence.ensurePlayerId(player)
        return KnoxPersistence.setPlayerCompanion(ids[1], playerId, "follow", hours)
    end
    if scenario == "group" or scenario == "faction" or scenario == "faction_base" then
        local group = KnoxPersistence.getTravelGroupFor(ids[1])
        if group ~= nil then
            for _, id in ipairs(ids) do
                local membership = KnoxPersistence.getTravelGroupFor(id)
                if membership == nil or membership.id ~= group.id then
                    group = nil
                    break
                end
            end
        end
        group = group or KnoxPersistence.createTravelGroup(ids, hours)
        if group == nil then
            return false, "group_creation_failed"
        end
        if scenario == "faction" or scenario == "faction_base" then
            local faction = group.factionId ~= nil
                and KnoxPersistence.getFaction(group.factionId)
                or KnoxPersistence.promoteTravelGroupToFaction(group.id, hours)
            if faction == nil then
                return false, "faction_creation_failed"
            end
            return true, faction.id
        end
        return true, group.id
    end
    return false, "unknown_scenario"
end

update = function()
    ticks = ticks + 1
    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getSpecificPlayer(0)
    if bridge == nil or player == nil or player:getCurrentSquare() == nil or getCell() == nil then
        return
    end
    if not populationReady then
        local ready, evidence = ensurePopulation(bridge, player, scenarioIds)
        if not ready then
            if ticks % STATUS_INTERVAL_TICKS == 0 then
                print(TAG .. " waiting=" .. tostring(evidence))
            end
            return
        end
        populationReady = true
        print(TAG .. " state=RUNNING " .. tostring(evidence))
    end
    retireDeadControllers(bridge)
    if ticks >= nextHibernationUpdate then
        nextHibernationUpdate = ticks + HIBERNATION_INTERVAL_TICKS
        hibernateDistantWorldSurvivors(bridge, currentPlayers())
    end
    if ticks >= nextPopulationUpdate then
        nextPopulationUpdate = ticks + POPULATION_INTERVAL_TICKS
        reconcileWorldPopulation(bridge)
    end
    KnoxZombieAwareness.update(controllers, activeIds, ticks)
    if not scenarioConfigured and #scenarioIds > 0 then
        local configured, evidence = configureScenario(player, currentScenario, scenarioIds)
        scenarioConfigured = configured == true
        print(TAG .. " scenario-configured=" .. tostring(configured)
            .. " type=" .. tostring(currentScenario) .. " evidence=" .. tostring(evidence))
        if not configured then
            return
        end
    end
    KnoxSurvivorRelationships.coordinate(controllers, activeIds, ticks)
    for _, id in ipairs(activeIds) do
        local controller = controllers[id]
        KnoxCompanionService.syncController(id, controller)
        if controller.state ~= "STOPPED" then
            local success, failure = pcall(function()
                controller:tick(ticks)
            end)
            if not success then
                controller.counts.failures = controller.counts.failures + 1
                controller.state = "STOPPED"
                print(TAG .. " id=" .. id .. " ERROR controller_tick=" .. tostring(failure))
            end
        end
    end
    reportPassIfReady(bridge)
    reportFactionBasePassIfReady()
    if ticks % RELATIONSHIP_INTERVAL_TICKS == 0 then
        KnoxSurvivorRelationships.observe(controllers, activeIds, ticks)
    end
    if ticks % STATUS_INTERVAL_TICKS == 0 then
        print(TAG .. " render " .. tostring(bridge:getRenderDiagnostics()))
        for _, id in ipairs(activeIds) do
            print(TAG .. " status " .. controllers[id]:status())
        end
    end
end

local function onGameStart()
    if not KnoxSettings.enabled() then
        return
    end
    ticks = 0
    controllers = {}
    KnoxSurvivorRuntime.clear()
    reservations = { threats = {}, items = {}, containers = {}, restSpots = {} }
    KnoxSurvivorRelationships.resetRuntime()
    populationReady = false
    passReported = false
    factionBasePassReported = false
    activeIds = {}
    scenarioIds = {}
    nextPopulationUpdate = 1
    nextHibernationUpdate = 1
    populationStatus = nil
    local scenario = KnoxSettings.developerToolsEnabled()
        and KnoxSettings.developerScenario()
        or "none"
    currentScenario = scenario
    scenarioConfigured = scenario == "none"
    local counts = { single = 1, companion = 1, group = 2, faction = 3, faction_base = 3 }
    for index = 1, (counts[scenario] or 0) do
        scenarioIds[#scenarioIds + 1] = "ks-dev-auto-" .. scenario .. "-" .. tostring(index)
    end
    populationReady = #scenarioIds == 0
    stop()
    Events.OnTick.Add(update)
    print(TAG .. " START scenario=" .. scenario
        .. " developerSurvivors=" .. tostring(#scenarioIds)
        .. " worldTarget=" .. tostring(KnoxSettings.worldPopulation()))
end

local function onMainMenuEnter()
    for id, controller in pairs(controllers) do
        controller:shutdown()
        KnoxSurvivorRuntime.unregister(id, controller)
    end
    KnoxPersistence.captureAllActiveSurvivors()
    KnoxSurvivorRuntime.clear()
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)

function Autonomy.spawnDeveloperScenario(player, scenario)
    if not KnoxSettings.developerToolsEnabled() then
        return false, "developer_tools_disabled"
    end
    local counts = { single = 1, companion = 1, group = 2, faction = 3, faction_base = 3 }
    local count = counts[scenario]
    local bridge = rawget(_G, "KnoxJavaBridge")
    if player == nil or bridge == nil or count == nil then
        return false, "scenario_unavailable"
    end
    local ids = {}
    for _ = 1, count do
        local id = KnoxPersistence.allocateDeveloperSurvivorId()
        ids[#ids + 1] = id
    end
    local ready, result = ensurePopulation(bridge, player, ids)
    if not ready then
        return false, result
    end
    local configured, configureResult = configureScenario(player, scenario, ids)
    if not configured then
        return false, configureResult
    end
    for _, id in ipairs(ids) do
        scenarioIds[#scenarioIds + 1] = id
        KnoxCompanionService.syncController(id, controllers[id])
    end
    return true, table.concat(ids, ",") .. " " .. tostring(configureResult)
end

-- Developer-only handoff gate for the away-team lifecycle. It uses the same
-- capture/remove sequence as distance hibernation; a mission is never persisted while
-- one of its members still owns an active engine shell.
function Autonomy.dispatchDeveloperScout(player, destinationSquare)
    if not KnoxSettings.developerToolsEnabled() then
        return false, "developer_tools_disabled"
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if player == nil or destinationSquare == nil or bridge == nil then
        return false, "dispatch_unavailable"
    end
    local selected, ownerKind, ownerId = {}, nil, nil
    for _, id in ipairs(activeIds) do
        local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {}
        if affiliation.kind == "faction" and type(affiliation.factionId) == "string" then
            ownerKind, ownerId = "faction", affiliation.factionId
            break
        end
    end
    if ownerKind == nil then
        return false, "need_loaded_faction_survivor"
    end
    for _, id in ipairs(activeIds) do
        local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {}
        if affiliation.kind == ownerKind and affiliation.factionId == ownerId then
            selected[#selected + 1] = id
        end
    end
    if #selected == 0 then
        return false, "no_faction_members"
    end
    for _, id in ipairs(selected) do
        local controller = controllers[id]
        local saved, evidence = false, "missing"
        if controller ~= nil then
            saved, evidence = controller:shutdown()
        end
        if not saved then
            return false, "capture_failed=" .. tostring(id) .. " " .. tostring(evidence)
        end
    end
    for _, id in ipairs(selected) do
        local removed = tostring(bridge:removeNpc(id))
        if string.find(removed, "REMOVED", 1, true) ~= 1 and removed ~= "NONE_ACTIVE" then
            return false, "remove_failed=" .. tostring(id) .. " " .. removed
        end
    end
    for _, id in ipairs(selected) do
        KnoxSurvivorRuntime.unregister(id, controllers[id])
        controllers[id] = nil
        removeActiveId(id)
    end
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local team, result = KnoxPersistence.createAwayTeam(
        ownerKind,
        ownerId,
        selected,
        "scout",
        {
            x = destinationSquare:getX(), y = destinationSquare:getY(),
            z = destinationSquare:getZ(), label = "Scouting destination",
        },
        now,
        now + 2
    )
    if team == nil then
        return false, "mission_create_failed=" .. tostring(result)
    end
    print(TAG .. " away-dispatched id=" .. tostring(team.id)
        .. " members=" .. table.concat(selected, ",") .. " result=" .. tostring(result))
    return true, team.id
end

-- Normal player-base scouting command. It sends exactly one available, loaded resident
-- so the base never empties itself from a broad context-menu action.
function Autonomy.dispatchBaseScout(player, baseId, destinationSquare)
    local bridge = rawget(_G, "KnoxJavaBridge")
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    if playerId == nil or destinationSquare == nil or bridge == nil then
        return false, "dispatch_unavailable"
    end
    local selected, controller = nil, nil
    for _, id in ipairs(KnoxPersistence.getBaseResidentIds(baseId)) do
        local duty = KnoxPersistence.getSurvivorDuty(id) or {}
        local runtime = controllers[id]
        if duty.mode == "base" and duty.ownerId == playerId and runtime ~= nil then
            selected, controller = id, runtime
            break
        end
    end
    if selected == nil then
        return false, "need_loaded_base_resident"
    end
    local saved, evidence = controller:shutdown()
    if not saved then
        return false, "capture_failed=" .. tostring(evidence)
    end
    local removed = tostring(bridge:removeNpc(selected))
    if string.find(removed, "REMOVED", 1, true) ~= 1 and removed ~= "NONE_ACTIVE" then
        return false, "remove_failed=" .. removed
    end
    KnoxSurvivorRuntime.unregister(selected, controller)
    controllers[selected] = nil
    removeActiveId(selected)
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local team, result = KnoxPersistence.createAwayTeam(
        "player", playerId, { selected }, "scout",
        {
            x = destinationSquare:getX(), y = destinationSquare:getY(),
            z = destinationSquare:getZ(), label = "Player scout destination",
        }, now, now + 2
    )
    if team == nil then
        return false, "mission_create_failed=" .. tostring(result)
    end
    return true, team.id
end

function Autonomy.status()
    return {
        ids = activeIds,
        controllers = controllers,
        ticks = ticks,
        running = KnoxSettings.enabled(),
        worldPopulation = KnoxPersistence.getPopulationState(),
    }
end

return Autonomy
