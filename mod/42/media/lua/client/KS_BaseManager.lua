require "KS_Persistence"
require "KS_SurvivorCapabilities"
require "KS_SurvivorRuntime"
require "KS_BaseStorage"

local BaseManager = rawget(_G, "KnoxBaseManager") or {}
_G.KnoxBaseManager = BaseManager

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

local function hasZoneType(base, zoneType)
    for _, zone in pairs(base ~= nil and base.zones or {}) do
        if zone ~= nil and zone.enabled ~= false and zone.type == zoneType then
            return true
        end
    end
    return false
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
    local guardX = math.floor(tonumber(area.x) or ((minX + maxX) / 2))
    local guardY = math.floor(tonumber(area.y) or ((minY + maxY) / 2))
    ensureFactionZone(base, "guard", {
        x1 = guardX - 1, y1 = guardY - 1,
        x2 = guardX + 1, y2 = guardY + 1, z = z, priority = 84,
    }, "Entry Watch")
    ensureFactionZone(base, "repair", {
        x1 = minX, y1 = minY, x2 = maxX, y2 = maxY, z = z, priority = 88,
    }, "Home Maintenance")
    local work = findOutdoorSquare(area, 3)
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
        ensureFactionZone(base, "corpse", {
            x1 = outer:getX() - 1, y1 = outer:getY() - 1,
            x2 = outer:getX() + 1, y2 = outer:getY() + 1,
            z = outer:getZ(), priority = 91,
        }, "Corpse Drop")
    end
end

local function ensureFactionStorage(base)
    if base == nil or next(base.storage or {}) ~= nil then return end
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
    local fallback = { "depot", "tools", "building", "weapons", "medical", "farming", "clothing" }
    for index, entry in ipairs(found) do
        local category = string.find(entry.kind, "fridge", 1, true) and "food"
            or string.find(entry.kind, "freezer", 1, true) and "food"
            or string.find(entry.kind, "medicine", 1, true) and "medical"
            or string.find(entry.kind, "wardrobe", 1, true) and "clothing"
            or fallback[math.min(index, #fallback)]
        BaseManager.setStoragePolicy(base.id, entry.object, category, entry.containerIndex)
        if index >= 9 then return end
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
    local existing = BaseManager.getForOwner("player", playerId)
    if existing ~= nil then
        return existing, "existing"
    end
    local area = areaFromBuilding(square:getBuilding(), square)
    if area == nil then
        return nil, "must_be_inside_building"
    end
    local overlapping = SafeHouse ~= nil and SafeHouse.getSafehouseOverlapping(
        area.minX,
        area.minY,
        area.minX + area.width,
        area.minY + area.height
    ) or nil
    if overlapping ~= nil then
        local owner = tostring(overlapping:getOwner() or "")
        if string.find(owner, "KnoxSurvivors:", 1, true) == 1 then
            return nil, "claimed_by_survivor_faction"
        end
    end
    local base, result = KnoxPersistence.createBase(
        "player",
        playerId,
        area,
        worldAge()
    )
    if base ~= nil then
        local faction = KnoxPersistence.ensurePlayerFaction(playerId, worldAge())
        faction.homeBaseId = base.id
        BaseManager.syncStructureProtection()
    end
    return base, result
end

function BaseManager.ensureFactionBase(faction)
    if faction == nil or faction.kind == "player" or faction.homeBase == nil then
        return nil, "not_ready"
    end
    local base = faction.homeBaseId ~= nil
        and KnoxPersistence.getBase(faction.homeBaseId)
        or nil
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
        ensureFactionZones(base)
        ensureFactionStorage(base)
        for _, survivorId in ipairs(faction.memberIds or {}) do
            KnoxPersistence.setFactionBaseResident(
                survivorId,
                faction.id,
                base.id,
                worldAge()
            )
        end
    end
    return base, base ~= nil and result or "failed"
end

function BaseManager.ensureFactionBases()
    for _, faction in pairs(KnoxPersistence.getFactions()) do
        BaseManager.ensureFactionBase(faction)
    end
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
    BaseManager.syncStructureProtection()
end

Events.OnGameStart.Add(onGameStart)

return BaseManager
