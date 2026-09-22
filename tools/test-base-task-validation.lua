local root = arg[1] or "."
require = function() return true end
dofile(root .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")
local Controller = KnoxAutonomyController

local moveCalls = 0
local actor = {
    getCurrentSquare = function() return {} end,
    getCharacterActions = function() return { isEmpty = function() return true end } end,
}
local queue = { queue = {} }
ISTimedActionQueue = { queues = { [actor] = queue }, clear = function() queue.queue = {} end }
KnoxActivityFeed = { speak = function() end, event = function() end }
KnoxSettings = { ignoreJobResourceRequirements = function() return false end }
KnoxBaseStorage = { findRequiredTransfer = function() return nil, "requirements_ready" end }
KnoxBaseTaskBoard = { finish = function() return {}, "blocked" end }
KnoxBaseBarricades = {
    resolveTarget = function() return nil, "target_no_longer_valid" end,
    isTargetValid = function(target) return target ~= nil end,
    approachResolved = function()
        return { getX = function() return 1 end, getY = function() return 2 end }, "resolved"
    end,
    queueAction = function() return nil, "missing_carried_hammer_or_plank" end,
    plankCount = function() return 0 end,
    isComplete = function() return false end,
}
KnoxBaseFarming = {
    resolveTarget = function() return nil, "plant_not_harvestable" end,
    queueAction = function() return nil, "missing_seed_or_water" end,
    snapshot = function() return nil end,
    isComplete = function() return false end,
}
KnoxBaseCorpseHandling = {
    isDragging = function() return false end,
    resolveTarget = function() return nil, "corpse_unloaded_or_moved" end,
    queueGrab = function() return nil, "missing_corpse" end,
    queueDrop = function() return nil, "not_dragging_corpse" end,
    nextGrabStep = function() return "ready", "attached", nil end,
    nextDropStep = function() return "ready", "released", nil end,
}

local function controller(state, kind, target)
    local c = setmetatable({
        id = "worker",
        character = actor,
        state = state,
        nextThreatScan = 100000,
        nextThink = 0,
        base = {},
        baseId = "base-1",
        baseTask = { id = "task-1", type = kind, state = "claimed", claimedBy = "worker", baseId = "base-1" },
        baseTaskCorpseTarget = target,
        counts = { failures = 0 },
        failureReasons = {},
        recoverFromDetached = function() return false end,
        releaseBaseCooking = function() end,
        releaseSupply = function() end,
        bridge = {
            cancelNpcMove = function() end,
            moveNpc = function() moveCalls = moveCalls + 1 return "MOVE_STARTED" end,
            tickNpc = function() return "Succeeded" end,
        },
        finishDecision = function(self) self.state = "IDLE" end,
    }, Controller)
    return c
end

-- A stale window must fail at claim time without a single footstep, and the
-- failure must install a retry delay instead of spinning claim-walk-fail.
for _, kind in ipairs({ "barricade", "farm_water" }) do
    moveCalls = 0
    local c = controller("IDLE", kind)
    assert(c:beginBaseTaskSupplyOrWork(1000) == true)
    assert(moveCalls == 0, kind .. " must not walk to a stale target")
    assert(c.baseTask == nil, kind .. " claim must be released")
    assert(c.nextThink == 1900, kind .. " must back off after a stale target")
    assert(c.failureReasons["base_task_stale:" .. kind] == 1)
end

-- A native action that refuses to queue also backs off with a visible reason.
KnoxBaseBarricades.resolveTarget = function() return { object = {}, square = {} }, "resolved" end
moveCalls = 0
local c = controller("BASE_TASK_MOVE", "barricade")
c:tick(10)
assert(c.state == "BASE_TASK_ACTION", "arrival must stage the native barricade action")
c:tick(11)
assert(c.baseTask == nil, "failed barricade claim must be released")
assert(c.failureReasons["base_task_action:barricade_queue:missing_carried_hammer_or_plank"] == 1,
    "queue refusal must be recorded visibly")
assert(c.nextThink == 911, "queue refusal must install the action retry delay")
assert(moveCalls == 0, "no work move may start without supplies validated")

-- A corpse drag without a drop square never issues a move.
moveCalls = 0
c = controller("BASE_TASK_ACTION", "haul_corpse", {})
c.baseTaskActionQueued = true
c.baseTaskCorpsePhase = "grab"
c:tick(20)
assert(c.baseTask == nil, "dropless haul must be released")
assert(moveCalls == 0, "a corpse drag without a drop square must not move")
local seen = false
for reason in pairs(c.failureReasons) do
    if reason == "base_task_action:corpse_drop_square_unavailable" then seen = true end
end
assert(seen, "missing drop square must be recorded visibly")

-- Ignore mode tops up the worker's pockets and walks straight to work: no
-- fetch trips, while native actions still validate real carried stock.
KnoxSettings = { ignoreJobResourceRequirements = function() return true end }
local toppedWith = nil
KnoxJobTestSupplies = {
    ensure = function() return 0, "test_stock_ready" end,
    topUp = function(character, requirements) toppedWith = requirements return 1, "topped_up" end,
}
KnoxBaseBarricades.resolveTarget = function() return { object = {}, square = {} }, "resolved" end
KnoxBaseJobs = { resolveTaskSquare = function()
    return { getX = function() return 1 end, getY = function() return 2 end }
end }
moveCalls = 0
c = controller("IDLE", "barricade")
c.baseTask.requirements = { items = { ["Base.Plank"] = 1 } }
assert(c:beginBaseTaskSupplyOrWork(100) == true)
assert(toppedWith ~= nil and toppedWith.items["Base.Plank"] == 1,
    "ignore mode must mint the task requirements into worker pockets")
assert(c.baseTaskBarricadeTarget ~= nil,
    "claim validation must carry the exact resolved opening into movement")
assert(c.state == "BASE_TASK_MOVE" and moveCalls == 1,
    "ignore mode must walk straight to work with no supply trip")

moveCalls=0
KnoxJobTestSupplies.topUp=function() return 0, "unavailable_items=Base.Plank" end
c=controller("IDLE","barricade")
c.baseTask.requirements={items={["Base.Plank"]=1}}
assert(c:beginBaseTaskSupplyOrWork(200))
assert(moveCalls==0 and c.baseTask==nil,"failed free supplies must block before walking")

-- Retargeting must skip an opening already owned by another queued/claimed
-- barricade task, then update the same claimed task instead of creating a
-- second target owner.
local candidates = {
    { id = "barricade:busy", x = 1, y = 1, z = 0, objectIndex = 1 },
    { id = "barricade:free", x = 2, y = 2, z = 0, objectIndex = 2 },
}
KnoxBaseBarricades.findTarget = function(_, _, eligible)
    for _, candidate in ipairs(candidates) do
        if eligible(candidate) then return candidate end
    end
    return nil
end
KnoxBaseBarricades.resolveTarget = function(_, target)
    return { object = target, square = {} }, "resolved"
end
local retargeted = nil
KnoxPersistence = KnoxPersistence or {}
KnoxPersistence.retargetClaimedBaseTask = function(_, _, _, target)
    retargeted = target
    return { id = "task-1", type = "barricade", state = "claimed",
        claimedBy = "worker", target = target, baseId = "base-1" }, "retargeted"
end
c = controller("IDLE", "barricade")
c.base.tasks = {
    ["task-1"] = c.baseTask,
    ["task-busy"] = { id = "task-busy", type = "barricade", state = "queued",
        target = candidates[1] },
}
c.baseTask.target = { id = "barricade:old" }
assert(c:retargetBarricadeTask() ~= nil and retargeted == candidates[2],
    "retargeting must skip another task's opening and retain one claimed owner")

-- Supply reservations are runtime-only, but must protect the actual selected
-- item and container until transfer succeeds, fails, or a combat interruption
-- releases the claimed job.
local sharedReservations = { items = {}, containers = {} }
local sharedItem, sharedContainer = {}, {}
local first = setmetatable({ id = "first", reservations = sharedReservations,
    releaseBaseRecreation = function() end }, Controller)
local second = setmetatable({ id = "second", reservations = sharedReservations,
    releaseBaseRecreation = function() end }, Controller)
local transfer = { item = sharedItem, source = { container = sharedContainer } }
assert(first:reserveBaseTaskSupplyTransfer(transfer), "first worker reserves selected supply")
assert(not second:reserveBaseTaskSupplyTransfer(transfer),
    "second worker cannot race the same stored material")
first:releaseBaseTaskSupplyTransfer()
assert(second:reserveBaseTaskSupplyTransfer(transfer),
    "released material becomes available to the next worker")
second:releaseSupply()
assert(first:reserveBaseTaskSupplyTransfer(transfer),
    "generic interruption cleanup must release the base-task supply lease")
first:releaseBaseTaskSupplyTransfer()

print("Base task validation PASS stale_fail_fast=true queue_backoff=true dropless_haul=true ignore_topup=true retarget_owner=true supply_lease=true")
