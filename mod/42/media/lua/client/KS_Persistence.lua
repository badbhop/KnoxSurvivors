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
    local survivor = root().survivors[TEST_SURVIVOR_ID]
    return survivor ~= nil and survivor.record or nil
end

function KnoxPersistence.setTestRecord(encoded)
    if type(encoded) ~= "string" or encoded == "" then
        return false
    end
    root().survivors[TEST_SURVIVOR_ID] = {
        id = TEST_SURVIVOR_ID,
        record = encoded,
    }
    return true
end

function KnoxPersistence.captureActiveTestSurvivor()
    local bridge = rawget(_G, "KnoxJavaBridge")
    if bridge == nil then
        return false, "bridge_unavailable"
    end
    local success, encoded = pcall(function()
        return bridge:captureTestNpcRecord()
    end)
    if not success or type(encoded) ~= "string" or encoded == ""
        or string.find(encoded, "CAPTURE_FAILED", 1, true) == 1 then
        return false, encoded
    end
    return KnoxPersistence.setTestRecord(encoded), encoded
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
    KnoxPersistence.captureActiveTestSurvivor()
end

Events.OnPostSave.Add(onPostSave)
