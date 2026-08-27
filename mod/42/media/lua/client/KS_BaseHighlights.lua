require "KS_Persistence"
require "KS_BaseManager"

local Highlights = rawget(_G, "KnoxBaseHighlights") or {}
_G.KnoxBaseHighlights = Highlights

local enabled = {}

local function setSquareHighlighted(square, highlight, color)
    if square == nil or square:getFloor() == nil then return end
    local floor = square:getFloor()
    if highlight then
        floor:setHighlighted(true, false)
        if color ~= nil and floor.setHighlightColor ~= nil then
            pcall(function() floor:setHighlightColor(color.r, color.g, color.b, color.a) end)
        end
        -- Also use vanilla area highlight as fallback for visibility at distance
        if color ~= nil and addAreaHighlight ~= nil then
            pcall(function()
                addAreaHighlight(square:getX(), square:getY(), square:getX(), square:getY(), square:getZ(), color.r, color.g, color.b, 0.35)
            end)
        end
    else
        floor:setHighlighted(false, false)
        if removeAreaHighlight ~= nil then
            pcall(function() removeAreaHighlight(square:getX(), square:getY(), square:getX(), square:getY(), square:getZ()) end)
        end
    end
end

local function forEachSquare(area, callback)
    if area == nil or tonumber(area.minX) == nil or tonumber(area.minY) == nil then return end
    local minX = math.floor(tonumber(area.minX))
    local minY = math.floor(tonumber(area.minY))
    local maxX = math.floor(tonumber(area.maxX) or (minX + (tonumber(area.width) or 1) - 1))
    local maxY = math.floor(tonumber(area.maxY) or (minY + (tonumber(area.height) or 1) - 1))
    local z = math.floor(tonumber(area.z) or 0)
    for x = minX, maxX do
        for y = minY, maxY do
            local sq = getCell() ~= nil and getCell():getGridSquare(x, y, z) or nil
            if sq ~= nil then callback(sq) end
        end
    end
end

function Highlights.isEnabled(playerNum)
    return enabled[tonumber(playerNum) or 0] == true
end

function Highlights.setEnabled(playerNum, value)
    enabled[tonumber(playerNum) or 0] = value == true
    Highlights.refresh(playerNum)
end

function Highlights.toggle(playerNum)
    Highlights.setEnabled(playerNum, not Highlights.isEnabled(playerNum))
    return Highlights.isEnabled(playerNum)
end

function Highlights.refresh(playerNum)
    playerNum = tonumber(playerNum) or 0
    local player = getSpecificPlayer(playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    local show = Highlights.isEnabled(playerNum) and base ~= nil
    -- Clear previous highlights by iterating all known areas once more
    -- Vanilla highlight is per-square; we just re-apply correct state.
    if base ~= nil then
        local territory = base.territory or base.home
        local colorTerritory = { r = 0.25, g = 0.55, b = 0.25, a = 0.85 }
        local colorZones = {
            guard = { r = 0.85, g = 0.2, b = 0.2, a = 0.9 },
            patrol = { r = 0.85, g = 0.55, b = 0.15, a = 0.85 },
            farming = { r = 0.2, g = 0.7, b = 0.2, a = 0.85 },
            woodcutting = { r = 0.55, g = 0.35, b = 0.15, a = 0.85 },
            corpse = { r = 0.5, g = 0.5, b = 0.5, a = 0.85 },
            animal_care = { r = 0.85, g = 0.7, b = 0.1, a = 0.85 },
            repair = { r = 0.2, g = 0.5, b = 0.85, a = 0.85 },
            construction = { r = 0.7, g = 0.4, b = 0.85, a = 0.85 },
            general = { r = 0.4, g = 0.4, b = 0.85, a = 0.75 },
        }
        -- First clear all then re-apply if enabled, to avoid stale highlights after disable.
        forEachSquare(territory, function(sq) setSquareHighlighted(sq, false) end)
        for _, zone in pairs(base.zones or {}) do
            if zone ~= nil and zone.x1 ~= nil then
                local area = { minX = zone.x1, minY = zone.y1, maxX = zone.x2, maxY = zone.y2, z = zone.z or 0 }
                forEachSquare(area, function(sq) setSquareHighlighted(sq, false) end)
            end
        end
        if show then
            forEachSquare(territory, function(sq) setSquareHighlighted(sq, true, colorTerritory) end)
            for _, zone in pairs(base.zones or {}) do
                if zone ~= nil and zone.enabled ~= false and zone.x1 ~= nil then
                    local area = { minX = zone.x1, minY = zone.y1, maxX = zone.x2, maxY = zone.y2, z = zone.z or 0 }
                    local col = colorZones[zone.type] or colorZones.general
                    forEachSquare(area, function(sq) setSquareHighlighted(sq, true, col) end)
                end
            end
        end
    end
end

local function onTick()
    -- Lightweight: only refresh when enabled; vanilla highlight otherwise persists.
end

Events.OnTick.Add(onTick)

return Highlights
