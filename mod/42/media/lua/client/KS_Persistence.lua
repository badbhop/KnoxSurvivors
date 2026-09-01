local KnoxPersistence = rawget(_G, "KnoxPersistence") or {}
_G.KnoxPersistence = KnoxPersistence

-- Kept separate from the legacy IsoZombie mod data that may exist in reused saves.
local MOD_DATA_KEY = "KnoxSurvivors_IsoPlayer"
local SCHEMA_VERSION = 14
local TEST_SURVIVOR_ID = "ks-test-1"

local FACTION_NAME_STYLES = {
    function(name) return "The " .. name .. " Group" end,
    function(name) return name .. "'s People" end,
    function(name) return "The " .. name .. " Crew" end,
    function(name) return name .. "'s Outfit" end,
}

local function stableFactionName(data, factionId, faction)
    if faction ~= nil and type(faction.name) == "string" and faction.name ~= "" then
        return faction.name
    end
    if faction ~= nil and faction.kind == "player" then return "Your Group" end
    local identity = faction ~= nil and faction.leaderId ~= nil
        and data.survivors[faction.leaderId] ~= nil
        and data.survivors[faction.leaderId].identity or nil
    local leaderName = identity ~= nil and tostring(identity.surname or "") or ""
    if leaderName == "" and identity ~= nil then leaderName = tostring(identity.forename or "") end
    if leaderName == "" then
        return "Survivor Group " .. tostring((tostring(factionId):match("(%d+)$")) or "")
    end
    local hash = 0
    for index = 1, #tostring(factionId) do
        hash = (hash * 31 + string.byte(tostring(factionId), index)) % 2147483647
    end
    return FACTION_NAME_STYLES[(hash % #FACTION_NAME_STYLES) + 1](leaderName)
end

-- Companion directives originate from UI ground selections and survive save/load.
-- Keep their validation at the persistence boundary so a corrupted or stale
-- selection cannot become a permanent controller command after restoration.
local function finiteCoordinate(value)
    value = tonumber(value)
    return value ~= nil and value == value and math.abs(value) <= 1000000
end

function KnoxPersistence.isValidCompanionDirective(directive)
    if type(directive) ~= "table" then
        return false
    end
    local kind = tostring(directive.kind or "")
    if kind ~= "loot_area" and kind ~= "loot_building"
        and kind ~= "loot_corpses" and kind ~= "go_to" and kind ~= "guard" then
        return false
    end
    local minX, minY = tonumber(directive.minX), tonumber(directive.minY)
    local maxX = tonumber(directive.maxX) or minX
    local maxY = tonumber(directive.maxY) or minY
    local z = tonumber(directive.z) or 0
    return finiteCoordinate(minX) and finiteCoordinate(minY)
        and finiteCoordinate(maxX) and finiteCoordinate(maxY) and finiteCoordinate(z)
        and minX <= maxX and minY <= maxY
end

local function root()
    local data = ModData.getOrCreate(MOD_DATA_KEY)
    local previousVersion = tonumber(data.schemaVersion) or 0
    if type(data.survivors) ~= "table" then
        data.survivors = {}
    end
    if type(data.relationships) ~= "table" then
        data.relationships = {}
    end
    if type(data.travelGroups) ~= "table" then
        data.travelGroups = {}
    end
    data.nextTravelGroupId = data.nextTravelGroupId or 1
    if type(data.factions) ~= "table" then
        data.factions = {}
    end
    -- Faction disposition is deliberately a separate, symmetric domain.  A
    -- survivor's affiliation answers "who owns this person"; this table
    -- answers "how do those two owners relate".  Keeping that boundary avoids
    -- turning a single encounter flag into permanent base-damage permission.
    if type(data.factionRelationships) ~= "table" then
        data.factionRelationships = {}
    end
    data.nextFactionId = data.nextFactionId or 1
    if type(data.camps) ~= "table" then
        data.camps = {}
    end
    data.nextCampId = tonumber(data.nextCampId) or 1
    if type(data.awayTeams) ~= "table" then
        data.awayTeams = {}
    end
    data.nextAwayTeamId = tonumber(data.nextAwayTeamId) or 1
    if type(data.knoxEvents) ~= "table" then data.knoxEvents = {} end
    if type(data.knoxEvents.records) ~= "table" then data.knoxEvents.records = {} end
    if type(data.knoxEvents.cooldowns) ~= "table" then data.knoxEvents.cooldowns = {} end
    if type(data.knoxEvents.automatic) ~= "table" then data.knoxEvents.automatic = {} end
    local automaticNext = tonumber(data.knoxEvents.automatic.nextCheckHours)
    local automaticCursor = tonumber(data.knoxEvents.automatic.cursor)
    data.knoxEvents.automatic.nextCheckHours = finiteCoordinate(automaticNext)
        and automaticNext >= 0 and automaticNext or 0
    data.knoxEvents.automatic.cursor = finiteCoordinate(automaticCursor)
        and automaticCursor >= 0 and math.floor(automaticCursor) or 0
    data.knoxEvents.nextId = tonumber(data.knoxEvents.nextId) or 1
    if type(data.players) ~= "table" then
        data.players = {}
    end
    data.nextPlayerId = data.nextPlayerId or 1
    data.nextDeveloperSurvivorId = data.nextDeveloperSurvivorId or 1
    data.nextWorldSurvivorId = data.nextWorldSurvivorId or 1
    if type(data.population) ~= "table" then
        data.population = {}
    end
    data.population.initialized = data.population.initialized == true
    data.population.nextRefillHours = tonumber(data.population.nextRefillHours) or 0
    data.population.lastTarget = tonumber(data.population.lastTarget) or 0
    data.population.belowTargetSinceHours = tonumber(
        data.population.belowTargetSinceHours
    )
    data.population.allocationCursor = math.max(
        0,
        math.floor(tonumber(data.population.allocationCursor) or 0)
    )
    if type(data.bases) ~= "table" then
        data.bases = {}
    end
    data.nextBaseId = data.nextBaseId or 1
    for _, base in pairs(data.bases) do
        if type(base) == "table" then
            base.zones = type(base.zones) == "table" and base.zones or {}
            base.nextZoneId = tonumber(base.nextZoneId) or 1
            base.storage = type(base.storage) == "table" and base.storage or {}
            base.tasks = type(base.tasks) == "table" and base.tasks or {}
            base.nextTaskId = tonumber(base.nextTaskId) or 1
            base.settings = type(base.settings) == "table" and base.settings or {}
            if base.settings.automaticJobs == nil then
                base.settings.automaticJobs = true
            end
            if base.settings.allowWorkOutsideHome == nil then
                base.settings.allowWorkOutsideHome = true
            end
        end
    end
    if data.domainV7Migrated ~= true then
        -- Older saves inferred membership from travel groups and faction copies.
        -- Materialize that ownership once so recruitment can never mistake an
        -- established faction member for an independent survivor.
        for factionId, faction in pairs(data.factions) do
            if type(faction) == "table" then
                faction.kind = faction.kind or "npc"
                faction.memberIds = faction.memberIds or {}
                for _, survivorId in ipairs(faction.memberIds) do
                    local survivor = data.survivors[survivorId] or { id = survivorId }
                    survivor.affiliation = {
                        kind = faction.kind == "player" and "player" or "faction",
                        ownerId = faction.ownerPlayerId,
                        factionId = factionId,
                        migratedAtSchema = 7,
                    }
                    survivor.duty = survivor.duty or {
                        mode = faction.kind == "player" and "companion" or "autonomous",
                        order = faction.kind == "player" and "follow" or "survive",
                        ownerId = faction.ownerPlayerId,
                        revision = 0,
                    }
                    survivor.playerRelationships = survivor.playerRelationships or {}
                    data.survivors[survivorId] = survivor
                end
            end
        end
        for _, group in pairs(data.travelGroups) do
            local faction = type(group) == "table" and group.factionId ~= nil
                and data.factions[group.factionId]
                or nil
            if faction ~= nil then
                faction.memberIds = faction.memberIds or {}
                for _, survivorId in ipairs(group.memberIds or {}) do
                    local found = false
                    for _, memberId in ipairs(faction.memberIds) do
                        if memberId == survivorId then
                            found = true
                            break
                        end
                    end
                    if not found then
                        faction.memberIds[#faction.memberIds + 1] = survivorId
                    end
                    local survivor = data.survivors[survivorId] or { id = survivorId }
                    survivor.affiliation = {
                        kind = faction.kind == "player" and "player" or "faction",
                        ownerId = faction.kind == "player" and faction.ownerPlayerId or nil,
                        factionId = faction.id,
                        migratedAtSchema = 7,
                    }
                    survivor.duty = survivor.duty or {
                        mode = faction.kind == "player" and "companion" or "autonomous",
                        order = faction.kind == "player" and "follow" or "survive",
                        ownerId = faction.kind == "player" and faction.ownerPlayerId or nil,
                        revision = 0,
                    }
                    survivor.playerRelationships = survivor.playerRelationships or {}
                    data.survivors[survivorId] = survivor
                end
                table.sort(faction.memberIds)
            end
        end
        data.domainV7Migrated = true
    end
    -- Names are saved once so a faction keeps its identity even if leadership
    -- changes later. Existing saves receive a deterministic name on migration.
    for factionId, faction in pairs(data.factions) do
        if type(faction) == "table" and (type(faction.name) ~= "string" or faction.name == "") then
            faction.name = stableFactionName(data, factionId, faction)
        end
    end
    -- Rebuild schemas 1 and 2 already stored compatible encoded survivor records.
    -- Add newer domain tables in place instead of erasing people on a version bump.
    if previousVersion < SCHEMA_VERSION then
        data.migratedFromSchema = previousVersion
    end
    data.schemaVersion = SCHEMA_VERSION
    return data
end

local AWAY_MISSION_TYPES = {
    scout = true,
    food = true,
    medicine = true,
    weapons = true,
    tools = true,
    building = true,
}

local function copyFlat(source)
    local copied = {}
    for key, value in pairs(source or {}) do
        copied[key] = value
    end
    return copied
end

local function copySerializable(source, depth)
    if type(source) ~= "table" then
        return source
    end
    if (depth or 0) >= 6 then
        return nil
    end
    local copied = {}
    for key, value in pairs(source) do
        local keyType = type(key)
        local valueType = type(value)
        if (keyType == "string" or keyType == "number")
            and (valueType == "string" or valueType == "number"
                or valueType == "boolean" or valueType == "table") then
            copied[key] = copySerializable(value, (depth or 0) + 1)
        end
    end
    return copied
end

local function ensureSurvivorState(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    local data = root()
    local survivor = data.survivors[id] or { id = id }
    survivor.affiliation = survivor.affiliation or {
        kind = "independent",
        ownerId = nil,
    }
    survivor.duty = survivor.duty or {
        mode = "autonomous",
        order = "survive",
        revision = 0,
    }
    -- Older saves predate companion stances. Normalize the persisted value at
    -- the identity boundary so every controller sync starts from a deliberate
    -- defensive default instead of treating nil as an implicit attack order.
    if survivor.duty.mode == "companion" then
        local stance = survivor.duty.combatStance
        if stance ~= "passive" and stance ~= "aggressive" and stance ~= "defensive" then
            survivor.duty.combatStance = "defensive"
        end
        survivor.duty.order = survivor.duty.order == "hold" and "hold" or "follow"
    end
    survivor.playerRelationships = survivor.playerRelationships or {}
    survivor.policies = survivor.policies or {
        allowClimbing = true,
    }
    local weaponPreference = survivor.policies.weaponPreference
    if weaponPreference ~= "melee" and weaponPreference ~= "ranged" and weaponPreference ~= "auto" then
        survivor.policies.weaponPreference = "auto"
    end
    if survivor.alive == nil then
        survivor.alive = true
    end
    data.survivors[id] = survivor
    return survivor
end

local function requeueClaimsForSurvivor(id, baseId, reason)
    local requeued = 0
    for _, base in pairs(root().bases) do
        if baseId == nil or base.id == baseId then
            for _, task in pairs(base.tasks or {}) do
                if task.state == "claimed" and task.claimedBy == id then
                    task.state = "queued"
                    task.lastClaimedBy = task.claimedBy
                    task.claimedBy = nil
                    task.claimedAtHours = nil
                    task.interruptedReason = tostring(reason or "duty_changed")
                    requeued = requeued + 1
                end
            end
        end
    end
    return requeued
end

function KnoxPersistence.requeueBaseTasksForSurvivor(id, baseId, reason)
    if type(id) ~= "string" or id == "" then
        return 0
    end
    return requeueClaimsForSurvivor(id, baseId, reason)
end

local function relationshipKey(firstId, secondId)
    if type(firstId) ~= "string" or firstId == ""
        or type(secondId) ~= "string" or secondId == "" or firstId == secondId then
        return nil
    end
    if firstId < secondId then
        return firstId .. "::" .. secondId, firstId, secondId
    end
    return secondId .. "::" .. firstId, secondId, firstId
end

local function stableTrait(id, salt)
    local value = 17 + salt * 31
    for index = 1, #id do
        value = (value * 33 + string.byte(id, index)) % 10007
    end
    return value % 101
end

function KnoxPersistence.getTestRecord()
    return KnoxPersistence.getRecord(TEST_SURVIVOR_ID)
end

function KnoxPersistence.getRecord(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and survivor.record or nil
end

function KnoxPersistence.allocateDeveloperSurvivorId()
    local data = root()
    local value = math.max(1, tonumber(data.nextDeveloperSurvivorId) or 1)
    local id = "ks-dev-" .. tostring(value)
    while data.survivors[id] ~= nil do
        value = value + 1
        id = "ks-dev-" .. tostring(value)
    end
    data.nextDeveloperSurvivorId = value + 1
    return id
end

function KnoxPersistence.allocateWorldSurvivor(origin, worldAgeHours)
    if type(origin) ~= "table" or tonumber(origin.x) == nil or tonumber(origin.y) == nil then
        return nil, "invalid_origin"
    end
    local data = root()
    local x = math.floor(tonumber(origin.x))
    local y = math.floor(tonumber(origin.y))
    local z = math.floor(tonumber(origin.z) or 0)
    local originKey = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
    for _, existing in pairs(data.survivors) do
        local existingOrigin = type(existing) == "table" and existing.origin or nil
        if existing ~= nil and existing.populationManaged == true
            and type(existingOrigin) == "table" then
            local existingKey = existingOrigin.key
                or (tostring(math.floor(tonumber(existingOrigin.x) or 0))
                    .. "," .. tostring(math.floor(tonumber(existingOrigin.y) or 0))
                    .. "," .. tostring(math.floor(tonumber(existingOrigin.z) or 0)))
            existingOrigin.key = existingKey
            if existingKey == originKey then
                return nil, "origin_already_used"
            end
        end
    end
    local value = math.max(1, tonumber(data.nextWorldSurvivorId) or 1)
    local id = "ks-world-" .. tostring(value)
    while data.survivors[id] ~= nil do
        value = value + 1
        id = "ks-world-" .. tostring(value)
    end
    data.nextWorldSurvivorId = value + 1
    local survivor = ensureSurvivorState(id)
    survivor.populationManaged = true
    survivor.alive = true
    survivor.origin = {
        x = x,
        y = y,
        z = z,
        key = originKey,
        region = tostring(origin.region or "Unknown"),
        regionKey = tostring(origin.regionKey or origin.region or "Unknown"),
        source = tostring(origin.source or "player_spawn"),
    }
    survivor.createdAtHours = tonumber(worldAgeHours) or 0
    survivor.unloadedSurvival = {
        pendingMaterialization = true, status = "unmaterialized", activity = "origin_shelter",
        virtualX = x, virtualY = y, virtualZ = z,
        lastHours = survivor.createdAtHours, virtualAtHours = survivor.createdAtHours,
        currentTravelKey = originKey,
        departAtHours = survivor.createdAtHours + 1 + value % 4,
    }
    return id, copyFlat(survivor.origin)
end

function KnoxPersistence.getPopulationState()
    return root().population
end

-- Like population state, this domain is mutated by its one owning service.
-- Event records reference canonical survivors/factions, never encoded actor copies.
function KnoxPersistence.getKnoxEventState()
    return root().knoxEvents
end

function KnoxPersistence.getSurvivorOrigin(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and type(survivor.origin) == "table"
        and copyFlat(survivor.origin)
        or nil
end

function KnoxPersistence.getActivatableSurvivorIds()
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if type(id) == "string" and type(survivor) == "table"
            and survivor.alive ~= false
            and (survivor.record ~= nil or type(survivor.origin) == "table") then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.getLivingWorldSurvivorIds()
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if type(id) == "string" and type(survivor) == "table"
            and survivor.populationManaged == true and survivor.alive ~= false then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.getAllWorldSurvivorIds()
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if type(id) == "string" and type(survivor) == "table"
            and survivor.populationManaged == true then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.getUsedWorldOriginKeys()
    local used = {}
    for _, survivor in pairs(root().survivors) do
        local origin = type(survivor) == "table" and survivor.origin or nil
        if survivor ~= nil and survivor.populationManaged == true
            and type(origin) == "table"
            and tonumber(origin.x) ~= nil and tonumber(origin.y) ~= nil then
            local key = origin.key
                or (tostring(math.floor(tonumber(origin.x)))
                    .. "," .. tostring(math.floor(tonumber(origin.y)))
                    .. "," .. tostring(math.floor(tonumber(origin.z) or 0)))
            origin.key = key
            used[key] = true
        end
    end
    return used
end

function KnoxPersistence.markSurvivorDead(id, worldAgeHours, reason)
    local survivor = ensureSurvivorState(id)
    if survivor == nil then
        return false
    end
    survivor.alive = false
    survivor.diedAtHours = tonumber(worldAgeHours) or 0
    survivor.deathReason = tostring(reason or "died")
    if KnoxPersistence.removeSurvivorFromSocialDomains ~= nil then
        KnoxPersistence.removeSurvivorFromSocialDomains(id, "died", worldAgeHours)
    end
    return true
end

function KnoxPersistence.isSurvivorAlive(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and survivor.alive ~= false
end

function KnoxPersistence.getLastKnownNeeds(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and type(survivor.lastKnownNeeds) == "table"
        and copyFlat(survivor.lastKnownNeeds)
        or nil
end

function KnoxPersistence.getInventorySummary(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and tostring(survivor.inventorySummary or "") or ""
end

function KnoxPersistence.setInventorySummary(id, summary, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(summary) ~= "string" then
        return false
    end
    survivor.inventorySummary = summary
    survivor.inventorySummaryAtHours = tonumber(worldAgeHours) or 0
    return true
end

function KnoxPersistence.getUnloadedSurvivalState(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and type(survivor.unloadedSurvival) == "table"
        and copySerializable(survivor.unloadedSurvival)
        or nil
end

function KnoxPersistence.setUnloadedSurvivalState(id, state)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(state) ~= "table" then
        return false
    end
    survivor.unloadedSurvival = copySerializable(state)
    return survivor.unloadedSurvival ~= nil
end

function KnoxPersistence.setTestRecord(encoded)
    return KnoxPersistence.setRecord(TEST_SURVIVOR_ID, encoded)
end

function KnoxPersistence.setRecord(id, encoded)
    if type(id) ~= "string" or id == "" then
        return false
    end
    if type(encoded) ~= "string" or encoded == "" then
        return false
    end
    local survivor = root().survivors[id] or { id = id }
    survivor.record = encoded
    root().survivors[id] = survivor
    return true
end

function KnoxPersistence.ensureSurvivorIdentity(id, forename, surname, worldAgeHours, ageYears)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    local data = root()
    local survivor = data.survivors[id] or { id = id }
    survivor.identity = survivor.identity or {}
    -- Lua treats an empty string as truthy, so `saved or live` would preserve
    -- nameless identities forever. Fill missing/empty legacy fields from the
    -- live randomized SurvivorFactory descriptor when it becomes available.
    if survivor.identity.forename == nil or survivor.identity.forename == "" then
        survivor.identity.forename = tostring(forename or "")
    end
    if survivor.identity.surname == nil or survivor.identity.surname == "" then
        survivor.identity.surname = tostring(surname or "")
    end
    survivor.identity.createdAtHours = survivor.identity.createdAtHours
        or tonumber(worldAgeHours)
        or 0
    survivor.identity.ageYears = survivor.identity.ageYears
        or tonumber(ageYears)
        or (18 + stableTrait(id, 3) % 53)
    survivor.identity.sociability = survivor.identity.sociability
        or stableTrait(id, 1)
    survivor.identity.aggression = survivor.identity.aggression
        or stableTrait(id, 2)
    data.survivors[id] = survivor
    return survivor.identity
end

function KnoxPersistence.ensureSurvivorIdentityFromCharacter(id, character, worldAgeHours)
    if character == nil then
        return nil
    end
    local success, forename, surname, hoursSurvived = pcall(function()
        local descriptor = character:getDescriptor()
        return descriptor ~= nil and descriptor:getForename() or "",
            descriptor ~= nil and descriptor:getSurname() or "",
            character:getHoursSurvived()
    end)
    if not success then
        return nil
    end
    local now = tonumber(worldAgeHours) or 0
    local identity = KnoxPersistence.ensureSurvivorIdentity(
        id,
        forename,
        surname,
        math.max(0, now - math.max(0, tonumber(hoursSurvived) or 0)),
        nil
    )
    if identity ~= nil and tonumber(identity.ageYears) ~= nil then
        pcall(function()
            character:setAge(math.floor(tonumber(identity.ageYears)))
        end)
    end
    return identity
end

function KnoxPersistence.getSurvivorIdentity(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and survivor.identity or nil
end

function KnoxPersistence.getPlayerRelationshipSnapshot(playerId, survivorId)
    local survivor = type(survivorId) == "string" and root().survivors[survivorId] or nil
    local relation = survivor ~= nil and type(survivor.playerRelationships) == "table"
        and survivor.playerRelationships[playerId]
        or nil
    return relation ~= nil and copyFlat(relation) or nil
end

function KnoxPersistence.getSurvivorCapabilities(id)
    local survivor = ensureSurvivorState(id)
    return survivor ~= nil and survivor.capabilities or nil
end

function KnoxPersistence.setSurvivorCapabilities(id, capabilities)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(capabilities) ~= "table" then
        return false
    end
    survivor.capabilities = capabilities
    return true
end

function KnoxPersistence.getSurvivorAffiliation(id)
    local survivor = ensureSurvivorState(id)
    return survivor ~= nil and copyFlat(survivor.affiliation) or nil
end

function KnoxPersistence.getSurvivorDuty(id)
    local survivor = ensureSurvivorState(id)
    return survivor ~= nil and copyFlat(survivor.duty) or nil
end

-- Events borrow a base duty, never replace faction/home/job intent. Validate the
-- entire party first: no partial assignment if one member changed jobs or died.
function KnoxPersistence.claimEventDuty(eventId, worldAgeHours)
    local data = root()
    local event = type(eventId) == "string" and data.knoxEvents.records[eventId] or nil
    if type(event) ~= "table" or event.kind ~= "faction_raid"
        or (event.phase ~= "scheduled" and event.phase ~= "spawning")
        or type(event.memberIds) ~= "table" or #event.memberIds == 0 then
        return false, "invalid_event"
    end
    local base = data.bases[event.sourceBaseId]
    if base == nil or base.ownerKind ~= "faction" or base.ownerId ~= event.sourceFactionId then
        return false, "invalid_home"
    end
    local seen, pending = {}, {}
    for _, id in ipairs(event.memberIds) do
        local survivor = type(id) == "string" and data.survivors[id] or nil
        local duty = survivor ~= nil and survivor.duty or nil
        local affiliation = survivor ~= nil and survivor.affiliation or nil
        if survivor == nil or survivor.alive == false or survivor.record == nil or seen[id]
            or affiliation == nil or affiliation.factionId ~= event.sourceFactionId
            or duty == nil or duty.mode ~= "base" or duty.baseId ~= event.sourceBaseId
            or (duty.eventId ~= nil and duty.eventId ~= eventId) then
            return false, "member_unavailable"
        end
        for _, task in pairs(base.tasks or {}) do
            if type(task) == "table" and task.state == "claimed" and task.claimedBy == id then
                return false, "member_working"
            end
        end
        seen[id] = true
        if duty.eventId == nil then pending[#pending + 1] = duty end
    end
    for _, duty in ipairs(pending) do
        duty.eventId = eventId
        duty.revision = (tonumber(duty.revision) or 0) + 1
        duty.changedAtHours = tonumber(worldAgeHours) or 0
    end
    return true, #pending == 0 and "existing" or "claimed"
end

function KnoxPersistence.releaseEventDuty(id, eventId, worldAgeHours)
    if type(eventId) ~= "string" or eventId == "" then return false, "invalid_event" end
    local data = root()
    local survivor = type(id) == "string" and data.survivors[id] or nil
    local duty = survivor ~= nil and survivor.duty or nil
    if duty == nil or duty.eventId ~= eventId then return false, "not_event_owner" end
    duty.eventId = nil
    duty.revision = (tonumber(duty.revision) or 0) + 1
    duty.changedAtHours = tonumber(worldAgeHours) or 0
    -- A removed home cannot remain an actionable base order. Keep affiliation;
    -- surviving members can use the existing faction/autonomy recovery instead.
    local base = data.bases[duty.baseId]
    if duty.mode == "base" and (base == nil or base.ownerKind ~= "faction"
        or base.ownerId ~= (survivor.affiliation or {}).factionId) then
        duty.mode, duty.order, duty.baseId = "autonomous", "survive", nil
    end
    return true, "released"
end

function KnoxPersistence.getAwayTeams()
    local teams = {}
    for id, team in pairs(root().awayTeams) do
        if type(team) == "table" then
            teams[id] = copySerializable(team)
        end
    end
    return teams
end

function KnoxPersistence.getAwayTeam(id)
    local team = type(id) == "string" and root().awayTeams[id] or nil
    return type(team) == "table" and copySerializable(team) or nil
end

-- Read-only progress snapshot for the Notebook/HUD.  Mission state remains
-- authoritative in the persisted team record; this helper only derives timing
-- fields and never advances or mutates a mission.
function KnoxPersistence.getAwayTeamProgress(id, worldAgeHours)
    local team = KnoxPersistence.getAwayTeam(id)
    if team == nil then
        return nil
    end
    local now = tonumber(worldAgeHours) or 0
    local departure = tonumber(team.departedAtHours) or now
    local eta = tonumber(team.etaHours) or departure
    local duration = math.max(0.25, eta - departure)
    local elapsed = math.max(0, now - departure)
    local progress = math.max(0, math.min(1, elapsed / duration))
    local remaining = team.state == "outbound" and math.max(0, eta - now) or 0
    team.elapsedHours = elapsed
    team.remainingHours = remaining
    team.progress = progress
    team.statusLabel = team.state == "outbound" and "En route"
        or team.state == "awaiting_collection" and "At destination"
        or team.state == "collecting" and "Collecting supplies"
        or team.state == "returning" and "Returning"
        or team.state == "complete" and "Returned"
        or team.state == "blocked" and "Unable to complete"
        or tostring(team.state or "Unknown")
    return team
end

function KnoxPersistence.getAwayTeamForSurvivor(survivorId)
    local survivor = ensureSurvivorState(survivorId)
    local id = survivor ~= nil and survivor.duty ~= nil and survivor.duty.awayTeamId or nil
    return id ~= nil and KnoxPersistence.getAwayTeam(id) or nil
end

-- Creates a durable mission assignment. The caller must first hibernate/remove any
-- loaded bodies; this data operation deliberately does not fabricate a world result or
-- mutate their inventories.
local function validateAwayTeamInput(ownerKind, ownerId, memberIds, missionType, destination)
    if (ownerKind ~= "player" and ownerKind ~= "faction")
        or type(ownerId) ~= "string" or ownerId == ""
        or not AWAY_MISSION_TYPES[missionType]
        or type(destination) ~= "table"
        or tonumber(destination.x) == nil or tonumber(destination.y) == nil then
        return nil, "invalid_mission"
    end
    local members, seen = {}, {}
    for _, id in ipairs(memberIds or {}) do
        local survivor = ensureSurvivorState(id)
        local affiliation = survivor ~= nil and survivor.affiliation or nil
        if type(id) ~= "string" or seen[id] or survivor == nil or survivor.alive == false
            or affiliation == nil or affiliation.kind ~= ownerKind
            or (ownerKind == "player" and affiliation.ownerId ~= ownerId)
            or (ownerKind == "faction" and affiliation.factionId ~= ownerId)
            or survivor.duty.mode == "away" or survivor.duty.eventId ~= nil then
            return nil, "invalid_member=" .. tostring(id)
        end
        seen[id] = true
        members[#members + 1] = id
    end
    if #members == 0 then
        return nil, "no_members"
    end
    return members, "valid"
end

-- Dispatchers validate this before taking a loaded shell down.  This protects
-- the identity/body handoff from ordinary bad owner, destination, or duty data;
-- the subsequent create call repeats the validation at the mutation boundary.
function KnoxPersistence.validateAwayTeam(ownerKind, ownerId, memberIds, missionType, destination)
    local members, result = validateAwayTeamInput(
        ownerKind, ownerId, memberIds, missionType, destination
    )
    return members ~= nil, result
end

function KnoxPersistence.createAwayTeam(ownerKind, ownerId, memberIds, missionType, destination, worldAgeHours, etaHours)
    local members, validation = validateAwayTeamInput(
        ownerKind, ownerId, memberIds, missionType, destination
    )
    if members == nil then
        return nil, validation
    end
    local data = root()
    local teamId = "away-" .. tostring(math.max(1, math.floor(data.nextAwayTeamId)))
    while data.awayTeams[teamId] ~= nil do
        data.nextAwayTeamId = data.nextAwayTeamId + 1
        teamId = "away-" .. tostring(data.nextAwayTeamId)
    end
    data.nextAwayTeamId = data.nextAwayTeamId + 1
    local departure = tonumber(worldAgeHours) or 0
    local eta = math.max(departure + 0.25, tonumber(etaHours) or (departure + 2))
    local team = {
        id = teamId,
        ownerKind = ownerKind,
        ownerId = ownerId,
        memberIds = members,
        missionType = missionType,
        destination = {
            x = math.floor(tonumber(destination.x)),
            y = math.floor(tonumber(destination.y)),
            z = math.floor(tonumber(destination.z) or 0),
            label = tostring(destination.label or "Unknown destination"),
        },
        state = "outbound",
        departedAtHours = departure,
        etaHours = eta,
        result = nil,
    }
    data.awayTeams[teamId] = team
    for _, id in ipairs(members) do
        local survivor = ensureSurvivorState(id)
        if survivor.duty.mode == "base" then
            requeueClaimsForSurvivor(id, survivor.duty.baseId, "away_mission")
        end
        survivor.duty = {
            mode = "away",
            order = "mission",
            awayTeamId = teamId,
            ownerId = ownerId,
            previousDuty = copySerializable(survivor.duty),
            changedAtHours = departure,
            revision = (tonumber(survivor.duty.revision) or 0) + 1,
        }
    end
    return copySerializable(team), "created"
end

local function restoreAwayTeamDuties(team, worldAgeHours)
    for _, id in ipairs(team.memberIds or {}) do
        local survivor = ensureSurvivorState(id)
        local previous = survivor.duty.previousDuty
        survivor.duty = type(previous) == "table" and previous or {
            mode = "autonomous", order = "survive", revision = 0,
        }
        survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
        survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    end
end

local function validAwayMember(team, survivorId)
    if team == nil or type(survivorId) ~= "string" then
        return false
    end
    for _, id in ipairs(team.memberIds or {}) do
        if id == survivorId then return true end
    end
    return false
end

-- The live-world executor calls this only after an ordinary inventory transfer
-- has succeeded.  The ledger deliberately accepts item *types*, never counts
-- or creates an item by itself, so an away result can be audited back to real
-- container movement rather than becoming a free-resource generator.
function KnoxPersistence.recordAwayTeamCollection(teamId, survivorId, itemTypes, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if not validAwayMember(team, survivorId) or team.state ~= "collecting"
        or type(itemTypes) ~= "table" then
        return nil, "invalid_collection"
    end
    team.collection = type(team.collection) == "table" and team.collection or {
        resources = {}, byMember = {},
    }
    team.collection.resources = type(team.collection.resources) == "table"
        and team.collection.resources or {}
    team.collection.byMember = type(team.collection.byMember) == "table"
        and team.collection.byMember or {}
    local member = team.collection.byMember[survivorId] or {}
    local accepted = 0
    for _, itemType in ipairs(itemTypes) do
        if type(itemType) == "string" and itemType ~= "" and #itemType <= 160 then
            member[itemType] = (tonumber(member[itemType]) or 0) + 1
            team.collection.resources[itemType] = (tonumber(team.collection.resources[itemType]) or 0) + 1
            accepted = accepted + 1
        end
    end
    team.collection.byMember[survivorId] = member
    team.collection.lastCollectedAtHours = tonumber(worldAgeHours) or 0
    return copySerializable(team.collection), accepted > 0 and "recorded" or "no_items"
end

function KnoxPersistence.beginAwayTeamCollection(teamId, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if team == nil or team.state ~= "awaiting_collection" then
        return nil, "not_awaiting_collection"
    end
    team.state = "collecting"
    team.collectionStartedAtHours = tonumber(worldAgeHours) or 0
    return copySerializable(team), "collecting"
end

-- Completion is intentionally a separate transition from collection.  A
-- transfer at the destination is not enough: the live executor must return
-- the team to its owner before this restores their ordinary duties.
function KnoxPersistence.completeAwayTeamMember(teamId, survivorId, success, reason, worldAgeHours)
    local team = type(teamId) == "string" and root().awayTeams[teamId] or nil
    if not validAwayMember(team, survivorId)
        or (team.state ~= "collecting" and team.state ~= "returning") then
        return nil, "invalid_completion"
    end
    team.memberResults = type(team.memberResults) == "table" and team.memberResults or {}
    team.memberResults[survivorId] = {
        success = success == true,
        reason = tostring(reason or (success and "returned" or "failed")),
        completedAtHours = tonumber(worldAgeHours) or 0,
    }
    local complete = true
    for _, id in ipairs(team.memberIds or {}) do
        if team.memberResults[id] == nil then complete = false; break end
    end
    if not complete then
        return copySerializable(team), "member_recorded"
    end
    team.state = "complete"
    team.completedAtHours = tonumber(worldAgeHours) or 0
    team.result = {
        kind = "resource_run",
        destination = copySerializable(team.destination),
        resources = copySerializable(team.collection ~= nil and team.collection.resources or {}),
        members = copySerializable(team.memberResults),
    }
    restoreAwayTeamDuties(team, worldAgeHours)
    return copySerializable(team), "complete"
end

-- Scouting has an explicit non-resource result. Resource missions advance only
-- to an awaiting-collection state; no item is generated and duty ownership is
-- retained until a live executor transfers real loot and returns the team.
function KnoxPersistence.advanceAwayTeams(worldAgeHours)
    local now, changed = tonumber(worldAgeHours) or 0, 0
    for _, team in pairs(root().awayTeams) do
        if type(team) == "table" and team.state == "outbound"
            and now >= (tonumber(team.etaHours) or math.huge) then
            if team.missionType == "scout" then
                team.state = "complete"
                team.completedAtHours = now
                team.result = {
                    kind = "scouted",
                    destination = copySerializable(team.destination),
                    resources = {},
                }
                restoreAwayTeamDuties(team, now)
            else
                team.state = "awaiting_collection"
                team.arrivedAtHours = now
                team.result = {
                    kind = "awaiting_live_collection",
                    destination = copySerializable(team.destination),
                    resources = {},
                }
            end
            changed = changed + 1
        end
    end
    return changed
end

function KnoxPersistence.isIndependentSurvivor(id)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "independent" then
        return false
    end
    local data = root()
    for _, group in pairs(data.travelGroups) do
        for _, memberId in ipairs(group.memberIds or {}) do
            if memberId == id then
                return false
            end
        end
    end
    for _, faction in pairs(data.factions) do
        for _, memberId in ipairs(faction.memberIds or {}) do
            if memberId == id then
                return false
            end
        end
    end
    return true
end

function KnoxPersistence.setSurvivorIndependent(id, reason, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil then
        return false
    end
    local nextRevision = (tonumber(survivor.duty.revision) or 0) + 1
    if survivor.duty.mode == "base" then
        requeueClaimsForSurvivor(id, survivor.duty.baseId, "left_base")
    end
    local previousFactionId = survivor.affiliation.factionId
    if previousFactionId ~= nil and KnoxPersistence.removeFactionMember ~= nil then
        KnoxPersistence.removeFactionMember(previousFactionId, id)
    end
    if KnoxPersistence.removeTravelGroupMember ~= nil then
        KnoxPersistence.removeTravelGroupMember(id)
    end
    for factionId, candidate in pairs(root().factions) do
        local listed = false
        for _, memberId in ipairs(candidate ~= nil and candidate.memberIds or {}) do
            listed = listed or memberId == id
        end
        if listed then
            KnoxPersistence.removeFactionMember(factionId, id, true)
        end
    end
    survivor.affiliation = {
        kind = "independent",
        ownerId = nil,
        changedAtHours = tonumber(worldAgeHours) or 0,
        reason = tostring(reason or "released"),
    }
    survivor.duty = {
        mode = "autonomous",
        order = "survive",
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = nextRevision,
    }
    return true
end

function KnoxPersistence.setPlayerCompanion(id, playerId, order, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(playerId) ~= "string" or playerId == "" then
        return false, "invalid_identity"
    end
    if survivor.record == nil then
        return false, "survivor_not_persisted"
    end
    if survivor.affiliation.kind ~= "independent"
        and not (survivor.affiliation.kind == "player"
            and survivor.affiliation.ownerId == playerId) then
        return false, "already_affiliated"
    end
    local existingGroup = KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(id) or nil
    if existingGroup ~= nil then
        if survivor.affiliation.kind == "player"
            and survivor.affiliation.ownerId == playerId then
            KnoxPersistence.removeTravelGroupMember(id)
        else
            return false, "already_with_group"
        end
    end
    if survivor.duty.mode == "base" then
        requeueClaimsForSurvivor(id, survivor.duty.baseId, "recalled_as_companion")
    end
    -- Player ownership is authoritative. Remove stale copies left in NPC rosters
    -- before assigning the player faction so later faction maintenance cannot
    -- absorb a companion back into an autonomous group.
    if KnoxPersistence.removeTravelGroupMember ~= nil then
        KnoxPersistence.removeTravelGroupMember(id)
    end
    for factionId, candidate in pairs(root().factions) do
        local listed = false
        for _, memberId in ipairs(candidate ~= nil and candidate.memberIds or {}) do
            listed = listed or memberId == id
        end
        local belongsToThisPlayer = candidate ~= nil and candidate.kind == "player"
            and candidate.ownerPlayerId == playerId
        if candidate ~= nil and listed and not belongsToThisPlayer then
            KnoxPersistence.removeFactionMember(factionId, id, true)
        end
    end
    local faction = KnoxPersistence.ensurePlayerFaction(playerId, worldAgeHours)
    if faction == nil then
        return false, "player_faction_failed"
    end
    survivor.affiliation = {
        kind = "player",
        ownerId = playerId,
        factionId = faction.id,
        joinedAtHours = survivor.affiliation.joinedAtHours
            or tonumber(worldAgeHours)
            or 0,
    }
    survivor.duty = {
        mode = "companion",
        order = order == "hold" and "hold" or "follow",
        combatStance = "defensive",
        ownerId = playerId,
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = (tonumber(survivor.duty.revision) or 0) + 1,
    }
    KnoxPersistence.addFactionMember(faction.id, id, worldAgeHours)
    return true, "companion"
end

function KnoxPersistence.setPlayerBaseResident(id, playerId, baseId, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(playerId) ~= "string" or playerId == ""
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId then
        return false, "not_player_survivor"
    end
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or base.ownerKind ~= "player" or base.ownerId ~= playerId then
        return false, "invalid_player_base"
    end
    if survivor.duty.mode == "base" and survivor.duty.baseId ~= baseId then
        requeueClaimsForSurvivor(id, survivor.duty.baseId, "base_changed")
    end
    survivor.duty = {
        mode = "base",
        order = "available",
        jobPreference = survivor.duty ~= nil and survivor.duty.jobPreference or "auto",
        ownerId = playerId,
        baseId = baseId,
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = (tonumber(survivor.duty.revision) or 0) + 1,
    }
    return true, "base_resident"
end

function KnoxPersistence.setFactionBaseResident(id, factionId, baseId, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local faction = KnoxPersistence.getFaction(factionId)
    local base = KnoxPersistence.getBase(baseId)
    if survivor == nil or faction == nil or faction.kind == "player"
        or base == nil or base.ownerKind ~= "faction" or base.ownerId ~= factionId
        or survivor.affiliation.factionId ~= factionId then
        return false, "not_faction_survivor"
    end
    if survivor.duty.mode == "base" and survivor.duty.baseId == baseId then
        return true, "existing"
    end
    if survivor.duty.mode == "base" then
        requeueClaimsForSurvivor(id, survivor.duty.baseId, "base_changed")
    end
    survivor.duty = {
        mode = "base",
        order = "available",
        jobPreference = survivor.duty ~= nil and survivor.duty.jobPreference or "auto",
        ownerId = factionId,
        baseId = baseId,
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = (tonumber(survivor.duty.revision) or 0) + 1,
    }
    return true, "base_resident"
end

function KnoxPersistence.getBaseResidentIds(baseId)
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if survivor ~= nil and survivor.duty ~= nil
            and survivor.duty.mode == "base" and survivor.duty.baseId == baseId then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.setBaseJobPreference(id, playerId, baseId, preference, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local allowed = preference == "auto" or preference == "guard" or preference == "patrol"
        or preference == "farming" or preference == "woodwork" or preference == "hauling"
        or preference == "animal_care" or preference == "repair"
    if survivor == nil or not allowed
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "base" or survivor.duty.baseId ~= baseId then
        return false
    end
    survivor.duty.jobPreference = preference
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.updateCompanionOrder(id, playerId, order, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local allowed = order == "follow" or order == "hold"
    if survivor == nil or not allowed
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    -- Follow/Hold is a replacement order, not an extra layer on top of an old
    -- Move/Guard directive. A player can therefore use either button to cancel
    -- an in-progress point command and immediately restore the primary duty.
    survivor.duty.order = order
    survivor.duty.directive = nil
    survivor.duty.ownerId = playerId
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.setCompanionCombatStance(id, playerId, stance, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local allowed = stance == "passive" or stance == "defensive" or stance == "aggressive"
    if survivor == nil or not allowed
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    survivor.duty.combatStance = stance
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.getSurvivorPolicies(id)
    local survivor = ensureSurvivorState(id)
    return survivor ~= nil and copyFlat(survivor.policies) or nil
end

-- Internal identity policy setter, also used by explicit developer scenarios.
-- Player-facing commands must go through the ownership-checked wrapper below.
function KnoxPersistence.setSurvivorWeaponPreference(id, preference)
    if type(id) ~= "string" or root().survivors[id] == nil then return false end
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.alive == false
        or (preference ~= "melee" and preference ~= "ranged" and preference ~= "auto") then return false end
    survivor.policies.weaponPreference = preference
    return true
end

function KnoxPersistence.setCompanionWeaponPreference(id, playerId, preference, worldAgeHours)
    if type(id) ~= "string" or root().survivors[id] == nil then return false end
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.alive == false
        or (preference ~= "melee" and preference ~= "ranged" and preference ~= "auto")
        or survivor.affiliation.kind ~= "player" or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then return false end
    if survivor.policies.weaponPreference ~= preference then
        KnoxPersistence.setSurvivorWeaponPreference(id, preference)
        survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
        survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    end
    return true
end

function KnoxPersistence.setCompanionClimbing(id, playerId, allowed, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    survivor.policies.allowClimbing = allowed == true
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.setCompanionDirective(id, playerId, directive, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or type(directive) ~= "table"
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    if not KnoxPersistence.isValidCompanionDirective(directive) then
        return false
    end
    local kind = tostring(directive.kind or "")
    local minX = tonumber(directive.minX)
    local minY = tonumber(directive.minY)
    local maxX = tonumber(directive.maxX)
    local maxY = tonumber(directive.maxY)
    survivor.duty.directive = {
        kind = kind,
        minX = minX,
        minY = minY,
        maxX = maxX or minX,
        maxY = maxY or minY,
        z = tonumber(directive.z) or 0,
        buildingId = directive.buildingId ~= nil and tostring(directive.buildingId) or nil,
        issuedAtHours = tonumber(worldAgeHours) or 0,
    }
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.clearCompanionDirective(id, playerId, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    if survivor == nil or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    survivor.duty.directive = nil
    survivor.duty.changedAtHours = tonumber(worldAgeHours) or 0
    survivor.duty.revision = (tonumber(survivor.duty.revision) or 0) + 1
    return true
end

function KnoxPersistence.getCompanionIds(playerId)
    local ids = {}
    if type(playerId) ~= "string" or playerId == "" then
        return ids
    end
    for id, survivor in pairs(root().survivors) do
        if survivor ~= nil and survivor.alive ~= false
            and survivor.affiliation ~= nil
            and survivor.affiliation.kind == "player"
            and survivor.affiliation.ownerId == playerId
            and survivor.duty ~= nil and survivor.duty.mode == "companion" then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.ensurePlayerId(player)
    if player == nil or player.getModData == nil then
        return nil
    end
    local modData = player:getModData()
    modData.KnoxSurvivors = modData.KnoxSurvivors or {}
    local playerId = modData.KnoxSurvivors.playerId
    local data = root()
    if type(playerId) ~= "string" or playerId == "" then
        playerId = "player-" .. tostring(data.nextPlayerId)
        data.nextPlayerId = data.nextPlayerId + 1
        modData.KnoxSurvivors.playerId = playerId
    end
    local playerRecord = data.players[playerId] or { id = playerId }
    local descriptor = player.getDescriptor ~= nil and player:getDescriptor() or nil
    if descriptor ~= nil then
        playerRecord.forename = tostring(descriptor:getForename() or "")
        playerRecord.surname = tostring(descriptor:getSurname() or "")
    end
    data.players[playerId] = playerRecord
    return playerId
end

function KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    local survivor = ensureSurvivorState(survivorId)
    if survivor == nil or type(playerId) ~= "string" or playerId == "" then
        return nil
    end
    local relation = survivor.playerRelationships[playerId]
    if relation == nil then
        relation = {
            trust = 30,
            meetings = 0,
            firstMetHours = nil,
            lastMetHours = nil,
            nextTalkHours = 0,
            nextRecruitHours = 0,
        }
        survivor.playerRelationships[playerId] = relation
    end
    return relation
end

function KnoxPersistence.recordPlayerRecruitRefusal(
    playerId,
    survivorId,
    worldAgeHours,
    cooldownHours
)
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if relation == nil then
        return nil
    end
    local now = tonumber(worldAgeHours) or 0
    relation.nextRecruitHours = math.max(
        tonumber(relation.nextRecruitHours) or 0,
        now + math.max(0, tonumber(cooldownHours) or 0)
    )
    return relation
end

function KnoxPersistence.recordPlayerConversation(
    playerId,
    survivorId,
    trustGain,
    worldAgeHours,
    cooldownHours
)
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if relation == nil then
        return nil, "invalid_identity"
    end
    local now = tonumber(worldAgeHours) or 0
    if (tonumber(relation.nextTalkHours) or 0) > now then
        return relation, "cooldown"
    end
    relation.firstMetHours = relation.firstMetHours or now
    relation.lastMetHours = now
    relation.meetings = (tonumber(relation.meetings) or 0) + 1
    relation.trust = math.max(0, math.min(100,
        (tonumber(relation.trust) or 30) + (tonumber(trustGain) or 0)))
    relation.nextTalkHours = now + math.max(0, tonumber(cooldownHours) or 0)
    return relation, "recorded"
end

function KnoxPersistence.recordEncounter(firstId, secondId, observation)
    local key, lowId, highId = relationshipKey(firstId, secondId)
    if key == nil or type(observation) ~= "table" then
        return nil
    end
    local relationships = root().relationships
    local record = relationships[key] or {
        firstId = lowId,
        secondId = highId,
        meetings = 0,
        nearbyHours = 0,
        sharedRoam = 0,
        sharedLoot = 0,
        sharedCombat = 0,
    }
    local worldAge = tonumber(observation.worldAgeHours) or 0
    record.firstMetHours = record.firstMetHours or worldAge
    record.lastMetHours = worldAge
    if observation.began == true then
        record.meetings = record.meetings + 1
    end
    record.nearbyHours = record.nearbyHours
        + math.max(0, math.min(0.25, tonumber(observation.nearbyHours) or 0))
    record.sharedRoam = record.sharedRoam
        + math.max(0, tonumber(observation.sharedRoam) or 0)
    record.sharedLoot = record.sharedLoot
        + math.max(0, tonumber(observation.sharedLoot) or 0)
    record.sharedCombat = record.sharedCombat
        + math.max(0, tonumber(observation.sharedCombat) or 0)
    relationships[key] = record
    return record
end

function KnoxPersistence.getRelationship(firstId, secondId)
    local key = relationshipKey(firstId, secondId)
    return key ~= nil and root().relationships[key] or nil
end

function KnoxPersistence.setRelationshipDisposition(
    firstId,
    secondId,
    disposition,
    nextEncounterHours
)
    local key, lowId, highId = relationshipKey(firstId, secondId)
    local validDisposition = disposition == "allied" or disposition == "neutral"
        or disposition == "hostile" or disposition == "declined"
    if key == nil or not validDisposition then
        return nil
    end
    local relationships = root().relationships
    local record = relationships[key] or {
        firstId = lowId,
        secondId = highId,
        meetings = 0,
        nearbyHours = 0,
        sharedRoam = 0,
        sharedLoot = 0,
        sharedCombat = 0,
    }
    record.disposition = disposition
    record.nextEncounterHours = tonumber(nextEncounterHours) or 0
    relationships[key] = record
    return record
end

function KnoxPersistence.getFactions()
    return root().factions
end

local FACTION_DISPOSITIONS = {
    allied = true,
    neutral = true,
    hostile = true,
}

local function factionRelationshipKey(firstFactionId, secondFactionId)
    if type(firstFactionId) ~= "string" or firstFactionId == ""
        or type(secondFactionId) ~= "string" or secondFactionId == ""
        or firstFactionId == secondFactionId then
        return nil
    end
    if firstFactionId < secondFactionId then
        return firstFactionId .. "|" .. secondFactionId, firstFactionId, secondFactionId
    end
    return secondFactionId .. "|" .. firstFactionId, secondFactionId, firstFactionId
end

-- This returns a copy so callers cannot silently mutate saved diplomacy
-- without recording the time and reason through the setter below.
function KnoxPersistence.getFactionRelationship(firstFactionId, secondFactionId)
    local key = factionRelationshipKey(firstFactionId, secondFactionId)
    local relationship = key ~= nil and root().factionRelationships[key] or nil
    return relationship ~= nil and copySerializable(relationship) or nil
end

function KnoxPersistence.setFactionRelationshipDisposition(
    firstFactionId,
    secondFactionId,
    disposition,
    worldAgeHours,
    reason
)
    local key, lowId, highId = factionRelationshipKey(firstFactionId, secondFactionId)
    if key == nil or FACTION_DISPOSITIONS[disposition] ~= true
        or KnoxPersistence.getFaction(lowId) == nil
        or KnoxPersistence.getFaction(highId) == nil then
        return nil, "invalid_faction_relationship"
    end
    local relationships = root().factionRelationships
    local relationship = relationships[key] or {
        firstFactionId = lowId,
        secondFactionId = highId,
        disposition = "neutral",
        createdAtHours = tonumber(worldAgeHours) or 0,
    }
    relationship.disposition = disposition
    relationship.changedAtHours = tonumber(worldAgeHours) or 0
    relationship.reason = type(reason) == "string" and reason or nil
    relationships[key] = relationship
    return copySerializable(relationship), "saved"
end

function KnoxPersistence.getPlayerFaction(playerId)
    if type(playerId) ~= "string" or playerId == "" then
        return nil
    end
    local player = root().players[playerId]
    local factionId = player ~= nil and player.factionId or nil
    local faction = factionId ~= nil and KnoxPersistence.getFaction(factionId) or nil
    if faction ~= nil and faction.kind == "player" and faction.ownerPlayerId == playerId then
        return faction
    end
    return nil
end

-- Base protection defaults to safety.  Only an explicit legacy hostile flag
-- or durable hostility between the survivor's faction and the owning player's
-- faction permits destructive base actions.
function KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId)
    local survivor = ensureSurvivorState(survivorId)
    if survivor == nil or type(playerId) ~= "string" or playerId == "" then
        return false
    end
    local affiliation = survivor.affiliation or {}
    if affiliation.hostileToPlayer == true then
        return true
    end
    if type(affiliation.hostileToPlayers) == "table"
        and affiliation.hostileToPlayers[playerId] == true then return true end
    local survivorFactionId = affiliation.factionId
    local playerFaction = KnoxPersistence.getPlayerFaction(playerId)
    if survivorFactionId == nil or playerFaction == nil
        or survivorFactionId == playerFaction.id then
        return false
    end
    local relationship = KnoxPersistence.getFactionRelationship(
        survivorFactionId,
        playerFaction.id
    )
    return relationship ~= nil and relationship.disposition == "hostile"
end

function KnoxPersistence.setSurvivorHostileToPlayer(survivorId, playerId, hostile)
    local survivor = ensureSurvivorState(survivorId)
    if survivor == nil or type(playerId) ~= "string" or playerId == "" then return false end
    survivor.affiliation = survivor.affiliation or { kind = "independent" }
    survivor.affiliation.hostileToPlayers = type(survivor.affiliation.hostileToPlayers) == "table"
        and survivor.affiliation.hostileToPlayers or {}
    survivor.affiliation.hostileToPlayers[playerId] = hostile == true or nil
    return true
end

function KnoxPersistence.ensurePlayerFaction(playerId, worldAgeHours)
    if type(playerId) ~= "string" or playerId == "" then
        return nil
    end
    local data = root()
    local player = data.players[playerId] or { id = playerId }
    local faction = player.factionId ~= nil and data.factions[player.factionId] or nil
    if faction ~= nil and (faction.kind ~= "player"
        or faction.ownerPlayerId ~= playerId) then
        faction = nil
        player.factionId = nil
    end
    if faction == nil then
        local factionId = "player-faction-" .. tostring(data.nextFactionId)
        data.nextFactionId = data.nextFactionId + 1
        faction = {
            id = factionId,
            name = "Your Group",
            kind = "player",
            ownerPlayerId = playerId,
            memberIds = {},
            formedAtHours = tonumber(worldAgeHours) or 0,
        }
        data.factions[factionId] = faction
        player.factionId = factionId
        data.players[playerId] = player
    end
    faction.kind = "player"
    faction.ownerPlayerId = playerId
    faction.memberIds = faction.memberIds or {}
    return faction
end

-- Contribution callers must first verify the real action/transfer. This ledger
-- records social consequences only; it never grants supplies or changes health.
local CONTRIBUTION_RULES = {
    defense = { trust = 4, reputation = 2, cooldown = 0.5 },
    gift = { trust = 3, reputation = 1, cooldown = 6 },
    trade = { trust = 2, reputation = 1, cooldown = 3 },
    treatment = { trust = 5, reputation = 2, cooldown = 6 },
    construction = { trust = 3, reputation = 1, cooldown = 6 },
}

local function contributionTime(value)
    local number = tonumber(value)
    return number ~= nil and number == number and number >= 0 and number < math.huge and number or nil
end

local function contributionLedger(owner, now)
    local ledger = owner.contributions
    if type(ledger) ~= "table" then
        ledger = { startedAtHours = now, earned = 0, nextAt = {} }
        owner.contributions = ledger
    end
    ledger.nextAt = type(ledger.nextAt) == "table" and ledger.nextAt or {}
    local start = tonumber(ledger.startedAtHours) or now
    ledger.startedAtHours = start
    if now < start then return nil end -- clock rollback must not reset reward budgets
    if now - start >= 24 then
        ledger.startedAtHours, ledger.earned, ledger.nextAt = now, 0, {}
    end
    return ledger
end

local function playerFactionRelationship(playerId, survivorId, now)
    local faction = KnoxPersistence.getFactionForSurvivor(survivorId)
    if faction == nil or faction.kind == "player" then return nil end
    local playerFaction = KnoxPersistence.ensurePlayerFaction(playerId, now)
    local key, lowId, highId = factionRelationshipKey(faction.id, playerFaction.id)
    if key == nil then return nil end
    local relationship = root().factionRelationships[key]
    if relationship == nil then
        relationship = { firstFactionId = lowId, secondFactionId = highId,
            disposition = "neutral", createdAtHours = now, reputation = 0 }
        root().factionRelationships[key] = relationship
    end
    return relationship
end

function KnoxPersistence.recordPlayerContribution(playerId, survivorId, kind, worldAgeHours)
    local rule, now = CONTRIBUTION_RULES[kind], contributionTime(worldAgeHours)
    if rule == nil or now == nil or type(playerId) ~= "string" or root().players[playerId] == nil
        or not KnoxPersistence.isSurvivorAlive(survivorId) then return nil, "invalid_contribution" end
    if KnoxPersistence.isSurvivorHostileToPlayer(survivorId, playerId) then return nil, "hostile" end
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    local ledger = contributionLedger(relation, now)
    if ledger == nil then return nil, "clock_rollback" end
    if now < (tonumber(ledger.nextAt[kind]) or 0) then return nil, "cooldown" end
    local gain = math.min(rule.trust, math.max(0, 12 - (tonumber(ledger.earned) or 0)))
    if gain <= 0 then return nil, "daily_limit" end
    ledger.nextAt[kind] = now + rule.cooldown
    ledger.earned = (tonumber(ledger.earned) or 0) + gain
    relation.trust = math.max(0, math.min(100, (tonumber(relation.trust) or 30) + gain))
    relation.firstMetHours = relation.firstMetHours or now
    relation.lastMetHours, relation.lastContribution = now, kind
    local reputationGain = 0
    local factionRelation = playerFactionRelationship(playerId, survivorId, now)
    if factionRelation ~= nil and factionRelation.disposition ~= "hostile" then
        local factionLedger = contributionLedger(factionRelation, now)
        if factionLedger ~= nil then
            reputationGain = math.min(rule.reputation, math.max(0, 8 - (tonumber(factionLedger.earned) or 0)))
            factionLedger.earned = (tonumber(factionLedger.earned) or 0) + reputationGain
            factionRelation.reputation = math.max(-100, math.min(100,
                (tonumber(factionRelation.reputation) or 0) + reputationGain))
            factionRelation.changedAtHours, factionRelation.reason = now, kind
        end
    end
    return { trustGain = gain, reputationGain = reputationGain }, "recorded"
end

-- Called only for a native player hit against a previously non-hostile survivor.
-- Retaliation against an existing hostile is not an unprovoked aggression event.
function KnoxPersistence.recordPlayerAggression(playerId, survivorId, worldAgeHours)
    local now = contributionTime(worldAgeHours)
    if now == nil or type(playerId) ~= "string" or root().players[playerId] == nil
        or type(survivorId) ~= "string" or root().survivors[survivorId] == nil then return false end
    local relation = KnoxPersistence.getPlayerRelationship(playerId, survivorId)
    if now < (tonumber(relation.nextAggressionHours) or 0) then return false end
    relation.trust = math.max(0, (tonumber(relation.trust) or 30) - 30)
    relation.nextAggressionHours = now + 1
    relation.lastAggressionHours = now
    local factionRelation = playerFactionRelationship(playerId, survivorId, now)
    if factionRelation ~= nil then
        factionRelation.reputation = math.max(-100, (tonumber(factionRelation.reputation) or 0) - 20)
        factionRelation.disposition = "hostile"
        factionRelation.changedAtHours, factionRelation.reason = now, "player_aggression"
    end
    return true
end

local function containsId(ids, id)
    for _, existing in ipairs(ids or {}) do
        if existing == id then
            return true
        end
    end
    return false
end

local function copyIds(ids)
    local copied = {}
    for _, id in ipairs(ids or {}) do
        if type(id) == "string" and id ~= "" and not containsId(copied, id) then
            copied[#copied + 1] = id
        end
    end
    table.sort(copied)
    return copied
end

function KnoxPersistence.addFactionMember(factionId, survivorId, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    local survivor = ensureSurvivorState(survivorId)
    if faction == nil or survivor == nil then
        return false
    end
    if faction.kind ~= "player" and (survivor.affiliation.kind == "player"
        or survivor.duty.mode == "companion"
        or survivor.duty.mode == "base" and survivor.affiliation.kind == "player") then
        return false
    end
    local group = KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(survivorId)
        or nil
    if group ~= nil and group.factionId ~= factionId
        and KnoxPersistence.removeTravelGroupMember ~= nil then
        KnoxPersistence.removeTravelGroupMember(survivorId)
    end
    local previousFactionId = survivor.affiliation.factionId
    if previousFactionId ~= nil and previousFactionId ~= factionId then
        KnoxPersistence.removeFactionMember(previousFactionId, survivorId, false)
    end
    faction.memberIds = faction.memberIds or {}
    if not containsId(faction.memberIds, survivorId) then
        faction.memberIds[#faction.memberIds + 1] = survivorId
        table.sort(faction.memberIds)
    end
    faction.memberJoinedAtHours = faction.memberJoinedAtHours or {}
    faction.memberJoinedAtHours[survivorId] = faction.memberJoinedAtHours[survivorId]
        or tonumber(worldAgeHours)
        or 0
    survivor.affiliation.factionId = factionId
    survivor.affiliation.kind = faction.kind == "player" and "player" or "faction"
    survivor.affiliation.ownerId = faction.kind == "player"
        and faction.ownerPlayerId
        or nil
    return true
end

function KnoxPersistence.removeFactionMember(factionId, survivorId, preserveDuty)
    local faction = KnoxPersistence.getFaction(factionId)
    local survivor = ensureSurvivorState(survivorId)
    if faction == nil or survivor == nil then
        return false
    end
    local retained = {}
    for _, id in ipairs(faction.memberIds or {}) do
        if id ~= survivorId then
            retained[#retained + 1] = id
        end
    end
    faction.memberIds = retained
    if faction.memberJoinedAtHours ~= nil then
        faction.memberJoinedAtHours[survivorId] = nil
    end
    if survivor.affiliation.factionId == factionId then
        if survivor.duty.mode == "base" then
            requeueClaimsForSurvivor(
                survivorId,
                survivor.duty.baseId,
                "faction_membership_changed"
            )
        end
        survivor.affiliation = {
            kind = "independent",
            ownerId = nil,
        }
        if preserveDuty ~= true then
            survivor.duty = {
                mode = "autonomous",
                order = "survive",
                revision = (tonumber(survivor.duty.revision) or 0) + 1,
            }
        end
    end
    return true
end

function KnoxPersistence.getTravelGroupFor(id)
    local matches = {}
    for groupId, group in pairs(root().travelGroups) do
        if group ~= nil and containsId(group.memberIds, id) then
            matches[#matches + 1] = {
                id = tostring(group.id or groupId),
                group = group,
            }
        end
    end
    table.sort(matches, function(first, second) return first.id < second.id end)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(id) or {}
    for _, match in ipairs(matches) do
        if affiliation.factionId ~= nil
            and match.group.factionId == affiliation.factionId then
            return match.group
        end
    end
    return matches[1] ~= nil and matches[1].group or nil
end

function KnoxPersistence.removeTravelGroupMember(survivorId)
    local data = root()
    local removed = false
    local factionIds = {}
    local groupIds = {}
    for groupId in pairs(data.travelGroups) do groupIds[#groupIds + 1] = groupId end
    table.sort(groupIds)
    for _, groupId in ipairs(groupIds) do
        local group = data.travelGroups[groupId]
        if group ~= nil and containsId(group.memberIds, survivorId) then
            local retained = {}
            for _, memberId in ipairs(group.memberIds or {}) do
                if memberId ~= survivorId then
                    retained[#retained + 1] = memberId
                end
            end
            group.memberIds = retained
            if group.memberJoinedAtHours ~= nil then
                group.memberJoinedAtHours[survivorId] = nil
            end
            if group.factionId ~= nil then factionIds[group.factionId] = true end
            if group.leaderId == survivorId then group.leaderId = retained[1] end
            if #retained < 2 then data.travelGroups[groupId] = nil end
            removed = true
        end
    end
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId) or {}
    if affiliation.factionId ~= nil and factionIds[affiliation.factionId] then
        KnoxPersistence.removeFactionMember(affiliation.factionId, survivorId)
    end
    return removed
end

function KnoxPersistence.getFaction(id)
    return type(id) == "string" and root().factions[id] or nil
end

function KnoxPersistence.getCamps()
    return root().camps
end

function KnoxPersistence.getFactionCamp(factionId)
    local faction = KnoxPersistence.getFaction(factionId)
    local campId = faction ~= nil and faction.campId or nil
    return campId ~= nil and root().camps[campId] or nil
end

-- Camps are deliberately lightweight shelter records.  They are not bases, do
-- not claim a SafeHouse, and do not create work/storage ownership; they merely
-- preserve where a homeless faction has gathered until it establishes a home.
function KnoxPersistence.createFactionCamp(factionId, location, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    if faction == nil or faction.homeBase ~= nil or type(location) ~= "table"
        or tonumber(location.x) == nil or tonumber(location.y) == nil then
        return nil, "invalid_camp"
    end
    local existing = KnoxPersistence.getFactionCamp(factionId)
    if existing ~= nil then
        return existing, "existing"
    end
    if #(faction.memberIds or {}) < 2 then
        return nil, "not_enough_members"
    end
    local data = root()
    local id = "camp-" .. tostring(data.nextCampId)
    data.nextCampId = data.nextCampId + 1
    local campMembers = {}
    for _, memberId in ipairs(faction.memberIds or {}) do
        campMembers[#campMembers + 1] = memberId
    end
    local camp = {
        id = id,
        factionId = factionId,
        name = tostring(location.name or "Temporary Shelter"),
        x = math.floor(tonumber(location.x)),
        y = math.floor(tonumber(location.y)),
        z = math.floor(tonumber(location.z) or 0),
        buildingId = location.buildingId ~= nil and tostring(location.buildingId) or nil,
        minX = tonumber(location.minX) ~= nil and math.floor(tonumber(location.minX)) or nil,
        minY = tonumber(location.minY) ~= nil and math.floor(tonumber(location.minY)) or nil,
        maxX = tonumber(location.maxX) ~= nil and math.floor(tonumber(location.maxX)) or nil,
        maxY = tonumber(location.maxY) ~= nil and math.floor(tonumber(location.maxY)) or nil,
        memberIds = campMembers,
        createdAtHours = tonumber(worldAgeHours) or 0,
        lastGatheredAtHours = tonumber(worldAgeHours) or 0,
    }
    data.camps[id] = camp
    faction.campId = id
    return camp, "created"
end

function KnoxPersistence.syncFactionCampMembers(factionId)
    local faction = KnoxPersistence.getFaction(factionId)
    local camp = faction ~= nil and KnoxPersistence.getFactionCamp(factionId) or nil
    if faction == nil or camp == nil then
        return nil
    end
    if faction.homeBase ~= nil then
        KnoxPersistence.clearFactionCamp(
            factionId,
            "home_established",
            tonumber(camp.lastGatheredAtHours) or 0
        )
        return nil
    end
    local members = {}
    local seen = {}
    for _, survivorId in ipairs(faction.memberIds or {}) do
        local survivor = ensureSurvivorState(survivorId)
        if survivor ~= nil and survivor.alive ~= false
            and survivor.affiliation.factionId == factionId
            and not seen[survivorId] then
            seen[survivorId] = true
            members[#members + 1] = survivorId
        end
    end
    camp.memberIds = members
    return camp
end

function KnoxPersistence.getCampForSurvivor(survivorId)
    local faction = KnoxPersistence.getFactionForSurvivor(survivorId)
    local camp = faction ~= nil and KnoxPersistence.syncFactionCampMembers(faction.id) or nil
    if camp == nil then
        return nil
    end
    for _, memberId in ipairs(camp.memberIds or {}) do
        if memberId == survivorId then
            return camp
        end
    end
    return nil
end

function KnoxPersistence.touchFactionCamp(factionId, worldAgeHours)
    local camp = KnoxPersistence.getFactionCamp(factionId)
    if camp ~= nil then
        camp.lastGatheredAtHours = tonumber(worldAgeHours) or camp.lastGatheredAtHours
    end
    return camp
end

function KnoxPersistence.clearFactionCamp(factionId, reason, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    local camp = faction ~= nil and KnoxPersistence.getFactionCamp(factionId) or nil
    if faction == nil or camp == nil then return false end
    root().camps[camp.id] = nil
    faction.campId = nil
    faction.lastCampReason = tostring(reason or "cleared")
    faction.lastCampChangedAtHours = tonumber(worldAgeHours) or 0
    return true
end

function KnoxPersistence.getFactionForSurvivor(id)
    local survivor = ensureSurvivorState(id)
    if survivor ~= nil and survivor.affiliation.factionId ~= nil then
        local faction = KnoxPersistence.getFaction(survivor.affiliation.factionId)
        if faction ~= nil then
            return faction
        end
    end
    local group = KnoxPersistence.getTravelGroupFor(id)
    return group ~= nil and group.factionId ~= nil
        and KnoxPersistence.getFaction(group.factionId)
        or nil
end

-- Persisted affiliation and rosters are authoritative.  Runtime controllers
-- may cache characters for movement, but every friend-or-foe decision should
-- derive from this classifier so unloaded members and save/load agree.
function KnoxPersistence.getSurvivorDisposition(firstId, secondId)
    if type(firstId) ~= "string" or type(secondId) ~= "string" then
        return "neutral"
    end
    if firstId == secondId then
        return "self"
    end
    if not KnoxPersistence.isSurvivorAlive(firstId)
        or not KnoxPersistence.isSurvivorAlive(secondId) then
        return "neutral"
    end
    local first = ensureSurvivorState(firstId)
    local second = ensureSurvivorState(secondId)
    if first == nil or second == nil then
        return "neutral"
    end
    local firstAffiliation = first.affiliation or {}
    local secondAffiliation = second.affiliation or {}
    if firstAffiliation.kind == "player" and secondAffiliation.kind == "player"
        and firstAffiliation.ownerId ~= nil
        and firstAffiliation.ownerId == secondAffiliation.ownerId then
        return "allied"
    end
    local firstGroup = KnoxPersistence.getTravelGroupFor(firstId)
    local secondGroup = KnoxPersistence.getTravelGroupFor(secondId)
    if firstGroup ~= nil and secondGroup ~= nil and firstGroup.id == secondGroup.id then
        return "allied"
    end
    local firstFaction = KnoxPersistence.getFactionForSurvivor(firstId)
    local secondFaction = KnoxPersistence.getFactionForSurvivor(secondId)
    if firstFaction ~= nil and secondFaction ~= nil and firstFaction.id == secondFaction.id then
        return "allied"
    end
    local personal = KnoxPersistence.getRelationship(firstId, secondId)
    if personal ~= nil and personal.disposition == "hostile" then
        return "hostile"
    end
    if firstFaction ~= nil and secondFaction ~= nil then
        local factionRelationship = KnoxPersistence.getFactionRelationship(
            firstFaction.id,
            secondFaction.id
        )
        if factionRelationship ~= nil then
            return factionRelationship.disposition
        end
    end
    if personal ~= nil and personal.disposition == "allied" then
        return "allied"
    end
    return "neutral"
end

function KnoxPersistence.areSurvivorsAllied(firstId, secondId)
    local disposition = KnoxPersistence.getSurvivorDisposition(firstId, secondId)
    return disposition == "self" or disposition == "allied"
end

function KnoxPersistence.areSurvivorsHostile(firstId, secondId)
    return KnoxPersistence.getSurvivorDisposition(firstId, secondId) == "hostile"
end

function KnoxPersistence.createTravelGroup(memberIds, worldAgeHours)
    if type(memberIds) ~= "table" or #memberIds < 2 then
        return nil
    end
    for _, id in ipairs(memberIds) do
        local survivor = type(id) == "string" and ensureSurvivorState(id) or nil
        if survivor == nil or survivor.record == nil then
            return nil
        end
        local existing = KnoxPersistence.getTravelGroupFor(id)
        if existing ~= nil then
            return existing
        end
        if survivor.affiliation == nil or survivor.affiliation.kind ~= "independent"
            or survivor.duty == nil or survivor.duty.mode ~= "autonomous"
            or not KnoxPersistence.isIndependentSurvivor(id) then
            return nil
        end
    end
    local data = root()
    local id = "travel-group-" .. tostring(data.nextTravelGroupId)
    data.nextTravelGroupId = data.nextTravelGroupId + 1
    local members = {}
    for _, memberId in ipairs(memberIds) do
        if type(memberId) == "string" and memberId ~= ""
            and not containsId(members, memberId) then
            members[#members + 1] = memberId
        end
    end
    if #members < 2 then
        return nil
    end
    table.sort(members)
    local group = {
        id = id,
        leaderId = members[1],
        memberIds = members,
        formedAtHours = tonumber(worldAgeHours) or 0,
        memberJoinedAtHours = {},
        factionId = nil,
    }
    for _, memberId in ipairs(members) do
        group.memberJoinedAtHours[memberId] = group.formedAtHours
    end
    data.travelGroups[id] = group
    for firstIndex = 1, #members do
        for secondIndex = firstIndex + 1, #members do
            KnoxPersistence.setRelationshipDisposition(
                members[firstIndex], members[secondIndex], "allied", worldAgeHours
            )
        end
    end
    return group
end

function KnoxPersistence.addTravelGroupMember(groupId, survivorId)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    if group == nil or type(survivorId) ~= "string" or survivorId == "" then
        return nil
    end
    local survivorState = root().survivors[survivorId]
    if survivorState == nil or survivorState.record == nil then
        return nil
    end
    local affiliation = KnoxPersistence.getSurvivorAffiliation(survivorId)
    local duty = KnoxPersistence.getSurvivorDuty(survivorId)
    if duty == nil or duty.mode ~= "autonomous"
        or affiliation == nil or (affiliation.kind ~= "independent"
        and affiliation.factionId ~= group.factionId) then
        return nil
    end
    local otherGroup = KnoxPersistence.getTravelGroupFor(survivorId)
    if otherGroup ~= nil and otherGroup.id ~= group.id then
        return nil
    end
    if not containsId(group.memberIds, survivorId) then
        group.memberIds[#group.memberIds + 1] = survivorId
        table.sort(group.memberIds)
        group.memberJoinedAtHours = group.memberJoinedAtHours or {}
        group.memberJoinedAtHours[survivorId] = getGameTime() ~= nil
            and getGameTime():getWorldAgeHours()
            or 0
    end
    for _, memberId in ipairs(group.memberIds) do
        if memberId ~= survivorId then
            KnoxPersistence.setRelationshipDisposition(
                memberId,
                survivorId,
                "allied",
                getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
            )
        end
    end
    if group.factionId ~= nil then
        local survivor = ensureSurvivorState(survivorId)
        survivor.affiliation.kind = "faction"
        survivor.affiliation.ownerId = nil
        KnoxPersistence.addFactionMember(
            group.factionId,
            survivorId,
            getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
        )
    end
    return group
end

function KnoxPersistence.evaluateTravelGroupFaction(groupId, worldAgeHours)
    local group = type(groupId) == "string" and root().travelGroups[groupId] or nil
    if group == nil or #group.memberIds < 3 then
        return nil, "requires_three_members"
    end
    if group.factionId ~= nil then
        return root().factions[group.factionId], "already_faction"
    end
    local now = tonumber(worldAgeHours) or 0
    local leaderId = group.leaderId
    for _, memberId in ipairs(group.memberIds) do
        if memberId ~= leaderId then
            local relationship = KnoxPersistence.getRelationship(leaderId, memberId)
            local sharedActivity = relationship ~= nil
                and ((relationship.sharedRoam or 0)
                    + (relationship.sharedLoot or 0)
                    + (relationship.sharedCombat or 0))
                or 0
            if relationship == nil
                or ((relationship.nearbyHours or 0) < 1 and sharedActivity < 1) then
                return nil, "requires_shared_survival"
            end
        end
    end
    return KnoxPersistence.promoteTravelGroupToFaction(group.id, now)
end

function KnoxPersistence.promoteTravelGroupToFaction(groupId, worldAgeHours)
    local data = root()
    local group = type(groupId) == "string" and data.travelGroups[groupId] or nil
    if group == nil or #group.memberIds < 3 then
        return nil, "requires_three_members"
    end
    for _, memberId in ipairs(group.memberIds) do
        local survivor = ensureSurvivorState(memberId)
        if survivor.affiliation.kind == "player"
            or survivor.duty.mode == "companion"
            or survivor.duty.mode == "base" and survivor.affiliation.kind == "player" then
            KnoxPersistence.removeTravelGroupMember(memberId)
            return nil, "contains_player_survivor"
        end
    end
    if group.factionId ~= nil then
        return data.factions[group.factionId], "already_faction"
    end
    local factionId = "faction-" .. tostring(data.nextFactionId)
    data.nextFactionId = data.nextFactionId + 1
    local faction = {
        id = factionId,
        kind = "npc",
        leaderId = group.leaderId,
        memberIds = copyIds(group.memberIds),
        formedAtHours = tonumber(worldAgeHours) or 0,
        homeSafehouse = nil,
    }
    faction.name = stableFactionName(data, factionId, faction)
    data.factions[factionId] = faction
    group.factionId = factionId
    for _, memberId in ipairs(group.memberIds) do
        local survivor = ensureSurvivorState(memberId)
        survivor.affiliation.kind = "faction"
        survivor.affiliation.ownerId = nil
        KnoxPersistence.addFactionMember(factionId, memberId, worldAgeHours)
    end
    return faction, "created"
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values or {}) do
        if type(key) == "string" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local function livingIds(data, ids)
    local result = {}
    for _, id in ipairs(ids or {}) do
        local survivor = type(id) == "string" and data.survivors[id] or nil
        if survivor ~= nil and survivor.alive ~= false and not containsId(result, id) then
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

-- Repair old or interrupted saves at one persistence boundary.  This is not a
-- second relationship model: it removes contradictory roster copies and then
-- rebuilds each survivor's affiliation from the single retained owner.
function KnoxPersistence.normalizeRelationshipDomains()
    local data = root()
    local changes = 0
    local factionOwner = {}
    local factionIds = sortedKeys(data.factions)

    for _, factionId in ipairs(factionIds) do
        local faction = data.factions[factionId]
        faction.id = faction.id or factionId
        local cleaned = livingIds(data, faction.memberIds)
        if #cleaned ~= #(faction.memberIds or {}) then changes = changes + 1 end
        faction.memberIds = cleaned
    end

    -- A valid persisted affiliation wins over duplicate roster copies.
    for survivorId, survivor in pairs(data.survivors) do
        local affiliation = type(survivor) == "table" and survivor.affiliation or nil
        local factionId = affiliation ~= nil and affiliation.factionId or nil
        local faction = factionId ~= nil and data.factions[factionId] or nil
        local duty = type(survivor) == "table" and survivor.duty or nil
        local playerOwnerId = affiliation ~= nil and affiliation.kind == "player"
            and affiliation.ownerId
            or (duty ~= nil and (duty.mode == "companion" or duty.mode == "base")
                and duty.ownerId or nil)
        local player = playerOwnerId ~= nil and data.players[playerOwnerId] or nil
        local playerFaction = player ~= nil and data.factions[player.factionId] or nil
        if playerFaction ~= nil and playerFaction.kind == "player"
            and playerFaction.ownerPlayerId == playerOwnerId then
            factionId = playerFaction.id
            faction = playerFaction
        end
        if survivor.alive ~= false and faction ~= nil then
            factionOwner[survivorId] = factionId
            if not containsId(faction.memberIds, survivorId) then
                faction.memberIds[#faction.memberIds + 1] = survivorId
                table.sort(faction.memberIds)
                changes = changes + 1
            end
        elseif affiliation ~= nil and factionId ~= nil then
            survivor.affiliation = { kind = "independent", ownerId = nil }
            changes = changes + 1
        end
    end

    -- Deterministically retain the first valid roster only when affiliation did
    -- not already identify an owner.
    for _, factionId in ipairs(factionIds) do
        local faction = data.factions[factionId]
        local retained = {}
        for _, survivorId in ipairs(faction.memberIds) do
            local owner = factionOwner[survivorId]
            if owner == nil or owner == factionId then
                factionOwner[survivorId] = factionId
                retained[#retained + 1] = survivorId
            else
                changes = changes + 1
            end
        end
        faction.memberIds = retained
    end

    for survivorId, factionId in pairs(factionOwner) do
        local survivor = data.survivors[survivorId]
        local faction = data.factions[factionId]
        local expectedKind = faction.kind == "player" and "player" or "faction"
        local expectedOwner = faction.kind == "player" and faction.ownerPlayerId or nil
        if survivor.affiliation.kind ~= expectedKind
            or survivor.affiliation.factionId ~= factionId
            or survivor.affiliation.ownerId ~= expectedOwner then
            survivor.affiliation = {
                kind = expectedKind,
                ownerId = expectedOwner,
                factionId = factionId,
            }
            changes = changes + 1
        end
    end

    local groupOwner = {}
    local groupIds = sortedKeys(data.travelGroups)
    for _, groupId in ipairs(groupIds) do
        local group = data.travelGroups[groupId]
        group.id = group.id or groupId
        if group.factionId ~= nil and data.factions[group.factionId] == nil then
            group.factionId = nil
            changes = changes + 1
        end
        local retained = {}
        for _, survivorId in ipairs(livingIds(data, group.memberIds)) do
            local survivor = data.survivors[survivorId]
            local affiliation = survivor.affiliation or {}
            local compatible = affiliation.kind ~= "player"
                and (group.factionId == nil or affiliation.factionId == group.factionId)
            if compatible and groupOwner[survivorId] == nil then
                groupOwner[survivorId] = groupId
                retained[#retained + 1] = survivorId
            else
                changes = changes + 1
            end
        end
        group.memberIds = retained
        if #retained < 2 then
            for _, survivorId in ipairs(retained) do
                if groupOwner[survivorId] == groupId then
                    groupOwner[survivorId] = nil
                end
            end
            data.travelGroups[groupId] = nil
            changes = changes + 1
        else
            if not containsId(retained, group.leaderId) then
                group.leaderId = retained[1]
                changes = changes + 1
            end
        end
    end

    for _, factionId in ipairs(factionIds) do
        local faction = data.factions[factionId]
        if faction ~= nil then
            if faction.kind ~= "player" and #faction.memberIds == 0 then
                if faction.campId ~= nil then data.camps[faction.campId] = nil end
                data.factions[factionId] = nil
                changes = changes + 1
            elseif faction.kind ~= "player" and not containsId(
                faction.memberIds,
                faction.leaderId
            ) then
                faction.leaderId = faction.memberIds[1]
                changes = changes + 1
            end
        end
    end

    for campId, camp in pairs(data.camps) do
        local faction = type(camp) == "table" and data.factions[camp.factionId] or nil
        if faction == nil or faction.campId ~= campId then
            data.camps[campId] = nil
            changes = changes + 1
        else
            camp.memberIds = livingIds(data, faction.memberIds)
        end
    end
    return changes
end

function KnoxPersistence.removeSurvivorFromSocialDomains(id, reason, worldAgeHours)
    local data = root()
    local survivor = type(id) == "string" and data.survivors[id] or nil
    if survivor == nil then return false end
    requeueClaimsForSurvivor(id, nil, reason or "social_membership_removed")
    for _, group in pairs(data.travelGroups) do
        local retained = {}
        for _, memberId in ipairs(group.memberIds or {}) do
            if memberId ~= id then retained[#retained + 1] = memberId end
        end
        group.memberIds = retained
    end
    for _, faction in pairs(data.factions) do
        local retained = {}
        for _, memberId in ipairs(faction.memberIds or {}) do
            if memberId ~= id then retained[#retained + 1] = memberId end
        end
        faction.memberIds = retained
    end
    for _, camp in pairs(data.camps) do
        local retained = {}
        for _, memberId in ipairs(camp.memberIds or {}) do
            if memberId ~= id then retained[#retained + 1] = memberId end
        end
        camp.memberIds = retained
    end
    survivor.formerAffiliation = copySerializable(survivor.affiliation)
    survivor.affiliation = { kind = "deceased", ownerId = nil }
    survivor.duty = {
        mode = "deceased",
        order = "none",
        changedAtHours = tonumber(worldAgeHours) or 0,
        revision = (tonumber(survivor.duty ~= nil and survivor.duty.revision) or 0) + 1,
    }
    KnoxPersistence.normalizeRelationshipDomains()
    return true
end

function KnoxPersistence.getFactionBaseCandidate(factionId)
    local faction = KnoxPersistence.getFaction(factionId)
    return faction ~= nil and faction.baseSearch ~= nil
        and faction.baseSearch.candidate
        or nil
end

function KnoxPersistence.isFactionBaseCandidateRejected(factionId, buildingId, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    local rejected = faction ~= nil and faction.baseSearch ~= nil
        and faction.baseSearch.rejected
        or nil
    local rejectedUntil = rejected ~= nil and tonumber(rejected[buildingId]) or nil
    if rejectedUntil ~= nil and rejectedUntil <= (tonumber(worldAgeHours) or 0) then
        rejected[buildingId] = nil
        return false
    end
    return rejectedUntil ~= nil
end

function KnoxPersistence.recordFactionBaseCandidate(factionId, candidate, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    if faction == nil or faction.homeBase ~= nil or type(candidate) ~= "table"
        or type(candidate.buildingId) ~= "string" then
        return nil, "invalid_candidate"
    end
    faction.baseSearch = faction.baseSearch or { rejected = {} }
    faction.baseSearch.rejected = faction.baseSearch.rejected or {}
    local rejectedUntil = tonumber(faction.baseSearch.rejected[candidate.buildingId]) or 0
    if rejectedUntil > (tonumber(worldAgeHours) or 0) then
        return nil, "candidate_rejected"
    end
    local current = faction.baseSearch.candidate
    if current == nil or (tonumber(candidate.score) or 0) > (tonumber(current.score) or 0) then
        candidate.discoveredAtHours = tonumber(worldAgeHours) or 0
        faction.baseSearch.candidate = candidate
        return candidate, "recorded"
    end
    return current, "kept_better_candidate"
end

function KnoxPersistence.rejectFactionBaseCandidate(factionId, buildingId, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    if faction == nil or type(buildingId) ~= "string" then
        return false
    end
    faction.baseSearch = faction.baseSearch or { rejected = {} }
    faction.baseSearch.rejected = faction.baseSearch.rejected or {}
    faction.baseSearch.rejected[buildingId] = (tonumber(worldAgeHours) or 0) + 24
    if faction.baseSearch.candidate ~= nil
        and faction.baseSearch.candidate.buildingId == buildingId then
        faction.baseSearch.candidate = nil
    end
    return true
end

function KnoxPersistence.confirmFactionHomeBase(factionId, buildingId, worldAgeHours)
    local faction = KnoxPersistence.getFaction(factionId)
    local candidate = faction ~= nil and faction.baseSearch ~= nil
        and faction.baseSearch.candidate
        or nil
    if candidate == nil or candidate.buildingId ~= buildingId then
        return nil, "candidate_mismatch"
    end
    candidate.selectedAtHours = tonumber(worldAgeHours) or 0
    faction.homeBase = candidate
    faction.baseSearch.candidate = nil
    KnoxPersistence.clearFactionCamp(factionId, "home_established", worldAgeHours)
    return faction.homeBase, "selected"
end

local function copyWorldArea(source)
    if type(source) ~= "table" then
        return nil
    end
    return {
        buildingId = source.buildingId,
        x = tonumber(source.x),
        y = tonumber(source.y),
        z = tonumber(source.z) or 0,
        minX = tonumber(source.minX),
        minY = tonumber(source.minY),
        width = tonumber(source.width),
        height = tonumber(source.height),
        score = tonumber(source.score),
    }
end

function KnoxPersistence.getBases()
    return root().bases
end

function KnoxPersistence.getBase(id)
    return type(id) == "string" and root().bases[id] or nil
end

function KnoxPersistence.getBaseForOwner(ownerKind, ownerId)
    for _, base in pairs(root().bases) do
        if base ~= nil and base.ownerKind == ownerKind and base.ownerId == ownerId then
            return base
        end
    end
    return nil
end

local function normalizedBaseTerritory(baseId, bounds, worldAgeHours)
    if type(bounds) ~= "table" then
        return nil, "invalid_base"
    end
    local minX = math.min(tonumber(bounds.minX) or 0, tonumber(bounds.maxX) or 0)
    local minY = math.min(tonumber(bounds.minY) or 0, tonumber(bounds.maxY) or 0)
    local maxX = math.max(tonumber(bounds.minX) or 0, tonumber(bounds.maxX) or 0)
    local maxY = math.max(tonumber(bounds.minY) or 0, tonumber(bounds.maxY) or 0)
    if maxX - minX < 2 or maxY - minY < 2 then
        return nil, "area_too_small"
    end
    for otherId, other in pairs(root().bases) do
        local territory = other ~= nil and (other.territory or other.home) or nil
        local otherMaxX = territory ~= nil and (territory.maxX
            or (territory.minX + territory.width - 1)) or nil
        local otherMaxY = territory ~= nil and (territory.maxY
            or (territory.minY + territory.height - 1)) or nil
        if otherId ~= baseId and territory ~= nil
            and maxX >= territory.minX and minX <= otherMaxX
            and maxY >= territory.minY and minY <= otherMaxY then
            return nil, "overlaps_existing_base"
        end
    end
    return {
        minX = minX,
        minY = minY,
        maxX = maxX,
        maxY = maxY,
        allFloors = true,
        changedAtHours = tonumber(worldAgeHours) or 0,
    }, "valid"
end

function KnoxPersistence.canSetBaseTerritory(baseId, bounds, worldAgeHours)
    return normalizedBaseTerritory(baseId, bounds, worldAgeHours)
end

function KnoxPersistence.createBase(ownerKind, ownerId, home, worldAgeHours, territoryBounds)
    if (ownerKind ~= "player" and ownerKind ~= "faction")
        or type(ownerId) ~= "string" or ownerId == "" then
        return nil, "invalid_owner"
    end
    local area = copyWorldArea(home)
    if area == nil or area.minX == nil or area.minY == nil
        or area.width == nil or area.height == nil then
        return nil, "invalid_home"
    end
    local existing = KnoxPersistence.getBaseForOwner(ownerKind, ownerId)
    if existing ~= nil then
        return existing, "existing"
    end
    local territory = nil
    if territoryBounds ~= nil then
        local result
        territory, result = normalizedBaseTerritory(nil, territoryBounds, worldAgeHours)
        if territory == nil then
            return nil, result
        end
    else
        territory = {
            minX = area.minX,
            minY = area.minY,
            maxX = area.minX + area.width - 1,
            maxY = area.minY + area.height - 1,
            allFloors = true,
        }
    end
    local data = root()
    local id = "base-" .. tostring(data.nextBaseId)
    data.nextBaseId = data.nextBaseId + 1
    local base = {
        id = id,
        ownerKind = ownerKind,
        ownerId = ownerId,
        name = ownerKind == "player" and "Home Base" or "Survivor Camp",
        createdAtHours = tonumber(worldAgeHours) or 0,
        home = area,
        territory = territory,
        zones = {},
        nextZoneId = 1,
        storage = {},
        tasks = {},
        nextTaskId = 1,
        settings = {
            automaticJobs = true,
            allowWorkOutsideHome = true,
        },
    }
    data.bases[id] = base
    return base, "created"
end

function KnoxPersistence.updateBaseTerritory(baseId, bounds, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(bounds) ~= "table" then
        return nil, "invalid_base"
    end
    local territory, result = normalizedBaseTerritory(baseId, bounds, worldAgeHours)
    if territory == nil then return nil, result end
    base.territory = territory
    return base.territory, "updated"
end

function KnoxPersistence.relocateBase(baseId, home, territoryBounds, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local area = copyWorldArea(home)
    if base == nil or area == nil or area.minX == nil or area.minY == nil
        or area.width == nil or area.height == nil then
        return nil, "invalid_home"
    end
    local territory, result = normalizedBaseTerritory(baseId, territoryBounds, worldAgeHours)
    if territory == nil then return nil, result end
    for _, task in pairs(base.tasks or {}) do
        if task ~= nil and task.state == "claimed" then
            return nil, "task_in_progress"
        end
    end
    -- Keep the same base identity so resident/faction ownership remains valid.
    -- Location-bound policies and queued work belong to the old property and are
    -- discarded; the actual world containers, items, and structures are untouched.
    base.home = area
    base.territory = territory
    base.zones = {}
    base.storage = {}
    base.tasks = {}
    base.relocatedAtHours = tonumber(worldAgeHours) or 0
    return base, "relocated"
end

function KnoxPersistence.addBaseZone(baseId, zoneType, bounds, label)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(zoneType) ~= "string" or type(bounds) ~= "table" then
        return nil, "invalid_zone"
    end
    local minX = math.min(tonumber(bounds.x1) or 0, tonumber(bounds.x2) or 0)
    local maxX = math.max(tonumber(bounds.x1) or 0, tonumber(bounds.x2) or 0)
    local minY = math.min(tonumber(bounds.y1) or 0, tonumber(bounds.y2) or 0)
    local maxY = math.max(tonumber(bounds.y1) or 0, tonumber(bounds.y2) or 0)
    local id = base.id .. "-zone-" .. tostring(base.nextZoneId or 1)
    base.nextZoneId = (base.nextZoneId or 1) + 1
    local zone = {
        id = id,
        type = zoneType,
        label = tostring(label or zoneType),
        x1 = minX,
        y1 = minY,
        x2 = maxX,
        y2 = maxY,
        z = tonumber(bounds.z) or 0,
        enabled = true,
        priority = tonumber(bounds.priority) or 50,
    }
    base.zones[id] = zone
    return zone, "created"
end

function KnoxPersistence.removeBaseZone(baseId, zoneId)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or base.zones[zoneId] == nil then
        return false, "unknown_zone"
    end
    -- Never delete a target below a resident who is already on the way or
    -- working. The owner can retry after that task safely finishes/blocks.
    for _, task in pairs(base.tasks or {}) do
        if task ~= nil and task.target ~= nil and task.target.autoZoneId == zoneId
            and task.state == "claimed" then
            return false, "zone_has_active_task"
        end
    end
    for taskId, task in pairs(base.tasks or {}) do
        if task ~= nil and task.target ~= nil and task.target.autoZoneId == zoneId then
            base.tasks[taskId] = nil
        end
    end
    base.zones[zoneId] = nil
    return true, "removed"
end

function KnoxPersistence.setBaseStoragePolicy(baseId, reference, category, depot)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(reference) ~= "table" or type(reference.key) ~= "string" then
        return nil, "invalid_container"
    end
    local policy = {
        key = reference.key,
        x = tonumber(reference.x),
        y = tonumber(reference.y),
        z = tonumber(reference.z) or 0,
        objectIndex = tonumber(reference.objectIndex),
        containerIndex = tonumber(reference.containerIndex) or 0,
        containerType = tostring(reference.containerType or "container"),
        category = tostring(category or "general"),
        depot = depot == true,
    }
    base.storage[policy.key] = policy
    return policy, "saved"
end

function KnoxPersistence.removeBaseStoragePolicy(baseId, key)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or base.storage[key] == nil then
        return false
    end
    base.storage[key] = nil
    return true
end

local function baseTaskTargetSignature(target)
    if type(target) ~= "table" then
        return nil
    end
    if type(target.key) == "string" and target.key ~= "" then
        return "key=" .. target.key
    end
    if type(target.id) == "string" and target.id ~= "" then
        return "id=" .. target.id
    end
    local x = tonumber(target.x or target.x1)
    local y = tonumber(target.y or target.y1)
    if x == nil or y == nil then
        return nil
    end
    return table.concat({
        "x=" .. tostring(x),
        "y=" .. tostring(y),
        "z=" .. tostring(tonumber(target.z) or 0),
        "x2=" .. tostring(tonumber(target.x2) or x),
        "y2=" .. tostring(tonumber(target.y2) or y),
        "object=" .. tostring(tonumber(target.objectIndex) or -1),
        "container=" .. tostring(tonumber(target.containerIndex) or -1),
    }, ";")
end

function KnoxPersistence.queueBaseTask(baseId, taskType, target, requirements, priority)
    local base = KnoxPersistence.getBase(baseId)
    if base == nil or type(taskType) ~= "string" or type(target) ~= "table" then
        return nil, "invalid_task"
    end
    local targetSignature = baseTaskTargetSignature(target)
    if targetSignature == nil then
        return nil, "target_needs_stable_identity"
    end
    local signature = tostring(taskType) .. ":" .. targetSignature
    for _, existing in pairs(base.tasks) do
        if existing.signature == signature
            and (existing.state == "queued" or existing.state == "claimed") then
            return existing, "existing"
        end
    end
    local id = base.id .. "-task-" .. tostring(base.nextTaskId or 1)
    base.nextTaskId = (base.nextTaskId or 1) + 1
    local task = {
        id = id,
        signature = signature,
        type = taskType,
        state = "queued",
        priority = math.max(0, math.min(100, tonumber(priority) or 50)),
        target = copySerializable(target, 0),
        requirements = copySerializable(requirements or {}, 0),
        attempts = 0,
    }
    base.tasks[id] = task
    return task, "queued"
end

function KnoxPersistence.claimBaseTask(baseId, taskId, survivorId, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    local survivor = type(survivorId) == "string" and root().survivors[survivorId] or nil
    if survivor == nil or survivor.record == nil then
        return nil, "unknown_survivor"
    end
    if survivor.duty == nil or survivor.duty.mode ~= "base"
        or survivor.duty.baseId ~= baseId or survivor.duty.eventId ~= nil then
        return nil, "not_base_resident"
    end
    if task == nil or task.state ~= "queued" then
        return nil, "unavailable"
    end
    task.state = "claimed"
    task.claimedBy = survivorId
    task.claimedAtHours = tonumber(worldAgeHours) or 0
    task.attempts = (tonumber(task.attempts) or 0) + 1
    return task, "claimed"
end

function KnoxPersistence.finishBaseTask(
    baseId,
    taskId,
    survivorId,
    succeeded,
    reason,
    worldAgeHours
)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil or task.state ~= "claimed" or task.claimedBy ~= survivorId then
        return nil, "not_claimed_by_survivor"
    end
    task.state = succeeded and "complete" or "blocked"
    task.completedAtHours = tonumber(worldAgeHours) or 0
    task.result = tostring(reason or (succeeded and "complete" or "blocked"))
    local repeatDelay = 0.10
    if succeeded and task.type ~= "sort_depot" then
        repeatDelay = 0
    end
    task.retryAtHours = task.completedAtHours + repeatDelay
    return task, "finished"
end

-- A player may stop queued or finished automatic work, but never a task that a
-- resident has already claimed.  Interrupting a native timed action here would
-- leave the action controller and the persistent board disagreeing about who
-- owns the job.  A cancelled record remains as the stable target signature so
-- the automatic planner does not immediately recreate the same unwanted task.
function KnoxPersistence.cancelBaseTask(baseId, taskId, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil then
        return nil, "unknown_task"
    end
    if task.state == "claimed" then
        return nil, "task_in_progress"
    end
    if task.state == "cancelled" then
        return task, "already_cancelled"
    end
    task.state = "cancelled"
    task.claimedBy = nil
    task.claimedAtHours = nil
    task.completedAtHours = tonumber(worldAgeHours) or 0
    task.cancelledAtHours = task.completedAtHours
    task.result = "cancelled_by_player"
    task.retryAtHours = nil
    return task, "cancelled"
end

function KnoxPersistence.resumeBaseTask(baseId, taskId, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil then
        return nil, "unknown_task"
    end
    if task.state ~= "cancelled" then
        return nil, "not_cancelled"
    end
    task.state = "queued"
    task.cancelledAtHours = nil
    task.completedAtHours = nil
    task.result = nil
    task.retryAtHours = nil
    task.resumedAtHours = tonumber(worldAgeHours) or 0
    return task, "resumed"
end

-- Reopen a completed or blocked recurring task without losing its history.
-- One task record represents one persistent work-zone assignment; this avoids
-- creating an unbounded queue every time a guard finishes a patrol.
function KnoxPersistence.requeueBaseTask(baseId, taskId, worldAgeHours)
    local base = KnoxPersistence.getBase(baseId)
    local task = base ~= nil and base.tasks[taskId] or nil
    if task == nil then
        return nil, "unknown_task"
    end
    if task.state ~= "complete" and task.state ~= "blocked" then
        return nil, "not_finished"
    end
    local now = tonumber(worldAgeHours) or 0
    local retryAt = tonumber(task.retryAtHours) or 0
    if now < retryAt then
        return nil, "retry_not_ready"
    end
    task.runs = (tonumber(task.runs) or 0) + 1
    task.lastResult = task.result
    task.lastCompletedAtHours = task.completedAtHours
    task.state = "queued"
    task.claimedBy = nil
    task.claimedAtHours = nil
    task.completedAtHours = nil
    task.result = nil
    task.retryAtHours = nil
    task.requeuedAtHours = now
    return task, "requeued"
end

function KnoxPersistence.recoverInterruptedBaseTasks()
    local recovered = 0
    for _, base in pairs(root().bases) do
        for _, task in pairs(base.tasks or {}) do
            if task.state == "claimed" then
                task.state = "queued"
                task.lastClaimedBy = task.claimedBy
                task.claimedBy = nil
                task.claimedAtHours = nil
                task.interruptedReason = "save_reloaded"
                recovered = recovered + 1
            end
        end
    end
    return recovered
end

function KnoxPersistence.getSurvivorIds()
    local ids = {}
    for id, survivor in pairs(root().survivors) do
        if type(id) == "string" and survivor ~= nil and survivor.record ~= nil then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

function KnoxPersistence.captureActiveTestSurvivor()
    return KnoxPersistence.captureActiveSurvivor(TEST_SURVIVOR_ID)
end

function KnoxPersistence.captureActiveSurvivor(id)
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then
        return false, "bridge_unavailable"
    end
    local success, encoded = pcall(function()
        return bridge:captureNpcRecord(id)
    end)
    if not success or type(encoded) ~= "string" or encoded == ""
        or string.find(encoded, "CAPTURE_FAILED", 1, true) == 1 then
        return false, encoded
    end
    local saved = KnoxPersistence.setRecord(id, encoded)
    if saved and bridge.getNpcRecordInventorySummary ~= nil then
        local summaryOk, summary = pcall(bridge.getNpcRecordInventorySummary, bridge, encoded)
        if summaryOk and type(summary) == "string" then
            local survivor = ensureSurvivorState(id)
            survivor.inventorySummary = summary
            survivor.inventorySummaryAtHours = getGameTime() ~= nil
                and getGameTime():getWorldAgeHours() or 0
        end
    end
    local capabilities = rawget(_G, "KnoxSurvivorCapabilities")
    if saved and capabilities ~= nil and capabilities.capture ~= nil then
        local character = bridge:getNpcCharacter(id)
        if character ~= nil then
            capabilities.capture(id, character)
        end
    end
    if saved then
        local character = bridge:getNpcCharacter(id)
        local needs = rawget(_G, "KnoxSurvivorNeeds")
        if character ~= nil and needs ~= nil and needs.snapshot ~= nil then
            local snapshotOk, snapshot = pcall(needs.snapshot, character)
            if snapshotOk and type(snapshot) == "table" then
                local survivor = ensureSurvivorState(id)
                survivor.lastKnownNeeds = copyFlat(snapshot)
                survivor.lastKnownNeedsAtHours = getGameTime() ~= nil
                    and getGameTime():getWorldAgeHours()
                    or 0
                local unloaded = rawget(_G, "KnoxUnloadedSurvival")
                if unloaded ~= nil and unloaded.captureLoaded ~= nil then
                    unloaded.captureLoaded(
                        id,
                        snapshot,
                        survivor.lastKnownNeedsAtHours
                    )
                end
            end
        end
    end
    return saved, encoded
end

function KnoxPersistence.captureAllActiveSurvivors()
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then
        return false, "bridge_unavailable"
    end
    local activeIds = tostring(bridge:getActiveNpcIds())
    if activeIds == "" then
        return true, "none_active"
    end
    local captured = 0
    local failures = {}
    for id in string.gmatch(activeIds, "[^,]+") do
        local saved, evidence = KnoxPersistence.captureActiveSurvivor(id)
        if not saved then
            -- Do not let one malformed or unloading shell prevent the remaining
            -- survivors from being written.  Save captures are independent; keep
            -- the successful records and report all failures to the caller.
            failures[#failures + 1] = "id=" .. tostring(id) .. " " .. tostring(evidence)
        else
            captured = captured + 1
        end
    end
    if #failures > 0 then
        return false, "captured=" .. tostring(captured)
            .. " failed=" .. table.concat(failures, " | ")
    end
    return true, "captured=" .. tostring(captured)
end

function KnoxPersistence.isDevGateComplete(name)
    local data = root()
    return data.devTests ~= nil
        and data.devTests.completed ~= nil
        and data.devTests.completed[name] == true
end

function KnoxPersistence.markDevGateComplete(name)
    local data = root()
    data.devTests = data.devTests or {}
    data.devTests.completed = data.devTests.completed or {}
    data.devTests.completed[name] = true
end

local function onSave()
    local saved, evidence = KnoxPersistence.captureAllActiveSurvivors()
    if not saved then
        print("[KnoxSurvivors][Persistence] save-capture-failed=" .. tostring(evidence))
    end
end

local function onGameStart()
    local normalized = KnoxPersistence.normalizeRelationshipDomains()
    if normalized > 0 then
        print("[KnoxSurvivors][Persistence] normalized-social-domains="
            .. tostring(normalized))
    end
    local recovered = KnoxPersistence.recoverInterruptedBaseTasks()
    if recovered > 0 then
        print("[KnoxSurvivors][Persistence] requeued-interrupted-base-tasks="
            .. tostring(recovered))
    end
end

Events.OnSave.Add(onSave)
Events.OnGameStart.Add(onGameStart)
