local projectRoot = arg[1] or "."

require = function()
    return true
end

local controllerPath = projectRoot
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
assert(loadfile(controllerPath))()
local Controller = assert(KnoxAutonomyController)

local useful = { square = {}, key = "building:useful", score = 90, distance = 8, danger = 0 }
local arbitrary = { square = {}, key = "area:arbitrary", score = 10, distance = 5, danger = 0 }
assert(Controller.selectRoamCandidate({ arbitrary, useful }, {}, 100) == useful,
    "a useful nearby destination must beat arbitrary wandering")

local memory = { ["building:useful"] = 300 }
assert(Controller.selectRoamCandidate({ useful, arbitrary }, memory, 100) == arbitrary,
    "a recently failed destination must be temporarily suppressed")
assert(not Controller.roamMemoryAvailable(memory, "building:useful", 299),
    "destination memory remains active until its bound")
assert(Controller.roamMemoryAvailable(memory, "building:useful", 300),
    "destination memory expires and stays lightweight")

local dangerous = { square = {}, key = "building:horde", score = 200, distance = 4, danger = 3 }
assert(Controller.selectRoamCandidate({ dangerous, arbitrary }, {}, 100) == arbitrary,
    "an obvious zombie concentration must not win an ordinary roaming choice")

assert(Controller.shouldInterruptRoamingForNeed("eat")
        and Controller.shouldInterruptRoamingForNeed("find_water")
        and Controller.shouldInterruptRoamingForNeed("rest"),
    "self-maintenance must be able to preempt roaming")
assert(not Controller.shouldInterruptRoamingForNeed("roam")
        and not Controller.shouldInterruptRoamingForNeed("fight"),
    "ordinary roaming and combat decisions are handled by their own owners")
assert(Controller.roamIntentKind("building") == "investigate_building",
    "a building destination has a readable durable purpose")
assert(Controller.roamIntentKind("area") == "travel_area",
    "ordinary onward travel has a readable durable purpose")
assert(Controller.roamIntentKind("building", "find_food") == "find_food",
    "travel cannot overwrite an unresolved survival purpose")

local handle = assert(io.open(controllerPath, "r"))
local source = handle:read("*a")
handle:close()
assert(string.find(source, 'if self.state == "IDLE" and ticks >= self.nextThink then', 1, true),
    "an active valid roaming goal must not be replaced by the think loop")
assert(string.find(source, 'self.roamGoalKey = nil', 1, true),
    "completed or interrupted roaming must release its destination identity")
assert(string.find(source, 'ROAM_NO_GOAL_RETRY_TICKS', 1, true),
    "no-goal recovery must schedule a bounded new decision")
assert(string.find(source, 'rememberRoamDestination(', 1, true),
    "completed and failed destinations must enter short-term memory")
assert(string.find(source, 'roamingBuildingValue', 1, true),
    "roaming should score plausible buildings with safe native metadata")
assert(string.find(source, 'definition:getRoomsNumber', 1, true)
    and string.find(source, 'building:hasWater', 1, true),
    "roaming building value should consider rooms and water when available")
assert(string.find(source, 'self:setLifeIntent(goal, "seeking"', 1, true),
    "world supply search persists its reason before selecting an action")
assert(string.find(source, 'self:clearLifeIntent()', 1, true),
    "completed or superseded autonomous purpose can be cleared")
assert(string.find(source, 'baseSupplyClaimsByBase', 1, true)
    and string.find(source, 'supplyClaimsFor', 1, true),
    "base supply searches use one shared loaded-controller claim table")
assert(string.find(source, 'untilHours = nowHours + 1.5', 1, true),
    "base supply claims have a bounded lease")
assert(string.find(source, 'claim.survivorId ~= self.id', 1, true),
    "residents do not duplicate an active supply search")
assert(string.find(source, 'self.baseSupplyTrip = true', 1, true)
    and string.find(source, 'local returnToBase = self.baseSupplyTrip == true', 1, true),
    "base supply trips return through the existing home-duty path")
assert(Controller.baseIdleJitter("resident-a") ~= Controller.baseIdleJitter("resident-b"),
    "base residents receive distinct deterministic idle phases")
assert(Controller.baseIdleChoice(0, "resident-a", 3) ~= nil
    and Controller.baseIdleChoice(90, "resident-a", 3) ~= nil,
    "base idle schedule remains bounded across decision ticks")

local function square(x, y, building, room)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return 0 end, getBuilding = function() return building end,
        getRoom = function() return room end, canStand = function() return true end }
end
local function building(id)
    return { getDef = function() return { getID = function() return id end } end }
end
local origin = square(0, 0)
local blockedRoom, goodRoom = {}, {}
local nearby = square(12, 0, building("blocked"), blockedRoom)
local nextBlock = square(30, 0, building("next"), goodRoom)
local emptyList = { size = function() return 0 end }
local queries = 0
local cell = { getGridSquare = function(_, x, y)
    queries = queries + 1
    if x == 12 and y == 0 then return nearby end
    if x == 30 and y == 0 then return nextBlock end
end, getZombieList = function() return emptyList end }
getCell = function() return cell end
ZombRand = function(n) return math.floor(n * .75) end
local destinations = {}
local actor = { getCurrentSquare = function() return origin end }
local roaming = setmetatable({ character = actor, id = "roam-test", recentRoamGoals = {},
    roamGoalOrder = {}, blockedAreas = { [blockedRoom] = 10000 },
    bridge = { moveNpc = function(_, _, destination)
        destinations[#destinations + 1] = destination return "MOVE_STARTED"
    end } }, { __index = Controller })
assert(roaming:beginRoam(100) and destinations[1] == nextBlock,
    "real roam selection reaches next block and avoids known blocked room")
assert(queries < 2500, "expanded loaded search stays bounded")
roaming.recentRoamGoals["building:next"] = 10000
assert(not roaming:beginRoam(101), "recent failed building is not reselected")
assert(roaming.nextThink > 101, "no loaded goal schedules retry instead of spinning")
cell.getGridSquare = function(_, x, y) return square(x, y) end
assert(roaming:beginRoam(200) and destinations[2]:getX() > 0,
    "open-ground fallback continues onward rather than reversing direction randomly")
assert(Controller.entryCandidateScore("window", false, false, false, true, true, true, true) == 4,
    "urgent permitted forced window is last resort after usable entrances")
assert(Controller.entryCandidateScore("door", false, false, false, true, false, false, true) == 4,
    "armed scavenging can select a locked door for forced entry")
assert(Controller.entryCandidateScore("window", false, false, true, true, true, true, true) == nil,
    "barricaded window remains excluded")
print("Roaming autonomy PASS useful=true memory=true danger=true stability=true needs=true next_block=true bounded_scan=true onward=true")

-- Actual gameplay caller -> canonical persistence -> relationship delivery.
-- Only the engine's route acknowledgement is stubbed; no native arrival is claimed.
local savedData = {}
ModData = { getOrCreate = function(key)
    savedData[key] = savedData[key] or {}; return savedData[key]
end }
Events = { OnSave = { Add = function() end }, OnGameStart = { Add = function() end } }
local worldHour = 80
getGameTime = function() return { getWorldAgeHours = function() return worldHour end } end
assert(loadfile(projectRoot .. "/mod/42/media/lua/client/KS_Persistence.lua"))()
KnoxSettings = { allowNPCFactions = function() return false end }
for _, id in ipairs({ "a-leader", "b-follower", "c-follower", "unrelated" }) do
    assert(KnoxPersistence.setRecord(id, "fixture-" .. id))
end
local group = assert(KnoxPersistence.createTravelGroup({ "a-leader", "b-follower", "c-follower" }, worldHour))
roaming.id, roaming.recentRoamGoals, roaming.roamGoalOrder = "a-leader", {}, {}
assert(roaming:beginRoam(300), "recognized leader uses the ordinary roaming path")
local issued = assert(KnoxPersistence.getTravelGroupLeaderOrder(group.id, worldHour))
assert(issued.kind == "follow" and issued.leaderId == roaming.id and issued.expiresAtHours == 80.25,
    "successful native route admission issues a bounded canonical follow order")
local controllers = { [roaming.id] = roaming }
for _, id in ipairs({ "b-follower", "c-follower", "unrelated" }) do
    controllers[id] = setmetatable({ id = id, character = actor, state = "IDLE" }, { __index = Controller })
end
assert(loadfile(projectRoot .. "/mod/42/media/lua/client/KS_SurvivorRelationships.lua"))()
KnoxSurvivorRelationships.coordinate(controllers, { "a-leader", "b-follower", "c-follower", "unrelated" }, 300)
for _, id in ipairs({ "b-follower", "c-follower" }) do
    assert(controllers[id].groupLeaderOrder.revision == issued.revision
        and controllers[id].groupLeaderId == "a-leader", "current followers receive the canonical directive")
end
assert(controllers.unrelated.groupLeaderOrder == nil, "unrelated survivors receive no directive")
assert(controllers["b-follower"]:issueGroupLeaderOrder("hold", 301) == nil,
    "controller wrapper rejects a non-leader")
local held = assert(roaming:issueGroupLeaderOrder("hold", 301))
KnoxSurvivorRelationships.coordinate(controllers, { "a-leader", "b-follower", "c-follower", "unrelated" }, 360)
assert(controllers["b-follower"].groupLeaderOrder.kind == "hold", "hold follows the same delivery path")
local savedMove = roaming.bridge.moveNpc
roaming.bridge.moveNpc = function() return "MOVE_FAILED fixture" end
roaming.recentRoamGoals, roaming.roamGoalOrder = {}, {}
assert(not roaming:beginRoam(400), "failed native route remains a failure")
assert(KnoxPersistence.getTravelGroupLeaderOrder(group.id, worldHour).revision == held.revision,
    "a failed travel request cannot replace hold with fabricated follow")
roaming.bridge.moveNpc = savedMove
roaming.recentRoamGoals, roaming.roamGoalOrder = {}, {}
assert(roaming:beginRoam(500))
local moving = assert(KnoxPersistence.getTravelGroupLeaderOrder(group.id, worldHour))
assert(moving.kind == "follow" and moving.revision > held.revision,
    "successful leader travel releases an old hold through canonical follow")
roaming.recentRoamGoals, roaming.roamGoalOrder = {}, {}
worldHour = 80.1
assert(roaming:beginRoam(600))
assert(KnoxPersistence.getTravelGroupLeaderOrder(group.id, worldHour).revision == moving.revision,
    "subsequent successful routes do not reissue the same live lease")
AdjacentFreeTileFinder = { Find = function(target) return target end }
roaming.bridge.moveNpcWithPace = savedMove
roaming.nextRegroupCallout = 9999
assert(roaming:beginGroupRegroup(actor, 601), "leader regroup uses existing native route ownership")
assert(KnoxPersistence.getTravelGroupLeaderOrder(group.id, worldHour).revision == moving.revision,
    "regroup shares the same deduplicated follow directive")
assert(KnoxPersistence.clearTravelGroupLeaderOrder(group.id, roaming.id))
KnoxSurvivorRelationships.coordinate(controllers, { "a-leader", "b-follower", "c-follower", "unrelated" }, 660)
assert(controllers["b-follower"].groupLeaderOrder == nil and controllers["c-follower"].groupLeaderOrder == nil,
    "canonical cancellation reaches all current followers")
actor.isDead = function() return true end
assert(roaming:issueGroupLeaderOrder("hold", 661) == nil, "a native dead leader cannot issue")
actor.isDead = nil
local savedSquare = actor.getCurrentSquare
actor.getCurrentSquare = function() return nil end
assert(roaming:issueGroupLeaderOrder("hold", 662) == nil, "a detached leader cannot issue")
actor.getCurrentSquare = savedSquare
print("Leader gameplay integration PASS route=true canonical=true delivery=true filtering=true failure=true deduplication=true")
