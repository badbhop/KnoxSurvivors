local root = arg[1] or "."
require = function() return true end
local data = {}
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
assert(loadfile(root .. "/mod/42/media/lua/client/KS_Persistence.lua"))()
local P = KnoxPersistence
local body = { isDead = function() return false end }
local payload, captureCalls = "native-record", 0
KnoxJavaBridge = {
    getNpcCharacter = function() return body end,
    captureNpcRecord = function() captureCalls = captureCalls + 1; return payload end,
}
assert(P.captureActiveSurvivor("new"))
assert(P.getRecord("new") == payload and P.isSurvivorPresent("new"))
payload = "CAPTURE_FAILED fixture"
assert(not P.captureActiveSurvivor("failed"))
assert(not P.isSurvivorPresent("failed") and P.getRecord("failed") == nil,
    "failed initial serialization must not create a ghost identity")
for _, id in ipairs({"new", "ks-test-1", "ks-dev-1"}) do
    P.setRecord(id, "last-alive-record")
    P.markSurvivorDead(id, 1, "test")
    local before = captureCalls
    assert(not P.captureActiveSurvivor(id))
    assert(captureCalls == before and not P.isSurvivorAlive(id)
        and P.getRecord(id) == "last-alive-record", "capture must not resurrect " .. id)
end
P.setRecord("departed", "saved")
data.survivors.departed.departure = {status = "departed"}
assert(not P.captureActiveSurvivor("departed") and P.getRecord("departed") == "saved")
body = nil
assert(not P.captureActiveSurvivor("missing") and not P.isSurvivorPresent("missing"))
body = { isDead = function() error("native failure") end }
assert(not P.captureActiveSurvivor("unknown") and not P.isSurvivorPresent("unknown"))
body = { isDead = function() return true end }
assert(not P.captureActiveSurvivor("corpse") and not P.isSurvivorPresent("corpse"))

-- A post-record hook failure is explicit, but the valid native record remains
-- available instead of being rolled back or silently reported as complete.
body = { isDead = function() return false end }
payload = "partial-native-record"
KnoxSurvivorCapabilities = {
    capture = function(id)
        if id == "partial" then error("capability fixture") end
    end,
}
local partialSaved, partialEvidence = P.captureActiveSurvivor("partial")
assert(not partialSaved and P.getRecord("partial") == payload
        and string.find(partialEvidence, "record_saved post_capture_failed=capabilities=", 1, true),
    "post-capture failure must be visible while preserving the valid record")

-- The outer save loop catches an entirely unexpected per-survivor exception
-- and still invokes every later survivor.
getGameTime = function() return { getWorldAgeHours = function() return 10 end } end
KnoxSurvivorNeeds = { snapshot = function() return { health = 100 } end }
KnoxUnloadedSurvival = { captureLoaded = function() return false end }
local ledgerSaved, ledgerEvidence = P.captureActiveSurvivor("ledger-rejected")
assert(not ledgerSaved and P.getRecord("ledger-rejected") == payload
    and string.find(ledgerEvidence, "unloaded=false", 1, true),
    "a rejected needs-ledger write must prevent a successful storage handoff")
KnoxUnloadedSurvival = nil
KnoxSurvivorNeeds = nil
KnoxJavaBridge.getActiveNpcIds = function() return "first,bad,last" end
local originalCapture = P.captureActiveSurvivor
local visited = {}
P.captureActiveSurvivor = function(id)
    visited[#visited + 1] = id
    if id == "bad" then error("unexpected fixture") end
    return true, "saved"
end
local allSaved, allEvidence = P.captureAllActiveSurvivors()
P.captureActiveSurvivor = originalCapture
assert(not allSaved and table.concat(visited, ",") == "first,bad,last"
        and string.find(allEvidence, "captured=2", 1, true)
        and string.find(allEvidence, "id=bad exception=", 1, true),
    "one unexpected survivor exception must not block later save captures")

print("First capture PASS live_admission=true atomic_failure=true death=true departure=true isolation=true partial=true")
