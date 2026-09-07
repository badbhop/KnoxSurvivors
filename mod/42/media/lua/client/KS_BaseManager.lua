require "KS_Persistence"
require "KS_SurvivorCapabilities"
require "KS_SurvivorRuntime"
require "KS_BaseStorage"
require "KS_ToolCupboard"
require "KS_Settings"

local BaseManager = rawget(_G, "KnoxBaseManager") or {}
_G.KnoxBaseManager = BaseManager

local PLAYER_BASE_YARD_PADDING = 6

BaseManager.ZONE_TYPES = {
    farming = true,
    woodcutting = true,
    log_processing = true,
    guard = true,
    patrol = true,
    corpse = true,
    animal_care = true,
    repair = true,
    construction = true,
    defense = true,
    general = true,
}

BaseManager.STORAGE_CATEGORIES = {
    depot = true,
    general = true,
    food = true,
    water = true,
    medical = true,
    weapons = true,
    ammunition = true,
    tools = true,
    building = true,
    farming = true,
    clothing = true,
}

local function worldAge()
    return getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
end

local function areaFromBuilding(building, square)
    local definition = building ~= nil and building:getDef() or nil
    if definition == nil then
        return nil
    end
    return {
        buildingId = tostring(definition:getID()),
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        minX = definition:getX(),
        minY = definition:getY(),
        width = definition:getW(),
        height = definition:getH(),
    }
end

local function territoryAround(area, padding)
    local pad = math.max(0, tonumber(padding) or 0)
    return {
        minX = area.minX - pad,
        minY = area.minY - pad,
        maxX = area.minX + area.width - 1 + pad,
        maxY = area.minY + area.height - 1 + pad,
    }
end

local function blockedBySurvivorSafehouse(area)
    local overlapping = SafeHouse ~= nil and SafeHouse.getSafehouseOverlapping(
        area.minX,
        area.minY,
        area.maxX + 1,
        area.maxY + 1
    ) or nil
    if overlapping == nil then return false end
    local owner = tostring(overlapping:getOwner() or "")
    return string.find(owner, "KnoxSurvivors:", 1, true) == 1
end

local function hasZoneType(base, zoneType)
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == zoneType then
            return true
        end
    end
    return false
end

local function countZoneType(base, zoneType)
    local count = 0
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == zoneType then
            count = count + 1
        end
    end
    return count
end

local function ensureFactionZone(base, zoneType, bounds, label)
    if not hasZoneType(base, zoneType) and bounds ~= nil then
        return KnoxPersistence.addBaseZone(base.id, zoneType, bounds, label)
    end
    return nil, "existing"
end

local function findOutdoorSquare(area, preferredDistance)
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil or area == nil then return nil end
    local centerX = math.floor((tonumber(area.minX) or 0)
        + math.max(1, tonumber(area.width) or 1) / 2)
    local centerY = math.floor((tonumber(area.minY) or 0)
        + math.max(1, tonumber(area.height) or 1) / 2)
    local z = tonumber(area.z) or 0
    for radius = math.max(2, tonumber(preferredDistance) or 2), 18 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local square = cell:getGridSquare(centerX + dx, centerY + dy, z)
                if square ~= nil and square:canStand() and square:getRoom() == nil then
                    return square
                end
            end
        end
        for dy = -radius + 1, radius - 1 do
            for _, dx in ipairs({ -radius, radius }) do
                local square = cell:getGridSquare(centerX + dx, centerY + dy, z)
                if square ~= nil and square:canStand() and square:getRoom() == nil then
                    return square
                end
            end
        end
    end
    return nil
end

-- Animal care should only appear when the claimed territory actually contains
-- a vanilla feeding trough.  This keeps normal bases uncluttered while making
-- the existing real trough executor discoverable for ranch/farm settlements.
local function findAnimalCareSquare(area)
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil or area == nil or instanceof == nil then return nil end
    local minX = tonumber(area.minX) or 0
    local minY = tonumber(area.minY) or 0
    local maxX = tonumber(area.maxX)
        or (minX + math.max(1, tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY)
        or (minY + math.max(1, tonumber(area.height) or 1) - 1)
    local z = tonumber(area.z) or 0
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            local objects = square ~= nil and square:getObjects() or nil
            if objects ~= nil then
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    local success, trough = pcall(function()
                        return instanceof(object, "IsoFeedingTrough")
                    end)
                    if success and trough == true then return square end
                end
            end
        end
    end
    return nil
end

local function ensureFactionZones(base)
    local area = base ~= nil and (base.territory or base.home) or nil
    if area == nil then return end
    local minX = tonumber(area.minX) or 0
    local minY = tonumber(area.minY) or 0
    local maxX = tonumber(area.maxX) or (minX + math.max(1, tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY) or (minY + math.max(1, tonumber(area.height) or 1) - 1)
    local z = tonumber(area.z) or 0
    ensureFactionZone(base, "patrol", {
        x1 = minX, y1 = minY, x2 = maxX, y2 = maxY, z = z, priority = 72,
    }, "Base Patrol")
    local entryWatch = findOutdoorSquare(area, 2)
    local guardX = entryWatch ~= nil and entryWatch:getX()
        or math.floor(tonumber(area.x) or ((minX + maxX) / 2))
    local guardY = entryWatch ~= nil and entryWatch:getY()
        or math.floor(tonumber(area.y) or ((minY + maxY) / 2))
    ensureFactionZone(base, "guard", {
        x1 = guardX - 1, y1 = guardY - 1,
        x2 = guardX + 1, y2 = guardY + 1, z = z, priority = 84,
    }, "Entry Watch")
    -- Larger settlements need relief and a second sight line.  Keep this as a
    -- second ordinary guard zone rather than inventing a separate security
    -- system; BaseJobs will claim/rotate it using the same fairness rules as
    -- every other resident duty.  The opposite corner keeps posts apart even
    -- when the first outdoor square resolves near the building entrance.
    local residentIds = KnoxPersistence.getBaseResidentIds ~= nil
        and KnoxPersistence.getBaseResidentIds(base.id) or {}
    local residentCount = type(residentIds) == "table" and #residentIds or 0
    if residentCount >= 6 and countZoneType(base, "patrol") < 2 then
        -- Split a large settlement's perimeter into a second route.  It is
        -- still an ordinary patrol zone; task claims and waypoint rotation
        -- remain owned by BaseJobs/CompanionPatrol.
        local outerPatrol = findOutdoorSquare(area, math.max(5,
            math.floor(math.max(6, tonumber(area.width) or 6) / 2)))
        local patrolX = outerPatrol ~= nil and outerPatrol:getX()
            or math.floor(maxX - 2)
        local patrolY = outerPatrol ~= nil and outerPatrol:getY()
            or math.floor(maxY - 2)
        ensureFactionZone(base, "patrol", {
            x1 = patrolX - 3, y1 = patrolY - 3,
            x2 = patrolX + 3, y2 = patrolY + 3, z = z, priority = 71,
        }, "Outer Patrol")
    end
    if residentCount >= 4 and countZoneType(base, "guard") < 2 then
        local farWatch = findOutdoorSquare(area, math.max(4,
            math.floor(math.max(4, tonumber(area.width) or 4) / 2)))
        local farX = farWatch ~= nil and farWatch:getX()
            or math.floor(maxX - 1)
        local farY = farWatch ~= nil and farWatch:getY()
            or math.floor(maxY - 1)
        ensureFactionZone(base, "guard", {
            x1 = farX - 1, y1 = farY - 1,
            x2 = farX + 1, y2 = farY + 1, z = z, priority = 83,
        }, "Outer Watch")
    end
    -- Structure repair scans the owned territory directly; it does not need a
    -- second full-base work-area overlay. Keep generated zones limited to work
    -- the player can understand spatially.
    if not hasZoneType(base, "construction") and not hasZoneType(base, "defense") then
        ensureFactionZone(base, "construction", {
            x1 = minX - 1, y1 = minY - 1,
            x2 = maxX + 1, y2 = maxY + 1, z = z, priority = 75,
        }, "Defense Perimeter")
    end
    local animalSquare = findAnimalCareSquare(area)
    if animalSquare ~= nil then
        ensureFactionZone(base, "animal_care", {
            x1 = animalSquare:getX() - 2, y1 = animalSquare:getY() - 2,
            x2 = animalSquare:getX() + 2, y2 = animalSquare:getY() + 2,
            z = animalSquare:getZ(), priority = 86,
        }, "Animal Care")
    end
    local work = findOutdoorSquare(area, 4)
    if work ~= nil then
        ensureFactionZone(base, "farming", {
            x1 = work:getX() - 2, y1 = work:getY() - 2,
            x2 = work:getX() + 2, y2 = work:getY() + 2,
            z = work:getZ(), priority = 82,
        }, "Food Plot")
    end
    local outer = findOutdoorSquare(area, 8)
    if outer ~= nil then
        ensureFactionZone(base, "woodcutting", {
            x1 = outer:getX() - 6, y1 = outer:getY() - 6,
            x2 = outer:getX() + 6, y2 = outer:getY() + 6,
            z = outer:getZ(), priority = 68,
        }, "Wood Lot")
        -- Keep log processing close to the wood lot while exposing it as its
        -- own durable work area. The executor distinguishes the two and uses
        -- real logs/saws; this only supplies a sensible default for new bases.
        ensureFactionZone(base, "log_processing", {
            x1 = outer:getX() - 2, y1 = outer:getY() - 2,
            x2 = outer:getX() + 2, y2 = outer:getY() + 2,
            z = outer:getZ(), priority = 70,
        }, "Log Processing")
        ensureFactionZone(base, "corpse", {
            x1 = outer:getX() - 1, y1 = outer:getY() - 1,
            x2 = outer:getX() + 1, y2 = outer:getY() + 1,
            z = outer:getZ(), priority = 91,
        }, "Corpse Drop")
    end
end

local function ensureFactionStorage(base)
    if base == nil then return end
    base.storage = base.storage or {}
    local area = base.territory or base.home
    local cell = getCell ~= nil and getCell() or nil
    if area == nil or cell == nil then return end
    local minX = tonumber(area.minX) or 0
    local minY = tonumber(area.minY) or 0
    local maxX = tonumber(area.maxX) or (minX + math.max(1, tonumber(area.width) or 1) - 1)
    local maxY = tonumber(area.maxY) or (minY + math.max(1, tonumber(area.height) or 1) - 1)
    local z = tonumber(area.z) or 0
    local found = {}
    for x = minX, maxX do
        for y = minY, maxY do
            local square = cell:getGridSquare(x, y, z)
            local objects = square ~= nil and square:getObjects() or nil
            if objects ~= nil then
                for objectIndex = 0, objects:size() - 1 do
                    local object = objects:get(objectIndex)
                    local count = object ~= nil and object:getContainerCount() or 0
                    for containerIndex = 0, count - 1 do
                        local container = object:getContainerByIndex(containerIndex)
                        local kind = container ~= nil and string.lower(tostring(container:getType() or "")) or ""
                        if container ~= nil and kind ~= "corpse" then
                            found[#found + 1] = {
                                object = object,
                                containerIndex = containerIndex,
                                kind = kind,
                            }
                        end
                    end
                end
            end
        end
    end
    for _, entry in ipairs(found) do
        if base.toolCupboardKey == nil and KnoxToolCupboard ~= nil then
            KnoxToolCupboard.designate(base, entry.object, entry.containerIndex, BaseManager)
        end
        if base.toolCupboardKey ~= nil then return end
    end
end

function BaseManager.get(id)
    return KnoxPersistence.getBase(id)
end

function BaseManager.getForOwner(ownerKind, ownerId)
    return KnoxPersistence.getBaseForOwner(ownerKind, ownerId)
end

function BaseManager.establishPlayerBase(player, square)
    if player == nil or square == nil then
        return nil, "invalid_location"
    end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local area = areaFromBuilding(square:getBuilding(), square)
    if area == nil then
        return nil, "must_be_inside_building"
    end
    local existing = BaseManager.getForOwner("player", playerId)
    if existing ~= nil then
        return existing, existing.home ~= nil and existing.home.buildingId == area.buildingId
            and "existing" or "move_confirmation_required"
    end
    local territory = territoryAround(area, PLAYER_BASE_YARD_PADDING)
    if blockedBySurvivorSafehouse(territory) then
        return nil, "claimed_by_survivor_faction"
    end
    local base, result = KnoxPersistence.createBase(
        "player",
        playerId,
        area,
        worldAge(),
        territory
    )
    if base ~= nil then
        local faction = KnoxPersistence.ensurePlayerFaction(playerId, worldAge())
        faction.homeBaseId = base.id
        BaseManager.syncStructureProtection()
    end
    return base, result
end

function BaseManager.movePlayerBase(player, square)
    if player == nil or square == nil then return nil, "invalid_location" end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local base = BaseManager.getForOwner("player", playerId)
    if base == nil then return BaseManager.establishPlayerBase(player, square) end
    local area = areaFromBuilding(square:getBuilding(), square)
    if area == nil then return nil, "must_be_inside_building" end
    if base.home ~= nil and base.home.buildingId == area.buildingId then
        return base, "existing"
    end
    local territory = territoryAround(area, PLAYER_BASE_YARD_PADDING)
    if blockedBySurvivorSafehouse(territory) then
        return nil, "claimed_by_survivor_faction"
    end
    local moved, result = KnoxPersistence.relocateBase(base.id, area, territory, worldAge())
    if moved ~= nil then
        BaseManager.syncStructureProtection()
    end
    return moved, result
end

function BaseManager.ensureFactionBase(faction)
    if faction == nil or faction.kind == "player" or faction.homeBase == nil then
        return nil, "not_ready"
    end
    local base = faction.homeBaseId ~= nil
        and KnoxPersistence.getBase(faction.homeBaseId)
        or nil
    -- A stale save may retain a base id after ownership changed or the base
    -- was replaced. Never let an NPC faction adopt a player/other-faction
    -- record just because its id still exists; rebuild the faction-owned
    -- record from the persisted home definition instead.
    if base ~= nil and (base.ownerKind ~= "faction" or base.ownerId ~= faction.id) then
        print("[KnoxSurvivors][BaseManager] discarded-stale-faction-base="
            .. tostring(faction.homeBaseId) .. " faction=" .. tostring(faction.id))
        faction.homeBaseId = nil
        base = nil
    end
    local result = "existing"
    if base == nil then
        base, result = KnoxPersistence.createBase(
            "faction",
            faction.id,
            faction.homeBase,
            faction.homeBase.selectedAtHours or worldAge()
        )
        if base ~= nil then
            faction.homeBaseId = base.id
        end
    end
    if base ~= nil then
        -- Keep the settlement identity visible everywhere the player sees the
        -- property. Do not overwrite a name the player or a future UI has
        -- intentionally customized.
        if (base.name == nil or base.name == "" or base.name == "Survivor Camp")
            and type(faction.name) == "string" and faction.name ~= "" then
            base.name = faction.name .. " Base"
        end
        local hasDefenseZone = false
        for _, zone in pairs(base.zones or {}) do
            if zone ~= nil and (zone.type == "construction" or zone.type == "defense") then
                hasDefenseZone = true
                break
            end
        end
        if not hasDefenseZone then
            local territory = base.territory or base.home
            if territory ~= nil then
                -- Factions choose a modest perimeter one tile beyond their home. It
                -- only becomes real work when residents carry the normal materials.
                KnoxPersistence.addBaseZone(base.id, "construction", {
                    x1 = (tonumber(territory.minX) or 0) - 1,
                    y1 = (tonumber(territory.minY) or 0) - 1,
                    x2 = (tonumber(territory.maxX)
                        or ((tonumber(territory.minX) or 0)
                            + (tonumber(territory.width) or 1) - 1)) + 1,
                    y2 = (tonumber(territory.maxY)
                        or ((tonumber(territory.minY) or 0)
                            + (tonumber(territory.height) or 1) - 1)) + 1,
                    z = tonumber(territory.z) or 0,
                    priority = 75,
                }, "Defense Perimeter")
            end
        end
        if KnoxSettings.autoGenerateBaseWorkAreas() then
            ensureFactionZones(base)
            ensureFactionStorage(base)
        end
        for _, survivorId in ipairs(faction.memberIds or {}) do
            local resident, residentResult = KnoxPersistence.setFactionBaseResident(
                survivorId,
                faction.id,
                base.id,
                worldAge()
            )
            -- Base creation can happen while the leader is still active in the
            -- world. Notify that runtime immediately so it drops stale roaming
            -- or faction-scouting intent and begins resident duty on its next
            -- decision boundary. Persisted duty remains authoritative; this is
            -- only the in-memory handoff signal.
            if resident and residentResult ~= "existing"
                and KnoxSurvivorRuntime ~= nil
                and KnoxSurvivorRuntime.notifyDutyChanged ~= nil then
                KnoxSurvivorRuntime.notifyDutyChanged(survivorId)
            end
        end
    end
    return base, base ~= nil and result or "failed"
end

function BaseManager.ensureFactionBases()
    for _, faction in pairs(KnoxPersistence.getFactions()) do
        BaseManager.ensureFactionBase(faction)
    end
end

function BaseManager.ensurePlayerBases()
    -- Player work areas and storage policies are explicit choices made through
    -- the Notebook. Automatic planning is reserved for autonomous NPC bases.
end

function BaseManager.containsSquare(base, square)
    local home = base ~= nil and (base.territory or base.home) or nil
    if home == nil or square == nil then
        return false
    end
    local x = square:getX()
    local y = square:getY()
    local maxX = home.maxX or (home.minX + home.width - 1)
    local maxY = home.maxY or (home.minY + home.height - 1)
    local floorMatches = home.allFloors == true or square:getZ() == (home.z or 0)
    return floorMatches and x >= home.minX and x <= maxX
        and y >= home.minY and y <= maxY
end

function BaseManager.setTerritory(player, baseId, firstSquare, secondSquare)
    local base = BaseManager.get(baseId)
    local playerId = player ~= nil and KnoxPersistence.ensurePlayerId(player) or nil
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId
        or firstSquare == nil or secondSquare == nil then
        return nil, "not_your_base"
    end
    local territory, result = KnoxPersistence.updateBaseTerritory(baseId, {
        minX = firstSquare:getX(),
        minY = firstSquare:getY(),
        maxX = secondSquare:getX(),
        maxY = secondSquare:getY(),
    }, worldAge())
    if territory ~= nil then
        BaseManager.syncStructureProtection()
    end
    return territory, result
end

function BaseManager.playerBaseAtSquare(square)
    for _, base in pairs(KnoxPersistence.getBases()) do
        if base ~= nil and base.ownerKind == "player"
            and BaseManager.containsSquare(base, square) then
            return base
        end
    end
    return nil
end

function BaseManager.canDamageStructure(survivorId, square)
    local base = BaseManager.playerBaseAtSquare(square)
    if base == nil then
        return true
    end
    return KnoxPersistence.isSurvivorHostileToPlayer(
        survivorId,
        base.ownerId
    )
end

function BaseManager.syncStructureProtection()
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil or bridge.setNpcProtectedArea == nil then
        return
    end
    local protected = nil
    local protectedPlayerId = nil
    for _, base in pairs(KnoxPersistence.getBases()) do
        if base ~= nil and base.ownerKind == "player" then
            protected = base.territory or base.home
            protectedPlayerId = base.ownerId
            break
        end
    end
    for _, survivorId in ipairs(KnoxSurvivorRuntime.activeIds()) do
        if protected == nil or KnoxPersistence.isSurvivorHostileToPlayer(
                survivorId,
                protectedPlayerId
            ) then
            bridge:clearNpcProtectedArea(survivorId)
        else
            bridge:setNpcProtectedArea(
                survivorId,
                protected.minX,
                protected.minY,
                protected.maxX or (protected.minX + protected.width - 1),
                protected.maxY or (protected.minY + protected.height - 1)
            )
        end
    end
end

function BaseManager.addZone(baseId, zoneType, bounds, label)
    if BaseManager.ZONE_TYPES[zoneType] ~= true then
        return nil, "unknown_zone_type"
    end
    return KnoxPersistence.addBaseZone(baseId, zoneType, bounds, label)
end

function BaseManager.containerReference(object, requestedContainerIndex, baseId)
    local square = object ~= nil and object:getSquare() or nil
    local containerIndex = math.max(0, tonumber(requestedContainerIndex) or 0)
    local container = object ~= nil and object.getContainerByIndex ~= nil
        and object:getContainerByIndex(containerIndex)
        or (object ~= nil and object:getContainer() or nil)
    if square == nil or container == nil then
        return nil
    end
    local objectIndex = object:getObjectIndex()
    local containerType = tostring(container:getType() or "container")
    local marker = object:getModData()
    marker.KnoxSurvivors = marker.KnoxSurvivors or {}
    marker.KnoxSurvivors.storageIds = marker.KnoxSurvivors.storageIds or {}
    local markerKey = tostring(baseId or "unbound") .. ":" .. tostring(containerIndex)
    local stableId = marker.KnoxSurvivors.storageIds[markerKey]
    if type(stableId) ~= "string" or stableId == "" then
        stableId = tostring(baseId or "base") .. ":container:"
            .. tostring(square:getX()) .. ":" .. tostring(square:getY())
            .. ":" .. tostring(square:getZ()) .. ":" .. tostring(objectIndex)
            .. ":" .. tostring(containerIndex)
        marker.KnoxSurvivors.storageIds[markerKey] = stableId
        if object.transmitModData ~= nil then
            object:transmitModData()
        end
    end
    return {
        key = stableId,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = objectIndex,
        containerIndex = containerIndex,
        containerType = containerType,
    }
end

function BaseManager.setStoragePolicy(baseId, object, category, containerIndex)
    local base = KnoxPersistence.getBase(baseId)
    if base ~= nil and base.toolCupboardKey ~= nil then
        local current = BaseManager.containerReference(object, containerIndex, baseId)
        if current ~= nil and current.key == base.toolCupboardKey then category = "depot" end
    end
    if BaseManager.STORAGE_CATEGORIES[category] ~= true then
        return nil, "unknown_storage_category"
    end
    local reference = BaseManager.containerReference(object, containerIndex, baseId)
    if reference == nil then
        return nil, "not_a_container"
    end
    return KnoxPersistence.setBaseStoragePolicy(
        baseId,
        reference,
        category,
        category == "depot"
    )
end

local function findTraitDefinition(id)
    local definitions = CharacterTraitDefinition.getTraits()
    for index = 0, definitions:size() - 1 do
        local definition = definitions:get(index)
        if definition ~= nil and tostring(definition:getType()) == id then
            return definition
        end
    end
    return nil
end

local function meetsRequirements(survivorId, profile, requirements, base)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    for perkId, required in pairs(requirements ~= nil and requirements.skills or {}) do
        local level = KnoxSurvivorCapabilities.skillLevel(profile, perkId)
        local perk = character ~= nil and Perks.FromString(perkId) or nil
        if perk ~= nil then
            level = character:getPerkLevel(perk)
        end
        if level < (tonumber(required) or 0) then
            return false, "skill=" .. tostring(perkId)
        end
    end
    for _, traitId in ipairs(requirements ~= nil and requirements.traits or {}) do
        local hasTrait = KnoxSurvivorCapabilities.hasTrait(profile, traitId)
        local definition = character ~= nil and findTraitDefinition(traitId) or nil
        if definition ~= nil then
            hasTrait = character:hasTrait(definition:getType())
        end
        if not hasTrait then
            return false, "trait=" .. tostring(traitId)
        end
    end
    for _, recipeId in ipairs(requirements ~= nil and requirements.recipes or {}) do
        if character == nil or not character:getKnownRecipes():contains(recipeId) then
            return false, "recipe=" .. tostring(recipeId)
        end
    end
    local available, reason = KnoxBaseStorage.requirementsAvailable(
        base,
        character,
        requirements
    )
    return available, available and "eligible" or reason
end

function BaseManager.canPerformTask(survivorId, baseId, task)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil then
        return false, "base_missing"
    end
    local duty = KnoxPersistence.getSurvivorDuty(survivorId)
    if duty == nil or duty.mode ~= "base" or duty.baseId ~= baseId then
        return false, "not_base_resident"
    end
    local profile = KnoxPersistence.getSurvivorCapabilities(survivorId)
    if profile == nil then
        return false, "capabilities_missing"
    end
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if character == nil or not BaseManager.containsSquare(base, character:getCurrentSquare()) then
        return false, "not_physically_at_base"
    end
    return meetsRequirements(
        survivorId,
        profile,
        task ~= nil and task.requirements or nil,
        base
    )
end

local function onGameStart()
    BaseManager.ensureFactionBases()
    BaseManager.ensurePlayerBases()
    BaseManager.syncStructureProtection()
end

Events.OnGameStart.Add(onGameStart)

return BaseManager
