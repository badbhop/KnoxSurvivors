local KnoxPersistence = rawget(_G, "KnoxPersistence") or {}
_G.KnoxPersistence = KnoxPersistence

-- Kept separate from the legacy IsoZombie mod data that may exist in reused saves.
local MOD_DATA_KEY = "KnoxSurvivors_IsoPlayer"
local SCHEMA_VERSION = 3
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
    -- Rebuild schemas 1 and 2 already stored compatible encoded survivor records.
    -- Add newer domain tables in place instead of erasing people on a version bump.
    if previousVersion < SCHEMA_VERSION then
        data.migratedFromSchema = previousVersion
    end
    data.schemaVersion = SCHEMA_VERSION
    return data
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
    data.survivors[id] = survivor
    return survivor.identity
end

function KnoxPersistence.getSurvivorIdentity(id)
    local survivor = type(id) == "string" and root().survivors[id] or nil
    return survivor ~= nil and survivor.identity or nil
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

function KnoxPersistence.getTravelGroupFor(id)
    for _, group in pairs(root().travelGroups) do
        if group ~= nil and containsId(group.memberIds, id) then
            return group
        end
    end
    return nil
end

function KnoxPersistence.createTravelGroup(memberIds, worldAgeHours)
    if type(memberIds) ~= "table" or #memberIds < 2 then
        return nil
    end
    for _, id in ipairs(memberIds) do
        local existing = KnoxPersistence.getTravelGroupFor(id)
        if existing ~= nil then
            return existing
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
    group.memberJoinedAtHours = group.memberJoinedAtHours or {}
    local latestJoin = group.formedAtHours or now
    for _, memberId in ipairs(group.memberIds) do
        local joined = tonumber(group.memberJoinedAtHours[memberId])
            or tonumber(group.formedAtHours)
            or now
        group.memberJoinedAtHours[memberId] = joined
        latestJoin = math.max(latestJoin, joined)
    end
    if now - latestJoin < 24 then
        return nil, "requires_one_day_together"
    end

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
        leaderId = group.leaderId,
        memberIds = copyIds(group.memberIds),
        formedAtHours = tonumber(worldAgeHours) or 0,
        homeSafehouse = nil,
    }
    data.factions[factionId] = faction
    group.factionId = factionId
    return faction, "created"
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
    return KnoxPersistence.setRecord(id, encoded), encoded
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

local function onPostSave()
    KnoxPersistence.captureAllActiveSurvivors()
end

Events.OnPostSave.Add(onPostSave)
