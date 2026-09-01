local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local data, hours = {}, 24
ModData = { getOrCreate = function(key) data[key] = data[key] or {} return data[key] end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return hours end } end
package.preload.SpawnRegions = function() return true end
SpawnRegionMgr = { getSpawnRegions = function() return { { name = "Town", points = { unemployed = {
    { posX = 400, posY = 200, posZ = 0 }, { posX = 700, posY = 200, posZ = 0 },
} } } } end }
getWorld = function() return { getMap = function() return "Named event runtime test" end } end

local playerSquare = { getX = function() return 200 end, getY = function() return 200 end,
    getZ = function() return 0 end }
local player = { getCurrentSquare = function() return playerSquare end }
getNumActivePlayers = function() return 1 end
getSpecificPlayer = function(index) return index == 0 and player or nil end

require "KS_Settings"
require "KS_Persistence"
require "KS_WorldPopulation"
require "KS_EventFactions"
require "KS_KnoxEvents"
local P, W, E = KnoxPersistence, KnoxWorldPopulation, KnoxEvents

KnoxSurvivorRuntime = { getCharacter = function() return nil end }
KnoxSurvivorNeeds = {}
KnoxFirearmSupport = {}
KnoxBaseManager = { containsSquare = function() return false end }
local originalRequire = require
require = function() return true end
local R = assert(loadfile(rootPath .. "/mod/42/media/lua/client/KS_EventRuntime.lua"))()
require = originalRequire

local event, scheduled = E.scheduleFactionEntry("police", "secure_area",
    { x = 200, y = 200, z = 0 }, 3, hours, 0)
assert(event ~= nil and scheduled == "scheduled" and event.phase == "scheduled")
assert(#P.getAllWorldSurvivorIds() == 0, "scheduling cannot create a survivor")
assert(E.scheduleFactionEntry("scientists", "research", { x = 200, y = 200, z = 0 }, 2,
    hours, 0) == nil, "world-age policy must apply before scheduling")

local dispatched, result = R.dispatch(event, {}, hours)
assert(dispatched and result == "dispatched")
event = E.get(event.id)
assert(event.phase == "approaching" and #event.memberIds == 3
    and type(event.sourceFactionId) == "string" and type(event.sourceGroupId) == "string")
local faction = assert(P.getFaction(event.sourceFactionId))
assert(faction.eventIdentity.policyId == "police"
    and faction.eventIdentity.sourceEventId == event.id and faction.name == "Police")
local seenDestinations = {}
for _, id in ipairs(event.memberIds) do
    local origin, duty = P.getSurvivorOrigin(id), P.getSurvivorDuty(id)
    assert(origin.source == "knox_event" and duty.eventId == event.id)
    local dx, dy = origin.x - playerSquare:getX(), origin.y - playerSquare:getY()
    assert(dx * dx + dy * dy >= 100 * 100, "event entry cannot be beside the player")
    local destination = assert(R.destination(event, id))
    local key = destination.x .. ":" .. destination.y .. ":" .. destination.z
    assert(not seenDestinations[key], "event members need distinct approach positions")
    seenDestinations[key] = true
end
local count = #P.getAllWorldSurvivorIds()
assert(not R.dispatch(event, {}, hours) and #P.getAllWorldSurvivorIds() == count,
    "a committed entry cannot allocate a second party")

local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z end }
end
local bodies, controllers = {}, {}
for _, id in ipairs(event.memberIds) do
    local destination = R.destination(event, id)
    local body = { x = destination.x, y = destination.y, z = destination.z }
    function body:getCurrentSquare() return square(self.x, self.y, self.z) end
    function body:getX() return self.x end
    function body:getY() return self.y end
    function body:isDead() return false end
    bodies[id] = body
    controllers[id] = { character = body, state = "IDLE", eventMoveFailures = 0 }
end
KnoxSurvivorRuntime.getCharacter = function(id) return bodies[id] end
R.update(controllers, hours)
assert(E.get(event.id).phase == "active", "real party positions establish arrival")
R.update(controllers, hours)
event = E.get(event.id)
assert(event.phase == "objective" and event.objective.kind == "secure_area",
    "named entry uses the common objective phase without a raid loot objective")
hours = event.objective.deadlineHours
R.update(controllers, hours)
event = E.get(event.id)
assert(event.phase == "withdrawing", "bounded objective time starts withdrawal")
for _, id in ipairs(event.memberIds) do
    local destination = R.destination(event, id)
    bodies[id].x, bodies[id].y, bodies[id].z = destination.x, destination.y, destination.z
end
R.update(controllers, hours)
event = E.get(event.id)
assert(event.phase == "completed")
for _, id in ipairs(event.memberIds) do
    assert(P.getSurvivorDuty(id).eventId == nil and P.isSurvivorAlive(id)
        and P.getUnloadedSurvivalState(id).eventEntryId == nil,
        "completion releases event duty and entry wait without deleting persistent survivors")
end
assert(P.getFaction(faction.id) ~= nil and #P.getAllWorldSurvivorIds() == count,
    "Police party remains ordinary persistent world population")

hours = hours + 1
local storedEvent = assert(E.scheduleFactionEntry("police", "secure_area",
    { x = 200, y = 200, z = 0 }, 2, hours, 0))
assert(R.dispatch(storedEvent, {}, hours))
storedEvent = E.get(storedEvent.id)
KnoxSurvivorNeeds.sleepRequired = function() return true end
KnoxJavaBridge = { consumeNpcRecordSupply = function() return nil end }
for _, id in ipairs(storedEvent.memberIds) do
    local origin = P.getSurvivorOrigin(id)
    assert(P.setRecord(id, "real-event-record-" .. id))
    P.setUnloadedSurvivalState(id, { hunger = .1, thirst = .1, health = 100,
        bleedingParts = 0, fatigue = .1, endurance = .9, lastHours = hours,
        virtualX = origin.x, virtualY = origin.y, virtualZ = origin.z,
        virtualAtHours = hours, status = "hibernated" })
    bodies[id] = nil
end
local simulation = require "KS_UnloadedSurvival"
local leader = storedEvent.memberIds[1]
local beforeX = P.getUnloadedSurvivalState(leader).virtualX
simulation.advanceAll({}, hours + 1)
local afterX = P.getUnloadedSurvivalState(leader).virtualX
assert(afterX < beforeX and E.get(storedEvent.id).unloadedTravel ~= nil,
    "fully stored named party reuses persistent cohort travel")
simulation.advanceAll({}, hours + 1)
assert(P.getUnloadedSurvivalState(leader).virtualX == afterX,
    "same-time named event update cannot double travel")

hours = hours + 1
local deferred = assert(E.scheduleFactionEntry("police", "secure_area",
    { x = 5000, y = 5000, z = 0 }, 2, hours, 0))
local before = #P.getAllWorldSurvivorIds()
local ok, why = R.dispatch(deferred, {}, hours)
assert(not ok and why == "no_safe_event_entry_origin")
deferred = E.get(deferred.id)
assert(deferred.phase == "spawning" and deferred.entryAttempts == 1
    and deferred.nextAttemptAtHours > hours and #P.getAllWorldSurvivorIds() == before)
local attempts = deferred.entryAttempts
assert(not R.dispatch(deferred, {}, hours) and E.get(deferred.id).entryAttempts == attempts,
    "persisted cooldown prevents an entry-attempt storm")

print("Named event runtime PASS scheduled=true atomic_entry=true no_duplicate=true distinct=true objective=true withdrawal=true persistence=true offscreen_travel=true bounded_retry=true")
