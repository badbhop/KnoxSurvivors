local TAG = "[KnoxSurvivors][NPC Probe]"
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
local update

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
                    stop()
                    return
                end
            end
        end

        if movementRequested and ticks - movementStartedAt >= MOVE_TIMEOUT_TICKS then
            print(TAG .. " MOVEMENT_FAILED timeout waiting for NPC to reach target")
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
                    stop()
                    return
                end
            end
            print(TAG .. " call failed: " .. tostring(result))
        end
    end

    if ticks >= MAX_TICKS then
        print(TAG .. " FAILED no valid loaded spawn square before retry limit")
        stop()
    end
end

local function onGameStart()
    ticks = 0
    complete = false
    movementAttempted = false
    movementRequested = false
    movementStartedAt = 0
    movementTarget = nil
    Events.OnTick.Add(update)
end

local function onMainMenuEnter()
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
