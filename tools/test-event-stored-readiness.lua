local rootPath = arg[1] or "."
require = function() return true end
local data, hours = {}, 10
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return hours end } end
local function load(name) return assert(loadfile(rootPath .. "/mod/42/media/lua/client/" .. name .. ".lua"))() end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k, v in pairs(value) do result[k] = clone(v) end; return result
end
load("KS_Persistence"); load("KS_KnoxEvents"); load("KS_BaseManager")
local P, E = KnoxPersistence, KnoxEvents
local ids = { "a", "b", "c", "d", "e" }
local state = { health = 100, endurance = .9, fatigue = .1, hunger = .1, thirst = .1,
    bleedingParts = 0, virtualX = 103, virtualY = 103, virtualZ = 0, lastHours = 10, status = "hibernated" }
for _, id in ipairs(ids) do
    assert(P.setRecord(id, "native-record-" .. id)); assert(P.ensureSurvivorIdentity(id, id, "Tester", hours))
    P.setUnloadedSurvivalState(id, state)
end
local group = assert(P.createTravelGroup(ids, hours))
for _, id in ipairs({ "b", "c", "d", "e" }) do
    P.recordEncounter("a", id, { worldAgeHours = hours, began = true, sharedRoam = 1 })
end
local faction = assert(P.evaluateTravelGroupFaction(group.id, hours))
local playerFaction = assert(P.ensurePlayerFaction("player-1", hours))
local home = assert(P.createBase("faction", faction.id, { minX = 100, minY = 100, width = 10, height = 10 }, hours))
local target = assert(P.createBase("player", "player-1", { minX = 200, minY = 200, width = 10, height = 10 }, hours))
for _, id in ipairs(ids) do assert(P.setFactionBaseResident(id, faction.id, home.id, hours)) end
assert(P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "hostile", hours, "fixture"))
local event = assert(E.scheduleRaid(faction.id, target.id, hours, 0))
local baseline = clone(data)
local bodies, javaActive, ready, inspections = {}, {}, {}, 0
KnoxSurvivorRuntime = { getCharacter = function(id) return bodies[id] end }
KnoxJavaBridge = { isStoredNpcWeaponReady = function(_, id, encoded)
    inspections = inspections + 1
    assert(encoded == "native-record-" .. id, "inspection uses the actual member record")
    return not javaActive[id] and ready[id] ~= false
end }
local bridge = KnoxJavaBridge
local R = load("KS_EventRuntime")
local function reset()
    data = clone(baseline); bodies, javaActive, ready = {}, {}, {}; hours = 10; KnoxJavaBridge = bridge
end
assert(R.storedMemberReady("a", home, hours))
assert(P.getRecord("a") == "native-record-a" and P.getSurvivorDuty("a").eventId == nil,
    "readiness does not claim/create/change a survivor")
for key, value in pairs({ health = 20, bleedingParts = 1, endurance = .3, fatigue = .8, hunger = .8,
    thirst = .8, pendingMaterialization = true, restMode = "sleep", baseReturn = {}, virtualX = 150,
    lastHours = 9 }) do
    local changed = clone(state); changed[key] = value; P.setUnloadedSurvivalState("a", changed)
    assert(not R.storedMemberReady("a", home, hours), "unsafe stored state accepted: " .. key)
end
local upstairs = clone(state); upstairs.virtualZ = 1; P.setUnloadedSurvivalState("a", upstairs)
assert(R.storedMemberReady("a", home, hours), "all-floor base membership includes upstairs residents")
for _, key in ipairs({ "health", "lastHours", "virtualX", "thirst" }) do
    local changed = clone(state); changed[key] = nil; P.setUnloadedSurvivalState("a", changed)
    assert(not R.storedMemberReady("a", home, hours), "missing state defaulted to ready: " .. key)
end
reset(); bodies.a = {}
assert(not R.storedMemberReady("a", home, hours), "loaded body cannot use stale saved readiness")
reset(); javaActive.a = true
assert(not R.storedMemberReady("a", home, hours), "Java activation guard wins over missing Lua controller")
reset(); KnoxJavaBridge = {}
assert(not R.storedMemberReady("a", home, hours), "older bridge fails closed")
reset(); KnoxJavaBridge = { isStoredNpcWeaponReady = function() error("missing saved item") end }
assert(not R.storedMemberReady("a", home, hours), "decode failure must defer without throwing")
reset(); ready.b = false
assert(not R.dispatch(event, {}, hours) and P.getSurvivorDuty("a").eventId == nil,
    "whole real stored party must qualify before any claim")
reset(); local changed = clone(state); changed.health = 10; P.setUnloadedSurvivalState("b", changed)
assert(not R.dispatch(event, {}, hours) and P.getSurvivorDuty("a").eventId == nil)
reset()
assert(not R.dispatch(event, { b = { state = "COMBAT" } }, hours),
    "present busy controller cannot fall back to an old healthy snapshot")
assert(R.dispatch(event, {}, hours), "wholly stored party can depart without actor creation")
assert(E.get(event.id).phase == "approaching")
for _, id in ipairs({ "a", "b" }) do
    assert(P.getSurvivorDuty(id).eventId == event.id and P.getSurvivorDuty(id).baseId == home.id)
end
for _, id in ipairs({ "c", "d", "e" }) do assert(P.getSurvivorDuty(id).eventId == nil) end
assert(#P.getSurvivorIds() == 5 and next(bodies) == nil, "dispatch did not manufacture actors")
data = clone(data)
assert(P.getSurvivorDuty("a").eventId == E.get(event.id).id, "stored dispatch survives save reconstruction")

reset(); ready.a = false; inspections = 0
R.update({}, hours)
for _ = 1, 20 do R.update({}, hours) end
assert(inspections == 1 and E.get(event.id).phase == "scheduled", "failed native decoding is not repeated each update")
hours = 10.06; R.update({}, hours)
assert(inspections == 2, "bounded readiness retry can recover")
ready.a = true; hours = 10.12; R.update({}, hours)
assert(E.get(event.id).phase == "approaching", "later readiness resumes the same real event")
for _, id in ipairs(ids) do assert(P.getRecord(id) == "native-record-" .. id) end
assert(not R.storedMemberReady("unknown", home, hours) and #P.getSurvivorIds() == 5)
print("Stored event readiness PASS native_record=true fresh_needs=true active_guard=true atomic_party=true no_spawn=true bounded_retry=true reload=true")
