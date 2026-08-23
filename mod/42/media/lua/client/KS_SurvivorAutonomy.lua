require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"
require "KS_SurvivorNeeds"
require "KS_SurvivorInventoryActions"

local TAG = "[KnoxSurvivors][Autonomy]"
local THINK_INTERVAL_TICKS = 30
local STATUS_INTERVAL_TICKS = 300
local THREAT_RADIUS = 10
local SUPPLY_SCAN_RADIUS = 20
local ROAM_MIN_RADIUS = 6
local ROAM_MAX_RADIUS = 18

local ticks = 0
local state = "IDLE"
local npc = nil
local pendingSupply = nil
local activeAction = nil
local activeDecision = nil
local combatTarget = nil
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
    if not success then
        return nil, x
    end
    return getCell():getGridSquare(x, y, z), tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function restoreSurvivor(bridge)
    local persistence = rawget(_G, "KnoxPersistence")
    local record = persistence ~= nil and persistence.getTestRecord() or nil
    if record == nil then
        return false, "missing_persistent_survivor"
    end
    local square, location = squareForRecord(bridge, record)
    if square == nil then
        return false, "saved_square_not_loaded location=" .. tostring(location)
    end
    local success, result = pcall(function()
        return bridge:restoreTestNpcRecord(record, square)
    end)
    return success and string.find(tostring(result), "RESTORED", 1, true) == 1, result
end

local function distanceSquared(a, b)
    local dx = a:getX() - b:getX()
    local dy = a:getY() - b:getY()
    return dx * dx + dy * dy
end

local function nearestThreat(character)
    local square = character:getCurrentSquare()
    local cell = getCell()
    if square == nil or cell == nil then
        return nil
    end
    local nearest = nil
    local nearestDistance = THREAT_RADIUS * THREAT_RADIUS
    local zombies = cell:getZombieList()
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local zombieSquare = zombie:getCurrentSquare()
        if not zombie:isDead() and zombieSquare ~= nil and zombieSquare:getZ() == square:getZ() then
            local distance = distanceSquared(square, zombieSquare)
            if distance <= nearestDistance then
                nearest = zombie
                nearestDistance = distance
            end
        end
    end
    return nearest
end

local function itemMatchesGoal(item, goal, character)
    if goal == "find_food" then
        return KnoxSurvivorNeeds.isSafeFood(item)
    end
    if goal == "find_water" then
        local thirst = character:getStats():get(CharacterStat.THIRST)
        return KnoxSurvivorNeeds.isWaterItem(item, thirst >= 0.90)
    end
    if goal == "find_medical" then
        return item:isCanBandage()
            or item:getFullType() == "Base.Sheet"
            or (item:IsClothing() and item:getFabricType() == "Cotton")
    end
    return false
end

local function findSupply(character, goal)
    local origin = character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
    for radius = 0, SUPPLY_SCAN_RADIUS do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if radius == 0 or math.abs(dx) == radius or math.abs(dy) == radius then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    if square ~= nil then
                        local objects = square:getObjects()
                        for objectIndex = 0, objects:size() - 1 do
                            local object = objects:get(objectIndex)
                            for containerIndex = 0, object:getContainerCount() - 1 do
                                local container = object:getContainerByIndex(containerIndex)
                                if container ~= nil and container:isExistYet() then
                                    local items = container:getItems()
                                    for itemIndex = 0, items:size() - 1 do
                                        local item = items:get(itemIndex)
                                        if itemMatchesGoal(item, goal, character) then
                                            local approach = AdjacentFreeTileFinder.Find(square, character)
                                            if approach ~= nil then
                                                return {
                                                    goal = goal,
                                                    item = item,
                                                    container = container,
                                                    object = object,
                                                    approach = approach,
                                                }
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function findRoamTarget(character)
    local origin = character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
    for _ = 1, 40 do
        local radius = ROAM_MIN_RADIUS + ZombRand(ROAM_MAX_RADIUS - ROAM_MIN_RADIUS + 1)
        local dx = ZombRand(radius * 2 + 1) - radius
        local dy = ZombRand(radius * 2 + 1) - radius
        if math.max(math.abs(dx), math.abs(dy)) >= ROAM_MIN_RADIUS then
            local square = getCell():getGridSquare(
                origin:getX() + dx,
                origin:getY() + dy,
                origin:getZ()
            )
            if square ~= nil and square:canStand() then
                return square
            end
        end
    end
    return nil
end

local function beginCombat(bridge, target)
    if target == nil or target:getCurrentSquare() == nil then
        return false
    end
    if not npc:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(npc)
    end
    local approach = AdjacentFreeTileFinder.Find(target:getCurrentSquare(), npc)
    if approach == nil then
        return false
    end
    local result = tostring(bridge:beginTestNpcLiveCombat(target, approach))
    if string.find(result, "COMBAT_STARTED", 1, true) ~= 1 then
        print(TAG .. " combat-start-failed=" .. result)
        bridge:resetTestNpcCombat()
        return false
    end
    combatTarget = target
    pendingSupply = nil
    activeAction = nil
    activeDecision = nil
    state = "COMBAT"
    print(TAG .. " state=COMBAT " .. result)
    return true
end

local function beginWorldSearch(bridge, decision)
    local supply = findSupply(npc, decision.kind)
    if supply == nil then
        return false
    end
    local result = tostring(bridge:moveTestNpc(supply.approach))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    pendingSupply = supply
    state = "MOVING_TO_SUPPLY"
    print(
        TAG
            .. " state=MOVING_TO_SUPPLY goal=" .. tostring(supply.goal)
            .. " item=" .. tostring(supply.item:getFullType())
    )
    return true
end

local function beginRoam(bridge)
    local target = findRoamTarget(npc)
    if target == nil then
        return false
    end
    local result = tostring(bridge:moveTestNpc(target))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    state = "ROAMING"
    print(TAG .. " state=ROAMING target=" .. target:getX() .. "," .. target:getY())
    return true
end

local function think(bridge)
    local threat = nearestThreat(npc)
    local decision = KnoxSurvivorNeeds.decide(npc, threat)
    if decision.kind == "fight" then
        beginCombat(bridge, decision.target)
        return
    end
    if decision.kind == "eat"
        or decision.kind == "drink"
        or decision.kind == "bandage"
        or decision.kind == "improvise_medical" then
        activeAction = KnoxSurvivorNeeds.execute(npc, decision)
        if activeAction ~= nil then
            activeDecision = decision.kind
            state = "TIMED_ACTION"
            print(
                TAG
                    .. " state=TIMED_ACTION kind=" .. tostring(decision.kind)
                    .. " item=" .. tostring(decision.item ~= nil
                        and decision.item:getFullType()
                        or decision.supplyPlan.item:getFullType())
            )
        end
        return
    end
    if decision.kind == "find_food"
        or decision.kind == "find_water"
        or decision.kind == "find_medical" then
        if not beginWorldSearch(bridge, decision) then
            beginRoam(bridge)
        end
        return
    end
    if decision.kind == "rest" or decision.kind == "sleep" then
        -- Furniture selection and safe sleeping are their own verified gate.
        -- Until then, stop expending endurance instead of faking recovery.
        state = "WAITING_TO_RECOVER"
        return
    end
    beginRoam(bridge)
end

update = function()
    ticks = ticks + 1
    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getSpecificPlayer(0)
    if bridge == nil or player == nil or player:getCurrentSquare() == nil or getCell() == nil then
        return
    end

    if state == "WAIT_START" then
        local restored, result = restoreSurvivor(bridge)
        if not restored then
            if string.find(tostring(result), "saved_square_not_loaded", 1, true) == nil then
                print(TAG .. " restore-failed=" .. tostring(result))
                state = "STOPPED"
                stop()
            end
            return
        end
        npc = bridge:getTestNpcCharacterForAction()
        if npc == nil then
            print(TAG .. " restore-failed=npc_character_unavailable")
            state = "STOPPED"
            stop()
            return
        end
        npc:setZombiesDontAttack(false)
        state = "IDLE"
        print(TAG .. " state=IDLE survivor=" .. tostring(result))
        return
    end

    if npc == nil then
        return
    end

    if state ~= "COMBAT" then
        local threat = nearestThreat(npc)
        if threat ~= nil and beginCombat(bridge, threat) then
            return
        end
    end

    if state == "COMBAT" then
        local result = tostring(bridge:tickTestNpcCombat())
        if string.find(result, "COMBAT_SUCCEEDED", 1, true) == 1 then
            print(TAG .. " combat-complete=" .. result)
            combatTarget = nil
            state = "IDLE"
            KnoxPersistence.captureActiveTestSurvivor()
        elseif string.find(result, "COMBAT_FAILED", 1, true) == 1 then
            print(TAG .. " combat-failed=" .. result)
            bridge:resetTestNpcCombat()
            combatTarget = nil
            state = "IDLE"
        end
        return
    end

    if state == "TIMED_ACTION" then
        if npc:getCharacterActions():isEmpty() then
            print(TAG .. " action-complete=" .. tostring(activeDecision))
            activeAction = nil
            activeDecision = nil
            state = "IDLE"
            KnoxPersistence.captureActiveTestSurvivor()
        end
        return
    end

    if state == "MOVING_TO_SUPPLY" or state == "ROAMING" then
        local movement = tostring(bridge:tickTestNpc())
        if movement == "Succeeded" then
            if state == "MOVING_TO_SUPPLY" and pendingSupply ~= nil then
                activeAction = KnoxInventoryActions.queueTransfer(
                    npc,
                    pendingSupply.item,
                    pendingSupply.container,
                    npc:getInventory(),
                    nil
                )
                activeDecision = "loot_" .. tostring(pendingSupply.goal)
                pendingSupply = nil
                state = activeAction ~= nil and "TIMED_ACTION" or "IDLE"
            else
                state = "IDLE"
            end
        elseif string.find(movement, "Failed", 1, true) == 1
            or string.find(movement, "TICK_FAILED", 1, true) == 1 then
            pendingSupply = nil
            state = "IDLE"
        end
        return
    end

    if state == "WAITING_TO_RECOVER" then
        if npc:getStats():get(CharacterStat.ENDURANCE) > KnoxSurvivorNeeds.thresholds.lowEndurance
            and npc:getStats():get(CharacterStat.FATIGUE) < KnoxSurvivorNeeds.thresholds.fatigue then
            state = "IDLE"
        end
        return
    end

    if state == "IDLE" and ticks % THINK_INTERVAL_TICKS == 0 then
        think(bridge)
    end
    if ticks % STATUS_INTERVAL_TICKS == 0 then
        print(
            TAG
                .. " status state=" .. tostring(state)
                .. " " .. KnoxSurvivorNeeds.describe(KnoxSurvivorNeeds.snapshot(npc))
        )
    end
end

local function onGameStart()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "autonomy" then
        return
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or not persistence.isDevGateComplete("needs_consume_reload_v1") then
        print(TAG .. " blocked=needs_reload_gate_missing")
        return
    end
    ticks = 0
    state = "WAIT_START"
    npc = nil
    pendingSupply = nil
    activeAction = nil
    activeDecision = nil
    combatTarget = nil
    stop()
    Events.OnTick.Add(update)
end

local function onMainMenuEnter()
    if npc ~= nil and not npc:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(npc)
    end
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge ~= nil then
        bridge:resetTestNpcCombat()
    end
    if KnoxPersistence ~= nil then
        KnoxPersistence.captureActiveTestSurvivor()
    end
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)
