local projectRoot = arg[1] or "."

require = function()
    return true
end

-- The engine always provides instanceof; the classifier gates the zombie-only
-- grapple flag on it so human shells can never throw through pcall.
instanceof = function(object, class)
    return class == "IsoZombie" and type(object) == "table" and object.__zombie == true
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
    areSurvivorsHostile = function(_, secondId)
        return secondId == "hostile-human"
    end,
}
local runtimeIds = {}
KnoxSurvivorRuntime = {
    idForCharacter = function(character) return runtimeIds[character] end,
}
KnoxActivityFeed = {
    speak = function() end,
}
KnoxSettings = {}
KnoxFirearmSupport = {
    prepareForThreat = function() return "ready", "MELEE" end,
}
KnoxSurvivorNeeds = { decide=function() return {kind="roam"} end,
    wakeForDanger = function(character)
        character.asleep = false
        return true
    end,
}

dofile(projectRoot .. "/mod/42/media/lua/client/KS_ThreatClassifier.lua")

local controllerPath = projectRoot
    .. "/mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"
assert(loadfile(controllerPath))()
local Controller = assert(KnoxAutonomyController)
local controllerSourceFile = assert(io.open(controllerPath, "r"))
local controllerSource = controllerSourceFile:read("*a")
controllerSourceFile:close()
assert(string.find(controllerSource, "local haulingCorpse", 1, true)
    and string.find(controllerSource, "interruptCorpseHaulForDefense", 1, true)
    and not string.find(controllerSource, 'reason = "corpse_carrier_threat"', 1, true),
    "corpse carriers must release into defense without retired flee")

-- Native grapple release is asynchronous: retain the haul claim while waiting,
-- enter combat only after hands are free, and bound a release that never ends.
do
    local dragging, releaseAttempts, suspended, defended = true, 0, 0, nil
    KnoxBaseCorpseHandling = { isDragging = function() return dragging end }
    local threat = { getCurrentSquare = function() return {} end }
    local carrier = setmetatable({
        id = "corpse-carrier",
        character = { setDoGrappleLetGo = function() releaseAttempts = releaseAttempts + 1 end },
        bridge = { cancelNpcMove = function() end },
        baseTask = { type = "haul_corpse", state = "claimed" },
    }, Controller)
    carrier.resetMovementRecovery = function() end
    carrier.suspendBaseTaskForThreat = function(_, reason)
        suspended = suspended + 1
        carrier.baseTask.interruptedReason = reason
        return true
    end
    carrier.allowsCompanionThreat = function() return true end
    carrier.beginCombat = function(_, target) defended = target; return true end
    assert(carrier:interruptCorpseHaulForDefense(threat, 100)
            and carrier.state == "CORPSE_DEFENSE_RELEASE" and defended == nil,
        "corpse carrier must wait for native release before attacking")
    dragging = false
    carrier:updateCorpseDefenseRelease(101)
    assert(defended == threat and carrier.baseTask ~= nil and suspended == 1
            and releaseAttempts >= 1,
        "released carrier must defend while retaining the interrupted haul claim")

    local abandoned = false
    dragging = true
    defended = nil
    carrier.baseTask = { type = "haul_corpse", state = "claimed" }
    carrier.abandonBaseTask = function() abandoned = true; carrier.baseTask = nil end
    carrier.recordFailure = function() end
    carrier:interruptCorpseHaulForDefense(threat, 200)
    carrier:updateCorpseDefenseRelease(291)
    assert(abandoned and defended == threat and carrier.state == "IDLE",
        "failed native corpse release must abandon the stale claim and still defend")
end

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
        __zombie = true,
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
local humanTarget = { getCurrentSquare = function() return square(2, 0, 0) end }
assert(not c:allowsCompanionThreat(humanTarget),
    "IsoPlayer human targets must not call the zombie-only getTarget method")
runtimeIds[humanTarget] = "hostile-human"
assert(c:allowsCompanionThreat(humanTarget),
    "defensive companion acquires a nearby human already classified as hostile")
runtimeIds[humanTarget] = nil

local reservationThreat = zombieAt(4, 0, nil)
local first = controller("first")
local second = controller("second")
first.reservations = c.reservations
second.reservations = c.reservations
zombies = { reservationThreat }
assert(first:selectCombatThreat(200) == reservationThreat,
    "first survivor sees an unclaimed ordinary threat")
first.reservations.threats[reservationThreat] = { first = true }
assert(second:selectCombatThreat(200) == nil,
    "ordinary non-immediate threat is not needlessly dog-piled")

weapon = meleeWeapon(10, 1.4, 6)
health, endurance, bodyParts = 100, 0.8, {}
zombies = {
    zombieAt(4, 0, nil),
    zombieAt(-4, 1, nil),
    zombieAt(1, 5, nil),
}
local capable = controller("capable")
local shouldFlee, capableRisk = capable:assessFlee()
assert(not shouldFlee and capableRisk.reason == nil,
    "a healthy armed survivor keeps a small non-targeting encounter")
zombies = {
    zombieAt(1, 0, character),
    zombieAt(-1, 0, character),
    zombieAt(0, 1, nil),
    zombieAt(0, -1, nil),
}
shouldFlee, capableRisk = capable:assessFlee()
assert(shouldFlee and capableRisk.reason == "outnumbered",
    "overwhelming immediate attackers with a lane admit retreat")

health = 20
zombies = { zombieAt(2, 0, character) }
shouldFlee, capableRisk = capable:assessFlee()
assert(shouldFlee and capableRisk.reason == "critical_health",
    "critical health and an immediate attacker admit retreat")

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
assert(shouldFlee and capableRisk.reason == "injured",
    "bleeding/severe injury lowers the retreat threshold")

health, endurance, bodyParts = 100, 0.12, {}
weapon = nil
zombies = {
    zombieAt(2, 0, character),
    zombieAt(-2, 0, character),
}
shouldFlee, capableRisk = capable:assessFlee()
assert(shouldFlee and capableRisk.reason == "exhausted",
    "exhaustion lowers the retreat threshold")

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
assert(isolatedFlee and not supportedFlee,
    "nearby allies raise the threshold for the same immediate crowd")

zombies = {
    zombieAt(2, 0, nil),
    zombieAt(-2, 0, nil),
    zombieAt(0, 2, nil),
    zombieAt(0, -2, nil),
}
local flee = controller("flee")
assert(flee:findFleeTarget(300) ~= nil, "overwhelming pressure selects a checked escape target")
assert(not flee:retreatIsSafelyClear(false, { nearestDistanceSquared = 100 }, 300)
    and flee:retreatIsSafelyClear(false, { nearestDistanceSquared = 100 }, 301),
    "retreat requires two safe scans before returning to normal decisions")

local surrounding = zombies
blockedEdge = function() return true end
assert(controller("wall"):findFleeTarget(310) == nil,
    "blocked lanes never fabricate an escape target")
blockedEdge = function() return false end
blockedEdge = function(_, b)
    return not (b:getY() == 0 and (b:getX() == 0 or b:getX() == 1))
end
zombies = { zombieAt(1, 0, character) }
local trapped = controller("trapped")
trapped.state, trapped.companionOrder = "IDLE", "follow"
trapped.bridge = {
    beginNpcLiveCombat = function() return "COMBAT_STARTED" end,
    resetNpcCombat = function() end,
}
assert(trapped:findFleeTarget(315) == nil, "blocked escape lanes reject retreat")
assert(trapped:beginFlee(315, { health = 100, endurance = .8 }) == false,
    "retreat admission never fabricates a route through blocked lanes")
assert(trapped.companionOrder == "follow", "trapped defense retains companion intent")
local passivePanic = controller("passive-panic")
passivePanic.companionOrder = "follow"
passivePanic.companionOwnerId = "player"
passivePanic.companionCombatStance = "passive"
assert(passivePanic:findEmergencyFleeTarget(316) ~= nil,
    "a non-combat fallback can locate a short safer tile")
assert(passivePanic:beginFlee(316, { health = 100, endurance = .8 }) == false,
    "a direct companion owner preserves its durable order instead of autonomous panic movement")
blockedEdge = function() return false end
zombies = surrounding

blockedEdge = function() return true end
local fencedZombie = zombieAt(1, 0, character)
assert(controller("fence-wait"):evaluateCombatThreat(fencedZombie, 320) == nil,
    "an immediately separating fence or wall prevents a zombie pursuit loop")
blockedEdge = function() return false end

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
}) and flee.state == "FLEEING" and moveCalls == 1 and cancelCalls > 0,
    "admitted retreat issues one native movement request while preserving intent")
assert(flee.companionOrder == "follow",
    "retreat does not erase the durable follow intent")

local postRetreat = zombieAt(4, 0, nil)
local unarmed = controller("unarmed")
unarmed.bridge = {
    beginNpcLiveCombat = function() return "COMBAT_FAILED NO_EQUIPPED_WEAPON" end,
    resetNpcCombat = function() end,
    cancelNpcMove = function() return true end,
    moveNpcWithPace = function() return "MOVE_STARTED" end,
}
weapon = nil
zombies = { postRetreat }
local immediateUnarmed = controller("immediate-unarmed")
zombies = { zombieAt(1, 0, nil) }
local earlyFlee = immediateUnarmed:assessFlee()
assert(not earlyFlee,
    "a lone unarmed survivor stays in the native shove decision instead of fleeing")
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
local unarmedFlee = unarmed:assessFlee()
assert(not unarmedFlee,
    "unarmed actor does not enter a flee loop after a transient combat bridge rejection")
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
}), "group leader admits a shared native retreat route")
assert(groupSecond:beginFlee(500, {
    reason = "outnumbered", zombies = 6, allies = 2,
    health = 100, endurance = 0.8,
}) and groupTargets["group-first"] ~= nil and groupTargets["group-second"] ~= nil,
    "group members receive the existing shared retreat plan through native movement")

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
    assert(decisions == 1 and finished == 1 and combat.combatTarget == nil,
        "invalid target cleanup runs before firearm state can preserve a stale reload/aim")
    assert(combat.companionOrder == "hold", "combat cleanup preserves durable Hold")
    mode = "reloading"
    combat.state, combat.combatTarget = "COMBAT", zombieAt(1, 0, character)
    combat:tick(combat.nextThreatScan)
    assert(decisions == 2 and finished == 2 and combat.combatTarget == nil,
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

-- Input list order must never hide an attacker behind three quiet zombies.
fleeingEnabled = true
survivorSquare = square(0, 0, 0)
local cautious = controller("cautious")
zombies = { zombieAt(4, 0, nil), zombieAt(4, 1, nil), zombieAt(4, -1, nil),
    zombieAt(1, 0, character) }
assert(not Controller.shouldRemainStealthy(cautious),
    "a later active attacker must release stealth even after three quiet zombies")
zombies = {}
health, endurance, weapon = 20, 0.05, nil
bodyParts = { wound({bleeding = true, deep = true}), wound({bleeding = true, deep = true}) }
assert(not cautious:assessFlee(), "injury without a threat requires care, not endless fleeing")
local pursuing = zombieAt(40, 0, character)
cautious.combatTarget = pursuing
assert(cautious:shouldDropCombatTarget(2000),
    "stale targeting cannot drag self-defense into an unlimited chase")
pursuing:setCurrentSquare(square(2, 0, 0))
assert(not cautious:shouldDropCombatTarget(2001), "nearby active attacker still permits self-defense")
local targetLookups = 0
local far = zombieAt(100, 0, character)
far.getTarget = function() targetLookups = targetLookups + 1; return character end
assert(cautious:evaluateCombatThreat(far, 2002) == nil and targetLookups == 0,
    "distant zombies skip social and target analysis outside all acquisition radii")
print("Threat-order, injury and chase boundaries PASS")

health, endurance, bodyParts, weapon = 100, 0.8, {}, meleeWeapon(10, 1.2, 4)
local indoors = controller("indoors")
indoors.currentTicks = 3000
zombies = { zombieAt(2, 0, nil), zombieAt(-2, 0, nil), zombieAt(0, 2, nil) }
for _, value in ipairs(zombies) do value.visible = false end
assert(not indoors:assessFlee(), "unseen threats do not admit a retreat")
zombies[1]:setTarget(character)
assert(not indoors:assessFlee(), "a healthy equipped survivor holds against one visible attacker")
zombies[1]:setTarget(nil)
zombies[1].visible = true
assert(not indoors:assessFlee(), "one visible non-targeting zombie does not trigger a retreat")
zombies[1].visible = false
indoors.currentTicks = 3001
assert(not indoors:assessFlee(), "visibility loss clears the admission pressure")
indoors.currentTicks = 3121
assert(not indoors:assessFlee(), "no stale threat observation can trigger a later retreat")
print("Retreat perception consistency PASS visibility=true targeting=true")

-- Survivor/player hostility must enter the same risk and escape model as zombies.
zombies = {}
local hostile = true
local enemy = zombieAt(2, 0, nil)
local threatened = controller("threatened")
threatened.currentTicks = 4000
runtimeIds[enemy] = "enemy"
KnoxSurvivorRuntime.activeIds = function() return {"enemy"} end
KnoxSurvivorRuntime.getCharacter = function(id) return id == "enemy" and enemy or nil end
KnoxPersistence.areSurvivorsHostile = function(a, b)
    return hostile and a == "threatened" and b == "enemy"
end
local retreat, risk = threatened:assessFlee()
assert(not retreat, "one hostile human does not force a healthy survivor to retreat")
assert(threatened:findFleeTarget(4000) ~= nil,
    "a safe route may exist without changing the retreat-admission decision")
hostile = false
assert(not threatened:assessFlee(), "non-hostile survivors do not add retreat pressure")
hostile = true
enemy.visible = false
threatened.perceivedThreats = {}
assert(not threatened:assessFlee(), "an unseen hostile survivor does not force a retreat")
enemy.visible = true
zombies = { zombieAt(4, 0, nil), zombieAt(4, 1, nil), zombieAt(4, -1, nil) }
assert(not Controller.shouldRemainStealthy(threatened),
    "quiet zombie crowd cannot suppress a visible human threat")
zombies = {}
KnoxSurvivorRuntime.activeIds = function() return {} end
runtimeIds[enemy], player = nil, enemy
KnoxPersistence.ensurePlayerId = function() return "hostile-player" end
KnoxPersistence.isSurvivorHostileToPlayer = function() return true end
KnoxSettings.allowSurvivorPlayerCombat = function() return false end
assert(not threatened:assessFlee(), "one hostile player does not force a healthy survivor to retreat")
KnoxSettings.allowSurvivorPlayerCombat = function() return true end
assert(not threatened:assessFlee(), "combat policy changes do not invent retreat pressure")
print("Human retreat and faction peace PASS admission_preserved=true")

-- A working resident must not abandon home to clear the neighborhood.
player = nil
KnoxSurvivorRuntime.activeIds = function() return {} end
health, endurance, bodyParts, weapon = 100, 0.8, {}, meleeWeapon(10, 1.2, 4)
survivorSquare = square(0, 0, 0)
local workerDuty = controller("worker-duty")
workerDuty.base = {territory = {minX = -10, minY = -10, maxX = 10, maxY = 10, allFloors = true}}
workerDuty.baseTask = {type = "haul_corpse", target = {}}
local distraction = zombieAt(8, 0, nil)
assert(workerDuty:evaluateCombatThreat(distraction, 5000) == nil,
    "a visible idle zombie does not interrupt a corpse hauler")
distraction:setTarget(character)
assert(workerDuty:evaluateCombatThreat(distraction, 5000) == nil,
    "a distant approaching zombie does not make a worker abandon the task early")
distraction:setCurrentSquare(square(2, 0, 0))
assert(workerDuty:evaluateCombatThreat(distraction, 5000) ~= nil,
    "nearby attacks still interrupt a base job")
workerDuty.baseTask = {type = "guard", target = {x1=0, y1=0, x2=0, y2=0, z=0}}
distraction:setCurrentSquare(square(8, 0, 0))
assert(workerDuty:evaluateCombatThreat(distraction, 5000) == nil,
    "guard post cannot turn a stale target into a neighborhood pursuit")
distraction:setCurrentSquare(square(2, 0, 0))
assert(workerDuty:evaluateCombatThreat(distraction, 5000) ~= nil, "guard retains immediate defense")
workerDuty.baseTask = {type="patrol", target={x1=-5,y1=-5,x2=5,y2=5,z=0}}
survivorSquare = square(5, 0, 0)
distraction:setCurrentSquare(square(8, 0, 0))
assert(workerDuty:evaluateCombatThreat(distraction, 5000) == nil,
    "patrol pursuit stops at the selected area")
distraction:setCurrentSquare(square(6, 0, 0))
assert(workerDuty:evaluateCombatThreat(distraction, 5000) ~= nil,
    "an attacker in reach can still be defended against at the boundary")
workerDuty.baseTask = nil
survivorSquare = square(0, 0, 0)
distraction:setCurrentSquare(square(8, 0, 0))
distraction:setTarget(nil)
assert(workerDuty:evaluateCombatThreat(distraction, 5000) == nil,
    "idle residents do not initiate long hunts within their yard")
print("Base duty combat boundaries PASS work=true guard=true patrol=true immediate_defense=true")

local carriedBody = zombieAt(1,0,character)
carriedBody.isReanimatedForGrappleOnly = function() return true end
local hauling = controller("hauling")
hauling.currentTicks = 6000
hauling.baseTask = {type="haul_corpse"}
zombies = {carriedBody}
health, endurance = 20, 0.05
assert(hauling:evaluateCombatThreat(carriedBody,6000)==nil, "carried corpse proxy is never a combat target")
assert(not hauling:assessFlee(), "carried corpse proxy does not scare an injured hauler")
hauling.perceivedThreats = {[carriedBody]={lastSeen=6000}}
assert(hauling:selectCombatThreat(6001)==nil, "old perception cannot resurrect a corpse proxy as a threat")
carriedBody.isReanimatedForGrappleOnly = function() return false end
assert(hauling:evaluateCombatThreat(carriedBody,6002) ~= nil and hauling:assessFlee(),
    "a real reanimated zombie remains a threat and admits an injured survivor to retreat")
print("Corpse combat classification PASS proxy_excluded=true actual_reanimation_preserved=true")

-- Routine travel perceives danger without treating every sighting as an order to hunt.
local traveler=controller("traveler")
local streetZombie=zombieAt(9,0,nil)
zombies={streetZombie}
health,endurance=100,0.8
assert(traveler:evaluateCombatThreat(streetZombie,7000)==nil and traveler.perceivedThreats[streetZombie]~=nil,
    "distant visible zombie is remembered for caution but not selected for a fight")
assert(Controller.shouldRemainStealthy(traveler), "one quiet visible zombie can be passed cautiously")
streetZombie:setCurrentSquare(square(2,0,0))
assert(not Controller.shouldRemainStealthy(traveler)
    and traveler:evaluateCombatThreat(streetZombie,7001)~=nil, "contact danger immediately releases stealth")
streetZombie:setCurrentSquare(square(8,0,0));streetZombie:setTarget(character)
assert(traveler:evaluateCombatThreat(streetZombie,7002)~=nil, "active nearby attacks still trigger defense")
streetZombie:setCurrentSquare(square(9,0,0))
traveler.combatTarget=streetZombie
assert(traveler:shouldDropCombatTarget(7003), "a stale attack target cannot extend pursuit across the neighborhood")
streetZombie:setTarget(nil);streetZombie:setCurrentSquare(square(5,0,0))
assert(not traveler:shouldDropCombatTarget(7004), "an existing close fight has a small continuation margin")
traveler.combatTarget=nil
KnoxSettings.zombieEngagementDistance=function() return 2 end
streetZombie:setCurrentSquare(square(3,0,0))
assert(traveler:evaluateCombatThreat(streetZombie,7005)==nil, "sandbox distance customizes automatic engagement")
KnoxSettings.zombieEngagementDistance=nil
traveler.companionOrder,traveler.companionCombatStance="follow","aggressive"
assert(not Controller.shouldRemainStealthy(traveler), "explicit aggressive orders are not suppressed by quiet travel")
traveler.companionOrder=nil
carriedBody.isReanimatedForGrappleOnly=function() return true end
traveler.combatTarget=carriedBody
assert(traveler:shouldDropCombatTarget(7006), "an already-targeted corpse proxy is released too")
KnoxSettings.cautiousTravel=function() return false end
assert(not Controller.shouldRemainStealthy(traveler), "disabling caution restores the ordinary crowd threshold")
KnoxSettings.cautiousTravel=nil
runtimeIds[enemy]="enemy"
enemy:setCurrentSquare(square(12,0,0));enemy.visible=true
assert(threatened:evaluateCombatThreat(enemy,7007)~=nil, "zombie engagement settings do not disable hostile human encounters")
runtimeIds[enemy]=nil
print("Cautious encounter policy PASS sightings=true contact=true pursuit=true customization=true human_combat=true")
