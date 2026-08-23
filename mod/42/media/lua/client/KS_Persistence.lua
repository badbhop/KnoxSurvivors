local KnoxPersistence = rawget(_G, "KnoxPersistence") or {}
_G.KnoxPersistence = KnoxPersistence

-- Kept separate from the legacy IsoZombie mod data that may exist in reused saves.
local MOD_DATA_KEY = "KnoxSurvivors_IsoPlayer"
local SCHEMA_VERSION = 3
local TEST_SURVIVOR_ID = "ks-test-1"

local function root()
    local data = ModData.getOrCreate(MOD_DATA_KEY)
    if data.schemaVersion ~= SCHEMA_VERSION then
        data.schemaVersion = SCHEMA_VERSION
        data.survivors = {}
    elseif data.survivors == nil then
        data.survivors = {}
    end
    return data
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
    root().survivors[id] = {
        id = id,
        record = encoded,
    }
    return true
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
