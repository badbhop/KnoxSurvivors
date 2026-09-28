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
        isBlockedTo = function() return false end,
        isHoppableTo = function() return false end,
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
local statusSource = assert(io.open(controllerPath, "rb")):read("*a")
assert(string.find(statusSource, "destination=", 1, true)
    and string.find(statusSource, "supplyAttempts=", 1, true),
    "developer status includes destination and base supply diagnostics")
assert(string.find(statusSource, "anchor:isSprinting()", 1, true)
    and string.find(statusSource, "distance >= 4", 1, true),
    "a sprinting formation leader requests catch-up before a large gap opens")
assert(string.find(statusSource, "self:updateFormationMovementPace(anchor)", 1, true),
    "formation posture refreshes before the companion decides it is already at its slot")
assert(string.find(statusSource, "self:resumeGroupFollowAfterSuccess(ticks)", 1, true),
    "native group-route completion returns through immediate formation arbitration")
assert(string.find(statusSource, "signals.play(member, \"yes\")", 1, true),
    "nearby autonomous followers acknowledge leader movement signals")

for _,context in ipairs({"urgent","directed","return_home","travel","local"}) do
    assert(Controller.travelPaceFor(900,false,context)=="cautious", "routine routes default to a cautious pace")
end
local originalPaceSettings=KnoxSettings
KnoxSettings={cautiousTravel=function() return false end}
assert(Controller.travelPaceFor(49, false, "urgent") == "walk",
    "short urgent movement remains a walk")
assert(Controller.travelPaceFor(64, false, "urgent") == "sprint",
    "meaningfully distant urgent supply travel may sprint; native locomotion still gates on fitness")
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
assert(not shouldFlee and assessment.reason == nil,
    "distant non-targeting threats do not interrupt formation work")
local ally = { getCurrentSquare = function() return square(1, 0, 0) end }
fleeController.groupMembers = { ally }
zombieCount = 5
shouldFlee = fleeController:assessFlee()
assert(not shouldFlee, "allies and distance keep a non-immediate crowd below retreat admission")
zombieCount = 6
zombieSquare = square(1, 0, 0)
shouldFlee, assessment = fleeController:assessFlee()
assert(shouldFlee and assessment.reason == "outnumbered",
    "an overwhelming immediate crowd admits a formation survivor to retreat")
zombieCount = 1
zombieSquare = square(2, 0, 0)
health = 25
shouldFlee, assessment = fleeController:assessFlee()
assert(shouldFlee and assessment.reason == "critical_health",
    "critical health plus an immediate threat admits retreat")

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
local followerState = "IdleState"
local followerActionState = "idle"
local follower = {
    getX = function() return 0.5 end,
    getY = function() return 0.5 end,
    getCurrentSquare = function() return followerSquare end,
    getCharacterActions = function()
        return { isEmpty = function() return true end }
    end,
    getCurrentStateName = function() return followerState end,
    getCurrentActionContextStateName = function() return followerActionState end,
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

local completedGroupFollow = followerController("completed-group-follow", 2)
completedGroupFollow.state = "GROUP_FOLLOW"
completedGroupFollow.activeDecision = "follow_group"
completedGroupFollow.formationMovementPace = "sprint"
completedGroupFollow.nextFormationRefresh = 999
local movesBeforeGroupSuccess = moveCount
completedGroupFollow:resumeGroupFollowAfterSuccess(75)
assert(completedGroupFollow.state == "IDLE"
    and completedGroupFollow.activeDecision == "follow_group"
    and completedGroupFollow.nextThink == 75
    and completedGroupFollow.nextFormationRefresh == 75
    and completedGroupFollow.formationMovementPace == nil,
    "native group-route success re-enters normal arbitration on the next tick")
assert(moveCount == movesBeforeGroupSuccess,
    "native group-route success does not issue a duplicate movement request itself")

leaderSquare = square(12, 10, 0)
assert(left:refreshFormationFollow(120), "moving leader refreshes formation path")
assert(captured.left:getX() == 11 and captured.left:getY() == 9,
    "formation destination follows moving leader")

followerSquare = square(11, 9, 0)
leaderSquare = square(12, 10, 1)
local cancellationBeforeFloorRefresh = cancelCount or 0
assert(left:refreshFormationFollow(165),
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
assert(left:refreshFormationFollow(240),
    "failed formation refresh is consumed")
assert(left.state == "GROUP_WAIT", "failed formation enters bounded wait")
assert(left.nextThink >= 300,
    "failed formation keeps full route cooldown")
assert(left.formationFailureCount == 1 and cancelCount > 0,
    "failed formation cancels stale owner and records retry")

left:finishDecision(240)
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
assert(not companion:refreshFormationFollow(60) and captured["companion:pace"]=="sneak"
    and moveCount==movesAfterStart, "actual leader crouching changes pace without replacing the route")
leader.isSneaking=function() return false end
companion.nextFormationRefresh=30
assert(not companion:refreshFormationFollow(20) and moveCount == movesAfterStart,
    "follow refresh does nothing before its cadence expires")

-- Native traversal keeps ownership, but the first landed update must not wait
-- for a cadence deadline that was scheduled before/during the climb.
followerActionState = "climbfence"
companion.nextFormationRefresh = 500
assert(not companion:refreshFormationFollow(21)
    and companion.formationTraversalBusy == true
    and companion.nextFormationRefresh == 51,
    "native fence traversal is observed without replacing its route")
followerActionState = "idle"
local movesBeforeLanding = moveCount
companion:refreshFormationFollow(22)
assert(companion.formationTraversalBusy == nil
    and companion.nextFormationRefresh == 67
    and moveCount >= movesBeforeLanding,
    "the first landed update reevaluates immediately instead of standing on the old cadence")
companion.nextFormationRefresh = 30

followerSquare = square(4, 10, 0)
assert(not companion:refreshFormationFollow(40),
    "pace-only refresh keeps the active destination owner")
assert(captured["companion:pace"] == "run" and moveCount == movesAfterStart,
    "moderate separation downgrades to run without repathing")

followerSquare = square(8, 10, 0)
assert(not companion:refreshFormationFollow(120),
    "close pace refresh keeps the active route")
assert(captured["companion:pace"] == "normal" and moveCount == movesAfterStart,
    "close companion walks without destination churn")

leaderSquare = square(11, 10, 0)
assert(not companion:refreshFormationFollow(180),
    "one-tile leader movement does not force a replacement")
assert(moveCount == movesAfterStart,
    "small leader movement creates no route request")

leaderForwardX = 0
leaderForwardY = 1
assert(companion:refreshFormationFollow(225),
    "sharp leader direction change refreshes the follow slot")
assert(moveCount == movesAfterStart + 1,
    "direction change creates one replacement request")

local arrival = captured.companion
followerSquare = square(arrival:getX(), arrival:getY(), arrival:getZ())
companion.movementFailureCount = 3
companion.formationFailureCount = 2
assert(companion:refreshFormationFollow(300), "catch-up reaches its trailing slot")
assert(companion.state == "COMPANION_WAIT"
        and companion.movementFailureCount == 0
        and companion.formationFailureCount == 0,
    "successful catch-up resets movement recovery")

local movesBeforeHold = moveCount
companion.companionOrder = "hold"
assert(not companion:beginCompanionFollow(330),
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
local current = square(10, 20, 1)
local candidate = square(12, 20, 1)
candidate.getMovingObjects = function()
    return { size = function() return occupied and 1 or 0 end }
end
candidate.getRoom = function() return indoors and {} or nil end
getGameTime = function() return { getTimeOfDay = function() return hour end } end
local requestedZ
local randomBounds = {}
ZombRand = function(bound) randomBounds[#randomBounds + 1] = bound; return 0 end
cell.getGridSquare = function(_, x, y, z) requestedZ = z; return candidate end
KnoxBaseManager=KnoxBaseManager or {}
KnoxBaseManager.containsSquare=function(base,sq)
    local area=base.territory or base.home
    return sq:getX()>=area.minX and sq:getX()<=area.maxX and sq:getY()>=area.minY and sq:getY()<=area.maxY
end
local ambient = setmetatable({
    base = { home = { minX = 10, minY = 20, width = 3, height = 3, z = 0 },
        territory = { minX = 9, minY = 19, maxX = 13, maxY = 23, allFloors = true } },
    character = { getCurrentSquare = function() return current end },
}, Controller)
assert(ambient:findBaseMovementTarget(false) == candidate and requestedZ == 1,
    "daytime ambient movement may use outdoors but stays on current floor")
assert(randomBounds[1] == 5 and randomBounds[2] == 5,
    "a small persisted min/max territory remains available for local walks")
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
local signalNow = 0
getTimestampMs=function() return signalNow end
local signals, acknowledgements, busy = 0, 0, false
local commanderCharacter = {
    playEmote = function(_, name) assert(name == "followme"); signals = signals + 1 end,
    getCharacterActions = function() return { isEmpty = function() return not busy end } end,
    getCurrentSquare = function() return square(0, 0, 0) end,
}
local followerAcknowledgement = {
    playEmote = function(_, name) assert(name == "yes"); acknowledgements = acknowledgements + 1 end,
    getCharacterActions = function() return { isEmpty = function() return true end } end,
    getCurrentSquare = function() return square(2, 0, 0) end,
}
local commander = setmetatable({ groupMembers = { commanderCharacter, followerAcknowledgement }, character = commanderCharacter }, Controller)
assert(commander:signalFollowers("followme", 100) and acknowledgements == 1,
    "leader movement signal receives one nearby follower acknowledgement")
assert(not commander:signalFollowers("followme", 101) and signals == 1, "signals are rate limited")
commander.groupMembers = { followerAcknowledgement }
signalNow = 3000
assert(commander:signalFollowers("followme", 1000) and acknowledgements == 2,
    "a two-person group still signals and acknowledges its single follower")
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

-- Exercise real delivery/arbitration, not a source-text assertion. Native
-- bridge results are fixtures; native movement itself still needs Build 42.
local orderHour, orderCancels, actionBusy = 10, 0, false
getGameTime = function() return { getWorldAgeHours = function() return orderHour end } end
local savedActions = follower.getCharacterActions
follower.getCharacterActions = function() return { isEmpty = function() return not actionBusy end } end
bridge.cancelNpcMove = function() orderCancels = orderCancels + 1; return "MOVE_CANCELLED fixture" end
local commanded = followerController("commanded", 1)
commanded.groupLeaderId, commanded.state = "leader", "GROUP_FOLLOW"
commanded.nextFormationRefresh = 9999
local function directive(kind, revision)
    return { kind = kind, revision = revision, leaderId = "leader", groupId = "group", expiresAtHours = 10.25 }
end
commanded:setGroupLeader("leader", leader, 1, 3, nil, directive("follow", 1))
assert(not commanded:applyGroupLeaderOrder(10) and commanded.state == "GROUP_FOLLOW"
    and orderCancels == 0, "follow delivery does not stop an already-correct route")
commanded:setGroupLeaderOrder(directive("hold", 2))
assert(commanded.state == "GROUP_FOLLOW" and orderCancels == 0,
    "delivery never cancels movement from the relationship coordinator")
followerState = "ClimbOverFenceState"
assert(not commanded:refreshFormationFollow(11) and orderCancels == 0,
    "a pending hold preserves native fence completion")
followerState = "IdleState"
actionBusy = true
assert(not commanded:applyGroupLeaderOrder(12) and orderCancels == 0,
    "a pending hold preserves native actions such as door interaction")
actionBusy = false
assert(commanded:refreshFormationFollow(13) and commanded.state == "IDLE"
    and commanded.nextThink == 13 and orderCancels == 1,
    "after landing hold reopens normal priority arbitration before refresh cadence")
commanded.state, commanded.activeDecision = "GROUP_WAIT", "leader_hold"
commanded.nextThink = 999
commanded:setGroupLeaderOrder(directive("hold", 2))
assert(not commanded:applyGroupLeaderOrder(14) and orderCancels == 1,
    "repeated delivery does not reset a wait or spam cancellation")
commanded:setGroupLeaderOrder(directive("follow", 3))
assert(commanded:applyGroupLeaderOrder(15) and commanded.nextThink == 15,
    "follow promptly releases a leader-owned hold")
for _, state in ipairs({ "COMBAT", "FLEEING", "TIMED_ACTION", "MOVING_TO_FOOD",
    "BASE_TASK_MOVE", "GROUP_SUPPORT", "MOVING_TO_WINDOW_ENTRY", "GROUP_REGROUP" }) do
    commanded.state = state
    commanded:setGroupLeaderOrder(nil)
    commanded:setGroupLeaderOrder(directive("hold", 4))
    assert(not commanded:applyGroupLeaderOrder(16) and commanded.state == state and orderCancels == 1,
        "leader orders do not steal ownership from " .. state)
end
commanded.state, commanded.nextThink = "IDLE", 0
assert(commanded:applyGroupLeaderOrder(17) and commanded.groupLeaderOrder.kind == "hold",
    "the same durable order remains available after interruption ends")
commanded.state, commanded.activeDecision, commanded.nextThink = "GROUP_WAIT", "leader_hold", 999
orderHour = 10.25
assert(commanded:applyGroupLeaderOrder(18) and commanded.groupLeaderOrder == nil,
    "cached hold expires even before the next relationship refresh")
orderHour = 10
commanded.state, commanded.nextThink = "GROUP_WAIT", 100
commanded:setGroupLeaderOrder(directive("follow", 5))
assert(not commanded:applyGroupLeaderOrder(19) and commanded.nextThink == 100,
    "new directives cannot erase existing route failure backoff")
commanded.state = "GROUP_FOLLOW"
commanded:setGroupLeaderOrder(directive("hold", 6))
bridge.cancelNpcMove = function() orderCancels = orderCancels + 1; return "MOVE_CANCEL_FAILED native" end
assert(not commanded:applyGroupLeaderOrder(20) and commanded.state == "GROUP_FOLLOW",
    "failed native cancellation is not fabricated as hold success")
local afterFailure = orderCancels
assert(not commanded:applyGroupLeaderOrder(21) and orderCancels == afterFailure,
    "failed cancellation has bounded retry instead of per-tick spam")
commanded:setGroupLeaderOrder(directive("follow", 7))
assert(not commanded:applyGroupLeaderOrder(22) and commanded.nextGroupOrderRetry == nil
    and orderCancels == afterFailure, "superseded hold releases its retry without stopping follow")
commanded:setGroupLeaderOrder(directive("hold", 8))
bridge.cancelNpcMove = function() orderCancels = orderCancels + 1; return "MOVE_CANCELLED fixture" end
assert(commanded:applyGroupLeaderOrder(80), "native cancellation can recover after its retry bound")
commanded.state, commanded.activeDecision, commanded.nextThink = "GROUP_WAIT", "leader_hold", 999
commanded:clearGroupLeader()
assert(commanded:applyGroupLeaderOrder(81) and commanded.groupLeaderOrder == nil,
    "leader loss releases the cached hold without replacing survivor identity")
follower.getCharacterActions = savedActions
print("Leader order arbitration PASS delivery=true traversal=true priority=true expiry=true bounded_retry=true")
