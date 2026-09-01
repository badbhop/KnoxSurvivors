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
local TRAVEL_BUCKET_SIZE = 300
local ORIGIN_TRAVEL_SPEED = 40 -- net tiles/game-hour, with separate shelter stops
local ORIGIN_TRAVEL_RADIUS = 600

local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value > -math.huge and value < math.huge
end

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

-- Meta buildings exist before their squares stream in. Choose a real ground-floor
-- room rectangle, never the building bounding-box center (which may be a courtyard).
-- This supplements player starts without consulting the player's current position.
local function addBuildingOrigins(catalog)
    local ok, buildings = pcall(function() return getWorld():getMetaGrid():getBuildings() end)
    if not ok or buildings == nil then return end
    local occupiedBuckets = {}
    local countOk, count = pcall(function() return buildings:size() end)
    if not countOk then return end
    for index = 0, count - 1 do
        local valid, x, y = pcall(function()
            local rooms = buildings:get(index):getRooms()
            for roomIndex = 0, rooms:size() - 1 do
                local room = rooms:get(roomIndex)
                if room:getZ() == 0 then
                    local rects = room:getRects()
                    for rectIndex = 0, rects:size() - 1 do
                        local rect = rects:get(rectIndex)
                        if rect:getW() >= 2 and rect:getH() >= 2 then
                            return rect:getX() + math.floor(rect:getW() / 2),
                                rect:getY() + math.floor(rect:getH() / 2)
                        end
                    end
                end
            end
        end)
        if valid and finite(x) and finite(y) then
            x, y = math.floor(x), math.floor(y)
            local bucket = math.floor(x / 100) .. ":" .. math.floor(y / 100)
            local key = coordinateKey(x, y, 0)
            if not occupiedBuckets[bucket] and not catalog.byKey[key] then
                local nearest, nearestDistance = nil, math.huge
                -- Regions have fixed anchors from player starts, so adding metadata
                -- never pulls the next region's allocation toward earlier additions.
                for _, region in ipairs(catalog.regions) do
                    local distance = (x - region.anchorX)^2 + (y - region.anchorY)^2
                    if distance < nearestDistance then nearest, nearestDistance = region, distance end
                end
                if nearest ~= nil then
                    local origin = { x = x, y = y, z = 0, key = key,
                        region = nearest.name, regionKey = nearest.key, source = "world_building" }
                    nearest.origins[#nearest.origins + 1] = origin
                    catalog.origins[#catalog.origins + 1] = origin
                    catalog.byKey[key] = origin
                    occupiedBuckets[bucket] = true
                    catalog.buildingOrigins = catalog.buildingOrigins + 1
                end
            end
        end
    end
end

local function indexTravelOrigins(catalog)
    catalog.travelBuckets = {}
    for _, origin in ipairs(catalog.origins) do
        local key = math.floor(origin.x / TRAVEL_BUCKET_SIZE) .. ":"
            .. math.floor(origin.y / TRAVEL_BUCKET_SIZE)
        local bucket = catalog.travelBuckets[key] or {}
        bucket[#bucket + 1] = origin
        catalog.travelBuckets[key] = bucket
    end
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

    local catalog = { regions = {}, origins = {}, byKey = {}, buildingOrigins = 0 }
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
            local x, y = 0, 0
            for _, origin in ipairs(region.origins) do x, y = x + origin.x, y + origin.y end
            region.anchorX, region.anchorY = x / #region.origins, y / #region.origins
            catalog.regions[#catalog.regions + 1] = region
        end
    end
    addBuildingOrigins(catalog)
    for _, region in ipairs(catalog.regions) do
        table.sort(region.origins, function(first, second) return first.key < second.key end)
    end
    table.sort(catalog.origins, function(first, second)
        return first.key < second.key
    end)
    if #catalog.origins == 0 then
        return nil, "no_player_spawn_origins"
    end
    indexTravelOrigins(catalog)
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
        print("[KnoxSurvivors][WorldPopulation] catalog playerStarts="
            .. tostring(#catalog.origins - catalog.buildingOrigins)
            .. " buildingOrigins=" .. tostring(catalog.buildingOrigins)
            .. " regions=" .. tostring(#catalog.regions))
    end
    return catalog, result
end

local EVENT_ENTRY_OFFSETS = {
    { 0, 0 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 }, { 2, 2 },
}

local function farEnoughFromPlayers(x, y, z, players, minimum)
    for _, player in ipairs(players or {}) do
        local square = player ~= nil and player:getCurrentSquare() or nil
        if square ~= nil and square:getZ() == z then
            local dx, dy = x - square:getX(), y - square:getY()
            if dx * dx + dy * dy < minimum * minimum then return false end
        end
    end
    return true
end

-- Selects a compact, unused party origin near an existing world anchor. No
-- square/body is loaded here; normal first-materialization safety remains final.
function WorldPopulation.eventEntryOrigins(target, count, seed, options)
    local x, y = type(target) == "table" and tonumber(target.x) or nil,
        type(target) == "table" and tonumber(target.y) or nil
    count = math.floor(tonumber(count) or 0)
    if not finite(x) or not finite(y) or count < 2 or count > #EVENT_ENTRY_OFFSETS then
        return nil, "invalid_event_entry"
    end
    options = type(options) == "table" and options or {}
    local minimum = math.max(60, math.min(300, tonumber(options.minimumTargetDistance) or 100))
    local maximum = math.max(minimum, math.min(1200, tonumber(options.maximumTargetDistance) or 600))
    local playerMinimum = math.max(60, math.min(300, tonumber(options.minimumPlayerDistance) or 100))
    local catalog, reason = WorldPopulation.spawnCatalog()
    if catalog == nil then return nil, reason end
    local used, candidates = KnoxPersistence.getUsedWorldOriginKeys(), {}
    for _, anchor in ipairs(catalog.origins) do
        local dx, dy = anchor.x - x, anchor.y - y
        local distance = math.sqrt(dx * dx + dy * dy)
        if anchor.z == 0 and distance >= minimum and distance <= maximum
            and farEnoughFromPlayers(anchor.x, anchor.y, 0, options.players, playerMinimum) then
            candidates[#candidates + 1] = {
                anchor = anchor,
                order = stableHash(tostring(seed or "event") .. ":" .. anchor.key),
                distance = distance,
            }
        end
    end
    table.sort(candidates, function(first, second)
        if first.order ~= second.order then return first.order < second.order end
        return first.anchor.key < second.anchor.key
    end)
    for _, candidate in ipairs(candidates) do
        local origins, valid = {}, true
        for index = 1, count do
            local offset = EVENT_ENTRY_OFFSETS[index]
            local ox, oy = candidate.anchor.x + offset[1], candidate.anchor.y + offset[2]
            local key = coordinateKey(ox, oy, 0)
            if used[key] or not farEnoughFromPlayers(ox, oy, 0, options.players, playerMinimum) then
                valid = false
                break
            end
            origins[index] = {
                x = ox, y = oy, z = 0, key = key,
                region = candidate.anchor.region,
                regionKey = candidate.anchor.regionKey,
                source = "knox_event",
                eventAnchorKey = candidate.anchor.key,
            }
        end
        if valid then return origins, "selected" end
    end
    return nil, "no_safe_event_entry_origin"
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
    local preferredSource = cursor % 3 == 2 and "world_building" or "player_spawn"
    for pass = 1, 2 do
        for offset = 0, count - 1 do
            local index = ((start + offset) % count) + 1
            local origin = region.origins[index]
            if not used[origin.key] and (pass == 2 or origin.source == preferredSource) then
                return origin
            end
        end
    end
    return nil
end

local function chooseTravelOrigin(catalog, id, state)
    local x, y = state.virtualX, state.virtualY
    local choices = {}
    local minX, maxX = math.floor((x - ORIGIN_TRAVEL_RADIUS) / TRAVEL_BUCKET_SIZE),
        math.floor((x + ORIGIN_TRAVEL_RADIUS) / TRAVEL_BUCKET_SIZE)
    local minY, maxY = math.floor((y - ORIGIN_TRAVEL_RADIUS) / TRAVEL_BUCKET_SIZE),
        math.floor((y + ORIGIN_TRAVEL_RADIUS) / TRAVEL_BUCKET_SIZE)
    for bx = minX, maxX do
        for by = minY, maxY do
            for _, origin in ipairs(catalog.travelBuckets[bx .. ":" .. by] or {}) do
                local distance = (origin.x - x)^2 + (origin.y - y)^2
                if origin.z == state.virtualZ and distance >= 16^2
                    and distance <= ORIGIN_TRAVEL_RADIUS^2 and origin.key ~= state.previousTravelKey then
                    choices[#choices + 1] = origin
                end
            end
        end
    end
    if #choices == 0 then return nil end
    table.sort(choices, function(a, b) return a.key < b.key end)
    return choices[(stableHash(id .. ":" .. tostring(state.travelSequence or 0)) % #choices) + 1]
end

-- Shared coarse itinerary for a durable position. The caller owns physiology,
-- duties and persistence. Return moving time so travel is not mistaken for rest.
function WorldPopulation.advanceItinerary(id, state, startHours, endHours)
    if type(state) ~= "table" or not finite(startHours) or not finite(endHours) then
        return false, "invalid_travel_clock", 0
    end
    local now = math.max(0, tonumber(endHours))
    if not finite(state.virtualX) or not finite(state.virtualY) or not finite(state.virtualZ) then
        return false, "invalid_virtual_location", 0
    end
    local cursor = math.max(tonumber(startHours), now - 48)
    if now <= cursor then return false, "up_to_date", 0 end
    local catalog = WorldPopulation.spawnCatalog()
    if catalog == nil then return false, "catalog_unavailable", 0 end
    local movingHours = 0
    for _ = 1, 8 do
        if cursor >= now then break end
        if state.travelTarget == nil then
            cursor = math.max(cursor, tonumber(state.departAtHours) or cursor)
            if cursor >= now then break end
            local target = chooseTravelOrigin(catalog, id, state)
            if target == nil then
                state.departAtHours = now + 3
                state.travelPhase = "shelter"
                break
            end
            state.travelTarget = { x = target.x, y = target.y, z = target.z, key = target.key }
            state.travelSequence = (tonumber(state.travelSequence) or 0) + 1
        end
        local target = state.travelTarget
        if not finite(target.x) or not finite(target.y) or not finite(target.z)
            or target.z ~= state.virtualZ then
            state.travelTarget = nil
            state.departAtHours = now + 3
            state.travelPhase = "shelter"
            break
        end
        local dx, dy = target.x - state.virtualX, target.y - state.virtualY
        local distance = math.sqrt(dx * dx + dy * dy)
        local available = (now - cursor) * ORIGIN_TRAVEL_SPEED
        if distance > available then
            state.virtualX = state.virtualX + dx / distance * available
            state.virtualY = state.virtualY + dy / distance * available
            state.travelPhase = "moving"
            movingHours = movingHours + now - cursor
            cursor = now
        else
            movingHours = movingHours + distance / ORIGIN_TRAVEL_SPEED
            cursor = cursor + distance / ORIGIN_TRAVEL_SPEED
            state.virtualX, state.virtualY, state.virtualZ = target.x, target.y, target.z
            state.previousTravelKey = state.currentTravelKey
            state.currentTravelKey = target.key
            state.travelTarget = nil
            state.travelPhase = "shelter"
            state.departAtHours = cursor + 2 + stableHash(id .. ":rest:" .. state.travelSequence) % 4
        end
    end
    state.virtualAtHours = now
    return true, "travel_advanced", movingHours
end

-- Before first body creation only location is known. This never invents health
-- or inventory. After capture the stored-survival controller owns the identity.
function WorldPopulation.advanceOriginTravel(id, hours)
    if not KnoxPersistence.isSurvivorAlive(id) or KnoxPersistence.getRecord(id) ~= nil then
        return false, "not_unmaterialized"
    end
    local origin = KnoxPersistence.getSurvivorOrigin(id)
    if origin == nil or not finite(hours) then return false, "origin_unavailable" end
    local duty = KnoxPersistence.getSurvivorDuty(id)
    if duty ~= nil and duty.mode ~= nil and duty.mode ~= "autonomous" then
        return false, "duty_owns_travel"
    end
    local now = math.max(0, tonumber(hours))
    local state = KnoxPersistence.getUnloadedSurvivalState(id)
    if state == nil then
        state = { pendingMaterialization = true, virtualX = origin.x, virtualY = origin.y,
            virtualZ = origin.z, lastHours = now, currentTravelKey = origin.key,
            activity = "origin_shelter", status = "unmaterialized" }
        KnoxPersistence.setUnloadedSurvivalState(id, state)
    end
    if state.pendingMaterialization ~= true then return false, "survival_ledger_owns_travel" end
    if type(state.eventEntryId) == "string" and state.eventEntryId ~= "" then
        state.activity, state.lastHours, state.virtualAtHours = "event_entry_waiting", now, now
        KnoxPersistence.setUnloadedSurvivalState(id, state)
        return false, "event_entry_waiting"
    end
    local advanced, result = WorldPopulation.advanceItinerary(id, state, tonumber(state.lastHours) or now, now)
    if not advanced then return false, result end
    state.activity = state.travelPhase == "moving" and "origin_travel" or "origin_shelter"
    state.lastHours, state.virtualAtHours = now, now
    return KnoxPersistence.setUnloadedSurvivalState(id, state), "origin_advanced"
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
    local uncapped = KnoxSettings.capsDisabled()
    local refillHours = KnoxSettings.populationRefillDays() * 24
    local state = KnoxPersistence.getPopulationState()
    local living = #KnoxPersistence.getLivingWorldSurvivorIds()
    local result = {
        status = "unchanged",
        addedIds = {},
        living = living,
        target = target,
        capsDisabled = uncapped,
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
        if living < target or uncapped then
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
    if living >= target and not uncapped then
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
        result.status = uncapped and "arrived" or "refilled"
        result.addedIds[1] = id
        result.living = living + 1
        if result.living >= target and not uncapped then
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

local function locationOutsideBand(x, y, players, maximumDistance)
    if maximumDistance == nil then return false end
    local maximum = maximumDistance + FIRST_SPAWN_SEARCH_RADIUS * math.sqrt(2)
    for _, player in ipairs(players) do
        local square = playerSquare(player)
        if square ~= nil and (square:getX() - x)^2 + (square:getY() - y)^2 <= maximum^2 then
            return false
        end
    end
    return true
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
    if locationOutsideBand(origin.x, origin.y, players, maximumDistance) then
        return nil, "outside_activation_distance"
    end
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

local function materializeVirtualLocation(id, bridge, record, players, maximumDistance)
    local state = KnoxPersistence.getUnloadedSurvivalState ~= nil
        and KnoxPersistence.getUnloadedSurvivalState(id) or nil
    if state == nil or (state.activity ~= "surviving"
        and state.activity ~= "group_travel"
        and state.activity ~= "group_waiting"
        and state.activity ~= "group_regrouping"
        and state.activity ~= "base_life"
        and state.activity ~= "sleeping"
        and state.activity ~= "resting"
        and state.activity ~= "sheltering"
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
    if locationOutsideBand(x, y, players, maximumDistance) then
        return record, nil, nil, nil, "outside_activation_distance"
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
            materializeVirtualLocation(id, bridge, record, players, maximumDistance)
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
    local location = origin
    local state = KnoxPersistence.getUnloadedSurvivalState(id)
    if state ~= nil and state.pendingMaterialization == true then
        if not finite(state.virtualX) or not finite(state.virtualY) or not finite(state.virtualZ) then
            return nil, "virtual_location_unavailable"
        end
        location = { x = state.virtualX, y = state.virtualY, z = state.virtualZ, key = id }
    end
    local square, squareResult = WorldPopulation.findFirstMaterializationSquare(location, options)
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
    if maximum == 0 then return candidates, { activation_budget_full = 1 } end
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
