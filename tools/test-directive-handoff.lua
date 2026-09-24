local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController
local function square(x, y)
    return { getX = function() return x end, getY = function() return y end,
        getZ = function() return 0 end, getBuilding = function() return nil end }
end
local origin, destination, waypoint = square(0, 0), square(100, 0), square(50, 0)
getCell = function() return { getGridSquare = function() return destination end } end
KnoxTravelRouting = { findRoadWaypoint = function() return waypoint end }
KnoxPersistence = {}
KnoxSurvivorNeeds = { wakeForDanger = function() end }
ISTimedActionQueue = { queues = {}, clear = function(character)
    character.cleared = character.cleared + 1
    ISTimedActionQueue.queues[character] = nil
end }
local function controller(state)
    local character = { cleared = 0, getCurrentSquare = function() return origin end,
        getCharacterActions = function() return { isEmpty = function() return true end } end }
    local c = setmetatable({ id = "npc", character = character, state = state,
        companionOrder = "follow", companionOwnerId = "owner", companionFormationSlot = 1,
        companionTarget = {}, reservations = { ambientSpots = {}, campPositions = {}, items = {}, containers = {} },
        moves = 0, cancels = 0, nextThink = 0,
    }, Controller)
    c.bridge = { moveNpc = function() c.moves = c.moves + 1; return "MOVE_STARTED" end,
        cancelNpcMove = function() c.cancels = c.cancels + 1 end }
    return c
end
local failures = {}
local function test(name, run)
    local ok, reason = pcall(run)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(reason) end
end

test("road route ownership", function()
    local c = controller("IDLE")
    assert(c:beginCompanionPointDirective(0, { kind = "go_to", minX = 100, minY = 0 }))
    assert(c.moves == 1)
    assert(c:interruptForDirective())
    assert(not c:continueRoadTravel(1) and c.moves == 1,
        "cancelled Go To must not resume its staged destination on a later arrival")
end)

test("Lua-only aid action", function()
    local c = controller("AID_ACTION")
    c.pendingAidPatient = {}
    ISTimedActionQueue.queues[c.character] = { queue = { { kind = "bandage" } } }
    assert(c:interruptForDirective())
    assert(c.character.cleared == 1 and c.pendingAidPatient == nil and c.state == "IDLE",
        "a queued medical action must stop before the replacement order owns the body")
    assert(c.companionOrder == "follow", "interruption retains durable order")
end)

test("rest approach handoff", function()
    local c = controller("MOVING_TO_REST")
    local chair = {}
    c.pendingRest = { object = chair }
    c.reservations.restSpots = { [chair] = c.id }
    c.ambientRest = true
    assert(c:interruptForDirective(), "Follow must interrupt walking to a Relax chair")
    assert(c.pendingRest == nil and c.reservations.restSpots[chair] == nil
        and c.ambientRest == nil and c.state == "IDLE")
end)

test("queued posture handoff", function()
    local c = controller("COMPANION_RELAX")
    ISTimedActionQueue.queues[c.character] = { queue = { { kind = "sit" } } }
    assert(c:interruptForDirective())
    assert(c.character.cleared == 1, "a pending sit must not start after Follow has resumed")
end)

test("ambient leases", function()
    local c = controller("BASE_PATROL")
    c.ambientMovementTarget = "tile"
    c.reservations.ambientSpots.tile = c.id
    c.reservations.ambientSpots.other = "other-npc"
    c.campPosition = "camp-tile"
    c.reservations.campPositions[c.campPosition] = c.id
    assert(c:interruptForDirective())
    assert(c.ambientMovementTarget == nil and c.campPosition == nil
        and c.reservations.ambientSpots.tile == nil and c.reservations.campPositions["camp-tile"] == nil,
        "cancelled movement must release its exact ambient and camp leases")
    assert(c.reservations.ambientSpots.other == "other-npc", "other survivors retain their leases")
end)

test("formation slot is not a new order", function()
    local c = controller("MOVING_TO_SUPPLY")
    local supply = { item = {} }
    c.pendingSupply = supply
    c:setCompanionOrder("owner", c.companionTarget, "follow", 2)
    assert(c.state == "MOVING_TO_SUPPLY" and c.pendingSupply == supply and c.cancels == 0,
        "party reindexing must not restart an unrelated active need or task")
    assert(c.companionFormationSlot == 2, "the next formation refresh must use the new slot")
    c:setCompanionOrder("owner", c.companionTarget, "hold", 2)
    assert(c.state == "IDLE" and c.pendingSupply == nil and c.cancels == 1,
        "a real replacement order still interrupts travel immediately")
end)

test("deferred emergency order", function()
    local c = controller("COMBAT")
    c:setCompanionOrder("owner", c.companionTarget, "hold", 1)
    assert(c.state == "COMBAT" and c.cancels == 0 and c.companionOrder == "hold",
        "a durable replacement order waits for emergency ownership to end")
end)

assert(#failures == 0, table.concat(failures, "\n"))
print("Directive handoff PASS: road, actions, rest, reservations, formation slots, emergency orders")
