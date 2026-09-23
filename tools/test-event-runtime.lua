local rootPath = arg[1] or "."
require = function() return true end
local data, hours = {}, 10
ModData = { getOrCreate = function() return data end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
getGameTime = function() return { getWorldAgeHours = function() return hours end } end
ZombRand = function() return 0 end
local function load(name) return assert(loadfile(rootPath .. "/mod/42/media/lua/client/" .. name .. ".lua"))() end
load("KS_Persistence")
load("KS_KnoxEvents")
load("KS_BaseManager")
load("KS_SurvivorAutonomyController")
local P, E, Controller = KnoxPersistence, KnoxEvents, KnoxAutonomyController
local bodies, controllers = {}, {}
KnoxSurvivorRuntime = { getCharacter = function(id) return bodies[id] end }
KnoxSurvivorNeeds = {
    snapshot = function(body) return body.needs end,
    wakeForDanger = function() return false end,
}
KnoxFirearmSupport = { isReady = function(_, weapon) return weapon.ready end }
ISTimedActionQueue = { clear = function() end }
local R = load("KS_EventRuntime")
local function square(x, y, z)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return z or 0 end, canStand = function() return true end,
        getBuilding = function() return nil end }
end
getCell = function() return { getGridSquare = function(_, x, y, z) return square(x, y, z) end } end
local function body()
    local b = { x = 103, y = 103, z = 0, needs = { health = 100, bleedingParts = 0,
        endurance = .9, fatigue = .1, hunger = .1, thirst = .1 }, busy = false,
        weapon = { IsWeapon = function() return true end, isBroken = function() return false end,
            isRanged = function() return false end } }
    function b:getCurrentSquare() return square(self.x, self.y, self.z) end
    function b:getX() return self.x end
    function b:getY() return self.y end
    function b:isDead() return self.dead == true end
    function b:getCharacterActions() return { isEmpty = function() return not self.busy end } end
    function b:getPrimaryHandItem() return self.weapon end
    function b:isSitOnGround() return false end
    function b:isSittingOnFurniture() return false end
    function b:setIsResting() end
    function b:setBed() end
    return b
end
local ids = { "a", "b", "c", "d", "e" }
for _, id in ipairs(ids) do
    assert(P.setRecord(id, "native-record-" .. id))
    assert(P.ensureSurvivorIdentity(id, id, "Tester", hours))
    bodies[id] = body()
    local bridge = { cancels = 0, moves = 0 }
    function bridge:cancelNpcMove() self.cancels = self.cancels + 1 end
    function bridge:moveNpcWithPace(_, destination, pace)
        self.moves, self.destination, self.pace = self.moves + 1, destination, pace
        return "MOVE_STARTED"
    end
    controllers[id] = setmetatable({ id = id, character = bodies[id], bridge = bridge,
        state = "BASE_IDLE", nextThink = 0, counts = { failures = 0 },
        reservations = { items = {}, containers = {}, restSpots = {} },
        groupMembers = {}, movementFailureStreak = 0, failureReasons = {} }, { __index = Controller })
end
local group = assert(P.createTravelGroup(ids, hours))
for _, id in ipairs({ "b", "c", "d", "e" }) do P.recordEncounter("a", id, { worldAgeHours = hours, began = true, sharedRoam = 1 }) end
local faction = assert(P.evaluateTravelGroupFaction(group.id, hours))
local playerFaction = assert(P.ensurePlayerFaction("player-1", hours))
local home = assert(P.createBase("faction", faction.id, { minX = 100, minY = 100, width = 10, height = 10 }, hours))
local target = assert(P.createBase("player", "player-1", { minX = 200, minY = 200, width = 10, height = 10 }, hours))
for _, id in ipairs(ids) do assert(P.setFactionBaseResident(id, faction.id, home.id, hours)) end
P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "hostile", hours, "fixture")
local event = assert(E.scheduleRaid(faction.id, target.id, hours, 0))
bodies.b.needs.bleedingParts = 1
assert(not R.dispatch(event, controllers, hours) and P.getSurvivorDuty("a").eventId == nil,
    "one injured member rejects dispatch without a partial claim")
bodies.b.needs.bleedingParts = 0
bodies.b.weapon = nil
assert(not R.dispatch(event, controllers, hours), "an empty hand fails cleanly without an IsWeapon exception")
bodies.b.weapon = { IsWeapon = function() return true end, isBroken = function() return false end,
    isRanged = function() return true end, ready = false }
assert(not R.dispatch(event, controllers, hours), "an unusable gun cannot qualify a raider")
bodies.b.weapon.ready = true
assert(R.dispatch(event, controllers, hours))
event = E.get(event.id)
assert(event.phase == "approaching" and P.getSurvivorDuty("a").eventId == event.id)
assert(P.getSurvivorDuty("a").baseId == home.id and P.getSurvivorAffiliation("a").factionId == faction.id)
assert(P.getSurvivorDuty("c").eventId == nil, "defenders are not borrowed")
home.tasks.fixture = { id = "fixture", state = "queued" }
assert(P.claimBaseTask(home.id, "fixture", "a", hours) == nil, "base tasks cannot steal dispatched members")
assert(not P.releaseEventDuty("a", "wrong-event", hours) and not P.releaseEventDuty("c", nil, hours))
for _, id in ipairs({ "a", "b" }) do R.syncController(id, controllers[id]) end
local ca, cb = controllers.a, controllers.b
assert(ca.eventAssignment.id == event.id and cb.groupLeader == bodies.a and #ca.groupMembers == 2)
local cancelCount = ca.bridge.cancels
for _ = 1, 10 do R.syncController("a", ca) end
assert(ca.bridge.cancels == cancelCount, "normal event sync does not cancel/recreate movement")
assert(ca:beginEventTravel(1) and ca.state == "EVENT_TRAVEL" and ca.bridge.moves == 1)
assert(ca.bridge.destination:getX() ~= bodies.a.x, "dispatch issues a real native movement destination")
assert(ca.eventAssignment.destination.y ~= cb.eventAssignment.destination.y, "separate arrival points")
ca.state = "COMBAT"
local assignment = ca.eventAssignment
R.syncController("a", ca)
assert(ca.state == "COMBAT" and ca.eventAssignment.id == assignment.id, "combat preemption retains event intent")
ca.state = "IDLE"
assert(ca:beginEventTravel(100), "travel can resume after combat")
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k, v in pairs(value) do result[k] = clone(v) end; return result
end
data = clone(data)
R.syncController("a", ca)
assert(P.getSurvivorDuty("a").eventId == event.id and ca.eventAssignment.id == event.id, "save-state reconstruction preserves the canonical duty binding")
for _, id in ipairs({ "a", "b" }) do
    local goal = R.destination(event, id)
    bodies[id].x, bodies[id].y, bodies[id].z = goal.x, goal.y, goal.z
    controllers[id].state = "IDLE"
end
-- Arrival uses the durable virtual position for an unloaded member, so a
-- save/load boundary cannot leave an otherwise-arrived raid stuck approaching.
local storedGoal = R.destination(event, "a")
P.setUnloadedSurvivalState("a", { hunger = .1, thirst = .1, health = 100, bleedingParts = 0,
    fatigue = .1, endurance = .9, lastHours = hours, virtualX = storedGoal.x,
    virtualY = storedGoal.y, virtualZ = storedGoal.z, status = "hibernated" })
bodies.a, controllers.a = nil, nil
R.update(controllers, 11)
assert(E.get(event.id).phase == "active", "actual positions, not a timer, establish arrival")
bodies.a, controllers.a = ca.character, ca
-- A defender or zombie can pull an arriving raider off its exact exterior
-- approach square.  Reaching the target perimeter is sufficient to begin the
-- real objective; normal combat remains responsible for the fight itself.
for _, id in ipairs({ "a", "b" }) do
    bodies[id].x, bodies[id].y = 198, 202
    controllers[id].state = id == "a" and "COMBAT" or "IDLE"
end
assert(R.raidMemberAtTarget(E.get(event.id), "a", ca)
    and R.raidMemberAtTarget(E.get(event.id), "b", cb),
    "raiders engaging around the target base remain at the raid target")
R.update(controllers, 11)
assert(E.get(event.id).phase == "objective" and E.get(event.id).objective.requiredItems == 4,
    "target-area combat does not block the bounded native-looting objective")
ca.state = "FLEEING"
R.update(controllers, 12)
assert(E.get(event.id).phase == "withdrawing" and E.get(event.id).reason == "party_retreating",
    "zombie or survival retreat cleanly withdraws an active raid")
R.syncController("a", ca)
assert(ca.eventAssignment.phase == "withdrawing" and P.getSurvivorDuty("a").eventId == event.id)
bodies.a.x, bodies.a.y = 102, 102
R.update(controllers, 13)
assert(P.getSurvivorDuty("a").eventId == nil and E.get(event.id).phase == "withdrawing",
    "one returned member releases only its own duty; remaining party is still owned")
bodies.b.x, bodies.b.y = 103, 102
R.update(controllers, 14)
assert(E.get(event.id).phase == "completed" and P.getSurvivorDuty("b").eventId == nil)
R.syncController("b", cb)
assert(cb.eventAssignment == nil and P.getSurvivorDuty("b").mode == "base", "return restores the existing base duty")
for _, id in ipairs(ids) do assert(P.getRecord(id) == "native-record-" .. id) end
assert(#P.getSurvivorIds() == 5, "dispatch/return never manufacture an actor or inventory")
print("Event runtime PASS readiness=true atomic_duty=true native_move=true stable_sync=true combat_resume=true reload=true return=true no_spawns=true")

-- A restored claim phase must still validate the whole party before writing a
-- single duty. Existing jobs/owners win a conflicting handoff.
hours = 40
P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "hostile", hours, "fixture")
event = assert(E.scheduleRaid(faction.id, target.id, hours, 0))
event = assert(E.transition(event.id, event.revision, "spawning", hours))
P.getBase(home.id).tasks.busy = { state = "claimed", claimedBy = "b" }
assert(not P.claimEventDuty(event.id, hours) and P.getSurvivorDuty("a").eventId == nil,
    "claim validates all members before changing any duty")
P.getBase(home.id).tasks.busy = nil
for _, id in ipairs({ "a", "b" }) do controllers[id].state = "BASE_IDLE" end
bodies.b.needs.endurance = .2
assert(not R.dispatch(event, controllers, hours), "restored spawning cannot bypass native readiness")
bodies.b.needs.endurance = .9
assert(R.dispatch(event, controllers, hours))
event = E.get(event.id)
R.syncController("a", ca)
ca:clearGroupLeader(); ca:setGroupMembers({})
local normalCell = getCell
getCell = function() return { getGridSquare = function() return nil end } end
assert(ca:beginEventTravel(200) and ca.eventMoveFailures == 1 and ca.state == "EVENT_WAIT")
local retry = ca.nextThink
R.syncController("a", ca)
assert(ca.nextThink == retry and ca.eventMoveFailures == 1, "projection refresh preserves route failure cooldown")
getCell = normalCell
ca:clearGroupLeader(); ca:setGroupMembers({})
assert(ca:beginEventTravel(retry) and ca.state == "EVENT_TRAVEL", "cooled-down travel can resume a native request")

-- Exercise the SAME stored-cohort scheduler used by normal groups. No event
-- timer can move a loaded body or grant a free inventory replacement.
local simulation = load("KS_UnloadedSurvival")
_G.KnoxOffscreenStoriesDisabled = true
KnoxSurvivorNeeds.sleepRequired = function() return true end
KnoxJavaBridge = { consumeNpcRecordSupply = function() return nil end }
for index, id in ipairs({ "a", "b" }) do
    P.setUnloadedSurvivalState(id, { hunger = .1, thirst = .1, health = 100, bleedingParts = 0,
        fatigue = .1, endurance = .9, lastHours = hours, virtualX = 103,
        virtualY = 103 + (index - 1) * 3, virtualZ = 0, status = "hibernated" })
    bodies[id] = nil
end
local function stored(id) return P.getUnloadedSurvivalState(id) end
local function near(a, b) return math.abs(a - b) < .000001 end
simulation.advanceAll({ "c", "d", "e" }, 41)
assert(stored("a").virtualX > 103 and near(stored("b").virtualY - stored("a").virtualY, 3),
    "stored raid travels toward its real destination as one cohort, preserving spacing")
assert(stored("a").endurance < .9 and stored("b").fatigue > .1, "travel uses existing physiological costs")
local x = stored("a").virtualX
simulation.advanceAll({ "c", "d", "e" }, 41)
assert(stored("a").virtualX == x, "same-time update cannot double travel")
simulation.advanceAll({ "b", "c", "d", "e" }, 42)
assert(stored("a").virtualX == x and stored("a").activity == "event_waiting_loaded",
    "one still-loaded member prevents the stored half travelling or snapping home")
data = clone(data)
simulation.advanceAll({ "c", "d", "e" }, 43)
assert(stored("a").virtualX > x, "stored cohort resumes from persisted coordinates after reload")
local bState = stored("b"); bState.endurance = .15; P.setUnloadedSurvivalState("b", bState)
x = stored("a").virtualX
simulation.advanceAll({ "c", "d", "e" }, 44)
assert(stored("a").virtualX == x and stored("b").restMode == "rest", "party rests for its most exhausted member")
P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "neutral", 45, "peace")
E.maintain(45)
assert(E.get(event.id).phase == "withdrawing")
simulation.advanceAll({ "c", "d", "e" }, 55)
R.update({}, 55)
assert(E.get(event.id).phase == "completed" and P.getSurvivorDuty("a").eventId == nil,
    "real virtual travel home releases the stored party, without rematerializing it")
assert(bodies.a == nil and bodies.b == nil and #P.getSurvivorIds() == 5)
for _, id in ipairs(ids) do assert(P.getRecord(id) == "native-record-" .. id) end
print("Event stored travel PASS shared_cohort=true mixed_loaded_wait=true reload=true needs=true return=true no_teleport=true")

hours = 80
P.setFactionRelationshipDisposition(faction.id, playerFaction.id, "hostile", hours, "fixture")
event = assert(E.scheduleRaid(faction.id, target.id, hours, 0))
event = assert(E.transition(event.id, event.revision, "spawning", hours))
assert(P.claimEventDuty(event.id, hours))
event = assert(E.transition(event.id, event.revision, "approaching", hours))
assert(P.markSurvivorDead("a", 81, "fixture_casualty"))
R.update({}, 81)
assert(not P.isSurvivorAlive("a") and E.get(event.id).phase == "completed"
    and P.getSurvivorDuty("b").eventId == nil, "casualty cleanup releases returned survivor without reviving the dead")
assert(#P.getSurvivorIds() == 5, "dead identity remains durable; no replacement raider")

hours = 110
event = assert(E.scheduleRaid(faction.id, target.id, hours, 0))
event = assert(E.transition(event.id, event.revision, "spawning", hours))
assert(P.claimEventDuty(event.id, hours))
P.getKnoxEventState().records[event.id].memberIds = "damaged"
E.maintain(111)
R.update({}, 111)
R.syncController("b", cb)
assert(P.getSurvivorDuty("b").eventId == event.id and cb.eventAssignment.destination == nil,
    "malformed deployed roster pauses safely rather than discarding actual ownership")
P.getKnoxEventState().records[event.id].memberIds = { "b" }
P.getBase(home.id).ownerId = "someone_else"
R.update({}, 112)
assert(E.get(event.id).phase == "failed" and P.getSurvivorDuty("b").eventId == nil,
    "a lost home releases the event without returning its member to an enemy-owned base")
assert(P.getSurvivorDuty("b").mode == "autonomous" and P.getSurvivorAffiliation("b").factionId == faction.id,
    "lost-home cleanup preserves the survivor's real faction")
print("Event cleanup PASS casualties=true no_resurrection=true corruption=true lost_home=true")
