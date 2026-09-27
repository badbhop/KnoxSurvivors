require "ISUI/ISPanel"

-- Directional speech indicators: when a survivor speaks within earshot but
-- off-screen, the owning player gets a small edge arrow toward them for a
-- few seconds (track them down, avoid them, stalk them...). Only relatively
-- close speech qualifies; distant lines stay feed-only. Arrows are drawn
-- line segments (no textures, no rotation APIs), one transparent overlay
-- panel per player, hidden whenever empty.
local Indicators = rawget(_G, "KnoxSpeechIndicators") or {}
_G.KnoxSpeechIndicators = Indicators

Indicators.MIN_TILES = 10
Indicators.MAX_TILES = 40
Indicators.DURATION_MS = 6000
Indicators.EDGE_INSET = 34
Indicators.ARROW_LEN = 16

local panels = {}
local active = {}

local function nowMs()
    if getTimestampMs ~= nil then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) ~= nil then return tonumber(value) end
    end
    return 0
end

local function playerSquare(playerNum)
    if getSpecificPlayer == nil then return nil end
    local ok, player = pcall(getSpecificPlayer, playerNum)
    if not ok or player == nil or player.getCurrentSquare == nil then return nil end
    local okSq, square = pcall(function() return player:getCurrentSquare() end)
    if not okSq or square == nil then return nil end
    return square
end

-- Isometric screen projection: screen x runs (x - y), screen y runs
-- (x + y). Returns normalized screen-space direction or nil when degenerate.
local function screenDirection(fromX, fromY, toX, toY)
    local sx, sy = (toX - fromX) - (toY - fromY), (toX - fromX) + (toY - fromY)
    local length = math.sqrt(sx * sx + sy * sy)
    if not (length > 0.01) then return nil end
    return sx / length, sy / length
end

-- Eight-wind compass on world deltas (map convention: north is -y),
-- independent of the screen projection used for the arrow itself.
local function compass(dx, dy)
    local ax, ay = math.abs(dx), math.abs(dy)
    if ax >= ay * 2.414 then return dx > 0 and "E" or "W" end
    if ay >= ax * 2.414 then return dy > 0 and "S" or "N" end
    if dx > 0 then return dy > 0 and "SE" or "NE" end
    return dy > 0 and "SW" or "NW"
end

local function drawArrow(panel, cx, cy, dx, dy, dist, r, g, b)
    -- Shaft toward the speaker plus a two-line head, then the distance.
    local hx, hy = cx + dx * Indicators.ARROW_LEN, cy + dy * Indicators.ARROW_LEN
    panel:drawLine2(cx, cy, hx, hy, 0.9, 0.05, 0.05, 0.05)
    panel:drawLine2(cx, cy, hx, hy, 0.9, r, g, b)
    local px, py = -dy, dx
    local s = 6
    panel:drawLine2(hx, hy, hx - dx * s + px * s * 0.6, hy - dy * s + py * s * 0.6, 0.9, r, g, b)
    panel:drawLine2(hx, hy, hx - dx * s - px * s * 0.6, hy - dy * s - py * s * 0.6, 0.9, r, g, b)
    if UIFont ~= nil and UIFont.Small ~= nil then
        panel:drawText(tostring(dist), hx + 8, hy - 8, r, g, b, 0.95, UIFont.Small)
    end
end

-- Called with a speaker square; notifies every player in earshot.
-- Returns distance + compass for the primary player, or nil when far.
function Indicators.noteSpeech(speakerSquare, speakerId, party)
    if speakerSquare == nil or speakerSquare.getX == nil then return nil end
    local okX, sx = pcall(function() return speakerSquare:getX() end)
    local okY, sy = pcall(function() return speakerSquare:getY() end)
    local okZ, sz = pcall(function() return speakerSquare:getZ() end)
    if not okX or not okY then return nil end
    local primary = nil
    for playerNum = 0, 3 do
        local here = playerSquare(playerNum)
        if here ~= nil then
            local okHx, hx = pcall(function() return here:getX() end)
            local okHy, hy = pcall(function() return here:getY() end)
            local okHz, hz = pcall(function() return here:getZ() end)
            if okHx and okHy then
                local sameFloor = okHz and okZ and hz == sz
                local dist = math.floor(math.sqrt((sx - hx) * (sx - hx)
                    + (sy - hy) * (sy - hy)) + 0.5)
                if sameFloor and dist >= Indicators.MIN_TILES
                    and dist <= Indicators.MAX_TILES then
                    local dx, dy = screenDirection(hx, hy, sx, sy)
                    if dx ~= nil then
                        active[playerNum] = active[playerNum] or {}
                        active[playerNum][tostring(speakerId or "?")] = {
                            dx = dx, dy = dy, dist = dist,
                            untilMs = nowMs() + Indicators.DURATION_MS,
                            party = party == true,
                        }
                        local panel = Indicators.panelFor(playerNum)
                        if panel ~= nil then panel:setVisible(true) end
                        if playerNum == 0 then
                            primary = { dist = dist, dir = compass(sx - hx, sy - hy) }
                        end
                    end
                end
            end
        end
    end
    return primary
end

function Indicators.prerender(playerNum, panel)
    local list = active[playerNum]
    if list == nil then
        if panel ~= nil then panel:setVisible(false) end
        return
    end
    local now = nowMs()
    local sw, sh = panel:getWidth(), panel:getHeight()
    local empty = true
    for id, mark in pairs(list) do
        if type(mark) ~= "table" or now >= (mark.untilMs or 0) then
            list[id] = nil
        else
            empty = false
            -- Clamp along the ray to the viewport rect with an inset.
            local inset = Indicators.EDGE_INSET
            local tx, ty = mark.dx, mark.dy
            local boundX = (sw / 2 - inset) / math.max(0.01, math.abs(tx))
            local boundY = (sh / 2 - inset) / math.max(0.01, math.abs(ty))
            local bound = math.min(boundX, boundY)
            local cx, cy = sw / 2 + tx * bound, sh / 2 + ty * bound
            local r, g, b = 1.0, 1.0, 1.0
            if mark.party then r, g, b = 0.55, 0.9, 0.45 end
            drawArrow(panel, cx, cy, tx, ty, mark.dist, r, g, b)
        end
    end
    if empty and panel ~= nil then panel:setVisible(false) end
end

local Overlay = ISPanel:derive("KnoxSpeechIndicatorOverlay")

function Overlay:prerender()
    ISPanel.prerender(self)
    Indicators.prerender(self.playerNum or 0, self)
end

function Indicators.panelFor(playerNum)
    local panel = panels[playerNum]
    if panel ~= nil then return panel end
    if getPlayerScreenWidth == nil then return nil end
    local ok, sw = pcall(getPlayerScreenWidth, playerNum)
    local ok2, sh = pcall(getPlayerScreenHeight, playerNum)
    if not ok or not ok2 then return nil end
    local left, top = 0, 0
    pcall(function()
        left = getPlayerScreenLeft(playerNum)
        top = getPlayerScreenTop(playerNum)
    end)
    panel = Overlay:new(left, top, sw, sh)
    panel:initialise()
    if panel.setWantMouseEvents ~= nil then panel:setWantMouseEvents(false) end
    panel:setVisible(false)
    if panel.setRenderThisPlayerOnly ~= nil then panel:setRenderThisPlayerOnly(playerNum) end
    panel.playerNum = playerNum
    panel:addToUIManager()
    panels[playerNum] = panel
    return panel
end

if Events ~= nil and Events.OnResolutionChange ~= nil then
    Events.OnResolutionChange.Add(function()
        for _, panel in pairs(panels) do
            pcall(function() panel:removeFromUIManager() end)
        end
        for key in pairs(panels) do panels[key] = nil end
    end)
end

return Indicators
