-- Night sheltering for unbased survivors. At night, independents head for the
-- nearest indoor shelter and sleep till dawn instead of roaming in the dark.
-- No state is invented: movement uses the normal bridge move, and sleep uses
-- the standard fatigue/native sleep path. Curtains are untouched (no verified
-- Build 42 Lua API for them); a roof and sleep carry the fantasy.
local NightShelter = rawget(_G, "KnoxNightShelter") or {}
_G.KnoxNightShelter = NightShelter

NightShelter.NIGHT_START_HOUR = 20
NightShelter.NIGHT_END_HOUR = 7
NightShelter.SHELTER_SCAN_RADIUS = 24

function NightShelter.currentHour()
    if getTimeOfDay == nil then
        return 12
    end
    local ok, hour = pcall(getTimeOfDay)
    if not ok then
        return 12
    end
    return tonumber(hour) or 12
end

function NightShelter.isNight(hour)
    local value = tonumber(hour) or NightShelter.currentHour()
    return value < NightShelter.NIGHT_END_HOUR or value >= NightShelter.NIGHT_START_HOUR
end

-- Indoors counts as sheltered: a room square under a roof.
function NightShelter.isSheltered(character)
    if character == nil or character.getCurrentSquare == nil then
        return false
    end
    local ok, square = pcall(function() return character:getCurrentSquare() end)
    if not ok or square == nil or square.getRoom == nil then
        return false
    end
    local roomOk, room = pcall(function() return square:getRoom() end)
    return roomOk and room ~= nil
end

local function shelterScore(square, originX, originY)
    local dx = square:getX() - originX
    local dy = square:getY() - originY
    local score = -(dx * dx + dy * dy)
    local building = square.getBuilding ~= nil and square:getBuilding() or nil
    if building ~= nil then
        local okResidential, residential = pcall(function() return building:isResidential() end)
        if okResidential and residential == true then
            score = score + 500
        else
            score = score + 100
        end
    end
    return score
end

-- Nearest indoor room square: houses first, any roof second, closeness always.
function NightShelter.findShelter(character, radius, eligible)
    if character == nil or getCell == nil then
        return nil
    end
    local ok, origin = pcall(function() return character:getCurrentSquare() end)
    if not ok or origin == nil then
        return nil
    end
    local scan = math.max(2, tonumber(radius) or NightShelter.SHELTER_SCAN_RADIUS)
    local best, bestScore = nil, nil
    for dx = -scan, scan, 2 do
        for dy = -scan, scan, 2 do
            local square = getCell():getGridSquare(
                origin:getX() + dx, origin:getY() + dy, origin:getZ()
            )
            if square ~= nil and square.canStand ~= nil and square.getRoom ~= nil then
                local usable, room = pcall(function()
                    if not square:canStand() then return nil end
                    return square:getRoom()
                end)
                local allowed = usable and room ~= nil
                if allowed and eligible ~= nil then
                    local filterOk, accepted = pcall(eligible, square)
                    allowed = filterOk and accepted == true
                end
                if allowed then
                    local score = shelterScore(square, origin:getX(), origin:getY())
                    if bestScore == nil or score > bestScore then
                        best, bestScore = square, score
                    end
                end
            end
        end
    end
    return best
end

-- A temporary travel group can sleep in an ordinary building, but it cannot
-- silently occupy an established player/faction territory. This is only a
-- destination filter: it does not claim a base, camp, storage or safehouse.
function NightShelter.isUnclaimedTemporaryShelter(square)
    if square == nil then return false end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence ~= nil and persistence.getBaseAtSquare ~= nil then
        local ok, base = pcall(
            persistence.getBaseAtSquare,
            square:getX(), square:getY(), square:getZ()
        )
        if ok and base ~= nil then return false end
    end
    return true
end

return NightShelter
