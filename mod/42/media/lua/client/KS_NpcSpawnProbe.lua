local TAG = "[KnoxSurvivors][TestLab]"
local MIN_RADIUS = 2
local MAX_RADIUS = 4
local MAX_TICKS = 900
local MOVE_DELAY_TICKS = 120
local MOVE_TIMEOUT_TICKS = 1200
local STATUS_INTERVAL = 120

local ticks = 0
local complete = false
local movementAttempted = false
local movementRequested = false
local movementStartedAt = 0
local movementTarget = nil
local resultReported = false
local update

local function reportResult(status, reason, evidence)
    if resultReported then
        return
    end
    resultReported = true
    print(
        TAG
            .. " RESULT scenario=movement status="
            .. tostring(status)
            .. " reason="
            .. tostring(reason)
            .. " evidence="
            .. tostring(evidence or "none")
    )
end

local function printScenarioRegistry(config)
    local names = { "movement", "equipment", "combat", "loot", "health", "medical", "persistence" }
    for _, name in ipairs(names) do
        print(
            TAG
                .. " SCENARIO name="
                .. name
                .. " state="
                .. tostring(config.scenarios[name] or "UNREGISTERED")
        )
    end
end

local function findSpawnSquare(player)
    local cell = getCell()
    local playerSquare = player:getCurrentSquare()
    if cell == nil or playerSquare == nil then
        return nil
    end

    local centerX = playerSquare:getX()
    local centerY = playerSquare:getY()
    local z = playerSquare:getZ()
    local playerNumber = player:getPlayerNum()
    local playerRoom = playerSquare:getRoom()

    local function isValid(square)
        return square ~= nil
            and square:canStand()
            and square:isCanSee(playerNumber)
            and square:getRoom() == playerRoom
    end

    for radius = MIN_RADIUS, MAX_RADIUS do
        local cardinalCandidates = {
            cell:getGridSquare(centerX + radius, centerY, z),
            cell:getGridSquare(centerX, centerY + radius, z),
            cell:getGridSquare(centerX - radius, centerY, z),
            cell:getGridSquare(centerX, centerY - radius, z),
        }
        for _, square in ipairs(cardinalCandidates) do
            if isValid(square) then
                return square
            end
        end

        for dx = -radius, radius do
            local candidates = {
                cell:getGridSquare(centerX + dx, centerY - radius, z),
                cell:getGridSquare(centerX + dx, centerY + radius, z),
            }
            for _, square in ipairs(candidates) do
                if isValid(square) then
                    return square
                end
            end
        end
        for dy = -radius + 1, radius - 1 do
            local candidates = {
                cell:getGridSquare(centerX - radius, centerY + dy, z),
                cell:getGridSquare(centerX + radius, centerY + dy, z),
            }
            for _, square in ipairs(candidates) do
                if isValid(square) then
                    return square
                end
            end
        end
    end

    return nil
end

local function findMovementTarget(player, spawnSquare)
    local cell = getCell()
    local playerSquare = player:getCurrentSquare()
    if cell == nil or playerSquare == nil or spawnSquare == nil then
        return nil
    end

    local centerX = playerSquare:getX()
    local centerY = playerSquare:getY()
    local z = playerSquare:getZ()
    local playerNumber = player:getPlayerNum()
    local playerRoom = playerSquare:getRoom()
    local spawnX = spawnSquare:getX()
    local spawnY = spawnSquare:getY()

    for radius = MAX_RADIUS, MIN_RADIUS, -1 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local square = cell:getGridSquare(centerX + dx, centerY + dy, z)
                if square ~= nil
                    and square:canStand()
                    and square:isCanSee(playerNumber)
                    and square:getRoom() == playerRoom
                    and math.abs(square:getX() - spawnX) + math.abs(square:getY() - spawnY) >= 3 then
                    return square
                end
            end
        end
        for dy = -radius + 1, radius - 1 do
            for _, dx in ipairs({ -radius, radius }) do
                local square = cell:getGridSquare(centerX + dx, centerY + dy, z)
                if square ~= nil
                    and square:canStand()
                    and square:isCanSee(playerNumber)
                    and square:getRoom() == playerRoom
                    and math.abs(square:getX() - spawnX) + math.abs(square:getY() - spawnY) >= 3 then
                    return square
                end
            end
        end
    end

    return nil
end

local function stop()
    if update ~= nil then
        Events.OnTick.Remove(update)
    end
end

update = function()
    if complete then
        ticks = ticks + 1
        local bridge = rawget(_G, "KnoxJavaBridge")

        if not movementAttempted and ticks >= MOVE_DELAY_TICKS and bridge ~= nil and movementTarget ~= nil then
            movementAttempted = true
            local success, result = pcall(function()
                return bridge:moveTestNpc(movementTarget)
            end)
            print(TAG .. " movement-request=" .. tostring(success) .. " result=" .. tostring(result))
            if success and string.find(tostring(result), "MOVE_STARTED", 1, true) == 1 then
                movementRequested = true
                movementStartedAt = ticks
            else
                print(TAG .. " MOVEMENT_FAILED movement request did not start")
                reportResult("FAIL", "movement_request", result)
                stop()
                return
            end
        end

        if movementRequested and bridge ~= nil then
            local tickSuccess, tickResult = pcall(function()
                return bridge:tickTestNpc()
            end)
            if not tickSuccess or string.find(tostring(tickResult), "Failed", 1, true) ~= nil
                or string.find(tostring(tickResult), "TICK_FAILED", 1, true) ~= nil then
                print(
                    TAG
                        .. " MOVEMENT_FAILED controller tick="
                        .. tostring(tickSuccess)
                        .. " result="
                        .. tostring(tickResult)
                )
                reportResult("FAIL", "controller_tick", tickResult)
                stop()
                return
            end
        end

        if ticks % STATUS_INTERVAL == 0 then
            if bridge ~= nil then
                local success, result = pcall(function()
                    return bridge:getTestNpcStatus()
                end)
                print(TAG .. " status=" .. tostring(success) .. " result=" .. tostring(result))
                if success and string.find(tostring(result), "movement=ARRIVED", 1, true) ~= nil then
                    print(TAG .. " MOVEMENT_PASS " .. tostring(result))
                    reportResult("PASS", "arrived", result)
                    stop()
                    return
                end
            end
        end

        if movementRequested and ticks - movementStartedAt >= MOVE_TIMEOUT_TICKS then
            print(TAG .. " MOVEMENT_FAILED timeout waiting for NPC to reach target")
            local statusSuccess, statusResult = pcall(function()
                return bridge:getTestNpcStatus()
            end)
            reportResult("FAIL", "timeout", statusSuccess and statusResult or "status_unavailable")
            stop()
        end
        return
    end

    ticks = ticks + 1
    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getSpecificPlayer(0)
    if bridge ~= nil and player ~= nil then
        local square = findSpawnSquare(player)
        if square ~= nil then
            print(
                TAG
                    .. " player="
                    .. tostring(player:getX())
                    .. ","
                    .. tostring(player:getY())
                    .. " visibleSpawn="
                    .. tostring(square:getX())
                    .. ","
                    .. tostring(square:getY())
            )
            local success, result = pcall(function()
                return bridge:spawnTestNpc(square)
            end)
            if success then
                print(TAG .. " " .. tostring(result))
                if string.find(tostring(result), "SPAWNED", 1, true) == 1 then
                    movementTarget = findMovementTarget(player, square)
                    if movementTarget ~= nil then
                        print(
                            TAG
                                .. " movementTarget="
                                .. tostring(movementTarget:getX())
                                .. ","
                                .. tostring(movementTarget:getY())
                                .. ","
                                .. tostring(movementTarget:getZ())
                        )
                        ticks = 0
                        complete = true
                        return
                    end
                    print(TAG .. " MOVEMENT_FAILED no visible target square far enough from spawn")
                    reportResult("FAIL", "no_movement_target", "spawned=true")
                    stop()
                    return
                end
            end
            print(TAG .. " call failed: " .. tostring(result))
        end
    end

    if ticks >= MAX_TICKS then
        print(TAG .. " FAILED no valid loaded spawn square before retry limit")
        reportResult("FAIL", "no_spawn_square", "retry_limit=" .. tostring(MAX_TICKS))
        stop()
    end
end

local function onGameStart()
    local config = rawget(_G, "KnoxDevTests")
    if config == nil or config.enabled ~= true then
        print(TAG .. " DISABLED")
        return
    end
    if config.activeScenario ~= "movement" then
        print(
            TAG
                .. " RESULT scenario="
                .. tostring(config.activeScenario)
                .. " status=BLOCKED reason=not_implemented evidence=none"
        )
        return
    end

    print(
        TAG
            .. " START auto=true scenario=movement sandboxOverrides="
            .. tostring(config.sandboxOverrides)
    )
    printScenarioRegistry(config)
    ticks = 0
    complete = false
    movementAttempted = false
    movementRequested = false
    movementStartedAt = 0
    movementTarget = nil
    resultReported = false
    stop()
    Events.OnTick.Add(update)
end

local function onMainMenuEnter()
    stop()
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge ~= nil then
        local success, result = pcall(function()
            return bridge:removeTestNpc()
        end)
        print(TAG .. " cleanup=" .. tostring(success) .. " result=" .. tostring(result))
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)
