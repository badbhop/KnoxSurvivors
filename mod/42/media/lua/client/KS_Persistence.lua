local KnoxPersistence = rawget(_G, "KnoxPersistence") or {}
_G.KnoxPersistence = KnoxPersistence

-- Kept separate from the legacy IsoZombie mod data that may exist in reused saves.
local MOD_DATA_KEY = "KnoxSurvivors_IsoPlayer"
local SCHEMA_VERSION = 7
local TEST_SURVIVOR_ID = "ks-test-1"

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
    data.nextFactionId = data.nextFactionId or 1
    if type(data.players) ~= "table" then
        data.players = {}
    end
    data.nextPlayerId = data.nextPlayerId or 1
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
    -- Rebuild schemas 1 and 2 already stored compatible encoded survivor records.
    -- Add newer domain tables in place instead of erasing people on a version bump.
    if previousVersion < SCHEMA_VERSION then
        data.migratedFromSchema = previousVersion
    end
    data.schemaVersion = SCHEMA_VERSION
    return data
end

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
    survivor.playerRelationships = survivor.playerRelationships or {}
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

function KnoxPersistence.ensureSurvivorIdentity(id, forename, surname, worldAgeHours)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    local data = root()
    local survivor = data.survivors[id] or { id = id }
    survivor.identity = survivor.identity or {}
    survivor.identity.forename = survivor.identity.forename or tostring(forename or "")
    survivor.identity.surname = survivor.identity.surname or tostring(surname or "")
    survivor.identity.createdAtHours = survivor.identity.createdAtHours
        or tonumber(worldAgeHours)
        or 0
    survivor.identity.sociability = survivor.identity.sociability
        or stableTrait(id, 1)
    survivor.identity.aggression = survivor.identity.aggression
        or stableTrait(id, 2)
    data.survivors[id] = survivor
    return survivor.identity
end

function KnoxPersistence.getSurvivorIdentity(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and survivor.identity or nil
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
    if KnoxPersistence.getTravelGroupFor ~= nil
        and KnoxPersistence.getTravelGroupFor(id) ~= nil then
        return false, "already_with_group"
    end
    if survivor.duty.mode == "base" then
        requeueClaimsForSurvivor(id, survivor.duty.baseId, "recalled_as_companion")
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

function KnoxPersistence.updateCompanionOrder(id, playerId, order, worldAgeHours)
    local survivor = ensureSurvivorState(id)
    local allowed = order == "follow" or order == "hold"
    if survivor == nil or not allowed
        or survivor.affiliation.kind ~= "player"
        or survivor.affiliation.ownerId ~= playerId
        or survivor.duty.mode ~= "companion" then
        return false
    end
    survivor.duty.order = order
    survivor.duty.ownerId = playerId
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
        if survivor ~= nil and survivor.affiliation ~= nil
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
        }
        survivor.playerRelationships[playerId] = relation
    end
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
    if key == nil then
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
    for _, group in pairs(root().travelGroups) do
        if group ~= nil and containsId(group.memberIds, id) then
            return group
        end
    end
    return nil
end

function KnoxPersistence.removeTravelGroupMember(survivorId)
    local data = root()
    local group = KnoxPersistence.getTravelGroupFor(survivorId)
    if group == nil then
        return false
    end
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
    if group.factionId ~= nil then
        KnoxPersistence.removeFactionMember(group.factionId, survivorId)
    end
    if group.leaderId == survivorId then
        group.leaderId = retained[1]
    end
    if #retained < 2 then
        data.travelGroups[group.id] = nil
    end
    return true
end

function KnoxPersistence.getFaction(id)
    return type(id) == "string" and root().factions[id] or nil
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

function KnoxPersistence.createTravelGroup(memberIds, worldAgeHours)
    if type(memberIds) ~= "table" or #memberIds < 2 then
        return nil
    end
    for _, id in ipairs(memberIds) do
        local survivor = type(id) == "string" and root().survivors[id] or nil
        if survivor == nil or survivor.record == nil then
            return nil
        end
        local existing = KnoxPersistence.getTravelGroupFor(id)
        if existing ~= nil then
            return existing
        end
        if not KnoxPersistence.isIndependentSurvivor(id) then
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
    if affiliation == nil or (affiliation.kind ~= "independent"
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

function KnoxPersistence.createBase(ownerKind, ownerId, home, worldAgeHours)
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
        return false
    end
    base.zones[zoneId] = nil
    return true
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
        or survivor.duty.baseId ~= baseId then
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
    return task, "finished"
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
    local capabilities = rawget(_G, "KnoxSurvivorCapabilities")
    if saved and capabilities ~= nil and capabilities.capture ~= nil then
        local character = bridge:getNpcCharacter(id)
        if character ~= nil then
            capabilities.capture(id, character)
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
    for id in string.gmatch(activeIds, "[^,]+") do
        local saved, evidence = KnoxPersistence.captureActiveSurvivor(id)
        if not saved then
            return false, "id=" .. tostring(id) .. " " .. tostring(evidence)
        end
        captured = captured + 1
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
    KnoxPersistence.captureAllActiveSurvivors()
end

local function onGameStart()
    local recovered = KnoxPersistence.recoverInterruptedBaseTasks()
    if recovered > 0 then
        print("[KnoxSurvivors][Persistence] requeued-interrupted-base-tasks="
            .. tostring(recovered))
    end
end

Events.OnSave.Add(onSave)
Events.OnGameStart.Add(onGameStart)
