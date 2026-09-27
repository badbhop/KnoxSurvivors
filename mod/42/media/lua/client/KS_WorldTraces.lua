-- World trace materializer: abstract fights and breaches record sites
-- while nobody watches; when a player walks into range, this turns them
-- into blood on the ground and smashed windows. Nothing is simulated
-- continuously (performance): record cheaply, materialize lazily, once.
local Traces = rawget(_G, "KnoxWorldTraces") or {}
_G.KnoxWorldTraces = Traces

local MATERIALIZE_RADIUS_SQUARED = 60 * 60
local BLOOD_SQUARES = 6
local WINDOW_SMASHES = 4
local WINDOW_SCAN_RADIUS = 6
local CHECK_INTERVAL_TICKS = 120

local ticks = 0
local nextCheck = 0

local function playerSquares()
    if getSpecificPlayer == nil then return {} end
    local count = 4
    if getNumActivePlayers ~= nil then
        local ok, n = pcall(getNumActivePlayers)
        if ok and tonumber(n) ~= nil then count = math.max(1, math.floor(tonumber(n))) end
    end
    local squares = {}
    for index = 0, math.max(0, count - 1) do
        local ok, player = pcall(getSpecificPlayer, index)
        if ok and player ~= nil and player.getCurrentSquare ~= nil then
            local okSq, square = pcall(function() return player:getCurrentSquare() end)
            if okSq and square ~= nil then squares[#squares + 1] = square end
        end
    end
    return squares
end

local function loadedSquare(x, y, z)
    if getCell == nil then return nil end
    local ok, square = pcall(function() return getCell():getGridSquare(x, y, z) end)
    if not ok then return nil end
    return square
end

local function splatBloodAt(square)
    if square == nil then return false end
    local has, checkOk = false, false
    if square.haveBlood ~= nil then
        checkOk, has = pcall(function() return square:haveBlood() end)
    end
    if checkOk and has then return true end
    local ok = pcall(function() square:splatBlood(4, 0.5) end)
    return ok
end

local function smashWindowsNear(x, y, z, budget)
    local smashed = 0
    for dx = -WINDOW_SCAN_RADIUS, WINDOW_SCAN_RADIUS do
        for dy = -WINDOW_SCAN_RADIUS, WINDOW_SCAN_RADIUS do
            if smashed >= budget then return smashed end
            local square = loadedSquare(x + dx, y + dy, z)
            local objects = square ~= nil and square.getObjects ~= nil
                and square:getObjects() or nil
            if objects ~= nil then
                for i = 0, objects:size() - 1 do
                    if smashed >= budget then return smashed end
                    local object = objects:get(i)
                    local ok, isWindow = pcall(function()
                        return instanceof(object, "IsoWindow")
                    end)
                    if ok and isWindow == true and object.isSmashed ~= nil then
                        local okState, smashedAlready = pcall(function()
                            return object:isSmashed()
                        end)
                        if okState and smashedAlready ~= true
                            and object.setSmashed ~= nil then
                            local okSmash = pcall(function()
                                object:setSmashed(true)
                            end)
                            if okSmash then smashed = smashed + 1 end
                        end
                    end
                end
            end
        end
    end
    return smashed
end

local function materialize(site)
    if type(site) ~= "table" then return false end
    local x, y, z = tonumber(site.x), tonumber(site.y), tonumber(site.z or 0)
    if x == nil or y == nil then return false end
    if site.kind == "fight" then
        local done = 0
        -- Ring first (the struggle), then the center.
        for radius = 2, 0, -1 do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if done >= BLOOD_SQUARES then break end
                    if math.max(math.abs(dx), math.abs(dy)) == radius
                        and splatBloodAt(loadedSquare(x + dx, y + dy, z)) then
                        done = done + 1
                    end
                end
                if done >= BLOOD_SQUARES then break end
            end
        end
        return done > 0
    elseif site.kind == "breach" then
        local blood = 0
        for radius = 3, 0, -1 do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if blood >= BLOOD_SQUARES then break end
                    if math.max(math.abs(dx), math.abs(dy)) == radius
                        and splatBloodAt(loadedSquare(x + dx, y + dy, z)) then
                        blood = blood + 1
                    end
                end
                if blood >= BLOOD_SQUARES then break end
            end
        end
        smashWindowsNear(x, y, z, WINDOW_SMASHES)
        return true
    end
    return false
end

local function nearPlayer(site, squares)
    if type(site) ~= "table" then return false end
    local x, y, z = tonumber(site.x), tonumber(site.y), tonumber(site.z or 0)
    if x == nil or y == nil then return false end
    for _, square in ipairs(squares) do
        if square:getZ() == z then
            local dx, dy = square:getX() - x, square:getY() - y
            if dx * dx + dy * dy <= MATERIALIZE_RADIUS_SQUARED then return true end
        end
    end
    return false
end

function Traces.update()
    ticks = ticks + 1
    if ticks < nextCheck then return end
    nextCheck = ticks + CHECK_INTERVAL_TICKS
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or persistence.getTraceSites == nil then return end
    if getCell == nil then return end
    local squares = playerSquares()
    if #squares == 0 then return end
    local done = 0
    for _, site in ipairs(persistence.getTraceSites()) do
        if done >= 3 then break end
        if type(site) == "table" and not site.visited and nearPlayer(site, squares)
            and loadedSquare(site.x, site.y, site.z or 0) ~= nil then
            local ok = false
            local okRun, result = pcall(materialize, site)
            if okRun then ok = result end
            if persistence.markTraceVisited ~= nil then
                pcall(persistence.markTraceVisited, site.id)
            end
            if ok then done = done + 1 end
        end
    end
end

if Events ~= nil and Events.OnTick ~= nil then
    Events.OnTick.Add(Traces.update)
end

return Traces
