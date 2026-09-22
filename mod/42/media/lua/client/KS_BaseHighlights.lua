require "KS_Persistence"
require "KS_BaseManager"

local Highlights = rawget(_G, "KnoxBaseHighlights") or {}
_G.KnoxBaseHighlights = Highlights

local enabled = {}
local draftByPlayer = {}
local highlightedFloors = {}

local function setSquareHighlighted(square, highlight, color)
    if square == nil or square:getFloor() == nil then return end
    local floor = square:getFloor()
    if highlight then
        highlightedFloors[floor] = true
        floor:setHighlighted(true, false)
        if color ~= nil and floor.setHighlightColor ~= nil then
            pcall(function() floor:setHighlightColor(color.r, color.g, color.b, color.a) end)
        end
    else
        floor:setHighlighted(false, false)
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
    local n = tonumber(playerNum)
    if n == nil then return false end
    return enabled[n] == true
end

function Highlights.setEnabled(playerNum, value)
    local n = tonumber(playerNum)
    if n == nil then return end
    enabled[n] = value == true
    Highlights.refresh(n)
end

function Highlights.toggle(playerNum)
    Highlights.setEnabled(playerNum, not Highlights.isEnabled(playerNum))
    return Highlights.isEnabled(playerNum)
end

function Highlights.setDraft(playerNum, active, zoneType)
    playerNum = tonumber(playerNum)
    if playerNum == nil then return end
    if active then
        draftByPlayer[playerNum] = { active = true, zoneType = zoneType }
    else
        draftByPlayer[playerNum] = nil
    end
    Highlights.refresh(playerNum)
end

function Highlights.isDraft(playerNum)
    local n = tonumber(playerNum)
    if n == nil then return false end
    local entry = draftByPlayer[n]
    return entry ~= nil and entry.active == true
end

local function drawPlayer(playerNum)
    playerNum = tonumber(playerNum) or 0
    local player = getSpecificPlayer(playerNum)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    local base = playerId ~= nil and KnoxBaseManager.getForOwner("player", playerId) or nil
    local draft = draftByPlayer[playerNum]
    local isDraft = draft ~= nil and draft.active
    local show = base ~= nil and (Highlights.isEnabled(playerNum) or isDraft)
    -- Clear previous highlights by iterating all known areas once more
    -- Vanilla highlight is per-square; we just re-apply correct state.
    -- During draft, existing are subdued so overlaps stay readable.
    if base ~= nil then
        local territory = base.territory or base.home
        -- Draft strongest, existing subdued: vanilla area-highlight-and-confirm pattern.
        local territoryAlpha = isDraft and 0.14 or 0.85
        local zoneAlpha = isDraft and 0.12 or 0.85
        local zoneAlphaGeneral = isDraft and 0.10 or 0.75
        local colorTerritory = { r = 0.25, g = 0.55, b = 0.25, a = territoryAlpha }
        -- Whole-map palette: every territory, work and storage color is
        -- visually distinct (no blue/blue, red/red or gray/gray twins), so a
        -- glance tells repair water apart from water storage and guard posts
        -- apart from weapon cupboards. Keep it that way when adding types.
        local colorZones = {
            guard = { r = 0.88, g = 0.16, b = 0.16, a = zoneAlpha },
            patrol = { r = 0.92, g = 0.55, b = 0.12, a = zoneAlpha },
            farming = { r = 0.22, g = 0.75, b = 0.22, a = zoneAlpha },
            woodcutting = { r = 0.55, g = 0.35, b = 0.15, a = zoneAlpha },
            log_processing = { r = 0.82, g = 0.68, b = 0.16, a = zoneAlpha },
            corpse = { r = 0.5, g = 0.5, b = 0.58, a = zoneAlpha },
            cooking = { r = 0.8, g = 0.3, b = 0.5, a = zoneAlpha },
            repair = { r = 0.3, g = 0.32, b = 0.88, a = zoneAlpha },
            general = { r = 0.52, g = 0.52, b = 0.75, a = zoneAlphaGeneral },
        }
        local colorStorage = {
            food = { r = 0.12, g = 0.82, b = 0.62, a = zoneAlpha },
            water = { r = 0.12, g = 0.32, b = 0.78, a = zoneAlpha },
            medical = { r = 1.0, g = 0.2, b = 0.4, a = zoneAlpha },
            weapons = { r = 0.5, g = 0.1, b = 0.1, a = zoneAlpha },
            ammunition = { r = 0.92, g = 0.92, b = 0.88, a = zoneAlpha },
            tools = { r = 0.9, g = 0.85, b = 0.2, a = zoneAlpha },
            building = { r = 0.7, g = 0.6, b = 0.45, a = zoneAlpha },
            farming = { r = 0.1, g = 0.45, b = 0.15, a = zoneAlpha },
            clothing = { r = 0.65, g = 0.4, b = 0.85, a = zoneAlpha },
            junk = { r = 0.3, g = 0.3, b = 0.33, a = zoneAlpha },
        }
        if show then
            forEachSquare(territory, function(sq) setSquareHighlighted(sq, true, colorTerritory) end)
            -- Work areas render over the base border so farming/woodcutting
            -- colors win inside the territory. Sort deterministically by
            -- priority so overlapping fills do not flicker with pairs() order.
            local ordered = {}
            for _, zone in pairs(base.zones or {}) do
                if zone ~= nil and zone.enabled ~= false and zone.x1 ~= nil then
                    ordered[#ordered + 1] = zone
                end
            end
            table.sort(ordered, function(a, b)
                local pa = tonumber(a.priority) or 50
                local pb = tonumber(b.priority) or 50
                if pa ~= pb then return pa < pb end
                return tostring(a.id) < tostring(b.id)
            end)
            for _, zone in ipairs(ordered) do
                local area = { minX = zone.x1, minY = zone.y1, maxX = zone.x2, maxY = zone.y2, z = zone.z or 0 }
                local col = colorZones[zone.type] or colorZones.general
                forEachSquare(area, function(sq) setSquareHighlighted(sq, true, col) end)
            end
            for _, policy in ipairs(KnoxBaseStorage.policies(base)) do
                local square = getCell() ~= nil and getCell():getGridSquare(policy.x, policy.y, policy.z) or nil
                local col = colorStorage[policy.storageRole] or colorStorage.building
                setSquareHighlighted(square, true, col)
            end
        end
    end
end

function Highlights.clear()
    -- Clear the actual objects touched, including removed zones/old boundaries.
    for floor in pairs(highlightedFloors) do floor:setHighlighted(false, false) end
    highlightedFloors = {}
end

function Highlights.refresh(playerNum)
    Highlights.clear()
    -- Reapply every viewer so clearing an overlapping area cannot erase another
    -- split-screen player's enabled highlights.
    local viewers = {}
    for number in pairs(enabled) do viewers[number] = true end
    for number in pairs(draftByPlayer) do viewers[number] = true end
    viewers[tonumber(playerNum) or 0] = true
    for number in pairs(viewers) do drawPlayer(number) end
end

Events.OnGameStart.Add(function()
    Highlights.clear()
    enabled, draftByPlayer = {}, {}
end)

return Highlights
