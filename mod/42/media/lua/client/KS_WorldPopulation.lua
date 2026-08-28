require "SpawnRegions"
require "KS_Persistence"
require "KS_Settings"

local WorldPopulation = rawget(_G, "KnoxWorldPopulation") or {}
_G.KnoxWorldPopulation = WorldPopulation

-- This module owns durable population allocation and loaded-square selection.
-- It deliberately has no OnTick hook. Autonomy calls maintain() and
-- activationCandidates() on a slow schedule instead of rescanning spawn files
-- or the entire map every frame.
local catalogCache = nil
local catalogCacheKey = nil
local FIRST_SPAWN_SEARCH_RADIUS = 4

local function coordinateKey(x, y, z)
    return tostring(math.floor(tonumber(x) or 0))
        .. "," .. tostring(math.floor(tonumber(y) or 0))
        .. "," .. tostring(math.floor(tonumber(z) or 0))
end

local function stableHash(value)
    local result = 5381
    value = tostring(value or "")
    for index = 1, #value do
        result = (result * 33 + string.byte(value, index)) % 2147483647
    end
    return result
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(first, second)
        return tostring(first) < tostring(second)
    end)
    return keys
end

local function currentMapKey()
    local success, map = pcall(function()
        return getWorld() ~= nil and getWorld():getMap() or "unknown"
    end)
    return success and tostring(map or "unknown") or "unknown"
end

local function buildSpawnCatalog()
    if SpawnRegionMgr == nil or SpawnRegionMgr.getSpawnRegions == nil then
        return nil, "spawn_region_manager_unavailable"
    end
    local success, loaded = pcall(SpawnRegionMgr.getSpawnRegions)
    if not success or type(loaded) ~= "table" then
        return nil, "spawn_regions_unavailable"
    end

    local rawRegions = {}
    for index, region in ipairs(loaded) do
        if type(region) == "table" and type(region.points) == "table" then
            rawRegions[#rawRegions + 1] = {
                index = index,
                name = tostring(region.name or ("Region " .. tostring(index))),
                points = region.points,
            }
        end
    end
    table.sort(rawRegions, function(first, second)
        if first.name == second.name then
            return first.index < second.index
        end
        return first.name < second.name
    end)

    local catalog = { regions = {}, origins = {}, byKey = {} }
    local nameOccurrences = {}
    for _, rawRegion in ipairs(rawRegions) do
        nameOccurrences[rawRegion.name] = (nameOccurrences[rawRegion.name] or 0) + 1
        local occurrence = nameOccurrences[rawRegion.name]
        local regionKey = rawRegion.name .. "#" .. tostring(occurrence)
        local region = {
            key = regionKey,
            name = rawRegion.name,
            origins = {},
        }
        local regionSeen = {}
        for _, profession in ipairs(sortedKeys(rawRegion.points)) do
            local professionPoints = rawRegion.points[profession]
            if type(professionPoints) == "table" then
                for _, point in ipairs(professionPoints) do
                    if type(point) == "table"
                        and tonumber(point.posX) ~= nil and tonumber(point.posY) ~= nil then
                        local x = math.floor(tonumber(point.posX))
                        local y = math.floor(tonumber(point.posY))
                        local z = math.floor(tonumber(point.posZ) or 0)
                        local key = coordinateKey(x, y, z)
                        if not regionSeen[key] and catalog.byKey[key] == nil then
                            regionSeen[key] = true
                            local origin = {
                                x = x,
                                y = y,
                                z = z,
                                key = key,
                                region = rawRegion.name,
                                regionKey = regionKey,
                                source = "player_spawn",
                            }
                            region.origins[#region.origins + 1] = origin
                            catalog.origins[#catalog.origins + 1] = origin
                            catalog.byKey[key] = origin
                        end
                    end
                end
            end
        end
        table.sort(region.origins, function(first, second)
            return first.key < second.key
        end)
        if #region.origins > 0 then
            catalog.regions[#catalog.regions + 1] = region
        end
    end
    table.sort(catalog.origins, function(first, second)
        return first.key < second.key
    end)
    if #catalog.origins == 0 then
        return nil, "no_player_spawn_origins"
    end
    return catalog, "loaded"
end

function WorldPopulation.invalidateSpawnCatalog()
    catalogCache = nil
    catalogCacheKey = nil
end

function WorldPopulation.spawnCatalog()
    local key = currentMapKey()
    if catalogCache ~= nil and catalogCacheKey == key then
        return catalogCache, "cached"
    end
    local catalog, result = buildSpawnCatalog()
    if catalog ~= nil then
        catalogCache = catalog
        catalogCacheKey = key
    end
    return catalog, result
end

local function regionCounts()
    local counts = {}
    for _, id in ipairs(KnoxPersistence.getAllWorldSurvivorIds()) do
        local origin = KnoxPersistence.getSurvivorOrigin(id)
        if origin ~= nil then
            local regionKey = tostring(origin.regionKey or origin.region or "Unknown")
            counts[regionKey] = (counts[regionKey] or 0) + 1
        end
    end
    return counts
end

local function firstUnusedOrigin(region, used, cursor)
    local count = #region.origins
    if count == 0 then
        return nil
    end
    local start = (stableHash(region.key) + cursor * 37) % count
    for offset = 0, count - 1 do
        local index = ((start + offset) % count) + 1
        local origin = region.origins[index]
        if not used[origin.key] then
            return origin
        end
    end
    return nil
end

local function chooseBalancedOrigin(catalog, used, counts, cursor)
    local available = {}
    local lowestCount = nil
    for index, region in ipairs(catalog.regions) do
        local origin = firstUnusedOrigin(region, used, cursor)
        if origin ~= nil then
            local count = (counts[region.key] or 0)
                + (region.key ~= region.name and (counts[region.name] or 0) or 0)
            if lowestCount == nil or count < lowestCount then
                lowestCount = count
                available = { { index = index, region = region, origin = origin } }
            elseif count == lowestCount then
                available[#available + 1] = {
                    index = index,
                    region = region,
                    origin = origin,
                }
            end
        end
    end
    if #available == 0 then
        return nil
    end
    -- Rotate equal-count regions using a persisted cursor. This keeps initial
    -- allocation balanced while avoiding dependence on Lua pairs() order.
    local selected = available[(cursor % #available) + 1]
    return selected.origin, selected.region.key
end

local function allocateOne(catalog, worldAgeHours, state, used, counts)
    local cursor = math.max(0, math.floor(tonumber(state.allocationCursor) or 0))
    local origin, regionKey = chooseBalancedOrigin(catalog, used, counts, cursor)
    if origin == nil then
        return nil, "spawn_origins_exhausted"
    end
    local id, result = KnoxPersistence.allocateWorldSurvivor(origin, worldAgeHours)
    if id == nil then
        return nil, result
    end
    used[origin.key] = true
    counts[regionKey] = (counts[regionKey] or 0) + 1
    state.allocationCursor = cursor + 1
    return id, "allocated"
end

-- Creates the initial region-balanced population in one save transaction.
-- Later deaths are replaced one survivor at a time, never as a catch-up burst.
function WorldPopulation.maintain(worldAgeHours)
    local now = math.max(0, tonumber(worldAgeHours) or 0)
    local target = KnoxSettings.worldPopulation()
    local refillHours = KnoxSettings.populationRefillDays() * 24
    local state = KnoxPersistence.getPopulationState()
    local living = #KnoxPersistence.getLivingWorldSurvivorIds()
    local result = {
        status = "unchanged",
        addedIds = {},
        living = living,
        target = target,
        nextRefillHours = tonumber(state.nextRefillHours) or 0,
    }

    if not state.initialized then
        if target == 0 then
            state.initialized = true
            state.lastTarget = target
            state.belowTargetSinceHours = nil
            state.nextRefillHours = 0
            result.status = "initialized_empty"
            result.nextRefillHours = state.nextRefillHours
            return result
        end
        local catalog, catalogResult = WorldPopulation.spawnCatalog()
        if catalog == nil then
            result.status = catalogResult
            return result
        end
        local used = KnoxPersistence.getUsedWorldOriginKeys()
        local counts = regionCounts()
        while living < target do
            local id = allocateOne(catalog, now, state, used, counts)
            if id == nil then
                break
            end
            result.addedIds[#result.addedIds + 1] = id
            living = living + 1
        end
        state.initialized = true
        state.lastTarget = target
        if living < target then
            state.belowTargetSinceHours = now
            state.nextRefillHours = now + refillHours
        else
            state.belowTargetSinceHours = nil
            state.nextRefillHours = 0
        end
        result.status = #result.addedIds > 0 and "initialized" or "spawn_origins_exhausted"
        result.living = living
        result.nextRefillHours = state.nextRefillHours
        return result
    end

    state.lastTarget = target
    if living >= target then
        state.belowTargetSinceHours = nil
        state.nextRefillHours = 0
        result.status = "at_target"
        result.nextRefillHours = state.nextRefillHours
        return result
    end
    if state.belowTargetSinceHours == nil then
        state.belowTargetSinceHours = now
        state.nextRefillHours = now + refillHours
        result.status = "waiting"
        result.nextRefillHours = state.nextRefillHours
        return result
    end
    if now < (tonumber(state.nextRefillHours) or 0) then
        result.status = "waiting"
        result.nextRefillHours = state.nextRefillHours
        return result
    end

    local catalog, catalogResult = WorldPopulation.spawnCatalog()
    if catalog == nil then
        result.status = catalogResult
        state.nextRefillHours = now + refillHours
        result.nextRefillHours = state.nextRefillHours
        return result
    end
    local id, allocationResult = allocateOne(
        catalog,
        now,
        state,
        KnoxPersistence.getUsedWorldOriginKeys(),
        regionCounts()
    )
    state.nextRefillHours = now + refillHours
    result.nextRefillHours = state.nextRefillHours
    if id ~= nil then
        result.status = "refilled"
        result.addedIds[1] = id
        result.living = living + 1
        if result.living >= target then
            state.belowTargetSinceHours = nil
            state.nextRefillHours = 0
            result.nextRefillHours = 0
        else
            state.belowTargetSinceHours = now
        end
    else
        result.status = allocationResult
    end
    return result
end

local function playersFrom(options)
    if type(options) == "table" and type(options.players) == "table" then
        return options.players
    end
    local players = {}
    local success, count = pcall(function()
        return getNumActivePlayers()
    end)
    if not success then
        count = 1
    end
    for playerIndex = 0, math.max(0, tonumber(count) or 1) - 1 do
        local playerSuccess, player = pcall(function()
            return getSpecificPlayer(playerIndex)
        end)
        if playerSuccess and player ~= nil then
            players[#players + 1] = player
        end
    end
    return players
end

local function playerSquare(player)
    local success, square = pcall(function()
        return player:getCurrentSquare()
    end)
    return success and square or nil
end

local function distanceSquared(square, other)
    local dx = square:getX() - other:getX()
    local dy = square:getY() - other:getY()
    return dx * dx + dy * dy
end

function WorldPopulation.nearestPlayerDistanceSquared(square, players)
    if square == nil then
        return nil
    end
    local nearest = nil
    for _, player in ipairs(players or playersFrom(nil)) do
        local other = playerSquare(player)
        if other ~= nil then
            local value = distanceSquared(square, other)
            if nearest == nil or value < nearest then
                nearest = value
            end
        end
    end
    return nearest
end

local function visibleToAnyPlayer(square, players)
    for fallbackIndex, player in ipairs(players) do
        local playerIndex = fallbackIndex - 1
        pcall(function()
            playerIndex = player:getPlayerNum()
        end)
        local canSeeSuccess, canSee = pcall(function()
            return square:isCanSee(playerIndex)
        end)
        if canSeeSuccess and canSee then
            return true
        end
        if not canSeeSuccess then
            local couldSeeSuccess, couldSee = pcall(function()
                return square:isCouldSee(playerIndex)
            end)
            if couldSeeSuccess and couldSee then
                return true
            end
        end
    end
    return false
end

local function safeStandable(square)
    if square == nil then
        return false
    end
    local standSuccess, standable = pcall(function()
        return square:canStand()
    end)
    if not standSuccess or not standable then
        return false
    end
    local fireSuccess, hasFire = pcall(function()
        return square:haveFire()
    end)
    if fireSuccess and hasFire then
        return false
    end
    local movingSuccess, occupied = pcall(function()
        local movingObjects = square:getMovingObjects()
        return movingObjects ~= nil and movingObjects:size() > 0
    end)
    return not (movingSuccess and occupied)
end

local function ringOffsets(radius, rotation)
    local offsets = {}
    if radius == 0 then
        return { { x = 0, y = 0 } }
    end
    for dx = -radius, radius do
        for dy = -radius, radius do
            if math.max(math.abs(dx), math.abs(dy)) == radius then
                offsets[#offsets + 1] = { x = dx, y = dy }
            end
        end
    end
    table.sort(offsets, function(first, second)
        if first.x == second.x then
            return first.y < second.y
        end
        return first.x < second.x
    end)
    local rotated = {}
    local count = #offsets
    local start = count > 0 and rotation % count or 0
    for offset = 0, count - 1 do
        rotated[#rotated + 1] = offsets[((start + offset) % count) + 1]
    end
    return rotated
end

local function withinMaximumDistance(square, players, maximumDistance)
    if maximumDistance == nil then
        return true, WorldPopulation.nearestPlayerDistanceSquared(square, players)
    end
    local nearest = WorldPopulation.nearestPlayerDistanceSquared(square, players)
    return nearest ~= nil and nearest <= maximumDistance * maximumDistance, nearest
end

-- First materialization may move at most four tiles from its original player
-- spawn point to find a valid square. It never occurs in sight of, or inside
-- the configured exclusion radius around, any local player.
function WorldPopulation.findFirstMaterializationSquare(origin, options)
    if type(origin) ~= "table" or getCell() == nil then
        return nil, "origin_or_cell_unavailable"
    end
    local players = playersFrom(options)
    local minimumDistance = type(options) == "table" and options.minimumDistance
        or KnoxSettings.minimumSpawnDistance()
    minimumDistance = math.max(0, tonumber(minimumDistance) or 0)
    local maximumDistance = type(options) == "table"
        and tonumber(options.maximumDistance)
        or nil
    local rotation = stableHash(origin.key or coordinateKey(origin.x, origin.y, origin.z))

    for radius = 0, FIRST_SPAWN_SEARCH_RADIUS do
        for _, offset in ipairs(ringOffsets(radius, rotation)) do
            local square = getCell():getGridSquare(
                math.floor(tonumber(origin.x)) + offset.x,
                math.floor(tonumber(origin.y)) + offset.y,
                math.floor(tonumber(origin.z) or 0)
            )
            if safeStandable(square) and not visibleToAnyPlayer(square, players) then
                local nearest = WorldPopulation.nearestPlayerDistanceSquared(square, players)
                local farEnough = nearest == nil
                    or nearest >= minimumDistance * minimumDistance
                local closeEnough = maximumDistance == nil
                    or (nearest ~= nil and nearest <= maximumDistance * maximumDistance)
                if farEnough and closeEnough then
                    return square, "ready"
                end
            end
        end
    end
    return nil, "no_safe_hidden_loaded_square"
end

local function recordLocation(bridge, record)
    if bridge == nil then
        return nil, nil, nil, "bridge_unavailable"
    end
    local success, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(record),
            bridge:getTestNpcRecordY(record),
            bridge:getTestNpcRecordZ(record)
    end)
    if not success or tonumber(x) == nil or tonumber(y) == nil or tonumber(z) == nil then
        return nil, nil, nil, "record_location_unavailable"
    end
    return math.floor(tonumber(x)), math.floor(tonumber(y)), math.floor(tonumber(z)), nil
end

local function materializeVirtualLocation(id, bridge, record, players)
    local state = KnoxPersistence.getUnloadedSurvivalState ~= nil
        and KnoxPersistence.getUnloadedSurvivalState(id) or nil
    if state == nil or (state.activity ~= "surviving"
        and state.activity ~= "group_travel"
        and state.activity ~= "base_life"
        and state.activity ~= "returning_to_base"
        and state.activity ~= "away_mission") then
        return record, nil, nil, nil, "no_virtual_travel"
    end
    local x = math.floor(tonumber(state.virtualX) or -1)
    local y = math.floor(tonumber(state.virtualY) or -1)
    local z = math.floor(tonumber(state.virtualZ) or 0)
    if x < 0 or y < 0 or getCell() == nil then
        return record, nil, nil, nil, "virtual_location_unavailable"
    end
    local selected = nil
    local rotation = stableHash(id .. ":virtual:" .. tostring(x) .. ":" .. tostring(y))
    for radius = 0, FIRST_SPAWN_SEARCH_RADIUS do
        for _, offset in ipairs(ringOffsets(radius, rotation)) do
            local square = getCell():getGridSquare(x + offset.x, y + offset.y, z)
            if safeStandable(square) and not visibleToAnyPlayer(square, players) then
                selected = square
                break
            end
        end
        if selected ~= nil then break end
    end
    if selected == nil then
        return record, nil, nil, nil, "virtual_square_not_loaded_or_visible"
    end
    if bridge.relocateNpcRecord == nil then
        return record, nil, nil, nil, "record_relocator_unavailable"
    end
    local ok, updated = pcall(
        bridge.relocateNpcRecord,
        bridge,
        record,
        selected:getX(),
        selected:getY(),
        selected:getZ()
    )
    if not ok or type(updated) ~= "string" or updated == "" then
        return record, nil, nil, nil, "record_relocation_failed"
    end
    if not KnoxPersistence.setRecord(id, updated) then
        return record, nil, nil, nil, "record_relocation_save_failed"
    end
    state.virtualX, state.virtualY, state.virtualZ = selected:getX(), selected:getY(), selected:getZ()
    KnoxPersistence.setUnloadedSurvivalState(id, state)
    return updated, selected:getX(), selected:getY(), selected:getZ(), nil
end

-- A saved record always wins over its origin. Restoration returns the exact
-- recorded square or waits for that square to load; it never silently moves a
-- persistent survivor back to their original spawn point.
function WorldPopulation.activationCandidate(id, bridge, options)
    if type(id) ~= "string" or id == "" or not KnoxPersistence.isSurvivorAlive(id) then
        return nil, "not_living"
    end
    local duty = KnoxPersistence.getSurvivorDuty(id)
    -- An away team owns its members' off-world lifecycle until it finishes or
    -- blocks. Normal proximity activation must not pull them back into a loaded
    -- engine shell just because the player passes their recorded origin.
    if duty ~= nil and duty.mode == "away" then
        return nil, "away_mission"
    end
    local players = playersFrom(options)
    local maximumDistance = type(options) == "table"
        and tonumber(options.maximumDistance)
        or nil
    local record = KnoxPersistence.getRecord(id)
    if record ~= nil then
        local virtualRecord, virtualX, virtualY, virtualZ, virtualResult =
            materializeVirtualLocation(id, bridge, record, players)
        if virtualResult ~= "no_virtual_travel" then
            if virtualResult ~= nil then return nil, virtualResult end
            record = virtualRecord
        end
        local x, y, z, locationError = virtualX, virtualY, virtualZ, nil
        if x == nil then
            x, y, z, locationError = recordLocation(bridge, record)
        end
        if locationError ~= nil then
            return nil, locationError
        end
        local square = getCell() ~= nil and getCell():getGridSquare(x, y, z) or nil
        if square == nil then
            return nil, "saved_square_not_loaded"
        end
        local closeEnough, nearest = withinMaximumDistance(square, players, maximumDistance)
        if not closeEnough then
            return nil, "outside_activation_distance"
        end
        return {
            id = id,
            mode = "restore",
            record = record,
            square = square,
            x = x,
            y = y,
            z = z,
            exact = true,
            firstMaterialization = false,
            distanceSquared = nearest,
        }, "ready"
    end

    local origin = KnoxPersistence.getSurvivorOrigin(id)
    if origin == nil then
        return nil, "origin_unavailable"
    end
    local square, squareResult = WorldPopulation.findFirstMaterializationSquare(origin, options)
    if square == nil then
        return nil, squareResult
    end
    return {
        id = id,
        mode = "spawn",
        origin = origin,
        square = square,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        exact = false,
        firstMaterialization = true,
        distanceSquared = WorldPopulation.nearestPlayerDistanceSquared(square, players),
    }, "ready"
end

local function activeLookup(activeIds)
    local lookup = {}
    for key, value in pairs(activeIds or {}) do
        if type(key) == "number" and type(value) == "string" then
            lookup[value] = true
        elseif type(key) == "string" and value then
            lookup[key] = true
        end
    end
    return lookup
end

-- Restore every durable survivor record, including companions and manually-created
-- development survivors. New first-materializations remain production-managed only.
function WorldPopulation.activationCandidates(bridge, activeIds, limit, options)
    local candidates = {}
    local rejected = {}
    local active = activeLookup(activeIds)
    local maximum = math.max(0, math.floor(tonumber(limit) or KnoxSettings.maxActiveSurvivors()))
    for _, id in ipairs(KnoxPersistence.getActivatableSurvivorIds()) do
        if not active[id] then
            local candidate, result = WorldPopulation.activationCandidate(id, bridge, options)
            if candidate ~= nil then
                candidates[#candidates + 1] = candidate
            else
                rejected[result] = (rejected[result] or 0) + 1
            end
        end
    end
    table.sort(candidates, function(first, second)
        local firstDistance = tonumber(first.distanceSquared) or math.huge
        local secondDistance = tonumber(second.distanceSquared) or math.huge
        if firstDistance == secondDistance then
            if first.mode ~= second.mode then
                return first.mode == "restore"
            end
            return first.id < second.id
        end
        return firstDistance < secondDistance
    end)
    while #candidates > maximum do
        table.remove(candidates)
    end
    return candidates, rejected
end

return WorldPopulation
