local projectRoot = arg[1] or "."

require = function()
    return true
end

local blockedEdge = function() return false end
local function square(x, y, z)
    return {
        getX = function() return x end,
        getY = function() return y end,
        getZ = function() return z or 0 end,
        canStand = function() return true end,
        isBlockedTo = function(self, other) return blockedEdge(self, other) end,
        isHoppableTo = function() return false end,
    }
end

local zombies = {}
local cell = {
    getZombieList = function()
        return {
            size = function() return #zombies end,
            get = function(_, index) return zombies[index + 1] end,
        }
    end,
    getGridSquare = function(_, x, y, z)
        return square(x, y, z)
    end,
}

getCell = function() return cell end
getNumActivePlayers = function() return 1 end
local player = nil
getSpecificPlayer = function() return player end
ZombRand = function() return 0 end
CharacterStat = { ENDURANCE = "endurance" }
AdjacentFreeTileFinder = {
    Find = function(target) return target end,
}
ISTimedActionQueue = { clear = function(character) character.actionsEmpty = true end }
KnoxPersistence = {
    captureActiveSurvivor = function() end,
    areSurvivorsAllied = function(firstId, secondId)
        return firstId == "primary" and secondId == "persisted-ally"
    end,
}
local runtimeIds = {}
KnoxSurvivorRuntime = {
    idForCharacter = function(character) return runtimeIds[character] end,
}
KnoxActivityFeed = {
    speak = function() end,
}
local fleeingEnabled = true
KnoxSettings = {
    allowSurvivorFleeing = function() return fleeingEnabled end,
}
KnoxFirearmSupport = {
    prepareForThreat = function() return "ready", "MELEE" end,
}
KnoxSurvivorNeeds = {
    wakeForDanger = function(character)
        character.asleep = false
        return true
    end,
}

local controllerPath = projectRoot
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
assert(loadfile(controllerPath))()
local Controller = assert(KnoxAutonomyController)

local traversalCharacter = {
    getCurrentStateName = function() return "ClimbOverFenceState" end,
    getCurrentActionContextStateName = function() return "climbfence" end,
}
assert(Controller.isNativeTraversalBusy(traversalCharacter),
    "native fence traversal blocks autonomy preemption until the action resolves")
traversalCharacter.getCurrentStateName = function() return "IdleState" end
traversalCharacter.getCurrentActionContextStateName = function() return "idle" end
assert(not Controller.isNativeTraversalBusy(traversalCharacter),
    "ordinary movement remains eligible for threat reevaluation")

assert(not Controller.selfCareReady({ eat = 300 }, "eat", 299)
        and Controller.selfCareReady({ eat = 300 }, "eat", 300),
    "failed self-care cannot be requested every tick and retries at its bound")

local survivorSquare = square(0, 0, 0)
local health = 100
local endurance = 0.8
local bodyParts = {}
local weapon = nil
local character = {
    getCurrentSquare = function() return survivorSquare end,
    getHealth = function() return health end,
    getStats = function()
        return { get = function() return endurance end }
    end,
    getBodyDamage = function()
        return {
            getBodyParts = function()
                return {
                    size = function() return #bodyParts end,
                    get = function(_, index) return bodyParts[index + 1] end,
                }
            end,
        }
    end,
    getPrimaryHandItem = function() return weapon end,
    CanSee = function(_, target) return target == nil or target.visible ~= false end,
    getCharacterActions = function()
        return { isEmpty = function() return true end }
    end,
    isSitOnGround = function() return false end,
    isSittingOnFurniture = function() return false end,
    setVariable = function() end,
    setIsResting = function() end,
    setBed = function() end,
}
player = character

local approachTarget = {
    getCurrentSquare = function() return square(4, 0, 0) end,
}
local approach = Controller.combatApproachSquare(character, approachTarget)
assert(approach ~= nil and approach:getX() == 3 and approach:getY() == 0,
    "combat approach chooses the nearest standable side instead of an arbitrary opposite tile")

local function zombieAt(x, y, target, z, options)
    options = options or {}
    local dead = false
    local currentTarget = target
    local currentSquare = square(x, y, z or 0)
    return {
        visible = true,
        isDead = function() return dead end,
        setDead = function(_, value) dead = value end,
        getCurrentSquare = function() return currentSquare end,
        setCurrentSquare = function(_, value) currentSquare = value end,
        getTarget = function() return currentTarget end,
        setTarget = function(_, value) currentTarget = value end,
        isOnFloor = function() return options.onFloor == true end,
        isCrawling = function() return options.crawling == true end,
    }
end

local function controller(id)
    return setmetatable({
        id = id,
        character = character,
        reservations = { threats = {}, items = {}, restSpots = {} },
        failedThreats = {},
        groupMembers = {},
        nextThreatScan = 0,
        nextThink = 0,
        counts = { failures = 0 },
        failureReasons = {},
        fleeSafeScans = 0,
    }, Controller)
end

-- Persistent Hold/Guard directives must not time out into planner churn.
do
    local held = controller("held")
    held.state, held.nextThink, held.companionOrder = "COMPANION_HOLD", 0, "hold"
    held:tick(500)
    assert(held.state == "COMPANION_HOLD" and held.nextThink > 500,
        "Hold remains authoritative after its refresh interval")
    local guarded = controller("guarded")
    guarded.state, guarded.nextThink, guarded.companionOrder = "COMPANION_GUARD", 0, "guard"
    guarded:tick(500)
    assert(guarded.state == "COMPANION_GUARD" and guarded.nextThink > 500,
        "Guard remains authoritative after its refresh interval")
end

local function meleeWeapon(condition, reach, skill)
    return {
        isBroken = function() return condition <= 0 end,
        getCondition = function() return condition end,
        getConditionMax = function() return 10 end,
        getMaxRange = function() return reach or 1.2 end,
        getWeaponSkill = function() return skill or 0 end,
    }
end

local function wound(options)
    options = options or {}
    return {
        bandaged = function() return options.bandaged == true end,
        bleeding = function() return options.bleeding == true end,
        bitten = function() return options.bitten == true end,
        isDeepWounded = function() return options.deep == true end,
        isCut = function() return options.cut == true end,
        getFractureTime = function() return options.fracture or 0 end,
    }
end

local c = controller("primary")
local distant = zombieAt(9, 0, nil)
local immediate = zombieAt(2, 0, nil)
zombies = { distant, immediate }
assert(c:selectCombatThreat(0) == immediate,
    "immediate threat outranks a distant visible zombie")

local quietCrowdA = zombieAt(3, 0, nil)
local quietCrowdB = zombieAt(4, 1, nil)
local quietCrowdC = zombieAt(5, -1, nil)
zombies = { quietCrowdA, quietCrowdB, quietCrowdC }
assert(Controller.shouldRemainStealthy(c),
    "three visible same-floor zombies allow cautious stealth while undetected")
quietCrowdB:setTarget(character)
assert(not Controller.shouldRemainStealthy(c),
    "being detected immediately releases stealth to existing fight-or-flee policy")

local hidden = zombieAt(2, 0, nil)
hidden.visible = false
assert(c:evaluateCombatThreat(hidden, 10) == nil,
    "distance alone does not reveal an idle threat through blocked LOS")
hidden.visible = true
assert(c:evaluateCombatThreat(hidden, 20) ~= nil,
    "close threat with native LOS is perceived")
hidden.visible = false
local remembered = c:evaluateCombatThreat(hidden, 100)
assert(remembered ~= nil and remembered.reason == "remembered",
    "recently lost visible threat remains in short bounded memory")
assert(c:evaluateCombatThreat(hidden, 141) == nil,
    "lost threat memory expires")
assert(c:evaluateCombatThreat(zombieAt(1, 0, nil, 1), 150) == nil,
    "threat directly above or below is not treated as adjacent")
assert(Controller.perceptionScanOffset("scan-a")
        ~= Controller.perceptionScanOffset("scan-b"),
    "survivor scans receive deterministic staggering where identifiers differ")

local ally = { getCurrentSquare = function() return square(1, 0, 0) end }
c.groupMembers = { ally }
local allyThreat = zombieAt(6, 0, ally)
local ordinaryThreat = zombieAt(5, 0, nil)
zombies = { ordinaryThreat, allyThreat }
assert(c:selectCombatThreat(15) == allyThreat,
    "a nearby ally under attack receives protection priority")

c.groupMembers = {}
local persistedAlly = { getCurrentSquare = function() return square(1, 0, 0) end }
runtimeIds[persistedAlly] = "persisted-ally"
local persistedAllyThreat = zombieAt(6, 0, persistedAlly)
zombies = { ordinaryThreat, persistedAllyThreat }
assert(c:selectCombatThreat(30) == persistedAllyThreat,
    "persisted social allegiance protects a loaded ally outside transient group caches")

c.groupMembers = {}
local current = zombieAt(4, 0, nil)
local marginallyCloser = zombieAt(3.8, 0, nil)
c.combatTarget = current
c.lastCombatRetarget = -1000
local closerAwareness = c:evaluateCombatThreat(marginallyCloser, 100)
assert(not c:shouldReplaceCombatTarget(marginallyCloser, closerAwareness, 100),
    "small distance changes do not thrash a valid combat target")

local emergency = zombieAt(1, 0, character)
local emergencyAwareness = c:evaluateCombatThreat(emergency, 100)
c.lastCombatRetarget = 95
assert(c:shouldReplaceCombatTarget(emergency, emergencyAwareness, 100),
    "a much more immediate active attacker can break retarget cooldown")

local downed = zombieAt(1, 0, nil, 0, { onFloor = true })
local standingAttacker = zombieAt(2, 0, character)
c.combatTarget = downed
c.lastCombatRetarget = 99
local standingAwareness = c:evaluateCombatThreat(standingAttacker, 100)
assert(c:shouldReplaceCombatTarget(standingAttacker, standingAwareness, 100),
    "a standing attacker outranks a downed non-crawler during retarget cooldown")
local crawler = zombieAt(1, 0, nil, 0, { onFloor = true, crawling = true })
assert(c:evaluateCombatThreat(crawler, 100).downed == false,
    "a real crawler remains a full immediate threat")

c.combatTarget = current
current:setDead(true)
assert(c:shouldDropCombatTarget(100), "dead current target is dropped")
local formerHostile = zombieAt(1, 0, character)
runtimeIds[formerHostile] = "new-ally"
c.combatTarget = formerHostile
assert(c:shouldDropCombatTarget(100), "new ally is dropped even with stale attack intent")
runtimeIds[formerHostile] = nil
c.combatTarget = current
current:setDead(false)
current:setCurrentSquare(nil)
assert(c:shouldDropCombatTarget(100), "unloaded current target is dropped")
local unreachable = zombieAt(4, 0, nil)
c.combatTarget = unreachable
c.failedThreats[unreachable] = 200
assert(c:shouldDropCombatTarget(100), "temporarily unreachable current target is dropped")

local leader = { getCurrentSquare = function() return square(0, 0, 0) end }
c.combatTarget = zombieAt(15, 0, nil)
c.companionTarget = leader
c.companionOrder = "follow"
c.companionCombatStance = "aggressive"
assert(c:evaluateCombatThreat(c.combatTarget, 100) == nil,
    "companion role leash rejects an unrelated distant chase")
assert(not c:allowsCompanionThreat(c.combatTarget),
    "aggressive stance does not abandon the leader role")

c.groupMembers = { ally }
c.companionCombatStance = "defensive"
local defending = zombieAt(6, 0, ally)
assert(c:allowsCompanionThreat(defending),
    "defensive companion can protect a nearby group member")

local reservationThreat = zombieAt(7, 0, nil)
local first = controller("first")
local second = controller("second")
first.reservations = c.reservations
second.reservations = c.reservations
zombies = { reservationThreat }
assert(first:selectCombatThreat(200) == reservationThreat,
    "first survivor sees an unclaimed ordinary threat")
first.reservations.threats[reservationThreat] = { first = true }
assert(second:selectCombatThreat(200) == nil,
    "ordinary distant threat is not needlessly dog-piled")

weapon = meleeWeapon(10, 1.4, 6)
health, endurance, bodyParts = 100, 0.8, {}
zombies = {
    zombieAt(4, 0, nil),
    zombieAt(-4, 1, nil),
    zombieAt(1, 5, nil),
}
local capable = controller("capable")
local shouldFlee, capableRisk = capable:assessFlee()
assert(not shouldFlee and capableRisk.zombies == 3,
    "a healthy skilled armed survivor may fight three spaced zombies")
fleeingEnabled = false
assert(not capable:assessFlee()
        and not capable:beginFlee(1, { health = 1, endurance = 1 }),
    "sandbox flee switch prevents both assessment and direct retreat ownership")
fleeingEnabled = true

zombies = {
    zombieAt(1, 0, character),
    zombieAt(-1, 0, character),
    zombieAt(0, 1, nil),
    zombieAt(0, -1, nil),
}
shouldFlee, capableRisk = capable:assessFlee()
assert(shouldFlee and capableRisk.reason == "close_collapse"
        and capableRisk.immediate == 4,
    "four zombies collapsing at contact range forces retreat regardless of raw ratio")

health = 20
zombies = { zombieAt(2, 0, character) }
shouldFlee, capableRisk = capable:assessFlee()
assert(shouldFlee and capableRisk.reason == "critical_health",
    "critical health forces retreat from even one active threat")

health, endurance = 65, 0.8
bodyParts = {
    wound({ bleeding = true, cut = true }),
    wound({ bleeding = true, deep = true }),
}
zombies = {
    zombieAt(2, 0, character),
    zombieAt(-2, 0, nil),
}
shouldFlee, capableRisk = capable:assessFlee()
assert(shouldFlee and capableRisk.reason == "heavy_bleeding"
        and capableRisk.bleedingParts == 2,
    "multiple untreated bleeding wounds materially increase combat risk")

health, endurance, bodyParts = 100, 0.12, {}
weapon = nil
zombies = {
    zombieAt(2, 0, character),
    zombieAt(-2, 0, character),
}
shouldFlee, capableRisk = capable:assessFlee()
assert(shouldFlee and capableRisk.reason == "exhausted",
    "exhaustion plus immediate attackers triggers retreat without a fixed ratio rule")

health, endurance, bodyParts = 100, 0.8, {}
weapon = nil
zombies = {
    zombieAt(2, 0, nil),
    zombieAt(-2, 0, nil),
    zombieAt(0, 2, nil),
}
local isolated = controller("isolated")
local isolatedFlee, isolatedRisk = isolated:assessFlee()
local supported = controller("supported")
supported.groupMembers = {
    { getCurrentSquare = function() return square(1, 1, 0) end },
    { getCurrentSquare = function() return square(-1, 1, 0) end },
}
local supportedFlee, supportedRisk = supported:assessFlee()
assert(isolatedFlee and not supportedFlee
        and supportedRisk.risk < isolatedRisk.risk,
    "nearby allies increase combat capacity without changing threat geometry")

zombies = {
    zombieAt(2, 0, nil),
    zombieAt(-2, 0, nil),
    zombieAt(0, 2, nil),
    zombieAt(0, -2, nil),
}
local flee = controller("flee")
local targetA = assert(flee:findFleeTarget(300), "symmetric threat field has an escape candidate")
local targetB = assert(flee:findFleeTarget(300), "escape candidate remains available")
assert(targetA:getX() == targetB:getX() and targetA:getY() == targetB:getY(),
    "symmetric danger chooses a deterministic retreat direction")

assert(not flee:retreatIsSafelyClear(true),
    "unsafe scan keeps retreat active")
assert(not flee:retreatIsSafelyClear(false),
    "one clear scan is not enough to reverse retreat")
assert(flee:retreatIsSafelyClear(false),
    "bounded clear confirmation exits retreat")
assert(not flee:retreatIsSafelyClear(true) and flee.fleeSafeScans == 0,
    "renewed danger resets clear confirmation")
assert(not flee:retreatIsSafelyClear(false, { targeting = 1 })
    and not flee:retreatIsSafelyClear(false, { close = 1 }),
    "falling below flee initiation threshold does not end an ongoing pursuit")
assert(not flee:retreatIsSafelyClear(false, { nearestDistanceSquared = 25 }),
    "a zombie five tiles away is not enough clearance to end an established retreat")
assert(not flee:retreatIsSafelyClear(false, {}, 301)
    and not flee:retreatIsSafelyClear(false, {}, 301)
    and flee:retreatIsSafelyClear(false, {}, 302),
    "arrival and threat scan in the same tick cannot count as two safe observations")

local surrounding = zombies
zombies = { zombieAt(2, 0, character) }
blockedEdge = function(a, b)
    return a:getX() >= -1 and b:getX() < -1
        or a:getX() < -1 and b:getX() >= -1
end
local wallEscape = assert(controller("wall"):findFleeTarget(310))
assert(wallEscape:getX() >= -1, "standable destination beyond a blocking wall is not an escape lane")
blockedEdge = function(_, b) return b:getY() ~= 0 or b:getX() < 0 end
zombies = { zombieAt(3, 0, character) }
assert(controller("crowded-corridor"):findFleeTarget(312) == nil,
    "safe-looking far endpoint must not send escape straight through a zombie in the corridor")
blockedEdge = function(_, b)
    return not (b:getY() == 0 and (b:getX() == 0 or b:getX() == 1))
end
zombies = { zombieAt(1, 0, character) }
local trapped = controller("trapped")
trapped.state, trapped.companionOrder = "FLEEING", "follow"
trapped.bridge = {
    beginNpcLiveCombat = function() return "COMBAT_STARTED" end,
    resetNpcCombat = function() end,
}
assert(trapped:findFleeTarget(315) == nil, "enclosed fixture has no immediate two-tile escape")
assert(not trapped:beginFlee(315, { health = 100, endurance = .8 })
    and trapped.state == "COMBAT" and trapped.combatTarget == zombies[1],
    "no escape lane hands an adjacent attacker to existing combat instead of waiting for a bite")
assert(trapped.companionOrder == "follow", "trapped defense retains companion intent")
local passivePanic = controller("passive-panic")
passivePanic.companionOrder = "follow"
passivePanic.companionCombatStance = "passive"
local panicMoves = 0
passivePanic.bridge = {
    cancelNpcMove = function() end,
    resetNpcCombat = function() end,
    moveNpcWithPace = function(_, _, target, pace)
        panicMoves = panicMoves + 1
        assert(target ~= nil and pace == "sprint",
            "passive survivor panic route still uses a bounded sprint")
        return "MOVE_STARTED"
    end,
}
assert(passivePanic:findEmergencyFleeTarget(316) ~= nil,
    "passive survivor gets a last-resort target when every checked lane is blocked")
assert(passivePanic:beginFlee(316, { health = 100, endurance = .8 })
    and passivePanic.state == "FLEEING" and panicMoves == 1,
    "passive survivor starts panic movement instead of standing in a fatal surround")
blockedEdge = function() return false end
zombies = surrounding

local moveCalls, cancelCalls = 0, 0
flee.bridge = {
    cancelNpcMove = function() cancelCalls = cancelCalls + 1 end,
    resetNpcCombat = function() end,
    moveNpcWithPace = function()
        moveCalls = moveCalls + 1
        return "MOVE_STARTED"
    end,
}
flee.companionOrder = "follow"
flee.companionTarget = leader
flee.state = "COMBAT"
flee.combatTarget = zombies[1]
flee.reservations.threats[zombies[1]] = { flee = true }
assert(flee:beginFlee(400, {
    reason = "outnumbered", zombies = 4, allies = 1,
    health = 100, endurance = 0.8,
}), "retreat interrupts combat and starts one owned move")
assert(moveCalls == 1 and cancelCalls == 1 and flee.state == "FLEEING",
    "retreat produces one movement request without churn")
assert(flee.combatTarget == nil and flee.companionOrder == "follow",
    "retreat releases combat while preserving the underlying follow order")

local movementTicks = 0
flee.bridge.tickNpc = function()
    movementTicks = movementTicks + 1
    return "Succeeded"
end
flee.observedState = "FLEEING"
flee.nextThreatScan = 999
flee:tick(410)
assert(movementTicks == 1 and flee.state == "FLEEING" and flee.fleeRecoveryUntil == 415,
    "arrival releases native movement but does not resume looting while still surrounded")
flee:tick(411)
assert(moveCalls == 1 and movementTicks == 1, "escape continuation waits for its bounded retry")
flee.fleeTarget = targetA
flee:recoverFleeMovement("FailedStuck", 420)
assert(flee.state == "FLEEING" and flee.fleeRecoveryUntil == 435
    and flee.failedFleeTarget.untilTick > 435, "failure releases movement and retains short failed-lane memory")
local recovered = assert(flee:findFleeTarget(435))
assert((recovered:getX() - targetA:getX())^2 + (recovered:getY() - targetA:getY())^2 > 9,
    "recovery does not immediately retry the same failed escape destination")
local priorMoves = moveCalls
flee:tick(434)
assert(moveCalls == priorMoves, "controller refresh does not bypass flee recovery cooldown")
flee:tick(435)
assert(moveCalls == priorMoves + 1 and flee.fleeRecoveryUntil == nil,
    "cooldown expiry requests one replacement escape")
for index = 1, 5 do
    flee:recoverFleeMovement("FailedStuck", 440 + index)
    assert(flee.fleeRecoveryUntil - (440 + index) <= 60, "escape failure backoff remains bounded")
end
zombies = {}
flee.nextThreatScan = 500
flee:tick(500)
flee.nextThreatScan = 510
flee:tick(510)
assert(flee.state == "IDLE" and flee.movementFailureCount == 0,
    "confirmed safe retreat releases ownership and clears the failure streak")
zombies = surrounding
assert(flee.companionOrder == "follow",
    "completed retreat leaves the durable Follow order available to resume")
local postRetreat = zombieAt(5, 0, nil)
assert(flee:evaluateCombatThreat(postRetreat, 511) == nil,
    "completed retreat cannot immediately reacquire a five-tile chase")
assert(flee:evaluateCombatThreat(zombieAt(1, 0, character), 512) ~= nil,
    "disengagement still permits adjacent self defense")
assert(flee:evaluateCombatThreat(postRetreat, flee.combatDisengageUntil) ~= nil,
    "post-retreat chase restriction expires instead of permanently disabling combat")

local unarmed = controller("unarmed")
unarmed.bridge = {
    beginNpcLiveCombat = function() return "COMBAT_FAILED NO_EQUIPPED_WEAPON" end,
    resetNpcCombat = function() end,
    cancelNpcMove = function() return true end,
    moveNpcWithPace = function() return "MOVE_STARTED" end,
}
weapon = nil
zombies = { postRetreat }
assert(not unarmed:beginCombat(postRetreat) and unarmed.unarmedCombatBlocked,
    "native no-weapon rejection records a survival fallback rather than a long generic combat retry")
local rejectedCalls = 0
unarmed.bridge.beginNpcLiveCombat = function()
    rejectedCalls = rejectedCalls + 1
    return "COMBAT_FAILED NO_EQUIPPED_WEAPON"
end
unarmed.currentTicks = 20
unarmed:beginCombat(postRetreat)
unarmed:beginCombat(zombieAt(2, 0, character))
assert(rejectedCalls == 0,
    "missing weapon does not repeatedly retry native combat even when target changes")
local unarmedFlee, unarmedRisk = unarmed:assessFlee()
assert(unarmedFlee and unarmedRisk.reason == "no_usable_weapon",
    "unarmed actor escapes instead of repeatedly chasing a zombie it cannot attack")
weapon = meleeWeapon(10, 1.5, 5)
unarmed.state = "IDLE"
unarmed.combatDisengageUntil = 0
unarmed:beginCombat(postRetreat)
assert(rejectedCalls == 1,
    "newly equipped weapon permits immediate reevaluation before the cooldown expires")
assert(not unarmed:assessFlee(), "finding a usable weapon removes unarmed-only retreat pressure")
weapon, zombies = nil, surrounding

local groupTargets = {}
local function groupRetreater(id, slot)
    local member = controller(id)
    member.groupLeaderId = "shared-leader"
    member.groupFormationSlot = slot
    member.groupMembers = { ally }
    member.bridge = {
        cancelNpcMove = function() end,
        resetNpcCombat = function() end,
        moveNpcWithPace = function(_, _, target)
            groupTargets[id] = target
            return "MOVE_STARTED"
        end,
    }
    return member
end
local groupFirst = groupRetreater("group-first", 1)
local groupSecond = groupRetreater("group-second", 2)
assert(groupFirst:beginFlee(500, {
    reason = "outnumbered", zombies = 6, allies = 2,
    health = 100, endurance = 0.8,
}), "first group member establishes a flee plan")
assert(groupSecond:beginFlee(500, {
    reason = "outnumbered", zombies = 6, allies = 2,
    health = 100, endurance = 0.8,
}), "second group member follows the flee plan")
local firstDx = groupTargets["group-first"]:getX() - survivorSquare:getX()
local firstDy = groupTargets["group-first"]:getY() - survivorSquare:getY()
local secondDx = groupTargets["group-second"]:getX() - survivorSquare:getX()
local secondDy = groupTargets["group-second"]:getY() - survivorSquare:getY()
assert(firstDx * secondDx + firstDy * secondDy > 0,
    "overwhelmed group retreats in a coherent shared direction")
assert(groupTargets["group-first"]:getX() ~= groupTargets["group-second"]:getX()
        or groupTargets["group-first"]:getY() ~= groupTargets["group-second"]:getY(),
    "group retreat keeps separate arrival tiles")

local selfCareCharacter = {
    actionsEmpty = false,
    asleep = true,
    getCharacterActions = function(self)
        return { isEmpty = function() return self.actionsEmpty end }
    end,
    isAsleep = function(self) return self.asleep end,
    isSitOnGround = function() return false end,
    isSittingOnFurniture = function() return false end,
    setVariable = function() end,
    setIsResting = function() end,
    setBed = function() end,
}
local selfCare = setmetatable({
    id = "self-care",
    character = selfCareCharacter,
    state = "TIMED_ACTION",
    activeDecision = "eat",
    selfCareIntent = { kind = "eat", before = {} },
    companionOrder = "follow",
    bridge = { cancelNpcMove = function() end },
    reservations = { restSpots = {} },
}, Controller)
assert(selfCare:interruptSelfCareForDanger(600),
    "immediate danger interrupts an owned self-care action")
assert(selfCareCharacter.actionsEmpty and not selfCareCharacter.asleep
        and selfCare.selfCareIntent == nil,
    "danger clears timed/sleep ownership without leaving stale self-care intent")
assert(selfCare.state == "IDLE" and selfCare.companionOrder == "follow"
        and selfCare.selfCareInterrupted == "eat",
    "interruption preserves the durable Follow order for later resume")

local closeRange = controller("close-range")
closeRange.bridge = {
    beginNpcLiveCombat = function() return "COMBAT_FAILED TEST_ROUTE" end,
    resetNpcCombat = function() end,
}
closeRange.currentTicks = 100
closeRange.rangedFallbackUntil = { [postRetreat] = 200 }
local prepared, melee = 0, 0
KnoxFirearmSupport.prepareForThreat = function()
    prepared = prepared + 1
    return "ready", "FIREARM"
end
KnoxFirearmSupport.fallbackToMelee = function()
    melee = melee + 1
    return "EQUIPPED Base.BaseballBat"
end
closeRange:beginCombat(postRetreat)
assert(melee == 1 and prepared == 0,
    "close-range fallback survives the next threat scan without selecting the gun again")
closeRange.currentTicks = 200
closeRange.failedThreats = {}
closeRange:beginCombat(postRetreat)
assert(melee == 1 and prepared == 1,
    "expired close-range fallback allows normal firearm selection again")

local relaxFinished = 0
local relaxKind = "roam"
KnoxSurvivorNeeds.decide = function() return { kind = relaxKind } end
local relaxing = setmetatable({ companionOrder = "relax", nextThink = 100,
    character = {}, selfCareRetryAt = {},
    finishDecision = function() relaxFinished = relaxFinished + 1 end }, Controller)
relaxing:updateCompanionRelax(100)
relaxing:updateCompanionRelax(280)
assert(relaxFinished == 0, "ordinary relax rechecks must not force standing and resitting")
relaxKind = "find_food"
relaxing:updateCompanionRelax(460)
assert(relaxFinished == 0, "missing supplies must not restart the relaxed posture")
relaxKind = "eat"
relaxing:updateCompanionRelax(640)
assert(relaxFinished == 1 and relaxing.nextThink == 640,
    "usable self-care interrupts relax for the ordinary needs owner")
relaxing.companionOrder = "follow"
relaxing:updateCompanionRelax(641)
assert(relaxFinished == 2, "replacement order ends relax immediately")
-- Exercise the full tick: general danger scanning must not consume the deadline
-- before combat can check invalid targets, replacement threats and preparation.
do
    fleeingEnabled = false
    zombies = {}
    local decisions, nativeTicks, finished = 0, 0, 0
    local mode = "ready"
    KnoxFirearmSupport.currentCombatState = function()
        decisions = decisions + 1
        return mode, "test"
    end
    local combat = controller("scheduled")
    local target = zombieAt(1, 0, character)
    combat.state, combat.combatTarget = "COMBAT", target
    combat.companionOrder = "hold"
    combat.bridge = {
        tickNpcCombat = function() nativeTicks = nativeTicks + 1; return "COMBAT_ATTACKING" end,
        resetNpcCombat = function() end,
    }
    combat.finishDecision = function(self)
        finished = finished + 1; self.state = "IDLE"
    end
    combat:tick(1000)
    assert(decisions == 1 and nativeTicks == 1, "combat must share scheduled danger scan")
    local deadline = combat.nextThreatScan
    combat:tick(1001)
    assert(decisions == 1 and nativeTicks == 2, "native combat ticks between bounded decisions")
    target:setDead(true)
    combat:tick(deadline)
    assert(decisions == 2 and finished == 1 and combat.combatTarget == nil,
        "invalid target cleanup must actually run in the full tick")
    assert(combat.companionOrder == "hold", "combat cleanup preserves durable Hold")
    mode = "reloading"
    combat.state, combat.combatTarget = "COMBAT", zombieAt(1, 0, character)
    combat:tick(combat.nextThreatScan)
    assert(decisions == 3 and finished == 2 and combat.combatTarget == nil,
        "scheduled reload handoff must release combat instead of starving")
    mode = "ready"
    local urgent = zombieAt(1, 0, character)
    zombies = {urgent}
    combat.state, combat.combatTarget = "COMBAT", zombieAt(5, 0, nil)
    local replacement
    combat.beginCombat = function(self, candidate)
        replacement = candidate; self.combatTarget = candidate; self.state = "COMBAT"
        return true
    end
    combat:tick(combat.nextThreatScan)
    assert(replacement == urgent, "full tick must replace distant commitment with an immediate attacker")
end
print("combat intelligence focused tests passed")
assert(Controller.fleePace({endurance=0.9, health=100, immediate=0, close=0}) == "run",
    "distant crowd retreat saves sprint endurance")
assert(Controller.fleePace({endurance=0.9, health=100, immediate=1}) == "sprint",
    "close attacker permits an urgent sprint")
assert(Controller.fleePace({endurance=0.2, health=100, immediate=2}) == "run",
    "exhausted survivor does not demand sprint")
