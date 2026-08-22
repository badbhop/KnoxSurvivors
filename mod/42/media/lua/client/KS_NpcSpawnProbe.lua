local TAG = "[KnoxSurvivors][NPC Probe]"
local MIN_RADIUS = 3
local MAX_RADIUS = 6
local MAX_TICKS = 900
local STATUS_INTERVAL = 300

local ticks = 0
local complete = false
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

    for radius = MIN_RADIUS, MAX_RADIUS do
        local cardinalCandidates = {
            cell:getGridSquare(centerX + radius, centerY, z),
            cell:getGridSquare(centerX, centerY + radius, z),
            cell:getGridSquare(centerX - radius, centerY, z),
            cell:getGridSquare(centerX, centerY - radius, z),
        }
        for _, square in ipairs(cardinalCandidates) do
            if square ~= nil and square:canStand() then
                return square
            end
        end

        for dx = -radius, radius do
            local candidates = {
                cell:getGridSquare(centerX + dx, centerY - radius, z),
                cell:getGridSquare(centerX + dx, centerY + radius, z),
            }
            for _, square in ipairs(candidates) do
                if square ~= nil and square:canStand() then
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
                if square ~= nil and square:canStand() then
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
        if ticks % STATUS_INTERVAL == 0 then
            local bridge = rawget(_G, "KnoxJavaBridge")
            if bridge ~= nil then
                local success, result = pcall(function()
                    return bridge:getTestNpcStatus()
                end)
                print(TAG .. " status=" .. tostring(success) .. " result=" .. tostring(result))
            end
        end
        return
    end

    ticks = ticks + 1
    local bridge = rawget(_G, "KnoxJavaBridge")
    local player = getSpecificPlayer(0)
    if bridge ~= nil and player ~= nil then
        local square = findSpawnSquare(player)
        if square ~= nil then
            local success, result = pcall(function()
                return bridge:spawnTestNpc(square)
            end)
            if success then
                print(TAG .. " " .. tostring(result))
                complete = true
                return
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
