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
    cooking = true,
    woodcutting = true,
    log_processing = true,
    guard = true,
    patrol = true,
    corpse = true,
    repair = true,
    general = true,
}

BaseManager.STORAGE_CATEGORIES = {
    food = true,
    water = true,
    medical = true,
    weapons = true,
    ammunition = true,
    tools = true,
    logs = true,
    general = true,
    building = true,
    farming = true,
    clothing = true,
    junk = true,
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

local function ensureFactionZone(base, zoneType, bounds, label, count)
    if countZoneType(base, zoneType) < (count or 1) and bounds ~= nil then
        return KnoxPersistence.addBaseZone(base.id, zoneType, bounds, label)
    end
    return nil, "existing"
end

local function findOutdoorSquare(area, preferredDistance, accepts)
    local cell = getCell ~= nil and getCell() or nil
    if cell == nil or area == nil then return nil end
    local centerX = math.floor((tonumber(area.minX) or 0)
        + math.max(1, tonumber(area.width)
            or ((tonumber(area.maxX) or area.minX) - area.minX + 1)) / 2)
    local centerY = math.floor((tonumber(area.minY) or 0)
        + math.max(1, tonumber(area.height)
            or ((tonumber(area.maxY) or area.minY) - area.minY + 1)) / 2)
    local z = tonumber(area.z) or 0
    for radius = math.max(2, tonumber(preferredDistance) or 2), 18 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local square = cell:getGridSquare(centerX + dx, centerY + dy, z)
                if square ~= nil and square:canStand() and square:getRoom() == nil
                    and (accepts == nil or accepts(square)) then
                    return square
                end
            end
        end
        for dy = -radius + 1, radius - 1 do
            for _, dx in ipairs({ -radius, radius }) do
                local square = cell:getGridSquare(centerX + dx, centerY + dy, z)
                if square ~= nil and square:canStand() and square:getRoom() == nil
                    and (accepts == nil or accepts(square)) then
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
        }, "Outer Patrol", 2)
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
        }, "Outer Watch", 2)
    end
    -- Structure repair scans the owned territory directly; it does not need a
    -- second full-base work-area overlay. Construction areas were removed.
    local work = not hasZoneType(base, "farming") and findOutdoorSquare(area, 4, function(square)
        if ISFarmingMenu == nil or ISFarmingMenu.canDigHereSquare == nil then return false end
        local ok, diggable = pcall(ISFarmingMenu.canDigHereSquare, square)
        return ok and diggable == true
    end) or nil
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
        -- own durable work area. Offset east so exclusive production areas do
        -- not share tiles; the executor distinguishes the two.
        ensureFactionZone(base, "log_processing", {
            x1 = outer:getX() + 7, y1 = outer:getY() - 2,
            x2 = outer:getX() + 11, y2 = outer:getY() + 2,
            z = outer:getZ(), priority = 70,
        }, "Log Processing")
        -- Corpse drop sits west of the wood lot for the same exclusivity reason.
        ensureFactionZone(base, "corpse", {
            x1 = outer:getX() - 10, y1 = outer:getY() - 1,
            x2 = outer:getX() - 8, y2 = outer:getY() + 1,
            z = outer:getZ(), priority = 91,
        }, "Corpse Drop")
    end
end

-- Faction storage helpers: a role is covered when any assigned policy serves
-- it, and container kinds map to roles by what those containers hold in the
-- world (cupboards/counters hold tools, crates/shelves hold materials).
local function storageRoleAssigned(base, role)
    for _, policy in pairs(base ~= nil and base.storage or {}) do
        if policy ~= nil and tostring(policy.storageRole or policy.key) == role then
            return true
        end
    end
    return false
end

local function containerFitsFactionRole(kind, role)
    kind = string.lower(tostring(kind or ""))
    if role == "tools" then
        return kind:find("cupboard", 1, true) ~= nil
            or kind:find("counter", 1, true) ~= nil
            or kind:find("drawer", 1, true) ~= nil
            or kind:find("locker", 1, true) ~= nil
            or kind:find("cabinet", 1, true) ~= nil
    end
    if role == "building" then
        return kind:find("crate", 1, true) ~= nil
            or kind:find("shelf", 1, true) ~= nil
            or kind:find("pallet", 1, true) ~= nil
    end
    if role == "logs" then
        return kind:find("woodpile", 1, true) ~= nil
            or kind:find("pallet", 1, true) ~= nil
            or kind:find("crate", 1, true) ~= nil
    end
    return false
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
        if entry.kind:find("fridge", 1, true) or entry.kind:find("freezer", 1, true) then
            local reference = BaseManager.containerReference(entry.object, entry.containerIndex, base.id)
            if reference ~= nil and base.storage[reference.key] == nil then
                BaseManager.setStoragePolicy(base.id, entry.object, "food", entry.containerIndex)
            end
        end
        -- Main Supplies auto-designation retired: typed storages are explicit.
    end
    -- Faction upkeep needs the same typed stores a player assigns by hand:
    -- without a tools/materials cupboard, barricade/repair/woodcutting tasks
    -- can never leave the supply-wait state. Designate from real world
    -- containers only; map loot and resident scavenging fill them.
    local roles = { "tools", "building", "logs" }
    for _, role in ipairs(roles) do
        if not storageRoleAssigned(base, role) then
            for _, entry in ipairs(found) do
                if containerFitsFactionRole(entry.kind, role) then
                    local reference = BaseManager.containerReference(
                        entry.object, entry.containerIndex, base.id)
                    if reference ~= nil and base.storage[reference.key] == nil then
                        BaseManager.setStoragePolicy(
                            base.id, entry.object, role, entry.containerIndex)
                        break
                    end
                end
            end
        end
    end
    -- Houses without a refrigerator still need a pantry. Fill uncovered
    -- categories from remaining real dry containers without reassigning any
    -- existing player or faction policy. Separate roles are optional capacity.
    for _, role in ipairs({ "food", "water", "tools", "logs", "building", "medical",
        "farming", "weapons", "ammunition", "clothing", "junk" }) do
        if not storageRoleAssigned(base, role) then
            for _, entry in ipairs(found) do
                if KnoxToolCupboard ~= nil and KnoxToolCupboard.isDryContainerType ~= nil
                    and KnoxToolCupboard.isDryContainerType(entry.kind) then
                    local reference = BaseManager.containerReference(entry.object, entry.containerIndex, base.id)
                    if reference ~= nil and base.storage[reference.key] == nil then
                        local policy = BaseManager.setStoragePolicy(base.id, entry.object, role, entry.containerIndex)
                        if policy ~= nil then break end
                    end
                end
            end
        end
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

-- Additional player base (outpost) in another building. The primary home
-- base is untouched: faction home, move flow and every singular getter
-- keep resolving to the earliest base. Territory overlap and faction
-- claims are enforced exactly like the first home.
function BaseManager.establishOutpost(player, square)
    if player == nil or square == nil then
        return nil, "invalid_location"
    end
    local playerId = KnoxPersistence.ensurePlayerId(player)
    local area = areaFromBuilding(square:getBuilding(), square)
    if area == nil then
        return nil, "must_be_inside_building"
    end
    local owned = KnoxPersistence.getBasesForOwner ~= nil
        and KnoxPersistence.getBasesForOwner("player", playerId) or {}
    for _, other in ipairs(owned) do
        if other ~= nil and other.home ~= nil
            and other.home.buildingId == area.buildingId then
            return other, "existing"
        end
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
        territory,
        true
    )
    if base == nil then return nil, result end
    base.name = "Outpost " .. tostring(#owned + 1)
    BaseManager.syncStructureProtection()
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
    if base == nil or object == nil or not BaseManager.containsSquare(base, object:getSquare()) then
        return nil, "outside_base"
    end
    if category == "depot" then return nil, "main_supplies_retired" end
    if BaseManager.STORAGE_CATEGORIES[category] ~= true then return nil, "unknown_storage_category" end
    local reference = BaseManager.containerReference(object, containerIndex, baseId)
    if reference == nil then return nil, "not_a_container" end
    local kind = string.lower(reference.containerType)
    if kind == "corpse" or kind:find("water", 1, true) or kind:find("rain", 1, true) then
        return nil, "use_item_storage"
    end
    -- Normalize legacy references before adding an explicit store.
    KnoxBaseStorage.policies(base)
    local policy, result = KnoxPersistence.setBaseStoragePolicy(baseId, reference, category, false)
    if policy ~= nil then
        -- Mirror the assigned type onto the world container for organization,
        -- and grant infinite weight (native max + bypass markers).
        local container = object.getContainerByIndex ~= nil
            and object:getContainerByIndex(tonumber(containerIndex) or 0) or nil
        if container ~= nil then
            if KnoxBaseStorage.syncContainerName ~= nil then
                KnoxBaseStorage.syncContainerName(policy, container)
            end
            if KnoxToolCupboard ~= nil and KnoxToolCupboard.applyInfinite ~= nil then
                pcall(function()
                    KnoxToolCupboard.applyInfinite(object, container, policy.key)
                end)
            end
        end
    end
    return policy, result
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
    local square=character~=nil and character:getCurrentSquare() or nil
    local jobs=rawget(_G,"KnoxBaseJobs")
    local atWork=square~=nil and jobs~=nil and jobs.containsWorkSquare~=nil
        and jobs.containsWorkSquare(base,square)
    if square==nil or (not BaseManager.containsSquare(base,square) and not atWork) then
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
    if KnoxPersistence.applyBaseDoorLocks ~= nil then
        pcall(function() KnoxPersistence.applyBaseDoorLocks() end)
    end
end

Events.OnGameStart.Add(onGameStart)

return BaseManager
