require "KS_SurvivorAutonomyController"
require "KS_CharacterAppearance"
require "KS_Persistence"
require "KS_SurvivorRelationships"

local TAG = "[KnoxSurvivors][Autonomy]"
local IDS = { "ks-test-1", "ks-test-2" }
local STATUS_INTERVAL_TICKS = 300
local RELATIONSHIP_INTERVAL_TICKS = 60
local DECISIONS_REQUIRED = 2
local GATE_KEY = "multi_survival_autonomy_v1"

local controllers = {}
local reservations = { threats = {}, items = {}, containers = {} }
local ticks = 0
local populationReady = false
local passReported = false
local update

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
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
    for radius = 6, 14 do
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

local function createSurvivor(bridge, id, origin)
    local square = findSpawnSquare(origin)
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
    local appearanceOk, appearance = KnoxCharacterAppearance.randomizeNewSurvivor(bridge, id)
    if not appearanceOk then
        bridge:removeNpc(id)
        return nil, "appearance_failed=" .. tostring(appearance)
    end
    local equipped = tostring(bridge:seedAndEquipNpc(id))
    local saved, evidence = KnoxPersistence.captureActiveSurvivor(id)
    if string.find(equipped, "EQUIPPED", 1, true) ~= 1 or not saved then
        bridge:removeNpc(id)
        return nil, "initialization_failed equipment=" .. equipped .. " save=" .. tostring(evidence)
    end
    return character, "SPAWNED " .. id .. " " .. tostring(appearance)
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

local function ensurePopulation(bridge, player)
    for _, id in ipairs(IDS) do
        if controllers[id] == nil then
            local character = bridge:getNpcCharacter(id)
            local result = "ADOPTED_ACTIVE"
            if character == nil then
                local record = KnoxPersistence.getRecord(id)
                if record ~= nil then
                    character, result = restoreSurvivor(bridge, id, record)
                else
                    character, result = createSurvivor(bridge, id, player:getCurrentSquare())
                end
            end
            if character == nil then
                return false, "id=" .. id .. " " .. tostring(result)
            end
            controllers[id] = KnoxAutonomyController.new(
                id,
                character,
                bridge,
                reservations,
                ticks
            )
            print(TAG .. " id=" .. id .. " state=ACTIVE " .. tostring(result))
        end
    end
    return bridge:getActiveNpcCount() == #IDS,
        "active=" .. tostring(bridge:getActiveNpcCount())
            .. " ids=" .. tostring(bridge:getActiveNpcIds())
end

local function completedDecisions(controller)
    return controller.counts.roam
        + controller.counts.loot
        + controller.counts.search
        + controller.counts.needs
        + controller.counts.combat
end

local function reportPassIfReady(bridge)
    if passReported then
        return
    end
    for _, id in ipairs(IDS) do
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
            .. " reason=two_independent_autonomy_controllers"
            .. " evidence=active=" .. tostring(bridge:getActiveNpcCount())
            .. " decisions=" .. tostring(completedDecisions(controllers[IDS[1]]))
            .. "," .. tostring(completedDecisions(controllers[IDS[2]]))
            .. " saved=" .. tostring(evidence)
    )
end

update = function()
    ticks = ticks + 1
    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getSpecificPlayer(0)
    if bridge == nil or player == nil or player:getCurrentSquare() == nil or getCell() == nil then
        return
    end
    if not populationReady then
        local ready, evidence = ensurePopulation(bridge, player)
        if not ready then
            if ticks % STATUS_INTERVAL_TICKS == 0 then
                print(TAG .. " waiting=" .. tostring(evidence))
            end
            return
        end
        populationReady = true
        print(TAG .. " state=RUNNING " .. tostring(evidence))
    end
    KnoxSurvivorRelationships.coordinate(controllers, IDS, ticks)
    for _, id in ipairs(IDS) do
        local controller = controllers[id]
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
    if ticks % RELATIONSHIP_INTERVAL_TICKS == 0 then
        KnoxSurvivorRelationships.observe(controllers, IDS, ticks)
    end
    if ticks % STATUS_INTERVAL_TICKS == 0 then
        print(TAG .. " render " .. tostring(bridge:getRenderDiagnostics()))
        for _, id in ipairs(IDS) do
            print(TAG .. " status " .. controllers[id]:status())
        end
    end
end

local function onGameStart()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true
        or (config.activeScenario ~= "survival" and config.activeScenario ~= "autonomy") then
        return
    end
    ticks = 0
    controllers = {}
    reservations = { threats = {}, items = {}, containers = {} }
    KnoxSurvivorRelationships.resetRuntime()
    populationReady = false
    passReported = false
    stop()
    Events.OnTick.Add(update)
    print(TAG .. " START survivors=2 combat=true needs=true looting=true equipment=true")
end

local function onMainMenuEnter()
    for _, controller in pairs(controllers) do
        controller:shutdown()
    end
    KnoxPersistence.captureAllActiveSurvivors()
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)
