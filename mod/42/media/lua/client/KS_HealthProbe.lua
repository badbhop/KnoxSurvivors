local TAG = "[KnoxSurvivors][TestLab]"
local MAX_TEST_TICKS = 1800
local STATUS_INTERVAL_TICKS = 60
local ZOMBIE_CONTROL_INTERVAL_TICKS = 15
local HEALTH_GATE_KEY = "health_injury_v1"
local HEALTH_RELOAD_GATE_KEY = "health_reload_v1"

local ticks = 0
local phase = "IDLE"
local npc = nil
local targetZombie = nil
local initialHealth = nil
local reportScenario = "health"
local update

local function report(status, reason, evidence)
    print(
        TAG
            .. " RESULT scenario="
            .. tostring(reportScenario)
            .. " status="
            .. tostring(status)
            .. " reason="
            .. tostring(reason)
            .. " evidence="
            .. tostring(evidence or "none")
    )
end

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
    end
end

local function removeZombie(zombie)
    if zombie == nil then
        return
    end
    zombie:setUseless(true)
    zombie:setCanWalk(false)
    zombie:setTarget(nil)
    zombie:removeFromWorld()
    zombie:removeFromSquare()
end

local function clearLoadedZombies(exceptZombie)
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.allowZombieCleanup ~= true then
        return 0
    end
    local cell = getCell()
    if cell == nil then
        return 0
    end
    local zombies = cell:getZombieList()
    local removed = 0
    for index = zombies:size() - 1, 0, -1 do
        local zombie = zombies:get(index)
        if zombie ~= exceptZombie then
            removeZombie(zombie)
            removed = removed + 1
        end
    end
    return removed
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

local function findZombieSquare(origin)
    local cell = getCell()
    local directions = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    }
    for _, direction in ipairs(directions) do
        local square = cell:getGridSquare(
            origin:getX() + direction[1],
            origin:getY() + direction[2],
            origin:getZ()
        )
        if square ~= nil and square:canStand() and not origin:isBlockedTo(square) then
            return square
        end
    end
    return nil
end

local function fail(reason, evidence)
    if npc ~= nil then
        npc:setZombiesDontAttack(true)
    end
    if targetZombie ~= nil then
        removeZombie(targetZombie)
        targetZombie = nil
    end
    report("FAIL", reason, evidence)
    phase = "FINISHED"
    stop()
end

local function startAttack(bridge)
    local prepared = tostring(bridge:prepareTestNpcHealthGate())
    if string.find(prepared, "HEALTH_GATE_READY", 1, true) ~= 1 then
        fail("health_gate_prepare_failed", prepared)
        return
    end
    initialHealth = bridge:getTestNpcHealth()
    local zombieSquare = findZombieSquare(npc:getCurrentSquare())
    if zombieSquare == nil then
        fail("no_adjacent_zombie_square", "stand_with_survivor_in_open_area=true")
        return
    end
    local zombies = addZombiesInOutfit(
        zombieSquare:getX(), zombieSquare:getY(), zombieSquare:getZ(), 1, nil, nil
    )
    targetZombie = zombies ~= nil and zombies:size() > 0 and zombies:get(0) or nil
    if targetZombie == nil then
        fail("test_zombie_spawn_failed", "square=" .. tostring(zombieSquare))
        return
    end
    local directed = tostring(bridge:directTestZombieAtNpc(targetZombie))
    if string.find(directed, "ZOMBIE_DIRECTED", 1, true) ~= 1 then
        fail("zombie_target_failed", directed)
        return
    end
    print(
        TAG
            .. " health-attack=STARTED initialHealth="
            .. tostring(initialHealth)
            .. " inventoryItems="
            .. tostring(npc:getInventory():getItems():size())
            .. " zombieSquare="
            .. tostring(zombieSquare:getX())
            .. ","
            .. tostring(zombieSquare:getY())
    )
    phase = "AWAITING_NATIVE_DAMAGE"
end

local function finishReceivedDamage(bridge, receivedHealth, receivedInjuries, receivedBleeding)
    removeZombie(targetZombie)
    targetZombie = nil
    local normalized = tostring(bridge:normalizeTestNpcMinorInjury())
    if string.find(normalized, "CONTROLLED_INJURY", 1, true) ~= 1 then
        fail("minor_injury_normalization_failed", normalized)
        return
    end
    local controlledHealth = bridge:getTestNpcHealth()
    local controlledInjuries = bridge:getTestNpcInjuredPartCount()
    local controlledBleeding = bridge:getTestNpcBleedingPartCount()
    if controlledHealth >= initialHealth or controlledInjuries < 1 or controlledBleeding < 1 then
        fail("controlled_injury_missing", normalized)
        return
    end

    local persistence = rawget(_G, "KnoxPersistence")
    local saved, record = persistence.captureActiveTestSurvivor()
    if not saved then
        fail("post_injury_save_failed", tostring(record))
        return
    end
    persistence.markDevGateComplete("health")
    persistence.markDevGateComplete(HEALTH_GATE_KEY)
    report(
        "PASS",
        "native_damage_received_and_injury_saved",
        "nativeHealthBefore=" .. tostring(initialHealth)
            .. " nativeHealthAfter=" .. tostring(receivedHealth)
            .. " nativeInjuredParts=" .. tostring(receivedInjuries)
            .. " nativeBleedingParts=" .. tostring(receivedBleeding)
            .. " controlledHealth=" .. tostring(controlledHealth)
            .. " controlledInjuredParts=" .. tostring(controlledInjuries)
            .. " controlledBleedingParts=" .. tostring(controlledBleeding)
            .. " injury=ForeArm_L wound=scratch"
            .. " inventoryItems=" .. tostring(npc:getInventory():getItems():size())
            .. " next=health_reload"
    )
    phase = "FINISHED"
    stop()
end

update = function()
    ticks = ticks + 1
    if ticks > MAX_TEST_TICKS then
        fail("timeout", "phase=" .. tostring(phase))
        return
    end

    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getSpecificPlayer(0)
    if bridge == nil or player == nil or player:getCurrentSquare() == nil or getCell() == nil then
        return
    end

    if phase == "WAIT_START" then
        local restored, result = restoreSurvivor(bridge)
        if not restored then
            if string.find(tostring(result), "saved_square_not_loaded", 1, true) ~= nil then
                return
            end
            fail("survivor_restore_failed", tostring(result))
            return
        end
        npc = bridge:getTestNpcCharacterForAction()
        if npc == nil then
            fail("npc_character_unavailable", tostring(result))
            return
        end
        print(TAG .. " survivor=" .. tostring(result))

        local persistence = rawget(_G, "KnoxPersistence")
        if persistence.isDevGateComplete(HEALTH_GATE_KEY) then
            reportScenario = "health_reload"
            if persistence.isDevGateComplete(HEALTH_RELOAD_GATE_KEY) then
                report("SKIP", "already_passed", "next=medical")
                phase = "FINISHED"
                stop()
                return
            end

            local restoredHealth = bridge:getTestNpcHealth()
            local restoredInjuries = bridge:getTestNpcInjuredPartCount()
            local restoredBleeding = bridge:getTestNpcBleedingPartCount()
            local restoredItems = npc:getInventory():getItems():size()
            if restoredHealth >= 100 or restoredInjuries < 1 or restoredBleeding < 1 then
                report(
                    "FAIL",
                    "saved_injury_not_restored",
                    "health=" .. tostring(restoredHealth)
                        .. " injuredParts=" .. tostring(restoredInjuries)
                        .. " bleedingParts=" .. tostring(restoredBleeding)
                        .. " inventoryItems=" .. tostring(restoredItems)
                )
                phase = "FINISHED"
                stop()
                return
            end
            if restoredItems < 11 then
                report(
                    "FAIL",
                    "post_loot_inventory_not_restored",
                    "inventoryItems=" .. tostring(restoredItems) .. " expectedAtLeast=11"
                )
                phase = "FINISHED"
                stop()
                return
            end
            persistence.markDevGateComplete(HEALTH_RELOAD_GATE_KEY)
            report(
                "PASS",
                "injury_and_inventory_restored",
                "health=" .. tostring(restoredHealth)
                    .. " injuredParts=" .. tostring(restoredInjuries)
                    .. " bleedingParts=" .. tostring(restoredBleeding)
                    .. " inventoryItems=" .. tostring(restoredItems)
                    .. " next=medical"
            )
            phase = "FINISHED"
            stop()
            return
        end
        clearLoadedZombies(nil)
        startAttack(bridge)
        return
    end

    if phase ~= "AWAITING_NATIVE_DAMAGE" then
        return
    end

    if ticks % ZOMBIE_CONTROL_INTERVAL_TICKS == 0 then
        clearLoadedZombies(targetZombie)
        local directed = tostring(bridge:directTestZombieAtNpc(targetZombie))
        if string.find(directed, "ZOMBIE_DIRECTED", 1, true) ~= 1 then
            fail("zombie_retarget_failed", directed)
            return
        end
    end

    local currentHealth = bridge:getTestNpcHealth()
    local injuredParts = bridge:getTestNpcInjuredPartCount()
    local bleedingParts = bridge:getTestNpcBleedingPartCount()
    if currentHealth < initialHealth - 0.01 or injuredParts > 0 or bleedingParts > 0 then
        finishReceivedDamage(bridge, currentHealth, injuredParts, bleedingParts)
        return
    end

    if ticks % STATUS_INTERVAL_TICKS == 0 then
        print(
            TAG
                .. " health-status=AWAITING_NATIVE_DAMAGE health="
                .. tostring(currentHealth)
                .. " zombieAttacking="
                .. tostring(targetZombie:isAttacking())
                .. " targetIsNpc="
                .. tostring(targetZombie:getTarget() == npc)
        )
    end
end

local function onGameStart()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true or config.activeScenario ~= "health" then
        return
    end
    print(TAG .. " START auto=true scenario=health clearsLoadedZombies=false sandboxOverrides=false")
    ticks = 0
    phase = "WAIT_START"
    npc = nil
    targetZombie = nil
    initialHealth = nil
    reportScenario = "health"
    stop()
    Events.OnTick.Add(update)
end

local function onMainMenuEnter()
    if npc ~= nil then
        npc:setZombiesDontAttack(true)
    end
    if targetZombie ~= nil then
        removeZombie(targetZombie)
    end
    targetZombie = nil
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil then
        persistence.captureActiveTestSurvivor()
    end
    stop()
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)
