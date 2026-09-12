local projectRoot = arg[1] or "."

require = function()
    return true
end

local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z end,
        canStand = function() return true end,
    }
end

local cell = {
    getGridSquare = function(_, x, y, z)
        return square(x, y, z)
    end,
}
getCell = function()
    return cell
end
ZombRand = function()
    return 0
end

AdjacentFreeTileFinder = {
    Find = function(target)
        return target
    end,
}
KnoxActivityFeed = {
    speak = function() end,
}
KnoxPersistence = {
    captureActiveSurvivor = function() end,
}
KnoxSurvivorNeeds = {
    wakeForDanger = function() return false end,
}
local supportPlan = nil
KnoxGroupSupport = {
    plan = function() return supportPlan end,
    queue = function() return {}, "queued" end,
    verify = function() return true end,
    mostUrgentNeed = function() return nil end,
}

local controllerPath = projectRoot
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
assert(loadfile(controllerPath))()
local Controller = assert(KnoxAutonomyController)

assert(Controller.shouldAssistGroupObjective({
    kind = "investigate_building", phase = "arrived",
}, 36), "nearby group members may help search a reached building")
assert(Controller.shouldAssistGroupObjective({
    kind = "scavenge", phase = "traveling",
}, 64), "nearby group members may share a scavenging objective")
assert(not Controller.shouldAssistGroupObjective({
    kind = "find_food", phase = "traveling",
}, 4), "one member's personal survival need is not assigned to the whole group")
assert(not Controller.shouldAssistGroupObjective({
    kind = "investigate_building", phase = "traveling",
}, 4), "followers stay cohesive while the leader is still approaching a building")
assert(not Controller.shouldAssistGroupObjective({
    kind = "scavenge", phase = "traveling",
}, 65), "followers do not split away from a distant leader to assist")
assert(Controller.shouldDelegateNeedToGroup("find_water", 64),
    "nearby follower delegates a missing survival resource to its leader")
assert(not Controller.shouldDelegateNeedToGroup("find_water", 65)
    and not Controller.shouldDelegateNeedToGroup("find_weapon", 4),
    "distant and nonessential goals remain individually owned")

for _,context in ipairs({"urgent","directed","return_home","travel","local"}) do
    assert(Controller.travelPaceFor(900,false,context)=="cautious", "routine routes default to a cautious pace")
end
local originalPaceSettings=KnoxSettings
KnoxSettings={cautiousTravel=function() return false end}
assert(Controller.travelPaceFor(49, false, "urgent") == "walk",
    "short urgent movement remains a walk")
assert(Controller.travelPaceFor(64, false, "urgent") == "run",
    "meaningfully distant urgent supply travel may run")
assert(Controller.travelPaceFor(143, false, "directed") == "walk",
    "short directed movement remains a walk")
assert(Controller.travelPaceFor(144, false, "directed") == "run",
    "long directed movement may jog through native run state")
assert(Controller.travelPaceFor(196, false, "travel") == "run",
    "long autonomous travel may jog")
assert(Controller.travelPaceFor(900, true, "travel") == "walk",
    "indoor movement stays walking")
assert(Controller.travelPaceFor(900, false, "local") == "walk",
    "local work never runs merely because its route is long")
KnoxSettings=originalPaceSettings

assert(Controller.isEntryTraversalFailure("Transition:FAILED_LOCKED_DOOR"),
    "locked door enters alternate-entry recovery")
assert(Controller.isEntryTraversalFailure("Transition:FAILED_BARRICADED_WINDOW"),
    "barricaded window enters alternate-entry recovery")
assert(Controller.isEntryTraversalFailure(
    "Transition:FAILED_LOCKED_OR_UNUSABLE_WINDOW"
), "failed native window open enters alternate-entry recovery")
assert(not Controller.isEntryTraversalFailure("Transition:FAILED_EDGE_COOLDOWN"),
    "edge cooldown remains ordinary bounded movement recovery")
assert(Controller.entryCandidateScore(
    "door", true, false, false, true, false, false
) == 0, "an already-open door remains usable regardless of lock state")
assert(Controller.entryCandidateScore(
    "door", false, false, false, true, false, false
) == nil, "a closed locked door is not selected as an alternate")
assert(Controller.entryCandidateScore(
    "window", false, false, false, true, false, false
) == nil, "a closed locked window is not selected as an alternate")
assert(Controller.entryCandidateScore(
    "window", true, false, false, false, false, true
) == 2, "an open climbable window remains a valid alternate")
assert(Controller.entryCandidateScore(
    "window", false, true, false, false, false, false
) == nil, "a broken but unclimbable window is rejected")

local zombieCount = 0
local zombieSquare = square(4, 0, 0)
cell.getZombieList = function()
    return {
        size = function() return zombieCount end,
        get = function()
            return {
                isDead = function() return false end,
                getCurrentSquare = function() return zombieSquare end,
            }
        end,
    }
end
local health = 100
local threatCharacter = {
    CanSee = function() return true end,
    getCurrentSquare = function() return square(0, 0, 0) end,
    getHealth = function() return health end,
    getStats = function()
        return { get = function() return 0.8 end }
    end,
}
CharacterStat = { ENDURANCE = "endurance" }
local fleeController = setmetatable({
    character = threatCharacter,
    groupMembers = {},
}, Controller)
zombieCount = 3
local shouldFlee, assessment = fleeController:assessFlee()
assert(not shouldFlee and assessment.zombies == 3 and assessment.allies == 1,
    "three distant zombies do not trigger the removed fixed ratio rule")
local ally = { getCurrentSquare = function() return square(1, 0, 0) end }
fleeController.groupMembers = { ally }
zombieCount = 5
shouldFlee = fleeController:assessFlee()
assert(not shouldFlee, "nearby allies reduce a group's combat risk")
zombieCount = 6
zombieSquare = square(1, 0, 0)
shouldFlee, assessment = fleeController:assessFlee()
assert(shouldFlee and assessment.allies == 2,
    "contact-range collapse still overwhelms the supported group")
zombieCount = 1
zombieSquare = square(2, 0, 0)
health = 25
shouldFlee, assessment = fleeController:assessFlee()
assert(shouldFlee and assessment.reason == "critical_health",
    "critical-health survivor flees any nearby zombie")

local threat = {}
local owners = { survivor = true }
local combatController = setmetatable({
    id = "survivor",
    reservations = { threats = { [threat] = owners } },
    combatTarget = threat,
}, Controller)
local originalNext = next
next = nil
combatController:releaseCombat()
next = originalNext
assert(combatController.combatTarget == nil, "combat target released")
assert(combatController.reservations.threats[threat] == nil,
    "empty reservation removed without global next")

local leaderSquare = square(10, 10, 0)
local leaderForwardX = 1
local leaderForwardY = 0
local leader = {
    getX = function() return 10.5 end,
    getY = function() return 10.5 end,
    getCurrentSquare = function() return leaderSquare end,
    getForwardDirectionX = function() return leaderForwardX end,
    getForwardDirectionY = function() return leaderForwardY end,
}
local followerSquare = square(0, 0, 0)
local follower = {
    getX = function() return 0.5 end,
    getY = function() return 0.5 end,
    getCurrentSquare = function() return followerSquare end,
    getCharacterActions = function()
        return { isEmpty = function() return true end }
    end,
}
local captured = {}
local moveCount = 0
local paceUpdateCount = 0
local bridge = {
    moveNpc = function(_, id, target)
        moveCount = moveCount + 1
        captured[id] = target
        return "MOVE_STARTED"
    end,
    moveNpcWithPace = function(_, id, target, pace)
        moveCount = moveCount + 1
        captured[id] = target
        captured[id .. ":pace"] = pace
        return "MOVE_STARTED"
    end,
    setNpcMovementPace = function(_, id, pace)
        paceUpdateCount = paceUpdateCount + 1
        captured[id .. ":pace"] = pace
        return true
    end,
    cancelNpcMove = function() return true end,
}

local function followerController(id, slot)
    return setmetatable({
        id = id,
        character = follower,
        bridge = bridge,
        groupLeader = leader,
        groupFormationSlot = slot,
        groupMembers = {},
        nextFormationRefresh = 0,
        nextThink = 0,
        formationFailureCount = 0,
        failureReasons = {},
        counts = { failures = 0 },
    }, Controller)
end

local left = followerController("left", 1)
-- Execute the actual controller route request with the real sandbox adapter.
-- Missing settings in older saves retain the paired one-tile layout below.
local priorSettings = KnoxSettings
assert(loadfile(projectRoot .. "/mod/42/media/lua/client/KS_Settings.lua"))()
SandboxVars = { KnoxSurvivors = { FollowerFormation = 2, FollowerSpacing = 2 } }
local column = followerController("column", 3)
assert(column:beginGroupFollow(10), "configured column starts native follow route")
assert(captured.column:getX() == 4 and captured.column:getY() == 10,
    "third single-file member trails by three configured intervals")
leaderForwardX, leaderForwardY = 0, -1
column = followerController("column-turn", 2)
assert(column:beginGroupFollow(10))
assert(captured["column-turn"]:getX() == 10 and captured["column-turn"]:getY() == 14,
    "single-file layout rotates behind the leader")
leaderForwardX, leaderForwardY = 1, 0
SandboxVars.KnoxSurvivors.FollowerFormation = 1
local spread = followerController("spread", 2)
assert(spread:beginGroupFollow(10))
assert(captured.spread:getX() == 8 and captured.spread:getY() == 12,
    "paired spacing scales both trailing and lateral separation")
local originalDuty = KnoxPersistence.getSurvivorDuty
KnoxPersistence.getSurvivorDuty = function(id)
    if id == "ordered" then return { mode = "companion", followerFormation = "single_file", followerSpacing = 3 } end
end
local ordered = followerController("ordered", 2)
assert(ordered:beginGroupFollow(10))
assert(captured.ordered:getX() == 4 and captured.ordered:getY() == 10,
    "persistent in-game formation order overrides the sandbox default on actual route requests")
KnoxPersistence.getSurvivorDuty = originalDuty
-- An unavailable preferred tile still uses the ordinary bounded fallback.
local normalLookup = cell.getGridSquare
cell.getGridSquare = function() return nil end
local blocked = followerController("blocked-column", 2)
local movesBeforeBlocked = moveCount
assert(not blocked:beginGroupFollow(10) and moveCount == movesBeforeBlocked,
    "blocked slots never turn the leader's own tile into a destination")
cell.getGridSquare = normalLookup
SandboxVars = nil
KnoxSettings = priorSettings
local right = followerController("right", 2)
local rear = followerController("rear", 3)
assert(left:beginGroupFollow(10), "left formation movement")
assert(right:beginGroupFollow(10), "right formation movement")
assert(rear:beginGroupFollow(10), "rear formation movement")
assert(captured.left:getX() == 9 and captured.left:getY() == 9,
    "left follower receives back-left slot")
assert(captured.right:getX() == 9 and captured.right:getY() == 11,
    "right follower receives back-right slot")
assert(captured.left:getX() ~= leaderSquare:getX()
        or captured.left:getY() ~= leaderSquare:getY(),
    "follow spacing never intentionally targets the leader tile")
assert(captured.left:getX() ~= captured.right:getX()
        or captured.left:getY() ~= captured.right:getY(),
    "multiple followers receive distinct practical slots")
assert((captured.rear:getX() ~= captured.left:getX()
        or captured.rear:getY() ~= captured.left:getY())
        and (captured.rear:getX() ~= captured.right:getX()
            or captured.rear:getY() ~= captured.right:getY()),
    "three group followers retain distinct targets")
assert(captured["left:pace"] == "sprint",
    "distant follower requests sprint catch-up")

local recipient, supportItem = {}, {}
supportPlan = { recipient = recipient, item = supportItem, kind = "find_water" }
local supportController = followerController("support", 1)
supportController.reservations = { supportRecipients = {}, supportItems = {} }
supportController.groupMembers = { leader }
supportController.groupLeader = leader
supportController.companionOrder = nil
supportController.baseId, supportController.campId = nil, nil
supportController.nextGroupSupportAt = 0
assert(supportController:beginGroupSupport(20)
    and supportController.state == "GROUP_SUPPORT",
    "one real ally-support transfer owns the controller")
assert(supportController.reservations.supportRecipients[recipient] == "support"
    and supportController.reservations.supportItems[supportItem] == "support",
    "recipient and real item are reserved during support")
assert(supportController:completeGroupSupport(21),
    "verified support transfer completes")
assert(supportController.pendingGroupSupport == nil
    and supportController.reservations.supportRecipients[recipient] == nil
    and supportController.reservations.supportItems[supportItem] == nil,
    "support completion releases all transient ownership")
supportPlan = nil

leaderSquare = square(12, 10, 0)
assert(left:refreshFormationFollow(60), "moving leader refreshes formation path")
assert(captured.left:getX() == 11 and captured.left:getY() == 9,
    "formation destination follows moving leader")

followerSquare = square(11, 9, 0)
leaderSquare = square(12, 10, 1)
local cancellationBeforeFloorRefresh = cancelCount or 0
assert(left:refreshFormationFollow(90),
    "leader floor change refreshes formation destination")
assert(captured.left:getX() == 11 and captured.left:getY() == 9
    and captured.left:getZ() == 1,
    "same XY on the wrong floor is not treated as formation arrival")
assert((cancelCount or 0) == cancellationBeforeFloorRefresh,
    "floor refresh supersedes through Java ownership without a cancel gap")

followerSquare = square(0, 0, 0)

local originalMoveWithPace = bridge.moveNpcWithPace
local cancelCount = 0
bridge.cancelNpcMove = function()
    cancelCount = cancelCount + 1
    return true
end
bridge.moveNpcWithPace = function()
    return "MOVE_ALREADY_REQUESTED"
end
leaderSquare = square(14, 10, 0)
assert(left:refreshFormationFollow(120),
    "failed formation refresh is consumed")
assert(left.state == "GROUP_WAIT", "failed formation enters bounded wait")
assert(left.nextThink >= 300,
    "failed formation keeps full route cooldown")
assert(left.formationFailureCount == 1 and cancelCount > 0,
    "failed formation cancels stale owner and records retry")

left:finishDecision(120)
assert(left.nextThink >= 300,
    "group fast refresh cannot overwrite a recorded failure cooldown")

local bottleneck = followerController("bottleneck", 1)
bottleneck.state = "GROUP_FOLLOW"
local failuresBeforeBottleneck = bottleneck.formationFailureCount
bottleneck:waitForFormationBottleneck("Transition:FAILED_LOCKED_DOOR", 200)
assert(bottleneck.state == "GROUP_WAIT" and bottleneck.nextThink >= 290,
    "known traversal bottleneck enters a bounded group wait")
assert(bottleneck.formationFailureCount == failuresBeforeBottleneck,
    "temporary bottleneck does not grow the formation failure streak")

bridge.moveNpcWithPace = originalMoveWithPace

leaderSquare = square(10, 10, 0)
leaderForwardX = 1
leaderForwardY = 0
followerSquare = square(-3, 10, 0)
local companion = followerController("companion", 1)
companion.groupLeader = nil
companion.companionTarget = leader
companion.companionFormationSlot = 1
companion.companionOrder = "follow"
assert(companion:beginCompanionFollow(10), "far companion starts catch-up")
assert(captured["companion:pace"] == "sprint",
    "far companion requests sprint catch-up")
local movesAfterStart = moveCount
leader.isSneaking=function() return true end
assert(not companion:refreshFormationFollow(40) and captured["companion:pace"]=="sneak"
    and moveCount==movesAfterStart, "actual leader crouching changes pace without replacing the route")
leader.isSneaking=function() return false end
companion.nextFormationRefresh=30
assert(not companion:refreshFormationFollow(20) and moveCount == movesAfterStart,
    "follow refresh does nothing before its cadence expires")

followerSquare = square(4, 10, 0)
assert(not companion:refreshFormationFollow(40),
    "pace-only refresh keeps the active destination owner")
assert(captured["companion:pace"] == "run" and moveCount == movesAfterStart,
    "moderate separation downgrades to run without repathing")

followerSquare = square(8, 10, 0)
assert(not companion:refreshFormationFollow(70),
    "close pace refresh keeps the active route")
assert(captured["companion:pace"] == "normal" and moveCount == movesAfterStart,
    "close companion walks without destination churn")

leaderSquare = square(11, 10, 0)
assert(not companion:refreshFormationFollow(100),
    "one-tile leader movement does not force a replacement")
assert(moveCount == movesAfterStart,
    "small leader movement creates no route request")

leaderForwardX = 0
leaderForwardY = 1
assert(companion:refreshFormationFollow(130),
    "sharp leader direction change refreshes the follow slot")
assert(moveCount == movesAfterStart + 1,
    "direction change creates one replacement request")

local arrival = captured.companion
followerSquare = square(arrival:getX(), arrival:getY(), arrival:getZ())
companion.movementFailureCount = 3
companion.formationFailureCount = 2
assert(companion:refreshFormationFollow(160), "catch-up reaches its trailing slot")
assert(companion.state == "COMPANION_WAIT"
        and companion.movementFailureCount == 0
        and companion.formationFailureCount == 0,
    "successful catch-up resets movement recovery")

local movesBeforeHold = moveCount
companion.companionOrder = "hold"
assert(not companion:beginCompanionFollow(190),
    "Hold cannot start companion follow")
assert(moveCount == movesBeforeHold, "Hold creates no movement request")

local recovery = followerController("recovery", 1)
recovery:recordMovementFailure("movement", "FailedStuck target=one", 100, 30, 240)
local firstRetry = recovery.nextThink
recovery:recordMovementFailure("movement", "FailedStuck target=two", 100, 30, 240)
local secondRetry = recovery.nextThink
recovery:recordMovementFailure("movement", "FailedStuck target=three", 100, 30, 240)
recovery:recordMovementFailure("movement", "FailedStuck target=four", 100, 30, 240)
recovery:recordMovementFailure("movement", "FailedStuck target=five", 100, 30, 240)
assert(firstRetry == 130 and secondRetry == 160 and recovery.nextThink == 340,
    "movement failures use bounded exponential backoff")
assert(recovery.failureReasons["movement:FailedStuck"] == 5,
    "dynamic failure details share one diagnostic streak")
recovery:finishDecision(100)
assert(recovery.nextThink == 340,
    "ordinary decision refresh preserves movement cooldown")
recovery:resetMovementRecovery()
assert(recovery.movementFailureCount == 0 and recovery.formationFailureCount == 0,
    "successful movement resets recovery streaks")

local crossFloorFailure = followerController("cross-floor-failure", 1)
crossFloorFailure:recordMovementFailure(
    "movement", "FailedInvalidZChange targetZ=2", 200, 30, 240
)
assert(crossFloorFailure.nextThink == 230,
    "unreachable cross-floor routes enter normal bounded recovery")

local interrupted = followerController("interrupted", 1)
interrupted.state = "COMPANION_FOLLOW"
interrupted.activeDecision = "follow_player"
interrupted.companionOrder = "follow"
interrupted.character = {
    getCharacterActions = function()
        return { isEmpty = function() return true end }
    end,
    isSitOnGround = function() return false end,
    isSittingOnFurniture = function() return false end,
    setVariable = function() end,
    setIsResting = function() end,
    setBed = function() end,
}
local cancellationBeforeInterrupt = cancelCount
assert(interrupted:interruptForDirective(), "movement can be interrupted")
assert(cancelCount == cancellationBeforeInterrupt + 1,
    "interruption explicitly releases Java movement ownership")
assert(interrupted.state == "IDLE" and interrupted.companionOrder == "follow",
    "temporary interruption preserves the underlying follow order")

local deadMember = {
    isDead = function() return true end,
    getCurrentSquare = function() return square(100, 100, 0) end,
}
local leaderController = setmetatable({
    character = leader,
    groupMembers = { leader, deadMember },
}, Controller)
assert(leaderController:findDistantGroupMember() == nil,
    "dead or stale members cannot hold a travelling leader in retrieval")

local groupInterrupted = followerController("group-interrupted", 1)
groupInterrupted.state = "GROUP_FOLLOW"
groupInterrupted.activeDecision = "follow_group"
groupInterrupted.abandonBaseTask = function() end
groupInterrupted.releaseSupply = function() end
groupInterrupted.releaseRestSpot = function() end
groupInterrupted.leaveRecoveryPosture = function() end
local originalLeader = groupInterrupted.groupLeader
assert(groupInterrupted:interruptForDirective(), "group travel can be interrupted")
assert(groupInterrupted.state == "IDLE" and groupInterrupted.groupLeader == originalLeader,
    "temporary interruption preserves durable group travel membership")

local droppedCorpse = false
local clearedActions = false
KnoxBaseCorpseHandling = {
    isDragging = function() return true end,
}
KnoxBaseTaskBoard = {
    finish = function()
        return {}, "complete"
    end,
}
ISTimedActionQueue = {
    clear = function() clearedActions = true end,
}
local corpseCharacter = {
    getCharacterActions = function()
        return { isEmpty = function() return false end }
    end,
    setDoGrappleLetGo = function()
        droppedCorpse = true
    end,
}
local corpseController = setmetatable({
    id = "corpse-worker",
    character = corpseCharacter,
    bridge = bridge,
    baseId = "base-1",
    baseTask = { id = "corpse-task", baseId = "base-1", type = "haul_corpse" },
}, Controller)
assert(corpseController:abandonBaseTask("combat_interrupt"),
    "interrupted corpse task should be closed")
assert(clearedActions and droppedCorpse,
    "interruption should clear actions and release a dragged corpse")

print("Autonomy formation PASS release=true slots=true refresh=true corpse_interrupt=true flee_policy=true")

-- Ambient movement must not constantly replace work or funnel residents
-- downstairs. Occupied tiles and outdoor nighttime targets are rejected.
local occupied, indoors, hour = false, false, 12
local current = square(5, 5, 1)
local candidate = square(10, 20, 1)
candidate.getMovingObjects = function()
    return { size = function() return occupied and 1 or 0 end }
end
candidate.getRoom = function() return indoors and {} or nil end
getGameTime = function() return { getTimeOfDay = function() return hour end } end
local requestedZ
local randomBounds = {}
ZombRand = function(bound) randomBounds[#randomBounds + 1] = bound; return 0 end
cell.getGridSquare = function(_, x, y, z) requestedZ = z; return candidate end
local ambient = setmetatable({
    base = { home = { minX = 10, minY = 20, width = 3, height = 3, z = 0 },
        territory = { minX = 9, minY = 19, maxX = 13, maxY = 23, allFloors = true } },
    character = { getCurrentSquare = function() return current end },
}, Controller)
assert(ambient:findBaseMovementTarget(false) == candidate and requestedZ == 1,
    "daytime ambient movement may use outdoors but stays on current floor")
assert(randomBounds[1] == 5 and randomBounds[2] == 5,
    "persisted min/max territory samples the whole yard, not one corner")
occupied = true
assert(ambient:findBaseMovementTarget(false) == nil, "avoid gathering on occupied tiles")
occupied, hour = false, 22
assert(ambient:findBaseMovementTarget(false) == nil, "nighttime idling stays indoors")
indoors = true
assert(ambient:findBaseMovementTarget(false) == candidate, "indoor night rest target allowed")
ambient.nextAmbientMoveAt = 500
assert(not ambient:beginBaseMovement(100, false) and ambient.state == "BASE_IDLE",
    "ambient cooldown prevents repeated patrol starts")

dofile(projectRoot .. "/mod/42/media/lua/client/KS_OrderSignals.lua")
local originalSignalTimestamp = getTimestampMs
getTimestampMs=function() return 0 end
local signals, busy = 0, false
local commander = setmetatable({ groupMembers = { {}, {} }, character = {
    playEmote = function(_, name) assert(name == "followme"); signals = signals + 1 end,
    getCharacterActions = function() return { isEmpty = function() return not busy end } end,
}}, Controller)
assert(commander:signalFollowers("followme", 100))
assert(not commander:signalFollowers("followme", 101) and signals == 1, "signals are rate limited")
busy = true
assert(not commander:signalFollowers("followme", 1100), "signals do not interrupt native work")
busy = false
commander.groupLeader = {}
assert(not commander:signalFollowers("followme", 1100), "followers do not issue leader signals")
commander.groupLeader=nil
local originalSignalSettings=KnoxSettings
KnoxSettings={orderGesturesEnabled=function() return false end}
assert(not commander:signalFollowers("followme", 2100), "NPC leaders respect the same gesture setting as players")
KnoxSettings=originalSignalSettings
getTimestampMs=originalSignalTimestamp
print("Base movement and leader signal policy PASS")

local onWorkArea, startCalls, starts, restoredClaim = true, 0, true, nil
KnoxBaseJobs = { containsWorkSquare = function() return onWorkArea end }
KnoxPersistence.getClaimedBaseTaskForSurvivor = function() return restoredClaim end
local external = setmetatable({ baseId = "base-1", id = "worker", base = {},
    character = { getCurrentSquare = function() return current end },
    beginBaseTask = function() startCalls = startCalls + 1; return starts end,
}, Controller)
assert(external:resumeExternalBaseWork(100) and startCalls == 1, "outdoor work does not require a home detour")
external.pendingBaseSupplyDeposit = {}
assert(not external:resumeExternalBaseWork(100) and startCalls == 1, "deliveries return home first")
external.pendingBaseSupplyDeposit, external.baseSupplyOrder = nil, {}
assert(not external:resumeExternalBaseWork(100) and startCalls == 1, "explicit supply orders retain priority")
external.baseSupplyOrder, onWorkArea = nil, false
assert(not external:resumeExternalBaseWork(100), "without a claim or work area resident returns home")
restoredClaim = { id = "saved-duty", state = "claimed" }
assert(external:resumeExternalBaseWork(100), "restored duty resumes after danger even outside its zone")
starts, external.nextThink = false, 200
assert(external:resumeExternalBaseWork(100), "failed start retains bounded recovery")
external.nextThink = 0
assert(not external:resumeExternalBaseWork(100), "no available work returns home")
print("External work continuation PASS")
