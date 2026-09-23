local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path

local data, hours = {}, 24
ModData = { getOrCreate = function(key) data[key] = data[key] or {} return data[key] end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return hours end } end
package.preload.SpawnRegions = function() return true end
SpawnRegionMgr = { getSpawnRegions = function() return { { name = "Town", points = { unemployed = {
    { posX = 400, posY = 200, posZ = 0 }, { posX = 700, posY = 200, posZ = 0 },
    { posX = 400, posY = 400, posZ = 0 }, { posX = 500, posY = 300, posZ = 0 },
    { posX = 300, posY = 500, posZ = 0 }, { posX = 600, posY = 400, posZ = 0 },
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
local threats = {
    { x = 201, y = 200, z = 0, dead = false },
}
local function zombieList()
    return { size = function() return #threats end,
        get = function(_, index)
            local state = threats[index + 1]
            if state == nil then return nil end
            return { isDead = function() return state.dead end,
                getCurrentSquare = function() return square(state.x, state.y, state.z) end }
        end }
end
getCell = function() return { getZombieList = zombieList } end
hours = event.objective.startedAtHours + 0.01
R.update(controllers, hours)
event = E.get(event.id)
assert(event.phase == "objective" and event.objective.lastThreatCount == 1
    and event.objective.clearSinceHours == nil, "real nearby threat keeps secure objective active")
threats = {}
hours = event.objective.startedAtHours + 0.03
R.update(controllers, hours)
event = E.get(event.id)
assert(event.phase == "objective" and event.objective.clearSinceHours == hours,
    "first clear scan starts persisted confirmation window")
hours = event.objective.startedAtHours + 0.09
R.update(controllers, hours)
event = E.get(event.id)
assert(event.phase == "withdrawing", "bounded objective time starts withdrawal")
assert(event.objective.outcome == "area_secure" and event.reason == "area_secured",
    "two separated real clear observations finish secure-area work")
for _, id in ipairs(event.memberIds) do
    local destination = R.destination(event, id)
    bodies[id].x, bodies[id].y, bodies[id].z = destination.x, destination.y, destination.z
end
R.update(controllers, hours)
event = E.get(event.id)
assert(event.phase == "withdrawing", "police patrol leaves instead of settling")
-- Simulate the autonomy owner capturing/removing the loaded shells; the
-- unloaded records wait at the departure point.
for _, id in ipairs(event.memberIds) do
    assert(P.beginEventDeparture(id, event.id, hours), "withdrawn patrol departs the county")
    local destination = R.destination(event, id)
    P.setUnloadedSurvivalState(id, { hunger = .1, thirst = .1, health = 100,
        bleedingParts = 0, fatigue = .1, endurance = .9, lastHours = hours,
        virtualX = destination.x, virtualY = destination.y, virtualZ = destination.z,
        virtualAtHours = hours, status = "hibernated" })
    bodies[id] = nil
    controllers[id] = nil
end
R.update(controllers, hours)
event = E.get(event.id)
assert(event.phase == "completed")
for _, id in ipairs(event.memberIds) do
    assert(P.getSurvivorDuty(id).eventId == nil and P.isSurvivorAlive(id)
        and P.getUnloadedSurvivalState(id).eventEntryId == nil,
        "departure releases event duty and entry wait without deleting persistent survivors")
end
assert(P.getFaction(faction.id) ~= nil and #P.getAllWorldSurvivorIds() == count,
    "Police party leaves no base and loses no population")

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
_G.KnoxOffscreenStoriesDisabled = true
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

-- Event-only parties remain real persistent identities while present, then
-- leave through their entry anchor without being marked dead or reactivated.
hours = 14 * 24
local scientists = assert(E.scheduleFactionEntry("scientists", "research",
    { x = 200, y = 200, z = 0 }, 2, hours, 0))
assert(R.dispatch(scientists, {}, hours))
scientists = E.get(scientists.id)
local scientistFactionId = scientists.sourceFactionId
for _, id in ipairs(scientists.memberIds) do
    local policy = assert(KnoxEventFactions.materializationPolicy(id))
    assert(policy.professionId == "base:doctor" and policy.loadoutTheme == "science"
        and policy.appearanceItems[1] == "Base.JacketLong_Doctor",
        "Scientist entry retains its first-materialization policy")
    local destination = assert(R.destination(scientists, id))
    assert(P.setRecord(id, "scientist-record-" .. id))
    P.setUnloadedSurvivalState(id, { hunger = .1, thirst = .1, health = 100,
        bleedingParts = 0, fatigue = .1, endurance = .9, lastHours = hours,
        virtualX = destination.x, virtualY = destination.y, virtualZ = destination.z,
        virtualAtHours = hours, status = "hibernated" })
    local body = { x = destination.x, y = destination.y, z = destination.z }
    function body:getCurrentSquare() return square(self.x, self.y, self.z) end
    function body:getX() return self.x end
    function body:getY() return self.y end
    function body:isDead() return false end
    bodies[id] = body
    controllers[id] = { character = body, state = "IDLE", eventMoveFailures = 0 }
end
R.update(controllers, hours)
R.update(controllers, hours)
scientists = E.get(scientists.id)
assert(scientists.phase == "objective" and scientists.objective.kind == "research")
for _, id in ipairs(scientists.memberIds) do
    bodies[id], controllers[id] = nil, nil
end
hours = scientists.objective.deadlineHours
R.update(controllers, hours)
scientists = E.get(scientists.id)
assert(scientists.phase == "withdrawing")
for _, id in ipairs(scientists.memberIds) do
    local destination = assert(R.destination(scientists, id))
    local state = P.getUnloadedSurvivalState(id)
    state.virtualX, state.virtualY, state.virtualZ = destination.x, destination.y, destination.z
    state.lastHours, state.virtualAtHours = hours, hours
    P.setUnloadedSurvivalState(id, state)
end
local loadedDepartingId = scientists.memberIds[1]
local loadedDestination = assert(R.destination(scientists, loadedDepartingId))
local loadedBody = { x = loadedDestination.x, y = loadedDestination.y, z = loadedDestination.z }
function loadedBody:getCurrentSquare() return square(self.x, self.y, self.z) end
function loadedBody:getX() return self.x end
function loadedBody:getY() return self.y end
function loadedBody:isDead() return false end
bodies[loadedDepartingId] = loadedBody
controllers[loadedDepartingId] = {
    character = loadedBody, state = "IDLE", eventMoveFailures = 0,
}
R.update(controllers, hours)
scientists = E.get(scientists.id)
local pending = assert(P.getSurvivorDeparture(loadedDepartingId))
assert(scientists.phase == "withdrawing" and pending.status == "pending"
    and not P.isSurvivorPresent(loadedDepartingId)
    and P.getSurvivorDuty(loadedDepartingId).eventId == scientists.id,
    "loaded departure blocks reactivation but retains event ownership until shell teardown")
bodies[loadedDepartingId], controllers[loadedDepartingId] = nil, nil
assert(P.finalizeEventDeparture(loadedDepartingId, scientists.id, hours))
R.update(controllers, hours)
scientists = E.get(scientists.id)
assert(scientists.phase == "completed", "event-only party completes after every real shell is retired")
local activatable = {}; for _, id in ipairs(P.getActivatableSurvivorIds()) do activatable[id] = true end
local living = {}; for _, id in ipairs(P.getLivingWorldSurvivorIds()) do living[id] = true end
for _, id in ipairs(scientists.memberIds) do
    local departure = assert(P.getSurvivorDeparture(id))
    assert(P.isSurvivorAlive(id) and not P.isSurvivorPresent(id)
        and departure.status == "departed" and departure.eventId == scientists.id
        and P.getSurvivorDuty(id).mode == "departed"
        and P.getRecord(id) == "scientist-record-" .. id
        and not activatable[id] and not living[id],
        "departure retains identity/record but excludes the survivor from world presence")
end
local departedFaction = assert(P.getFaction(scientistFactionId))
assert(departedFaction.lifecycle == "departed" and #departedFaction.memberIds == 0,
    "departed event faction remains as history without active members")

hours = hours + 1
local scavengers = assert(E.scheduleFactionEntry("scavengers", "scavenge_world",
    { x = 200, y = 200, z = 0 }, 3, hours, 0))
assert(R.dispatch(scavengers, {}, hours))
scavengers = E.get(scavengers.id)
for _, id in ipairs(scavengers.memberIds) do
    local destination = assert(R.destination(scavengers, id))
    local body = { x = destination.x, y = destination.y, z = destination.z }
    function body:getCurrentSquare() return square(self.x, self.y, self.z) end
    function body:getX() return self.x end
    function body:getY() return self.y end
    function body:isDead() return false end
    bodies[id] = body
    controllers[id] = { character = body, state = "IDLE", eventMoveFailures = 0 }
end
R.update(controllers, hours)
R.update(controllers, hours)
scavengers = E.get(scavengers.id)
assert(scavengers.phase == "objective" and scavengers.objective.kind == "scavenge_world"
    and scavengers.objective.requiredItems == 6 and E.objectiveCount(scavengers) == 0,
    "Scavenger search starts with no fabricated loot evidence")
assert(E.finishFactionEntryObjective(scavengers.id, scavengers.revision, hours, "no_supplies") == nil,
    "Scavenger search cannot finish before real completion/exhaustion/deadline evidence")

local scavengerId = scavengers.memberIds[1]
local scavengerBody = bodies[scavengerId]
local searchDirective = nil
controllers[scavengerId].eventAssignment = { id = scavengers.id }
controllers[scavengerId].beginExploration = function(_, _, directive)
    searchDirective = directive
    return true
end
assert(R.beginObjectiveWork(controllers[scavengerId], 100)
    and searchDirective.kind == "loot_area" and searchDirective.eventId == scavengers.id
    and searchDirective.minX == 182 and searchDirective.maxX == 218,
    "Scavengers reuse the bounded existing loot-area controller")
local carried = {}
function scavengerBody:getInventory() return carried end
KnoxSurvivorRuntime.idForCharacter = function(character)
    return character == scavengerBody and scavengerId or nil
end
instanceof = function() return false end
local source = {
    getSourceGrid = function() return square(201, 200, 0) end,
    getParent = function() return {} end,
    isInCharacterInventory = function() return false end,
}
assert(R.captureLootContext(scavengerBody, source, carried) ~= nil,
    "real world container inside the bounded search area is eligible")
source.getSourceGrid = function() return square(240, 200, 0) end
assert(R.captureLootContext(scavengerBody, source, carried) == nil,
    "containers outside the bounded search area cannot count")

hours = hours + 0.1
assert(E.recordLoot(scavengers.id, scavengerId,
    { itemId = "real-scavenged-item", fullType = "Base.Crisps", x = 201, y = 200, z = 0 }, hours))
for _, id in ipairs(scavengers.memberIds) do
    for _ = 1, 3 do assert(E.recordEmptySearch(scavengers.id, id)) end
end
R.reviewObjective(scavengers, hours)
scavengers = E.get(scavengers.id)
assert(scavengers.phase == "withdrawing" and scavengers.objective.outcome == "partial_supplies"
    and E.objectiveCount(scavengers) == 1,
    "only durable real-transfer evidence produces a partial Scavenger outcome: "
        .. tostring(scavengers.phase) .. "/" .. tostring(scavengers.objective.outcome))
for _, id in ipairs(scavengers.memberIds) do
    local destination = assert(R.destination(scavengers, id))
    bodies[id].x, bodies[id].y, bodies[id].z = destination.x, destination.y, destination.z
end
R.update(controllers, hours)
scavengers = E.get(scavengers.id)
assert(scavengers.phase == "completed"
    and #P.getFaction(scavengers.sourceFactionId).memberIds == 3,
    "persistent Scavengers rejoin ordinary world life after the evidenced transfer")

print("Named event runtime PASS scheduled=true atomic_entry=true no_duplicate=true distinct=true objective=true withdrawal=true persistence=true offscreen_travel=true bounded_retry=true event_departure=true scavenging=true")
