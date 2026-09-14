require "KS_ThreatClassifier"
local function isCorpseProxy(character)
    local threats = rawget(_G, "KnoxThreatClassifier")
    return threats ~= nil and threats.isCorpseProxy(character) or false
end

require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISRestAction"
require "TimedActions/ISSitOnGround"
require "TimedActions/ISSmashWindow"
require "Util/AdjacentFreeTileFinder"
require "KS_SurvivorNeeds"
require "KS_FirearmSupport"
require "KS_SurvivorInventoryActions"
require "KS_Persistence"
require "KS_ActivityFeed"
require "KS_SurvivorDialogue"
require "KS_GroupSupport"
require "KS_SurvivorLooting"
require "KS_EquipmentIntelligence"
require "KS_FactionBaseScouting"
require "KS_FactionSafehouse"
require "KS_BaseManager"
require "KS_BaseTaskBoard"
require "KS_BaseJobs"
require "KS_BaseSupplyPlanner"
require "KS_BaseStorage"
require "KS_BaseRecreation"
require "KS_BaseCooking"
require "KS_OrderSignals"
require "KS_BaseBarricades"
require "KS_BaseFarming"
require "KS_BaseWoodcutting"
require "KS_BaseCorpseHandling"
require "KS_BaseAnimalCare"
require "KS_BaseRepairs"
require "KS_BaseConstruction"
require "KS_CompanionPatrol"
require "KS_AwayTeamExecutor"
require "KS_FactionCamps"
require "KS_SurvivorRuntime"

local Controller = rawget(_G, "KnoxAutonomyController") or {}
_G.KnoxAutonomyController = Controller
Controller.__index = Controller

-- A Lua action may be turning, waiting to start, or between native actions.
-- An empty Java list alone does not mean its transfer/work has finished.
local function hasPendingTimedActions(character)
    if character == nil then return false end
    local actions = character:getCharacterActions()
    if actions ~= nil and not actions:isEmpty() then return true end
    local queues = ISTimedActionQueue ~= nil and ISTimedActionQueue.queues or nil
    local queue = queues ~= nil and queues[character] or nil
    return queue ~= nil and type(queue.queue) == "table" and #queue.queue > 0
end

local function sayDialogue(character, survivorId, event, ticks, cooldown, lines)
    local dialogue = rawget(_G, "KnoxSurvivorDialogue")
    if dialogue == nil then return false end
    if lines ~= nil and dialogue.sayLines ~= nil then
        return dialogue.sayLines(character, survivorId, event, lines, ticks, cooldown)
    end
    if dialogue.say ~= nil then
        return dialogue.say(character, survivorId, event, ticks, cooldown)
    end
    return false
end

-- A task can enter the loaded controller from an older save, a restored claim,
-- or a direct developer/UI call. Persistence normally migrates these records,
-- but the controller is the final execution boundary and must never dispatch
-- legacy vocabulary to the concrete executors below. Normalize the existing
-- task in place so every downstream branch continues to use one authoritative
-- task object and no second task manager is needed.
local function canonicalBaseTask(task)
    if type(task) ~= "table" then return task end
    local catalog = rawget(_G, "KnoxOrderCatalog")
    if catalog ~= nil and catalog.normalizeTaskType ~= nil then
        local normalized = catalog.normalizeTaskType(task.type)
        if normalized ~= nil then task.type = normalized end
    end
    return task
end

local THINK_MIN_TICKS = 30
local THINK_JITTER_TICKS = 45
local THREAT_SCAN_TICKS = 15
local COMBAT_RETARGET_COOLDOWN_TICKS = 90
local COMBAT_RETARGET_SCORE_MARGIN = 24
local COMBAT_EMERGENCY_SCORE_MARGIN = 60
local THREAT_IMMEDIATE_RADIUS = 3.5
local THREAT_VISIBLE_RADIUS = 16
local THREAT_MEMORY_TICKS = 120
local THREAT_MEMORY_SCORE_PENALTY = 48
local THREAT_SELF_TARGET_RADIUS = 20
local THREAT_GROUP_ASSIST_RADIUS = 10
local GROUP_COMBAT_LEASH_RADIUS = 12
local COMBAT_DISENGAGE_RADIUS = 18
local THREAT_MAX_DISTANCE_SQUARED = math.max(THREAT_VISIBLE_RADIUS,
    THREAT_SELF_TARGET_RADIUS, THREAT_GROUP_ASSIST_RADIUS, COMBAT_DISENGAGE_RADIUS) ^ 2
local THREAT_FAILURE_COOLDOWN_TICKS = 900
local SUPPLY_SCAN_RADIUS = 12
local SUPPLY_RETRY_TICKS = 600
local EXPLORATION_SCAN_RADIUS = 12
local EXPLORATION_RETRY_TICKS = 180
local CONVENIENT_INSPECTION_RADIUS = 2
local LOOT_TRAVEL_COOLDOWN_TICKS = 900
local EMPTY_SEARCH_COOLDOWN_TICKS = 1800
local BLOCKED_AREA_COOLDOWN_TICKS = 3600
local LOCKED_DOOR_MIN_ENDURANCE = 0.40
local ROAM_MIN_RADIUS = 6
local ROAM_MAX_RADIUS = 48
local ROAM_GOAL_COOLDOWN_TICKS = 7200
local ROAM_FAILURE_COOLDOWN_TICKS = 7200
local ROAM_MEMORY_LIMIT = 12
local ROAM_NO_GOAL_RETRY_TICKS = 90
local ROAM_NEEDS_RECHECK_TICKS = 90
local ROAM_DANGER_RADIUS = 6
local ROAM_DANGER_LIMIT = 2
local RECOVERY_RECHECK_TICKS = 180
local RECOVERY_TIMEOUT_TICKS = 900
local SLEEP_RECOVERY_TIMEOUT_TICKS = 36000
local RECOVERY_SEAT_SCAN_RADIUS = 8
local RECOVERY_POSTURE_TIMEOUT_TICKS = 180
local SELF_CARE_RETRY_TICKS = 300
local BASE_AMBIENT_REST_TICKS = 1800
local CAMP_DECISION_TICKS = 180
local CAMP_EXCURSION_COOLDOWN_TICKS = 1800
local CAMP_POSITION_FAILURE_TICKS = 300
local MOVEMENT_TIMEOUT_TICKS = 1500
local ACTION_TIMEOUT_TICKS = 1200
local GROUP_SOFT_LEASH_SQUARED = 100
local GROUP_RETRIEVE_LEASH_SQUARED = 196
local FORMATION_ARRIVAL_TOLERANCE_SQUARED = 0
local GROUP_OBJECTIVE_ASSIST_RADIUS_SQUARED = 64
local GROUP_OBJECTIVE_ASSIST_RETRY_TICKS = 300
local GROUP_OBJECTIVE_ASSIST_COOLDOWN_TICKS = 1800
local GROUP_SUPPORT_RETRY_TICKS = 600
local GROUP_SUPPORT_COOLDOWN_TICKS = 1800
-- Keep a follower committed to its route while a moving leader's slot drifts;
-- replanning after a one-tile adjustment causes visible direction thrashing.
local FORMATION_REPATH_SHIFT_SQUARED = 3
local FORMATION_REFRESH_TICKS = 30
-- Native path requests are expensive and can make a follower oscillate through
-- doorways when its anchor is moving. Hold a route briefly and require a real
-- slot change before replacing it.
local FORMATION_ROUTE_COMMIT_TICKS = 45
local FORMATION_BOTTLENECK_WAIT_TICKS = 90
local FORMATION_FAILURE_COOLDOWN_TICKS = 180
local FORMATION_FAILURE_MAX_COOLDOWN_TICKS = 720
local MOVEMENT_FAILURE_COOLDOWN_TICKS = 180
local MOVEMENT_FAILURE_MAX_COOLDOWN_TICKS = 1440
local ENTRY_SCAN_RADIUS = 16
local FLEE_SCAN_RADIUS = 12
local FLEE_TARGET_DISTANCE = 12
local FLEE_RECHECK_TICKS = 45
local FLEE_PLAN_TICKS = 240
local FLEE_SAFE_CONFIRM_SCANS = 2
local FLEE_CLEAR_DISTANCE_SQUARED = 64
local FLEE_DISENGAGE_TICKS = 600

-- Short-lived, loaded-world coordination only.  This is deliberately not
-- persistence: a flee route is a reaction to the zombies visible right now,
-- not a mission or a world-state change that should survive save/load.
local fleePlans = rawget(_G, "KnoxFleePlans") or {}
_G.KnoxFleePlans = fleePlans

-- Supply-search leases coordinate loaded controllers only. The survivor duty's
-- `activeSupplyRun` is the durable owner; container reservations, lease expiry,
-- and which loaded controller currently searches must never enter base ModData.
local baseSupplyClaimsByBase = {}

local function supplyClaimsFor(baseId)
    local key = tostring(baseId or "")
    if key == "" then return nil end
    local claims = baseSupplyClaimsByBase[key]
    if type(claims) ~= "table" then
        claims = {}
        baseSupplyClaimsByBase[key] = claims
    end
    return claims
end

local function restoreSupplyClaim(baseId, kind, survivorId)
    if kind == nil or survivorId == nil then return false end
    local claims = supplyClaimsFor(baseId)
    if claims == nil then return false end
    local now = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    local current = claims[kind]
    if type(current) ~= "table" or current.survivorId == survivorId
        or (tonumber(current.untilHours) or 0) <= now then
        claims[kind] = { survivorId = survivorId, untilHours = now + 1.5 }
        return true
    end
    return false
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function navigationDistanceSquared(first, second)
    if first == nil or second == nil or first:getZ() ~= second:getZ() then
        return math.huge
    end
    return distanceSquared(first, second)
end

local function travelPaceFor(distance, sameBuilding, context)
    local settings = rawget(_G, "KnoxSettings")
    if settings == nil or settings.cautiousTravel == nil or settings.cautiousTravel() then
        return "cautious"
    end
    if sameBuilding or distance == math.huge then
        return "walk"
    end
    local thresholds = {
        urgent = 8,
        directed = 12,
        return_home = 12,
        travel = 14,
    }
    local threshold = thresholds[tostring(context or "")]
    if threshold ~= nil and distance >= threshold * threshold then
        -- Build 42 exposes walk/run/sprint, not a separate jog state. A long
        -- ordinary route therefore requests native run, which reads as a jog;
        -- the Java locomotion policy drops it back to walking near arrival or
        -- when endurance, fatigue, or health make running inappropriate.
        return "run"
    end
    return "walk"
end

local function moveWithTravelPace(bridge, id, character, target, context)
    local current = character ~= nil and character:getCurrentSquare() or nil
    local targetSquare = target
    local distance = navigationDistanceSquared(current, targetSquare)
    local sameBuilding = false
    if current ~= nil and targetSquare ~= nil then
        local ok, currentBuilding, targetBuilding = pcall(function()
            return current:getBuilding(), targetSquare:getBuilding()
        end)
        sameBuilding = ok and currentBuilding ~= nil and currentBuilding == targetBuilding
    end
    local pace = travelPaceFor(distance, sameBuilding, context)
    if bridge.moveNpcWithPace ~= nil then
        return bridge:moveNpcWithPace(id, target, pace), pace
    end
    return bridge:moveNpc(id, target), pace
end

function Controller.travelPaceFor(distance, sameBuilding, context)
    return travelPaceFor(distance, sameBuilding, context)
end

local function nativeTraversalBusy(character)
    if character == nil then
        return false
    end
    local ok, stateName, actionName = pcall(function()
        return tostring(character:getCurrentStateName() or ""),
            tostring(character:getCurrentActionContextStateName() or "")
    end)
    if not ok then
        return false
    end
    local state = string.lower(stateName .. " " .. actionName)
    return string.find(state, "climb", 1, true) ~= nil
        or string.find(state, "vault", 1, true) ~= nil
        or string.find(state, "openwindow", 1, true) ~= nil
        or string.find(state, "smashwindow", 1, true) ~= nil
end

local function combatApproachSquare(character, target)
    local current = character ~= nil and character:getCurrentSquare() or nil
    local targetSquare = target ~= nil and target:getCurrentSquare() or nil
    local cell = getCell()
    if current == nil or targetSquare == nil or cell == nil then
        return nil
    end
    local best, bestDistance = nil, math.huge
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local square = cell:getGridSquare(
                    targetSquare:getX() + dx,
                    targetSquare:getY() + dy,
                    targetSquare:getZ()
                )
                if square ~= nil and (square == current or square:canStand()) then
                    local distance = navigationDistanceSquared(current, square)
                    if distance < bestDistance then
                        best = square
                        bestDistance = distance
                    end
                end
            end
        end
    end
    return best or AdjacentFreeTileFinder.Find(targetSquare, character)
end

function Controller.isNativeTraversalBusy(character)
    return nativeTraversalBusy(character)
end

function Controller.combatApproachSquare(character, target)
    return combatApproachSquare(character, target)
end

local function directionComponent(value)
    if value > 0.35 then
        return 1
    end
    if value < -0.35 then
        return -1
    end
    return 0
end

local function findFormationTarget(anchor, follower, slotIndex, survivorId)
    local anchorSquare = anchor ~= nil and anchor:getCurrentSquare() or nil
    local followerSquare = follower ~= nil and follower:getCurrentSquare() or nil
    local cell = getCell()
    if anchorSquare == nil or followerSquare == nil or cell == nil then
        return nil
    end

    local forwardX = directionComponent(anchor:getForwardDirectionX())
    local forwardY = directionComponent(anchor:getForwardDirectionY())
    if forwardX == 0 and forwardY == 0 then
        forwardY = 1
    end
    local slot = math.max(1, tonumber(slotIndex) or 1)
    local row = math.floor((slot - 1) / 2) + 1
    local side = slot % 2 == 1 and -1 or 1
    local spacing = KnoxSettings ~= nil and KnoxSettings.followerSpacing ~= nil
        and KnoxSettings.followerSpacing() or 1
    local formation = KnoxSettings ~= nil and KnoxSettings.followerFormation ~= nil
        and KnoxSettings.followerFormation() or "paired"
    local duty = survivorId ~= nil and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(survivorId) or nil
    if duty ~= nil and duty.mode == "companion" then
        if duty.followerFormation == "paired" or duty.followerFormation == "single_file" then
            formation = duty.followerFormation
        end
        if duty.followerSpacing == 1 or duty.followerSpacing == 2 or duty.followerSpacing == 3 then
            spacing = duty.followerSpacing
        end
    end
    if formation == "single_file" then
        row, side = slot, 0
    end
    local lateralX = -forwardY
    local lateralY = forwardX
    local target = cell:getGridSquare(
        anchorSquare:getX() + (-forwardX * row + lateralX * side) * spacing,
        anchorSquare:getY() + (-forwardY * row + lateralY * side) * spacing,
        anchorSquare:getZ()
    )
    if target ~= nil and target ~= anchorSquare
        and (target == followerSquare or target:canStand()) then
        return target
    end
    local fallback = AdjacentFreeTileFinder.Find(anchorSquare, follower)
    if fallback ~= nil and (fallback:getX() ~= anchorSquare:getX()
        or fallback:getY() ~= anchorSquare:getY()
        or fallback:getZ() ~= anchorSquare:getZ()) then
        return fallback
    end
    return nil
end

local function formationPace(anchor, follower)
    if anchor == nil or follower == nil
        or anchor:getCurrentSquare() == nil or follower:getCurrentSquare() == nil then
        return "normal"
    end
    local distance = navigationDistanceSquared(
        anchor:getCurrentSquare(), follower:getCurrentSquare()
    )
    local ok, sneaking = pcall(function() return anchor:isSneaking() end)
    if ok and sneaking == true then return "sneak" end
    -- Keep ordinary formation walking calm, but let a follower close a real gap
    -- instead of asking the engine to walk one tile at a time behind a running anchor.
    if distance >= 144 then
        return "sprint"
    end
    if distance >= 25 then
        return "run"
    end
    return "normal"
end

local function moveWithFormationPace(bridge, id, target, anchor, follower)
    local pace = formationPace(anchor, follower)
    return bridge:moveNpcWithPace(
        id,
        target,
        pace
    ), pace
end

local function formationRefreshDelay(slot)
    -- Followers already receive different spatial slots. A small, deterministic
    -- time offset also keeps a tight group from refreshing into the same doorway
    -- or window edge on one controller tick. It is spacing, not a new formation.
    return ((math.max(1, tonumber(slot) or 1) - 1) % 3) * 4
end

local function reservedByOther(reservations, kind, value, id)
    local owner = reservations[kind][value]
    return owner ~= nil and owner ~= id
end

local function reserve(reservations, kind, value, id)
    if value == nil or reservedByOther(reservations, kind, value, id) then
        return false
    end
    reservations[kind][value] = id
    return true
end

local function release(reservations, kind, value, id)
    if value ~= nil and reservations[kind][value] == id then
        reservations[kind][value] = nil
    end
end

local function ambientSpotKey(square)
    if square == nil or square.getX == nil or square.getY == nil then
        return nil
    end
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":"
        .. tostring(square.getZ ~= nil and square:getZ() or 0)
end

local function threatUnavailable(self, zombie, ticks)
    if self.unarmedRejectedTarget == zombie and self.unarmedRetryUntil ~= nil
        and self.character:getPrimaryHandItem() ~= self.rejectedCombatItem then
        self.failedThreats[zombie] = nil
        return false
    end
    local unavailableUntil = self.failedThreats[zombie]
    if unavailableUntil ~= nil and unavailableUntil <= ticks then
        self.failedThreats[zombie] = nil
        return false
    end
    return unavailableUntil ~= nil
end

local function threatReservationCount(reservations, zombie, excludeId)
    local owners = reservations.threats[zombie]
    if type(owners) ~= "table" then
        return owners ~= nil and owners ~= excludeId and 1 or 0
    end
    local count = 0
    for id in pairs(owners) do
        if id ~= excludeId then
            count = count + 1
        end
    end
    return count
end

local function threatAttackerLimit(reason)
    if reason == "active_target" then
        return 3
    end
    if reason == "group_target" or reason == "immediate"
        or reason == "player_target" then
        return 2
    end
    return 1
end

local function reserveThreat(reservations, zombie, id, limit)
    if zombie == nil or threatReservationCount(reservations, zombie, id)
        >= math.max(1, tonumber(limit) or 1) then
        return false
    end
    local owners = reservations.threats[zombie]
    if type(owners) ~= "table" then
        owners = {}
        reservations.threats[zombie] = owners
    end
    owners[id] = true
    return true
end

local function releaseThreat(reservations, zombie, id)
    local owners = zombie ~= nil and reservations.threats[zombie] or nil
    if type(owners) ~= "table" then
        if owners == id then
            reservations.threats[zombie] = nil
        end
        return
    end
    owners[id] = nil
    local occupied = false
    for _ in pairs(owners) do
        occupied = true
        break
    end
    if not occupied then
        reservations.threats[zombie] = nil
    end
end

local function targetsGroupMember(self, target)
    if target == nil then
        return false
    end
    if target == self.character or target == self.groupLeader
        or target == self.companionTarget then
        return true
    end
    for _, member in ipairs(self.groupMembers or {}) do
        if target == member then
            return true
        end
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local targetId = runtime ~= nil and runtime.idForCharacter ~= nil
        and runtime.idForCharacter(target)
        or nil
    if targetId ~= nil and KnoxPersistence.areSurvivorsAllied ~= nil then
        return KnoxPersistence.areSurvivorsAllied(self.id, targetId)
    end
    return false
end

local function targetsAnyPlayer(target, distance)
    if target == nil then
        return false
    end
    local maxDist2 = THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS
    if distance > maxDist2 then
        return false
    end
    local count = getNumActivePlayers and getNumActivePlayers() or 1
    for pIdx = 0, math.max(0, tonumber(count) or 1) - 1 do
        local p = getSpecificPlayer(pIdx)
        if p ~= nil and target == p then
            return true
        end
    end
    return false
end

local function targetOf(character)
    if character == nil or character.getTarget == nil then return nil end
    local ok, target = pcall(function() return character:getTarget() end)
    return ok and target or nil
end

local function allowSurvivorPlayerCombat()
    local settings = rawget(_G, "KnoxSettings")
    return settings == nil or settings.allowSurvivorPlayerCombat == nil
        or settings.allowSurvivorPlayerCombat()
end

local function hostileHuman(self, character, knownSurvivorId)
    if character == nil or character == self.character then return false end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local survivorId = knownSurvivorId or (runtime ~= nil and runtime.idForCharacter ~= nil
        and runtime.idForCharacter(character) or nil)
    if survivorId ~= nil then
        return KnoxPersistence.areSurvivorsHostile ~= nil
            and KnoxPersistence.areSurvivorsHostile(self.id, survivorId) or false
    end
    if not allowSurvivorPlayerCombat() then return false end
    local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, count - 1) do
        local player = getSpecificPlayer(playerNum)
        if player ~= nil and player == character then
            local playerId = KnoxPersistence.ensurePlayerId ~= nil
                and KnoxPersistence.ensurePlayerId(player) or nil
            return playerId ~= nil and KnoxPersistence.isSurvivorHostileToPlayer ~= nil
                and KnoxPersistence.isSurvivorHostileToPlayer(self.id, playerId) or false
        end
    end
    return false
end

local function combatAnchor(self)
    if self.companionOrder ~= nil then
        return self.companionTarget
    end
    return self.groupLeader
end

local function withinDutyCombatLeash(self, threat)
    local current, other = self.character:getCurrentSquare(), threat:getCurrentSquare()
    if current == nil or other == nil or current:getZ() ~= other:getZ() then return false end
    local distance = distanceSquared(current, other)
    -- Contact defense remains possible even while returning to a displaced post.
    if distance <= 4 then return true end
    local task = self.baseTask
    local directive = self.companionDirective
    local kind, area
    if directive ~= nil and (directive.kind == "guard" or directive.kind == "patrol_area") then
        kind, area = directive.kind, directive
    elseif task ~= nil and (task.type == "guard" or task.type == "patrol") then
        kind, area = task.type, task.target
    elseif self.base ~= nil then
        kind, area = "resident", self.base.territory or self.base.home
    end
    if kind == nil and task == nil then return true end
    if area ~= nil then
        local minX, minY = tonumber(area.minX or area.x1 or area.x), tonumber(area.minY or area.y1 or area.y)
        local maxX, maxY = tonumber(area.maxX or area.x2) or minX, tonumber(area.maxY or area.y2) or minY
        if kind == "guard" and minX ~= nil and minY ~= nil then
            local patrol = rawget(_G, "KnoxCompanionPatrol")
            local post = task ~= nil and patrol ~= nil and patrol.guardPost ~= nil
                and patrol.guardPost(area, task.id or task.claimedBy) or nil
            local x = post ~= nil and post.x or math.floor((minX + maxX) / 2)
            local y = post ~= nil and post.y or math.floor((minY + maxY) / 2)
            minX, maxX, minY, maxY = x - 4, x + 4, y - 4, y + 4
        end
        if minX ~= nil and minY ~= nil and (other:getX() < math.min(minX, maxX)
            or other:getX() > math.max(minX, maxX) or other:getY() < math.min(minY, maxY)
            or other:getY() > math.max(minY, maxY)) then return false end
        if area.allFloors ~= true and other:getZ() ~= (tonumber(area.z) or 0) then return false end
    end
    local target = targetOf(threat)
    local attackingDuty = target == self.character or targetsGroupMember(self, target)
    -- A worker seeing trouble is not an order to clear the surrounding streets.
    -- Nearby attacks can interrupt; the durable job/post survives that interruption.
    return attackingDuty and distance <= 16
end

local function withinCombatRoleLeash(self, threat)
    if threat == nil or not withinDutyCombatLeash(self, threat) then
        return false
    end
    local target = targetOf(threat)
    if target == self.character then
        return true
    end
    if targetsGroupMember(self, target) then
        local survivorSquare = self.character:getCurrentSquare()
        local threatSquare = threat:getCurrentSquare()
        if survivorSquare ~= nil and threatSquare ~= nil
            and navigationDistanceSquared(survivorSquare, threatSquare)
                <= THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS then
            return true
        end
    end
    local anchor = combatAnchor(self)
    if anchor == nil then
        return true
    end
    local anchorSquare = anchor:getCurrentSquare()
    local targetSquare = threat:getCurrentSquare()
    return anchorSquare ~= nil and targetSquare ~= nil
        and navigationDistanceSquared(anchorSquare, targetSquare)
            <= GROUP_COMBAT_LEASH_RADIUS * GROUP_COMBAT_LEASH_RADIUS
end

local function threatReasonAndBonus(
    targetingSelf, targetingGroup, targetingPlayer, immediate
)
    if targetingSelf then
        return "active_target", immediate and 240 or 160, 5
    end
    if targetingGroup then
        return "group_target", immediate and 190 or 120, 4
    end
    if immediate then
        return "immediate", 90, 3
    end
    if targetingPlayer then
        return "player_target", 55, 2
    end
    return "visible", 0, 1
end

local function withinZombieEngagement(self, zombie, distance, targetingSelf, targetingGroup)
    if self.companionOrder ~= nil and self.companionCombatStance == "aggressive" then return true end
    local settings = rawget(_G, "KnoxSettings")
    local radius = settings ~= nil and settings.zombieEngagementDistance ~= nil
        and settings.zombieEngagementDistance() or 4
    if targetingSelf or targetingGroup then radius = math.max(radius, 8) end
    if zombie == self.combatTarget then radius = math.max(radius, 6) end
    return distance <= radius * radius
end

local function evaluateThreat(self, zombie, ticks)
    local square = self.character:getCurrentSquare()
    local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
    local distance = square ~= nil and zombieSquare ~= nil
        and distanceSquared(square, zombieSquare) or math.huge
    if square == nil or zombie == nil or zombie:isDead() or isCorpseProxy(zombie) or zombieSquare == nil
        or zombieSquare:getZ() ~= square:getZ()
        or distance > THREAT_MAX_DISTANCE_SQUARED
        or threatUnavailable(self, zombie, ticks)
        or not withinCombatRoleLeash(self, zombie) then
        if self.perceivedThreats ~= nil and zombie ~= nil then
            self.perceivedThreats[zombie] = nil
        end
        return nil
    end
    -- Escaping a crowd must not immediately become a fresh five-tile chase.
    -- Nearby self-defense remains available, but distant acquisition waits.
    if ticks < (self.combatDisengageUntil or 0) and distance > 3.0625 then
        return nil
    end
    local humanThreat = hostileHuman(self, zombie)
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local isHuman = humanThreat or (runtime ~= nil and runtime.idForCharacter ~= nil
        and runtime.idForCharacter(zombie) ~= nil)
    for playerNum = 0, math.max(0, (getNumActivePlayers ~= nil and getNumActivePlayers() or 1) - 1) do
        if getSpecificPlayer(playerNum) == zombie then isHuman = true; break end
    end
    if isHuman and not humanThreat then return nil end
    local target = targetOf(zombie)
    local targetingSelf = target == self.character
        and distance <= THREAT_SELF_TARGET_RADIUS * THREAT_SELF_TARGET_RADIUS
    local targetingGroup = target ~= self.character
        and targetsGroupMember(self, target)
        and distance <= THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS
    local targetingPlayer = targetsAnyPlayer(target, distance)
    local immediate = distance <= THREAT_IMMEDIATE_RADIUS * THREAT_IMMEDIATE_RADIUS
    local visible = false
    if distance <= THREAT_VISIBLE_RADIUS * THREAT_VISIBLE_RADIUS then
        local success, result = pcall(function()
            return self.character:CanSee(zombie)
        end)
        visible = success and result == true
    end
    self.perceivedThreats = self.perceivedThreats
        or setmetatable({}, { __mode = "k" })
    local perceived = visible or targetingSelf or targetingGroup or targetingPlayer
    local remembered = false
    if perceived then
        self.perceivedThreats[zombie] = { lastSeen = ticks }
    else
        local memory = self.perceivedThreats[zombie]
        remembered = memory ~= nil
            and ticks - (memory.lastSeen or -THREAT_MEMORY_TICKS - 1)
                <= THREAT_MEMORY_TICKS
            and distance <= COMBAT_DISENGAGE_RADIUS * COMBAT_DISENGAGE_RADIUS
        if not remembered then
            self.perceivedThreats[zombie] = nil
            return nil
        end
    end
    -- Perception is not permission to hunt. Keep sightings for avoidance, while
    -- only nearby danger can interrupt a routine route or start an automatic fight.
    if not isHuman and not withinZombieEngagement(self, zombie, distance, targetingSelf, targetingGroup) then
        return nil
    end
    local reason, bonus, priority
    if remembered then
        reason, bonus, priority = "remembered", -THREAT_MEMORY_SCORE_PENALTY, 0
    else
        reason, bonus, priority = threatReasonAndBonus(
            targetingSelf, targetingGroup, targetingPlayer, immediate and visible
        )
    end
    local onFloor, crawling = false, false
    if zombie.isOnFloor ~= nil then
        local ok, value = pcall(function() return zombie:isOnFloor() end)
        onFloor = ok and value == true
    end
    if zombie.isCrawling ~= nil then
        local ok, value = pcall(function() return zombie:isCrawling() end)
        crawling = ok and value == true
    end
    local downed = onFloor and not crawling
    if downed then
        -- A knocked-down zombie remains a valid target, but it must not hide a
        -- standing attacker that is already reaching the survivor or an ally.
        priority = math.max(0, priority - 2)
    end
    local reservationCount = threatReservationCount(self.reservations, zombie, self.id)
    return {
        reason = reason,
        priority = priority,
        distance = math.sqrt(distance),
        distanceSquared = distance,
        reservationCount = reservationCount,
        attackerLimit = threatAttackerLimit(reason),
        score = distance - bonus + reservationCount * 24 + (downed and 120 or 0)
            + (humanThreat and -35 or 0),
        downed = downed,
        human = humanThreat,
    }
end

local function nearestThreat(self, ticks)
    local cell = getCell()
    if self.character:getCurrentSquare() == nil or cell == nil then
        return nil
    end
    local nearest, nearestAwareness = nil, nil
    local zombies = cell:getZombieList()
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local scenarioOwner = rawget(_G, "KnoxCombatTestScenarios") ~= nil
            and KnoxCombatTestScenarios.preferredNpcId ~= nil
            and KnoxCombatTestScenarios.preferredNpcId(zombie) or nil
        if scenarioOwner == nil or scenarioOwner == self.id then
            local awareness = evaluateThreat(self, zombie, ticks)
            if awareness ~= nil
                and awareness.reservationCount < awareness.attackerLimit
                and (nearestAwareness == nil or awareness.score < nearestAwareness.score) then
                nearest = zombie
                nearestAwareness = awareness
            end
        end
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.activeIds ~= nil and runtime.getCharacter ~= nil then
        for _, otherId in ipairs(runtime.activeIds()) do
            if otherId ~= self.id then
                local human = runtime.getCharacter(otherId)
                local awareness = hostileHuman(self, human) and evaluateThreat(self, human, ticks) or nil
                if awareness ~= nil
                    and awareness.reservationCount < awareness.attackerLimit
                    and (nearestAwareness == nil or awareness.score < nearestAwareness.score) then
                    nearest, nearestAwareness = human, awareness
                end
            end
        end
    end
    if allowSurvivorPlayerCombat() then
        local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
        for playerNum = 0, math.max(0, count - 1) do
            local human = getSpecificPlayer(playerNum)
            local awareness = hostileHuman(self, human) and evaluateThreat(self, human, ticks) or nil
            if awareness ~= nil
                and awareness.reservationCount < awareness.attackerLimit
                and (nearestAwareness == nil or awareness.score < nearestAwareness.score) then
                nearest, nearestAwareness = human, awareness
            end
        end
    end
    self.pendingThreatAwareness = nearestAwareness
    return nearest
end

function Controller:selectCombatThreat(ticks)
    return nearestThreat(self, ticks)
end

local function shouldReplaceCombatTarget(self, candidate, awareness, ticks)
    if candidate == nil or candidate == self.combatTarget then
        return false
    end
    local current = self.combatTarget
    local candidateAwareness = awareness or evaluateThreat(self, candidate, ticks)
    if candidateAwareness == nil then
        return false
    end
    local currentAwareness = current ~= nil and evaluateThreat(self, current, ticks) or nil
    if currentAwareness == nil then
        return true
    end
    local improvement = currentAwareness.score - candidateAwareness.score
    local inCooldown = ticks - (self.lastCombatRetarget
        or -COMBAT_RETARGET_COOLDOWN_TICKS) < COMBAT_RETARGET_COOLDOWN_TICKS
    if inCooldown then
        return candidateAwareness.priority > currentAwareness.priority
            and improvement >= COMBAT_EMERGENCY_SCORE_MARGIN
    end
    return improvement >= COMBAT_RETARGET_SCORE_MARGIN
end

local function shouldDropCombatTarget(self, ticks)
    local target = self.combatTarget
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    local human = target ~= nil and runtime ~= nil and runtime.idForCharacter ~= nil
        and runtime.idForCharacter(target) ~= nil
    for playerNum = 0, math.max(0, (getNumActivePlayers ~= nil and getNumActivePlayers() or 1) - 1) do
        if target ~= nil and getSpecificPlayer(playerNum) == target then human = true; break end
    end
    -- Recruitment/peace or a sandbox change can invalidate hostility mid-fight.
    -- Check before the target's stale attack intent grants continued self-defense.
    if human and not hostileHuman(self, target) then return true end
    local survivorSquare = self.character:getCurrentSquare()
    local targetSquare = target ~= nil and target:getCurrentSquare() or nil
    if target == nil or target:isDead() or isCorpseProxy(target) or survivorSquare == nil or targetSquare == nil
        or targetSquare:getZ() ~= survivorSquare:getZ()
        or not withinCombatRoleLeash(self, target) then
        return true
    end
    local targetObject = targetOf(target)
    if not human and not withinZombieEngagement(self, target,
        distanceSquared(survivorSquare, targetSquare), targetObject == self.character,
        targetsGroupMember(self, targetObject)) then return true end
    -- An enemy can retain an old target after separation. That reference is
    -- not permission to abandon a base/group and chase across the map.
    local leash = targetObject == self.character
        and THREAT_SELF_TARGET_RADIUS or COMBAT_DISENGAGE_RADIUS
    if distanceSquared(survivorSquare, targetSquare) > leash * leash then return true end
    if targetObject == self.character or targetsGroupMember(self, targetObject) then
        return false
    end
    return evaluateThreat(self, target, ticks) == nil
end

function Controller:evaluateCombatThreat(zombie, ticks)
    return evaluateThreat(self, zombie, ticks)
end

function Controller:shouldReplaceCombatTarget(candidate, awareness, ticks)
    return shouldReplaceCombatTarget(self, candidate, awareness, ticks)
end

function Controller:shouldDropCombatTarget(ticks)
    return shouldDropCombatTarget(self, ticks)
end

local function safeMethod(object, methodName, fallback, ...)
    if object == nil then
        return fallback
    end
    local lookupOk, method = pcall(function() return object[methodName] end)
    if not lookupOk or type(method) ~= "function" then
        return fallback
    end
    local ok, value = pcall(method, object, ...)
    if not ok or value == nil then
        return fallback
    end
    return value
end

local function nearbyHostileHumans(self, radius)
    local square = self.character:getCurrentSquare()
    local found, seen = {}, {}
    if square == nil then return found end
    local function include(character, survivorId)
        if character == nil or character == self.character or seen[character] then return end
        seen[character] = true
        local other = safeMethod(character, "getCurrentSquare", nil)
        -- Range/floor checks precede relationship lookups for distant residents.
        if other ~= nil and other:getZ() == square:getZ()
            and distanceSquared(square, other) <= radius * radius
            and safeMethod(character, "isDead", false) ~= true
            and hostileHuman(self, character, survivorId) then
            found[#found + 1] = character
        end
    end
    local runtime = rawget(_G, "KnoxSurvivorRuntime")
    if runtime ~= nil and runtime.activeIds ~= nil and runtime.getCharacter ~= nil then
        for _, id in ipairs(runtime.activeIds()) do
            if id ~= self.id then include(runtime.getCharacter(id), id) end
        end
    end
    if allowSurvivorPlayerCombat() and getSpecificPlayer ~= nil then
        local count = getNumActivePlayers ~= nil and getNumActivePlayers() or 1
        for index = 0, math.max(0, count - 1) do include(getSpecificPlayer(index)) end
    end
    return found
end

local function nearbyRetreatThreats(self, radius)
    local square = self.character:getCurrentSquare()
    local cell = getCell()
    local found, humans = {}, {}
    if square == nil or cell == nil then return found, humans end
    local zombies = cell:getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if z ~= nil and not z:isDead() and not isCorpseProxy(z) and z:getCurrentSquare() ~= nil and z:getCurrentSquare():getZ() == square:getZ() then
            if distanceSquared(square, z:getCurrentSquare()) <= radius * radius then
                found[#found + 1] = z
            end
        end
    end
    for _, human in ipairs(nearbyHostileHumans(self, radius)) do
        found[#found + 1], humans[human] = human, true
    end
    return found, humans
end

local function shouldRemainStealthy(self)
    if self.companionOrder ~= nil and self.companionCombatStance == "aggressive" then return false end
    local square = self.character ~= nil and self.character:getCurrentSquare() or nil
    local cell = getCell()
    if square == nil or cell == nil then return false end
    local settings = rawget(_G, "KnoxSettings")
    local cautious = settings == nil or settings.cautiousTravel == nil or settings.cautiousTravel()
    local minimum = cautious and 1 or 3
    local nearby = 0
    local zombies = cell:getZombieList()
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
        if zombie ~= nil and not zombie:isDead() and not isCorpseProxy(zombie) and zombieSquare ~= nil
            and zombieSquare:getZ() == square:getZ() then
            local distance = distanceSquared(square, zombieSquare)
            if distance <= 144 then
                local target = zombie:getTarget()
                if distance <= 64 and (target == self.character or targetsGroupMember(self, target)
                    or targetsAnyPlayer(target, distance)) then return false end
                -- Continue through the entire nearby set: a later attacker or
                -- contact-range zombie must override an earlier quiet sighting.
                if nearby < minimum or distance <= 4 then
                    local ok, visible = pcall(function() return self.character:CanSee(zombie) end)
                    if ok and visible == true then
                        if distance <= 4 then return false end
                        nearby = nearby + 1
                    end
                end
            end
        end
    end
    if nearby < minimum then return false end
    for _, human in ipairs(nearbyHostileHumans(self, 12)) do
        local target = targetOf(human)
        if target == self.character or targetsGroupMember(self, target)
            or safeMethod(self.character, "CanSee", false, human) == true then return false end
    end
    return true
end

function Controller.shouldRemainStealthy(self)
    return shouldRemainStealthy(self)
end

local function nearbyAllyCount(self, radius)
    local square = self.character:getCurrentSquare()
    if square == nil then return 1 end
    local seen = { [self.character] = true }
    local count = 1
    local function include(character)
        local dead = false
        if character ~= nil then
            local ok, result = pcall(function() return character:isDead() end)
            dead = ok and result == true
        end
        if character ~= nil and not dead and not seen[character]
            and character:getCurrentSquare() ~= nil
            and character:getCurrentSquare():getZ() == square:getZ()
            and distanceSquared(square, character:getCurrentSquare()) <= radius * radius then
            seen[character] = true
            count = count + 1
        end
    end
    include(self.groupLeader)
    include(self.companionTarget)
    for _, member in ipairs(self.groupMembers or {}) do include(member) end
    return count
end

local function injuryRisk(character)
    local bleeding, severe = 0, 0
    local bodyDamage = safeMethod(character, "getBodyDamage", nil)
    local parts = safeMethod(bodyDamage, "getBodyParts", nil)
    if parts == nil then
        return bleeding, severe
    end
    local size = tonumber(safeMethod(parts, "size", 0)) or 0
    for index = 0, size - 1 do
        local part = safeMethod(parts, "get", nil, index)
        local bandaged = safeMethod(part, "bandaged", false) == true
        if safeMethod(part, "bleeding", false) == true and not bandaged then
            bleeding = bleeding + 1
        end
        if safeMethod(part, "bitten", false) == true
            or safeMethod(part, "isDeepWounded", false) == true
            or safeMethod(part, "isCut", false) == true
            or (tonumber(safeMethod(part, "getFractureTime", 0)) or 0) > 0 then
            severe = severe + 1
        end
    end
    return bleeding, severe
end

local function weaponCapacity(character)
    local weapon = safeMethod(character, "getPrimaryHandItem", nil)
    if weapon == nil then
        return 0, 0, false
    end
    local broken = safeMethod(weapon, "isBroken", false) == true
    local condition = tonumber(safeMethod(weapon, "getCondition", 0)) or 0
    local conditionMax = math.max(1,
        tonumber(safeMethod(weapon, "getConditionMax", 1)) or 1)
    if broken or condition <= 0 then
        return 0, 0, false
    end
    local reach = math.max(0,
        tonumber(safeMethod(weapon, "getMaxRange", 0, character)) or 0)
    local skill = math.max(0,
        tonumber(safeMethod(weapon, "getWeaponSkill", 0, character)) or 0)
    return reach, skill, condition / conditionMax
end

local function approachSector(origin, square)
    local dx = square:getX() - origin:getX()
    local dy = square:getY() - origin:getY()
    local sx = dx > 0.35 and 1 or (dx < -0.35 and -1 or 0)
    local sy = dy > 0.35 and 1 or (dy < -0.35 and -1 or 0)
    return tostring(sx) .. ":" .. tostring(sy)
end

-- A standable destination behind a wall is not an immediately usable escape lane.
-- This checks only a short loaded segment; native routing/traversal still own movement.
local function fleeLaneClear(origin, target)
    local cell = getCell()
    if origin == nil or target == nil or cell == nil or origin:getZ() ~= target:getZ() then return false end
    local dx, dy = target:getX() - origin:getX(), target:getY() - origin:getY()
    local steps = math.max(math.abs(dx), math.abs(dy))
    if steps > FLEE_TARGET_DISTANCE + 2 then return false end
    local previous = origin
    for step = 1, steps do
        local nextSquare = cell:getGridSquare(
            math.floor(origin:getX() + dx * step / steps + 0.5),
            math.floor(origin:getY() + dy * step / steps + 0.5), origin:getZ())
        if nextSquare == nil or not nextSquare:canStand()
            or safeMethod(previous, "isBlockedTo", true, nextSquare)
            or safeMethod(previous, "isHoppableTo", true, nextSquare) then return false end
        previous = nextSquare
    end
    return true
end

local function fleeRouteSafety(origin, target, threats)
    if origin == nil or target == nil then return nil end
    local dx, dy = target:getX() - origin:getX(), target:getY() - origin:getY()
    local length2 = dx * dx + dy * dy
    if length2 == 0 then return nil end
    local nearest, nearestStart = math.huge, math.huge
    for _, zombie in ipairs(threats) do
        local square = zombie:getCurrentSquare()
        local zx, zy = square:getX() - origin:getX(), square:getY() - origin:getY()
        local startDistance = zx * zx + zy * zy
        nearestStart = math.min(nearestStart, startDistance)
        local progress = math.max(0, math.min(1, (zx * dx + zy * dy) / length2))
        local clearance = (zx - dx * progress)^2 + (zy - dy * progress)^2
        -- Already-touching attackers must not prevent movement away, but a safe
        -- endpoint across a zombie is not a safe route through that zombie.
        if clearance < math.min(startDistance, 1.5625) - 0.01 then return nil end
        nearest = math.min(nearest, distanceSquared(target, square))
    end
    if nearest < math.huge and nearest <= nearestStart + 0.25 then return nil end
    return nearest
end

local function fleeDestinationAvailable(self, square, ticks)
    local failed = self.failedFleeTarget
    if failed ~= nil and ticks < failed.untilTick and square ~= nil
        and square:getZ() == failed.z
        and (square:getX() - failed.x)^2 + (square:getY() - failed.y)^2 <= 9 then return false end
    return fleeLaneClear(self.character:getCurrentSquare(), square)
end

local function openEscapeLaneCount(origin, threats)
    local cell = getCell()
    if origin == nil or cell == nil or #threats == 0 then return 0 end
    local currentNearest = math.huge
    for _, zombie in ipairs(threats) do
        currentNearest = math.min(currentNearest,
            distanceSquared(origin, zombie:getCurrentSquare()))
    end
    local count = 0
    for _, direction in ipairs({
        { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
        { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
    }) do
        local candidate = cell:getGridSquare(
            origin:getX() + direction[1] * 3,
            origin:getY() + direction[2] * 3,
            origin:getZ()
        )
        if candidate ~= nil and candidate:canStand() and fleeLaneClear(origin, candidate) then
            local nearest = math.huge
            for _, zombie in ipairs(threats) do
                nearest = math.min(nearest,
                    distanceSquared(candidate, zombie:getCurrentSquare()))
            end
            if nearest >= currentNearest + 1 then
                count = count + 1
            end
        end
    end
    return count
end

local function fleeAssessment(self)
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.allowSurvivorFleeing ~= nil
        and not settings.allowSurvivorFleeing() then
        return false, { reason = "disabled", zombies = 0, humans = 0, allies = 1,
            health = 100, endurance = 1, risk = 0, immediate = 0,
            escapeLanes = 0, nearestDistanceSquared = math.huge }
    end
    local square = self.character:getCurrentSquare()
    local threats = {}
    local now = self.currentTicks or 0
    self.perceivedThreats = self.perceivedThreats or setmetatable({}, { __mode = "k" })
    local candidates, humanThreats = nearbyRetreatThreats(self, FLEE_SCAN_RADIUS)
    for _, zombie in ipairs(candidates) do
        local target = safeMethod(zombie, "getTarget", nil)
        local visible = safeMethod(self.character, "CanSee", false, zombie) == true
        local attacking = target == self.character or targetsGroupMember(self, target)
        local memory = self.perceivedThreats[zombie]
        if visible or attacking then
            self.perceivedThreats[zombie] = { lastSeen = now }
            threats[#threats + 1] = zombie
        elseif memory ~= nil and now >= memory.lastSeen
            and now - memory.lastSeen <= THREAT_MEMORY_TICKS then
            threats[#threats + 1] = zombie
        else
            self.perceivedThreats[zombie] = nil
        end
    end
    -- Risk uses perceived danger, matching combat's visibility and short memory.
    -- Escape routing below checks physical zombies and hostile humans along the route.
    local count = #threats
    local health = 100
    local okH, h = pcall(function()
        return self.character:getHealth()
    end)
    if okH and type(h) == "number" then
        health = h
        if health <= 1 then
            health = health * 100
        end
    end
    local bodyHealth = safeMethod(safeMethod(self.character, "getBodyDamage", nil),
        "getOverallBodyHealth", nil)
    if type(bodyHealth) == "number" then health = bodyHealth end
    local endurance = 1
    local okE, e = pcall(function()
        return self.character:getStats():get(CharacterStat.ENDURANCE)
    end)
    if okE and type(e) == "number" then
        endurance = e
    end
    local allies = nearbyAllyCount(self, FLEE_SCAN_RADIUS)
    local immediate, close, targeting, humanCount = 0, 0, 0, 0
    local nearestDistanceSquared = math.huge
    local sectors = {}
    local risk = 0
    for _, zombie in ipairs(threats) do
        if humanThreats[zombie] then humanCount = humanCount + 1 end
        local zombieSquare = zombie:getCurrentSquare()
        local distance2 = distanceSquared(square, zombieSquare)
        nearestDistanceSquared = math.min(nearestDistanceSquared, distance2)
        if distance2 <= 3.0625 then
            immediate = immediate + 1
            risk = risk + 3
        elseif distance2 <= 10.5625 then
            close = close + 1
            risk = risk + 1.75
        elseif distance2 <= 36 then
            risk = risk + 0.75
        else
            risk = risk + 0.25
        end
        sectors[approachSector(square, zombieSquare)] = true
        local target = safeMethod(zombie, "getTarget", nil)
        if target == self.character or targetsGroupMember(self, target) then
            targeting = targeting + 1
            risk = risk + 0.75
        end
    end
    local sectorCount = 0
    for _ in pairs(sectors) do sectorCount = sectorCount + 1 end
    if immediate >= 3 then risk = risk + (immediate - 2) * 2 end
    if sectorCount >= 3 then risk = risk + (sectorCount - 2) * 1.25 end

    local escapeLanes = openEscapeLaneCount(square, threats)
    if count > 0 and escapeLanes <= 1 then
        risk = risk + 2.5
    elseif count > 0 and escapeLanes <= 3 then
        risk = risk + 1
    end

    local bleedingParts, severeWounds = injuryRisk(self.character)
    risk = risk + math.min(3, bleedingParts * 1.5)
        + math.min(3, severeWounds * 1.5)
    if health < 50 then
        risk = risk + 2.5
    elseif health < 70 then
        risk = risk + 1
    end
    if endurance < 0.18 then
        risk = risk + 3
    elseif endurance < 0.35 then
        risk = risk + 1.5
    end

    local weaponReach, combatSkill, weaponCondition = weaponCapacity(self.character)
    if weaponCondition == false then
        risk = risk + 1.5
    else
        risk = risk - math.min(1, weaponReach * 0.5)
            - math.min(2, combatSkill * 0.2)
            - math.min(0.5, weaponCondition * 0.5)
    end
    risk = risk - math.max(0, allies - 1) * 2

    local critical = health <= 25 and count > 0
    local unarmed = self.unarmedCombatBlocked == true and weaponCondition == false and count > 0
    local closeCollapse = immediate >= 4
        or (immediate >= 3 and targeting >= 2)
    local surrounded = sectorCount >= 4 and immediate + close >= 4
        and escapeLanes <= 3
    -- Wounds/exhaustion alone belong to self-care. Retreat requires a threat;
    -- otherwise a badly hurt resident can loop forever instead of resting.
    local unsafe = count > 0 and (critical or unarmed or closeCollapse or surrounded or risk >= 7.5)
    local reason = nil
    if critical then
        reason = "critical_health"
    elseif unarmed then
        reason = "no_usable_weapon"
    elseif closeCollapse then
        reason = "close_collapse"
    elseif surrounded then
        reason = "surrounded"
    elseif bleedingParts >= 2 then
        reason = "heavy_bleeding"
    elseif endurance < 0.18 then
        reason = "exhausted"
    elseif unsafe then
        reason = "combat_risk"
    end
    return unsafe, {
        zombies = count - humanCount,
        humans = humanCount,
        allies = allies,
        health = health,
        endurance = endurance,
        immediate = immediate,
        close = close,
        targeting = targeting,
        nearestDistanceSquared = nearestDistanceSquared,
        approachSectors = sectorCount,
        escapeLanes = escapeLanes,
        bleedingParts = bleedingParts,
        severeWounds = severeWounds,
        weaponReach = weaponReach,
        weaponCondition = weaponCondition,
        combatSkill = combatSkill,
        risk = risk,
        reason = reason,
    }
end

-- Kept as a controller method so the policy can be verified without starting a
-- move or mutating combat state. Runtime decisions still use the same helper.
function Controller:assessFlee()
    return fleeAssessment(self)
end

local function retreatIsSafelyClear(self, stillUnsafe, assessment, ticks)
    local pursued = assessment ~= nil and ((assessment.immediate or 0) > 0
        or (assessment.close or 0) > 0 or (assessment.targeting or 0) > 0
        or (assessment.nearestDistanceSquared or math.huge) < FLEE_CLEAR_DISTANCE_SQUARED)
    if stillUnsafe or pursued then
        self.fleeSafeScans = 0
        self.fleeLastSafeScan = nil
        return false
    end
    if ticks ~= nil and self.fleeLastSafeScan == ticks then return false end
    self.fleeLastSafeScan = ticks
    self.fleeSafeScans = (self.fleeSafeScans or 0) + 1
    return self.fleeSafeScans >= FLEE_SAFE_CONFIRM_SCANS
end

function Controller:retreatIsSafelyClear(stillUnsafe, assessment, ticks)
    return retreatIsSafelyClear(self, stillUnsafe, assessment, ticks)
end

local function appendFleeDirection(directions, x, y)
    local length = math.sqrt(x * x + y * y)
    if length < 0.01 then return end
    x, y = x / length, y / length
    for _, direction in ipairs(directions) do
        if direction.x * x + direction.y * y > 0.985 then
            return
        end
    end
    directions[#directions + 1] = { x = x, y = y }
end

local function findFleeTarget(self, ticks)
    local origin = self.character:getCurrentSquare()
    local cell = getCell()
    if origin == nil or cell == nil then return nil end
    local awayX, awayY = 0, 0
    local threats = nearbyRetreatThreats(self, FLEE_SCAN_RADIUS + FLEE_TARGET_DISTANCE)
    for _, zombie in ipairs(threats) do
        local zs = zombie ~= nil and zombie:getCurrentSquare() or nil
        if zombie ~= nil and not zombie:isDead() and not isCorpseProxy(zombie) and zs ~= nil
            and zs:getZ() == origin:getZ() then
            local dx = origin:getX() - zs:getX()
            local dy = origin:getY() - zs:getY()
            local distance2 = dx * dx + dy * dy
            if distance2 <= (FLEE_SCAN_RADIUS + 4) ^ 2 and distance2 > 0 then
                -- Nearby bodies matter more than the edge of the horde. This
                -- points the escape route away from the actual pressure instead
                -- of letting several distant zombies cancel one close threat.
                local weight = 1 / distance2
                awayX = awayX + dx * weight
                awayY = awayY + dy * weight
            end
        end
    end
    local length = math.sqrt(awayX * awayX + awayY * awayY)
    local directions = {}
    if self.lastFleeDirectionX ~= nil and ticks <= (self.fleeDirectionUntil or -1) then
        appendFleeDirection(directions, self.lastFleeDirectionX, self.lastFleeDirectionY)
    end
    if length >= 0.01 then
        awayX, awayY = awayX / length, awayY / length
        appendFleeDirection(directions, awayX, awayY)
        appendFleeDirection(directions, awayX - awayY, awayY + awayX)
        appendFleeDirection(directions, awayX + awayY, awayY - awayX)
        appendFleeDirection(directions, -awayY, awayX)
        appendFleeDirection(directions, awayY, -awayX)
    end
    do
        -- Also consider tangents/backtracking when the away-vector hits a wall.
        -- Fixed candidates keep recovery deterministic, not random pacing.
        for _, direction in ipairs({
            { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
            { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
        }) do
            appendFleeDirection(directions, direction[1], direction[2])
        end
    end
    local best, bestScore = nil, -math.huge
    for _, direction in ipairs(directions) do
        for distance = FLEE_TARGET_DISTANCE, 2, -1 do
            local x = math.floor(origin:getX() + direction.x * distance + 0.5)
            local y = math.floor(origin:getY() + direction.y * distance + 0.5)
            local square = cell:getGridSquare(x, y, origin:getZ())
            if square ~= nil and square:canStand() and fleeDestinationAvailable(self, square, ticks) then
                local nearest = fleeRouteSafety(origin, square, threats)
                local alignment = 0
                if self.lastFleeDirectionX ~= nil
                    and ticks <= (self.fleeDirectionUntil or -1) then
                    alignment = (direction.x * self.lastFleeDirectionX
                        + direction.y * self.lastFleeDirectionY) * 8
                end
                if nearest ~= nil then
                    local score = nearest + distance * 0.5 + alignment
                    if score > bestScore then best, bestScore = square, score end
                end
            end
        end
    end
    return best
end

function Controller:findFleeTarget(ticks)
    return findFleeTarget(self, ticks)
end

-- If a survivor is forbidden from fighting, waiting for a perfectly clear
-- lane is equivalent to standing still while the horde closes.  This is a
-- last-resort panic route only: normal fleeing still requires a checked lane,
-- and an armed survivor gets the existing adjacent-combat fallback.  The
-- native mover owns the actual traversal, so this target is deliberately short
-- and chosen by threat distance rather than by a long speculative route.
local function findEmergencyFleeTarget(self, ticks)
    local origin = self.character:getCurrentSquare()
    local cell = getCell()
    if origin == nil or cell == nil then return nil end
    local threats = nearbyRetreatThreats(self, FLEE_SCAN_RADIUS + FLEE_TARGET_DISTANCE)
    if #threats == 0 then return nil end
    local currentNearest = math.huge
    for _, zombie in ipairs(threats) do
        currentNearest = math.min(currentNearest,
            distanceSquared(origin, zombie:getCurrentSquare()))
    end
    local best, bestScore = nil, -math.huge
    local directions = {
        { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
        { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
    }
    for distance = math.min(FLEE_TARGET_DISTANCE, 8), 1, -1 do
        for _, direction in ipairs(directions) do
            local square = cell:getGridSquare(
                origin:getX() + direction[1] * distance,
                origin:getY() + direction[2] * distance,
                origin:getZ()
            )
            local failed = self.failedFleeTarget
            local recentlyFailed = failed ~= nil and ticks < failed.untilTick
                and square ~= nil and square:getZ() == failed.z
                and (square:getX() - failed.x)^2 + (square:getY() - failed.y)^2 <= 9
            if square ~= nil and square:canStand() and not recentlyFailed then
                local nearest = math.huge
                local occupied = false
                for _, zombie in ipairs(threats) do
                    local threatSquare = zombie:getCurrentSquare()
                    local threatDistance = distanceSquared(square, threatSquare)
                    nearest = math.min(nearest, threatDistance)
                    if threatDistance <= 2.25 then occupied = true end
                end
                if not occupied and nearest > currentNearest + 0.25 then
                    local score = nearest + distance * 0.25
                    if score > bestScore then
                        best, bestScore = square, score
                    end
                end
            end
        end
        if best ~= nil then return best end
    end
    return nil
end

function Controller:findEmergencyFleeTarget(ticks)
    return findEmergencyFleeTarget(self, ticks)
end

local function groupFleeKey(self)
    if self.groupLeaderId ~= nil then
        return self.groupLeaderId
    end
    if #(self.groupMembers or {}) > 1 then
        return self.id
    end
    return nil
end

local function groupFleeTarget(self, ticks)
    local key = groupFleeKey(self)
    if key == nil then return nil, false end
    local plan = fleePlans[key]
    if plan == nil or (tonumber(plan.expiresAt) or -1) < ticks then
        fleePlans[key] = nil
        return nil, false
    end
    local cell = getCell()
    if cell == nil then return nil, true end
    -- Members use small, deterministic offsets around their leader's safe
    -- destination.  That keeps a fleeing group together without stacking every
    -- body on one tile or forcing a second, contradictory threat calculation.
    local slot = math.max(1, tonumber(self.groupFormationSlot) or 1)
    local offsets = {
        { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
        { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
    }
    local offset = offsets[((slot - 1) % #offsets) + 1]
    local square = cell:getGridSquare(
        plan.x + offset[1], plan.y + offset[2], plan.z
    )
    if square ~= nil and square:canStand() then
        local current = self.character:getCurrentSquare()
        if current ~= nil and navigationDistanceSquared(current, square) <= 2.25 then
            return nil, true
        end
        if fleeDestinationAvailable(self, square, ticks)
            and fleeRouteSafety(current, square,
                nearbyRetreatThreats(self, FLEE_SCAN_RADIUS + FLEE_TARGET_DISTANCE)) ~= nil then
            return square, true
        end
    end
    local center = cell:getGridSquare(plan.x, plan.y, plan.z)
    return center ~= nil and center:canStand() and fleeDestinationAvailable(self, center, ticks)
        and fleeRouteSafety(self.character:getCurrentSquare(), center,
            nearbyRetreatThreats(self, FLEE_SCAN_RADIUS + FLEE_TARGET_DISTANCE)) ~= nil
        and center or nil, true
end

local function itemMatchesGoal(item, goal, character)
    if goal == "find_food" then
        return KnoxSurvivorNeeds.isSafeFood(item)
    end
    if goal == "find_water" then
        local thirst = character:getStats():get(CharacterStat.THIRST)
        return KnoxSurvivorNeeds.isWaterItem(item, thirst >= 0.90)
    end
    if goal == "find_medical" then
        return item:isCanBandage()
            or item:getFullType() == "Base.Sheet"
            or (item:IsClothing() and item:getFabricType() == "Cotton")
    end
    if goal == "find_weapon" then
        return KnoxEquipmentIntelligence ~= nil
            and KnoxEquipmentIntelligence.isMeaningfulWeaponUpgrade ~= nil
            and KnoxEquipmentIntelligence.isMeaningfulWeaponUpgrade(character, item) == true
    end
    if goal == "find_tools" then
        return KnoxSurvivorLooting ~= nil
            and KnoxSurvivorLooting.isEssentialTool ~= nil
            and KnoxSurvivorLooting.isEssentialTool(item) == true
    end
    return false
end

local function containerUnavailable(self, container, ticks)
    local value = self.inspectedContainers[container]
    if type(value) == "number" and value <= ticks then
        self.inspectedContainers[container] = nil
        return false
    end
    return value ~= nil
end

local function containerArea(container)
    local square = container ~= nil and container:getSourceGrid() or nil
    if square == nil then
        return nil
    end
    return square:getRoom() or square
end

local function areaUnavailable(self, container, ticks)
    local area = containerArea(container)
    local unavailableUntil = area ~= nil and self.blockedAreas[area] or nil
    if type(unavailableUntil) == "number" and unavailableUntil <= ticks then
        self.blockedAreas[area] = nil
        return false
    end
    return unavailableUntil ~= nil
end

local function markPendingAreaBlocked(self, ticks, reason)
    local container = self.pendingSupply ~= nil and self.pendingSupply.container or nil
    local area = containerArea(container)
    if area ~= nil then
        self.blockedAreas[area] = ticks + BLOCKED_AREA_COOLDOWN_TICKS
    end
    self.forceTravel = true
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " blocked-area=" .. tostring(reason)
            .. " retry=" .. tostring(BLOCKED_AREA_COOLDOWN_TICKS)
    )
end

function Controller:hasNeedEscort()
    if self.baseId ~= nil or self.baseTask ~= nil then return false end
    return self.companionOrder ~= nil and self.companionDirective == nil
        or self.groupLeaderId ~= nil or self.groupLeader ~= nil
end

function Controller:allowNeedDetour(square, ticks, checkRoute)
    if not self:hasNeedEscort() then return true end
    if self.companionOrder == "hold" then return false end
    local leader = self.companionOrder ~= nil and self.companionTarget or self.groupLeader
    local anchor = leader ~= nil and leader:getCurrentSquare() or nil
    local origin = self.character:getCurrentSquare()
    if square == nil or anchor == nil or origin == nil
        or square:getZ() ~= anchor:getZ() or square:getZ() ~= origin:getZ()
        or distanceSquared(origin, square) > 16
        or distanceSquared(anchor, square) > 36
        or safeMethod(leader, "isDead", true) then return false end
    -- Reuse short-lived perceptions; do not add a population scan per container.
    for threat, memory in pairs(self.perceivedThreats or {}) do
        local threatSquare = safeMethod(threat, "getCurrentSquare", nil)
        if ticks - (memory.lastSeen or 0) <= THREAT_MEMORY_TICKS
            and not safeMethod(threat, "isDead", true)
            and threatSquare ~= nil and threatSquare:getZ() == square:getZ()
            and (distanceSquared(threatSquare, square) <= 36
                or distanceSquared(threatSquare, origin) <= 36) then return false end
    end
    return checkRoute == false or fleeLaneClear(origin, square)
end

local function findSupply(self, goal, ticks, matcher)
    local origin = self.character:getCurrentSquare()
    if origin == nil or getCell() == nil then return nil end
    local storage = rawget(_G, "KnoxBaseStorage")
    local policies = self.base ~= nil and storage ~= nil and storage.policies ~= nil
        and storage.policies(self.base) or {}
    local assigned = {}
    for _, policy in ipairs(policies) do
        local resolved = storage.resolvePolicy(policy)
        if resolved ~= nil then assigned[resolved.container] = resolved end
    end
    local restocking = self.baseSupplyTrip == true and goal ~= "base_supply"
    local function inspect(container, square)
        if container == nil or (restocking and assigned[container] ~= nil) or not container:isExistYet()
            or containerUnavailable(self, container, ticks) or areaUnavailable(self, container, ticks)
            or not self:allowNeedDetour(square, ticks, false) then return nil end
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if (matcher ~= nil and matcher(item) == true
                    or matcher == nil and itemMatchesGoal(item, goal, self.character))
                and not reservedByOther(self.reservations, "items", item, self.id) then
                local approach = AdjacentFreeTileFinder.Find(square, self.character)
                if approach ~= nil and self:allowNeedDetour(approach, ticks) then
                    return {goal=goal, item=item, container=container, approach=approach}
                end
            end
        end
        return nil
    end
    if not restocking then
        -- Meals/drinks use the kitchen first, then any actual supplies at home.
        -- This also allows native routes to a pantry on another loaded floor.
        for pass = 1, 2 do
            for _, policy in ipairs(policies) do
                local preferred = (goal == "find_food" or goal == "find_water") and policy.storageRole == "food"
                if (pass == 1 and preferred or pass == 2 and not preferred)
                    and math.abs((tonumber(policy.z) or 0) - origin:getZ()) <= 2
                    and ((tonumber(policy.x) or math.huge) - origin:getX()) ^ 2
                        + ((tonumber(policy.y) or math.huge) - origin:getY()) ^ 2 <= 128 * 128 then
                    local resolved = storage.resolvePolicy(policy)
                    local supply = resolved ~= nil and inspect(resolved.container, resolved.square) or nil
                    if supply ~= nil then return supply end
                end
            end
        end
    end
    for radius = 0, SUPPLY_SCAN_RADIUS do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if radius == 0 or math.abs(dx) == radius or math.abs(dy) == radius then
                    local square = getCell():getGridSquare(origin:getX() + dx, origin:getY() + dy, origin:getZ())
                    if square ~= nil then
                        local objects = square:getObjects()
                        for objectIndex = 0, objects:size() - 1 do
                            local object = objects:get(objectIndex)
                            for containerIndex = 0, object:getContainerCount() - 1 do
                                local supply = inspect(object:getContainerByIndex(containerIndex), square)
                                if supply ~= nil then return supply end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function directiveAllowsSquare(directive, square, object)
    if directive == nil then
        return true
    end
    if square == nil or square:getZ() ~= (tonumber(directive.z) or 0) then
        return false
    end
    local kind = tostring(directive.kind or "")
    if kind == "loot_building" then
        local building = square:getBuilding()
        local definition = building ~= nil and building:getDef() or nil
        return definition ~= nil
            and tostring(definition:getID()) == tostring(directive.buildingId)
    end
    local x, y = square:getX(), square:getY()
    local inside = x >= (tonumber(directive.minX) or x)
        and x <= (tonumber(directive.maxX) or x)
        and y >= (tonumber(directive.minY) or y)
        and y <= (tonumber(directive.maxY) or y)
    if not inside then
        return false
    end
    return kind ~= "loot_corpses" or instanceof(object, "IsoDeadBody")
end

local function findExploration(self, ticks, directive)
    local origin = self.character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
    local fallback = nil
    local scanRadius = directive ~= nil and 30 or EXPLORATION_SCAN_RADIUS
    for radius = 0, scanRadius do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if radius == 0 or math.abs(dx) == radius or math.abs(dy) == radius then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    if square ~= nil then
                        local objects = square:getObjects()
                        for objectIndex = 0, objects:size() - 1 do
                            local object = objects:get(objectIndex)
                            for containerIndex = 0, object:getContainerCount() - 1 do
                                local container = object:getContainerByIndex(containerIndex)
                                if container ~= nil and container:isExistYet()
                                    and directiveAllowsSquare(directive, square, object)
                                    and not containerUnavailable(self, container, ticks)
                                    and not areaUnavailable(self, container, ticks)
                                    and not reservedByOther(
                                        self.reservations,
                                        "containers",
                                        container,
                                        self.id
                                    ) then
                                    local approach = AdjacentFreeTileFinder.Find(
                                        square,
                                        self.character
                                    )
                                    if approach ~= nil then
                                        local candidates = KnoxSurvivorLooting.plan(
                                            self.character,
                                            container,
                                            2
                                        )
                                        local available = {}
                                        for _, candidate in ipairs(candidates) do
                                            if not reservedByOther(
                                                self.reservations,
                                                "items",
                                                candidate.item,
                                                self.id
                                            ) then
                                                available[#available + 1] = candidate
                                            end
                                        end
                                        if #available > 0 then
                                            return {
                                                goal = "explore",
                                                items = available,
                                                container = container,
                                                approach = approach,
                                            }
                                        end
                                        if radius <= CONVENIENT_INSPECTION_RADIUS then
                                            fallback = fallback or {
                                                goal = "inspect",
                                                container = container,
                                                approach = approach,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return fallback
end

local function roamDestinationKey(square)
    if square == nil then
        return nil
    end
    local building = square:getBuilding()
    local definition = building ~= nil and building:getDef() or nil
    if definition ~= nil then
        return "building:" .. tostring(definition:getID())
    end
    return "area:" .. tostring(math.floor(square:getX() / 6))
        .. ":" .. tostring(math.floor(square:getY() / 6))
        .. ":" .. tostring(square:getZ())
end

local function roamMemoryAvailable(memory, key, ticks)
    if key == nil then
        return true
    end
    local unavailableUntil = (memory or {})[key]
    if unavailableUntil == nil then
        return true
    end
    if unavailableUntil <= (ticks or 0) then
        memory[key] = nil
        return true
    end
    return false
end

local function rememberRoamDestination(self, key, ticks, cooldown)
    if key == nil then
        return
    end
    self.recentRoamGoals[key] = math.max(
        self.recentRoamGoals[key] or 0,
        ticks + cooldown
    )
    for index = #self.roamGoalOrder, 1, -1 do
        if self.roamGoalOrder[index] == key then
            table.remove(self.roamGoalOrder, index)
        end
    end
    self.roamGoalOrder[#self.roamGoalOrder + 1] = key
    while #self.roamGoalOrder > ROAM_MEMORY_LIMIT do
        local oldest = table.remove(self.roamGoalOrder, 1)
        self.recentRoamGoals[oldest] = nil
    end
end

local function zombiePressureAt(square, radius)
    local cell = getCell()
    if square == nil or cell == nil then
        return 0
    end
    local count = 0
    local zombies = cell:getZombieList()
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local zombieSquare = zombie ~= nil and zombie:getCurrentSquare() or nil
        if zombie ~= nil and not zombie:isDead() and not isCorpseProxy(zombie) and zombieSquare ~= nil
            and zombieSquare:getZ() == square:getZ()
            and distanceSquared(square, zombieSquare) <= radius * radius then
            count = count + 1
        end
    end
    return count
end

function Controller.selectRoamCandidate(candidates, recentGoals, ticks)
    local best = nil
    for _, candidate in ipairs(candidates or {}) do
        if candidate.square ~= nil
            and roamMemoryAvailable(recentGoals, candidate.key, ticks)
            and (candidate.danger or 0) <= ROAM_DANGER_LIMIT
            and (best == nil or candidate.score > best.score
                or (candidate.score == best.score
                    and candidate.distance < best.distance)) then
            best = candidate
        end
    end
    return best
end

function Controller.roamMemoryAvailable(memory, key, ticks)
    return roamMemoryAvailable(memory, key, ticks)
end

function Controller.shouldInterruptRoamingForNeed(kind)
    return kind ~= nil and kind ~= "roam" and kind ~= "fight"
end

local CARDINAL_OFFSETS = {
    { x = 1, y = 0 },
    { x = -1, y = 0 },
    { x = 0, y = 1 },
    { x = 0, y = -1 },
}

-- Keep roaming destination selection useful without scanning inventories or
-- creating a second planner. Optional native building metadata is queried
-- defensively so modded/partial building objects fail back to distance only.
local function roamingBuildingValue(building)
    if building == nil then return 0 end
    local value = 0
    local definition = building.getDef ~= nil and building:getDef() or nil
    if definition ~= nil then
        local okRooms, rooms = pcall(function() return definition:getRoomsNumber() end)
        if okRooms then value = value + math.min(18, math.max(0, tonumber(rooms) or 0) * 2) end
        local okArea, area = pcall(function() return definition:getArea() end)
        if okArea then value = value + math.min(14, math.max(0, tonumber(area) or 0) / 40) end
    end
    local okResidential, residential = pcall(function() return building:isResidential() end)
    if okResidential and residential == true then value = value + 12 end
    local okWater, hasWater = pcall(function() return building:hasWater() end)
    if okWater and hasWater == true then value = value + 10 end
    return value
end

local function findRoamTarget(self, ticks)
    local character = self.character
    local origin = character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
    local candidates = {}
    local seenBuildings = {}
    -- Sample loaded squares every two tiles, rather than growing nested square
    -- scans. This reaches the next block without per-tick world searching.
    for dx = -ROAM_MAX_RADIUS, ROAM_MAX_RADIUS, 2 do
        for dy = -ROAM_MAX_RADIUS, ROAM_MAX_RADIUS, 2 do
                local radius = math.max(math.abs(dx), math.abs(dy))
                if radius >= ROAM_MIN_RADIUS then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    local building = square ~= nil and square:getBuilding() or nil
                    if square ~= nil and square:canStand() and square:getRoom() ~= nil
                        and (self.blockedAreas[square:getRoom()] or 0) <= ticks
                        and building ~= nil
                        and (seenBuildings[building] == nil or radius < seenBuildings[building].distance) then
                        local key = roamDestinationKey(square)
                        seenBuildings[building] = {
                            square = square,
                            key = key,
                            kind = "building",
                            distance = radius,
                            score = 100 - radius + roamingBuildingValue(building),
                        }
                    end
                end
        end
    end
    for _, candidate in pairs(seenBuildings) do
        if roamMemoryAvailable(self.recentRoamGoals, candidate.key, ticks) then
            candidate.danger = zombiePressureAt(candidate.square, ROAM_DANGER_RADIUS)
            candidates[#candidates + 1] = candidate
        end
    end
    local selected = Controller.selectRoamCandidate(
        candidates,
        self.recentRoamGoals,
        ticks
    )
    if selected ~= nil then
        return selected.square, selected.key, selected.kind
    end
    local heading = self.roamHeading
    if heading == nil then
        heading = CARDINAL_OFFSETS[ZombRand(#CARDINAL_OFFSETS) + 1]
        self.roamHeading = { x = heading.x, y = heading.y }
    end
    local onward, onwardKey, onwardScore = nil, nil, -math.huge
    for _ = 1, 40 do
        local radius = ROAM_MIN_RADIUS + ZombRand(ROAM_MAX_RADIUS - ROAM_MIN_RADIUS + 1)
        local dx = ZombRand(radius * 2 + 1) - radius
        local dy = ZombRand(radius * 2 + 1) - radius
        if math.max(math.abs(dx), math.abs(dy)) >= ROAM_MIN_RADIUS then
            local square = getCell():getGridSquare(
                origin:getX() + dx,
                origin:getY() + dy,
                origin:getZ()
            )
            local key = roamDestinationKey(square)
            if square ~= nil and square:canStand()
                and roamMemoryAvailable(self.recentRoamGoals, key, ticks)
                and zombiePressureAt(square, ROAM_DANGER_RADIUS) <= ROAM_DANGER_LIMIT then
                local progress = dx * heading.x + dy * heading.y
                if progress > onwardScore then
                    onward, onwardKey, onwardScore = square, key, progress
                end
            end
        end
    end
    return onward, onwardKey, onward ~= nil and "nearby_area" or nil
end

local REST_QUALITY = {
    goodBed = 5,
    averageBed = 4,
    averageChair = 3,
    badBed = 2,
    badChair = 1,
}

local function furnitureQuality(object, sleeping)
    local properties = object ~= nil and object:getProperties() or nil
    local bedType = properties ~= nil and properties:get("BedType") or nil
    local quality = REST_QUALITY[tostring(bedType)] or 3
    if not sleeping then
        local name = properties ~= nil and string.lower(tostring(properties:get("CustomName") or "")) or ""
        if string.find(name, "sofa", 1, true) or string.find(name, "couch", 1, true) then
            quality = quality + 4
        elseif string.find(string.lower(tostring(bedType)), "bed", 1, true) then
            quality = quality - 3
        end
    end
    return quality, tostring(bedType or "seat")
end

local function usableSeat(self, object)
    if object == nil or object:getObjectIndex() == -1
        or reservedByOther(self.reservations, "restSpots", object, self.id) then
        return false
    end
    local success, count = pcall(function()
        return SeatingManager.getInstance():getTilePositionCount(object)
    end)
    if not success or count <= 0 then
        return false
    end
    local occupiedSuccess, occupied = pcall(function()
        return object:isFurnitureOccupied(self.character)
    end)
    return not occupiedSuccess or not occupied
end

local function usableBed(self, object)
    if object == nil or object:getObjectIndex() == -1
        or reservedByOther(self.reservations, "restSpots", object, self.id) then
        return false
    end
    local properties = object:getProperties()
    local bedType = properties ~= nil and tostring(properties:get("BedType") or "") or ""
    if string.find(string.lower(bedType), "bed", 1, true) == nil then
        return false
    end
    local occupiedSuccess, occupied = pcall(function()
        return object:isFurnitureOccupied(self.character)
    end)
    return not occupiedSuccess or not occupied
end

local function usableRestFurniture(self, object, sleeping)
    if sleeping then
        return usableBed(self, object)
    end
    return usableSeat(self, object)
end

local function findBestRestSpot(self, sleeping, squareAllowed)
    local origin = self.character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
    local best = nil
    for radius = 0, RECOVERY_SEAT_SCAN_RADIUS do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = getCell():getGridSquare(
                        origin:getX() + dx,
                        origin:getY() + dy,
                        origin:getZ()
                    )
                    if square ~= nil and (squareAllowed == nil or squareAllowed(square)) then
                        local objects = square:getObjects()
                        for index = 0, objects:size() - 1 do
                            local object = objects:get(index)
                            if usableRestFurniture(self, object, sleeping) then
                                local approach = AdjacentFreeTileFinder.Find(
                                    square,
                                    self.character,
                                    nil
                                )
                                if approach ~= nil
                                    and (squareAllowed == nil or squareAllowed(approach)) then
                                    local quality, bedType = furnitureQuality(object, sleeping)
                                    local sleepFurniture = string.find(
                                        string.lower(bedType),
                                        "bed",
                                        1,
                                        true
                                    ) ~= nil
                                    local distance = distanceSquared(origin, approach)
                                    if (not sleeping or sleepFurniture)
                                        and (best == nil or quality > best.quality
                                            or (quality == best.quality
                                                and distance < best.distance)) then
                                        best = {
                                            object = object,
                                            approach = approach,
                                            quality = quality,
                                            bedType = bedType,
                                            distance = distance,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function safeObjectBoolean(object, methodName, fallback)
    if object == nil then
        return fallback
    end
    local ok, value = pcall(function()
        return object[methodName](object)
    end)
    if not ok then
        return fallback
    end
    return value == true
end

local function safeWindowCanClimb(window, character)
    local ok, value = pcall(function()
        return window:canClimbThrough(character)
    end)
    return ok and value == true
end

function Controller.entryCandidateScore(
    kind,
    open,
    smashed,
    barricaded,
    locked,
    permaLocked,
    canClimb,
    allowForcedEntry
)
    if barricaded then
        return nil
    end
    if kind == "door" then
        if open then
            return 0
        end
        return not locked and 1 or nil
    end
    if kind == "window" then
        if open or smashed then
            return canClimb and 2 or nil
        end
        if not locked and not permaLocked then return 3 end
        return allowForcedEntry and 4 or nil
    end
    return nil
end

local function findAlternateEntry(self, supply, ticks)
    local targetSquare = supply ~= nil and supply.container ~= nil
        and supply.container:getSourceGrid()
        or nil
    if targetSquare == nil and supply ~= nil and supply.container ~= nil
        and supply.container:getParent() ~= nil then
        targetSquare = supply.container:getParent():getSquare()
    end
    local targetRoom = targetSquare ~= nil and targetSquare:getRoom() or nil
    local origin = self.character:getCurrentSquare()
    if targetRoom == nil or origin == nil or getCell() == nil then
        return nil
    end

    local best = nil
    local bestScore = math.huge
    local bestDistance = math.huge
    local urgent = self.activeDecision == "find_food" or self.activeDecision == "find_water"
        or self.activeDecision == "find_medical"
    local allowForcedEntry = urgent and KnoxBaseManager.canDamageStructure(self.id, targetSquare)
        and KnoxSurvivorNeeds.snapshot(self.character).endurance >= LOCKED_DOOR_MIN_ENDURANCE
    local roomSquares = targetRoom:getSquares()
    local attempts = supply.entryAttempts or {}
    for index = 0, roomSquares:size() - 1 do
        local inside = roomSquares:get(index)
        if inside ~= nil and inside:getZ() == origin:getZ()
            and math.abs(inside:getX() - targetSquare:getX()) <= ENTRY_SCAN_RADIUS
            and math.abs(inside:getY() - targetSquare:getY()) <= ENTRY_SCAN_RADIUS then
            for _, offset in ipairs(CARDINAL_OFFSETS) do
                local outside = getCell():getGridSquare(
                    inside:getX() + offset.x,
                    inside:getY() + offset.y,
                    inside:getZ()
                )
                if outside ~= nil and outside:getRoom() ~= targetRoom and outside:canStand() then
                    local isFailedEdge = outside:getX() == origin:getX()
                        and outside:getY() == origin:getY()
                        and outside:getZ() == origin:getZ()
                    local candidate = nil
                    local score = math.huge

                    local door = inside:getDoorTo(outside)
                    if door == nil then
                        door = outside:getDoorTo(inside)
                    end
                    local doorOpen = door ~= nil
                        and safeObjectBoolean(door, "IsOpen", false)
                    local doorScore = door ~= nil and Controller.entryCandidateScore(
                        "door",
                        doorOpen,
                        false,
                        safeObjectBoolean(door, "isBarricaded", true),
                        safeObjectBoolean(door, "isLocked", true),
                        false,
                        false
                    ) or nil
                    if not isFailedEdge and doorScore ~= nil and attempts[door] == nil then
                        score = doorScore
                        candidate = {
                            outside = outside,
                            inside = inside,
                            object = door,
                            kind = "door",
                        }
                    end

                    local window = inside:getWindowTo(outside)
                    if window == nil then
                        window = outside:getWindowTo(inside)
                    end
                    local windowOpen = window ~= nil
                        and safeObjectBoolean(window, "IsOpen", false)
                    local windowSmashed = window ~= nil
                        and safeObjectBoolean(window, "isSmashed", false)
                    local windowScore = window ~= nil and Controller.entryCandidateScore(
                        "window",
                        windowOpen,
                        windowSmashed,
                        safeObjectBoolean(window, "isBarricaded", true),
                        safeObjectBoolean(window, "isLocked", true),
                        safeObjectBoolean(window, "isPermaLocked", true),
                        not (windowOpen or windowSmashed)
                            or safeWindowCanClimb(window, self.character),
                        allowForcedEntry
                    ) or nil
                    -- Lock metadata is not permission to skip trying the handle.
                    -- Each distinct window gets a non-destructive attempt first.
                    if window ~= nil and not safeObjectBoolean(window, "isBarricaded", true)
                        and not windowOpen and not windowSmashed and attempts[window] == nil then
                        windowScore = 3
                    end
                    local forceWindow = attempts[window] == "closed" and allowForcedEntry
                        and not windowOpen and not windowSmashed and windowScore ~= nil
                    if candidate == nil and windowScore ~= nil
                        and ((not isFailedEdge and attempts[window] == nil) or forceWindow) then
                        -- After a failed entrance, try usable windows first;
                        -- smashing remains after every non-destructive option.
                        score = forceWindow and 4 or (windowScore < 4 and windowScore - 4 or windowScore)
                        candidate = {
                            outside = outside,
                            inside = inside,
                            object = window,
                            kind = "window",
                            force = forceWindow,
                        }
                    end

                    if candidate ~= nil and self:allowNeedDetour(outside, ticks or 0) then
                        local distance = distanceSquared(origin, outside)
                        if score < bestScore
                            or (score == bestScore and distance < bestDistance) then
                            best = candidate
                            bestScore = score
                            bestDistance = distance
                        end
                    end
                end
            end
        end
    end
    return best
end

function Controller.isEntryTraversalFailure(movement)
    movement = tostring(movement or "")
    return string.find(movement, "FAILED_LOCKED_DOOR", 1, true) ~= nil
        or string.find(movement, "FAILED_BARRICADED_DOOR", 1, true) ~= nil
        or string.find(movement, "FAILED_LOCKED_OR_UNUSABLE_WINDOW", 1, true) ~= nil
        or string.find(movement, "FAILED_BARRICADED_WINDOW", 1, true) ~= nil
        or string.find(movement, "FAILED_BLOCKED_WINDOW", 1, true) ~= nil
end

function Controller.selfCareReady(retryAt, kind, ticks)
    return ((retryAt or {})[kind] or 0) <= (ticks or 0)
end

local function perceptionScanOffset(id)
    local value = 0
    local text = tostring(id or "")
    for index = 1, #text do
        value = (value + string.byte(text, index)) % THREAT_SCAN_TICKS
    end
    return value
end

local function carriedItemByType(character, fullType)
    if character == nil or type(fullType) ~= "string" or fullType == "" then
        return nil
    end
    local inventory = character:getInventory()
    local items = inventory ~= nil and inventory:getItems() or nil
    if items == nil then return nil end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local ok, value = pcall(function() return item:getFullType() end)
        if ok and tostring(value or "") == fullType then
            return item
        end
    end
    return nil
end

function Controller.perceptionScanOffset(id)
    return perceptionScanOffset(id)
end

function Controller.new(id, character, bridge, reservations, ticks)
    local self = setmetatable({}, Controller)
    self.id = id
    self.character = character
    self.bridge = bridge
    self.reservations = reservations
    self.state = "IDLE"
    self.pendingSupply = nil
    self.pendingDepositTrip = nil
    self.pendingBaseSupplyDeposit = nil
    self.baseSupplyOrder = nil
    self.baseSupplyOrderAttempts = 0
    self.baseSupplyKind = nil
    self.activeDecision = nil
    self.lifeIntent = KnoxPersistence ~= nil
        and KnoxPersistence.getSurvivorLifeIntent ~= nil
        and KnoxPersistence.getSurvivorLifeIntent(id) or nil
    if self.lifeIntent ~= nil and self.lifeIntent.kind == "base_supply_deposit" then
        local recovered = carriedItemByType(self.character, self.lifeIntent.targetKey)
        if recovered ~= nil then
            self.pendingBaseSupplyDeposit = { item = recovered }
        else
            self:clearLifeIntent()
        end
    end
    self.combatTarget = nil
    self.failedThreats = {}
    self.rangedFallbackUntil = setmetatable({}, { __mode = "k" })
    self.perceivedThreats = setmetatable({}, { __mode = "k" })
    self.nextThink = ticks + 15 + ZombRand(30)
    -- Spread independent survivor scans across the interval so a group does not
    -- traverse the loaded zombie list on one shared tick.
    self.nextThreatScan = ticks + perceptionScanOffset(id)
    self.lastCombatRetarget = -COMBAT_RETARGET_COOLDOWN_TICKS
    self.nextWorldSearch = 0
    self.nextBaseSupplySearch = 0
    self.nextExplorationSearch = 0
    self.recoveryStarted = 0
    self.recoveryPostureStarted = 0
    self.pendingRest = nil
    self.selfCareIntent = nil
    self.selfCareRetryAt = {}
    self.selfCareInterrupted = nil
    self.inspectedContainers = {}
    self.blockedAreas = {}
    self.recentRoamGoals = {}
    self.roamGoalOrder = {}
    self.roamGoalKey = nil
    self.roamGoalKind = nil
    self.nextRoamNeedsCheck = ticks
    self.campId = nil
    self.camp = nil
    self.campSlot = 1
    self.campPositionCycle = 0
    self.campPosition = nil
    self.campExcursion = false
    self.campExcursionExplored = false
    self.nextCampExcursion = ticks
    self.reservations.campPositions = self.reservations.campPositions or {}
    self.forceTravel = false
    self.stateStartedAt = ticks
    self.observedState = self.state
    self.entryDetour = nil
    self.nextNeedCallout = 0
    self.nextActionCallout = 0
    self.groupLeaderId = nil
    self.groupLeader = nil
    self.groupFormationSlot = 1
    self.groupSize = 1
    self.groupMembers = {}
    self.groupObjective = nil
    self.groupObjectiveRevision = nil
    self.groupObjectiveChanged = false
    self.nextGroupObjectiveAssist = 0
    self.pendingGroupSupport = nil
    self.nextGroupSupportAt = 0
    self.companionOwnerId = nil
    self.companionTarget = nil
    self.companionOrder = nil
    self.companionCombatStance = "defensive"
    self.companionFormationSlot = 1
    self.companionDirective = nil
    self.directiveMisses = 0
    self.allowClimbing = true
    self.failureReasons = {}
    self.formationTargetX = nil
    self.formationTargetY = nil
    self.formationTargetZ = nil
    self.formationMovementPace = nil
    self.nextFormationRefresh = 0
    self.formationCommitUntil = 0
    self.formationFailureCount = 0
    self.movementFailureCount = 0
    self.regroupMember = nil
    self.nextRegroupCallout = 0
    self.baseId = nil
    self.base = nil
    self.baseTask = nil
    self.baseTaskStartedAt = nil
    self.baseTaskSupplyTransfer = nil
    self.baseResupplyAttempts = 0
    self.baseTaskRetryAt = 0
    self.baseTaskActionQueued = false
    self.baseTaskBarricadeTarget = nil
    self.baseTaskBarricadeBefore = 0
    self.baseTaskFarmingTarget = nil
    self.baseTaskFarmingBefore = nil
    self.baseTaskWoodcuttingTarget = nil
    self.baseTaskWoodcuttingBefore = nil
    self.baseTaskCorpseTarget = nil
    self.baseTaskCorpsePhase = nil
    self.baseTaskCorpseGrabVerifyUntil = nil
    self.baseTaskCorpseGrabRetryIssued = nil
    self.baseTaskCorpseDropVerifyUntil = nil
    self.baseTaskCorpseDropRetryIssued = nil
    self.baseTaskAnimalTarget = nil
    self.baseTaskAnimalBefore = nil
    self.baseTaskRepairTarget = nil
    self.baseTaskRepairBefore = nil
    self.baseTaskConstructionTarget = nil
    self.factionId = nil
    self.awayTeamId = nil
    self.awayCollected = false
    self.awaySearchMisses = 0
    self.factionBaseCandidate = nil
    self.announcedFactionBaseCandidate = nil
    self.pendingRobbery = nil
    self.pendingThreatAwareness = nil
    self.fleeSafeScans = 0
    self.lastFleeDirectionX = nil
    self.lastFleeDirectionY = nil
    self.fleeDirectionUntil = 0
    self.counts = {
        roam = 0,
        loot = 0,
        search = 0,
        needs = 0,
        combat = 0,
        groupTravel = 0,
        baseScout = 0,
        robberies = 0,
        failures = 0,
    }
    character:setZombiesDontAttack(false)
    return self
end

local function currentWorldAgeHours()
    return getGameTime ~= nil and getGameTime() ~= nil
        and getGameTime():getWorldAgeHours() or 0
end

function Controller.roamIntentKind(destinationKind, existingKind)
    if existingKind == "find_food" or existingKind == "find_water"
        or existingKind == "find_medical" then
        return existingKind
    end
    return destinationKind == "building" and "investigate_building" or "travel_area"
end

function Controller:setLifeIntent(kind, phase, square, targetKey)
    local nextIntent = {
        kind = kind,
        phase = phase,
        targetKey = targetKey,
        targetX = square ~= nil and square:getX() or nil,
        targetY = square ~= nil and square:getY() or nil,
        targetZ = square ~= nil and square:getZ() or nil,
        startedAtHours = self.lifeIntent ~= nil
            and self.lifeIntent.kind == kind
            and self.lifeIntent.startedAtHours or currentWorldAgeHours(),
    }
    local current = self.lifeIntent
    if current ~= nil and current.kind == nextIntent.kind
        and current.phase == nextIntent.phase
        and current.targetKey == nextIntent.targetKey
        and current.targetX == nextIntent.targetX
        and current.targetY == nextIntent.targetY
        and current.targetZ == nextIntent.targetZ then
        return false
    end
    self.lifeIntent = nextIntent
    if KnoxPersistence ~= nil and KnoxPersistence.setSurvivorLifeIntent ~= nil then
        KnoxPersistence.setSurvivorLifeIntent(
            self.id, nextIntent, currentWorldAgeHours()
        )
    end
    return true
end

function Controller:clearLifeIntent()
    if self.lifeIntent == nil then return false end
    self.lifeIntent = nil
    if KnoxPersistence ~= nil and KnoxPersistence.clearSurvivorLifeIntent ~= nil then
        KnoxPersistence.clearSurvivorLifeIntent(self.id)
    end
    return true
end

function Controller:recordFailure(reason, ticks, cooldown)
    local key = tostring(reason or "unknown")
    self.lastFailure={reason=key,ticks=ticks}
    self.counts.failures = self.counts.failures + 1
    self.failureReasons[key] = (self.failureReasons[key] or 0) + 1
    self.nextThink = math.max(
        self.nextThink or 0,
        (ticks or 0) + (cooldown or THINK_MIN_TICKS)
    )
    local count = self.failureReasons[key]
    if count == 1 or count % 10 == 0 then
        print("[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " action-failed=" .. key .. " count=" .. tostring(count)
            .. " retryAt=" .. tostring(self.nextThink))
    end
end

local function movementFailureKind(result)
    local text = tostring(result or "unknown")
    return string.match(text, "^[^%s:]+") or "unknown"
end

function Controller:recordMovementFailure(scope, result, ticks, baseCooldown, maxCooldown)
    self.movementFailureCount = (self.movementFailureCount or 0) + 1
    local exponent = math.min(self.movementFailureCount - 1, 3)
    local cooldown = math.min(
        (baseCooldown or MOVEMENT_FAILURE_COOLDOWN_TICKS) * (2 ^ exponent),
        maxCooldown or MOVEMENT_FAILURE_MAX_COOLDOWN_TICKS
    )
    self:recordFailure(
        tostring(scope or "movement") .. ":" .. movementFailureKind(result),
        ticks,
        cooldown
    )
    return cooldown
end

function Controller:resetMovementRecovery()
    self.movementFailureCount = 0
    self.formationFailureCount = 0
end

function Controller:handleFormationMovementFailure(movement, ticks, companionFollow)
    self.bridge:cancelNpcMove(self.id)
    self.formationFailureCount = (self.formationFailureCount or 0) + 1
    local cooldown = math.min(
        FORMATION_FAILURE_COOLDOWN_TICKS * self.formationFailureCount,
        FORMATION_FAILURE_MAX_COOLDOWN_TICKS
    )
    self:recordFailure(
        "formation_movement:" .. movementFailureKind(movement),
        ticks,
        cooldown
    )
    if companionFollow == nil then
        companionFollow = self.state == "COMPANION_FOLLOW"
    end
    self.regroupMember = nil
    self.formationMovementPace = nil
    self.activeDecision = companionFollow and "follow_player" or "follow_group"
    self.state = companionFollow and "COMPANION_WAIT" or "GROUP_WAIT"
    -- recordFailure owns the retry time. Do not let the ordinary grouped
    -- finishDecision fast path replace this with its five-tick refresh.
    self.nextFormationRefresh = self.nextThink
end

function Controller:waitForFormationBottleneck(movement, ticks)
    self.bridge:cancelNpcMove(self.id)
    self.regroupMember = nil
    self.formationMovementPace = nil
    self.activeDecision = "follow_group"
    self.state = "GROUP_WAIT"
    self:recordFailure(
        "formation_bottleneck:" .. movementFailureKind(movement),
        ticks,
        FORMATION_BOTTLENECK_WAIT_TICKS
    )
    self.nextFormationRefresh = self.nextThink
end

function Controller:updateFormationMovementPace(anchor)
    local pace = formationPace(anchor, self.character)
    if pace == self.formationMovementPace then
        return false
    end
    if self.bridge.setNpcMovementPace == nil
        or not self.bridge:setNpcMovementPace(self.id, pace) then
        return false
    end
    self.formationMovementPace = pace
    return true
end


function Controller:setGroupLeader(id, character, formationSlot, groupSize, objective)
    self.groupLeaderId = id
    self.groupLeader = character
    self.groupFormationSlot = math.max(1, tonumber(formationSlot) or 1)
    self.groupSize = math.max(1, tonumber(groupSize) or 1)
    local objectiveRevision = objective ~= nil and objective.revision or nil
    if objectiveRevision ~= self.groupObjectiveRevision then
        self.groupObjectiveChanged = true
        self.groupObjectiveRevision = objectiveRevision
    end
    self.groupObjective = objective
    if id ~= nil then self:clearLifeIntent() end
end

function Controller:clearGroupLeader()
    self.groupLeaderId = nil
    self.groupLeader = nil
    self.groupFormationSlot = 1
    self.groupSize = 1
    self.groupObjective = nil
    self.groupObjectiveRevision = nil
    self.groupObjectiveChanged = false
    self.nextGroupObjectiveAssist = 0
end

function Controller:setGroupMembers(members)
    self.groupMembers = members or {}
end

function Controller:setGroupObjective(objective)
    local previousKind = self.groupObjective ~= nil
        and tostring(self.groupObjective.kind or "") or nil
    local nextKind = objective ~= nil and tostring(objective.kind or "") or nil
    local changed = nextKind ~= previousKind
        or (objective ~= nil and objective.revision or nil)
            ~= self.groupObjectiveRevision
    self.groupObjective = objective
    self.groupObjectiveRevision = objective ~= nil and objective.revision or nil
    if changed and self.groupLeaderId == nil and objective ~= nil
        and KnoxOrderSignals ~= nil and KnoxOrderSignals.group ~= nil then
        KnoxOrderSignals.group(
            self.character,
            self.groupMembers,
            tostring(objective.kind or "")
        )
    end
end

function Controller.shouldAssistGroupObjective(objective, leaderDistanceSquared)
    if type(objective) ~= "table"
        or tonumber(leaderDistanceSquared) == nil
        or leaderDistanceSquared > GROUP_OBJECTIVE_ASSIST_RADIUS_SQUARED then
        return false
    end
    if objective.kind == "scavenge" then
        return objective.phase == "seeking" or objective.phase == "traveling"
            or objective.phase == "arrived" or objective.phase == "reassess"
    end
    return objective.kind == "investigate_building"
        and (objective.phase == "arrived" or objective.phase == "reassess")
end

function Controller.shouldDelegateNeedToGroup(kind, leaderDistanceSquared)
    return (kind == "find_food" or kind == "find_water" or kind == "find_medical")
        and tonumber(leaderDistanceSquared) ~= nil
        and leaderDistanceSquared <= GROUP_OBJECTIVE_ASSIST_RADIUS_SQUARED
end

function Controller:interruptForDirective()
    self.securityRoute=nil
    self:releaseBaseCooking()
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    if vehicles ~= nil and vehicles.cancel ~= nil then vehicles.cancel(self.character) end
    self:cancelTrade("directive_changed")
    local safe = self.state == "IDLE" or self.state == "ROAMING"
        or self.state == "EVENT_TRAVEL" or self.state == "EVENT_WAIT"
        or self.state == "MOVING_TO_SUPPLY"
        or self.state == "MOVING_TO_EXPLORE"
        or self.state == "GROUP_FOLLOW" or self.state == "GROUP_WAIT"
        or self.state == "GROUP_REGROUP"
        or self.state == "COMPANION_FOLLOW"
        or self.state == "COMPANION_WAIT" or self.state == "COMPANION_HOLD"
        or self.state == "COMPANION_GUARD" or self.state == "COMPANION_RELAX"
        or self.state == "MOVING_TO_COMPANION_POINT"
        or self.state == "MOVING_TO_COMPANION_PATROL"
        or self.state == "COMPANION_PATROL_WAIT"
        or self.state == "COMPANION_DUTY_WAIT" or self.state == "BASE_SECURITY_WAIT"
        or self.state == "BASE_RETURN" or self.state == "BASE_PATROL"
        or self.state == "BASE_IDLE" or self.state == "BASE_AMBIENT_REST"
        or self.state == "CAMP_IDLE" or self.state == "CAMP_AMBIENT_REST"
        or self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION"
        or self.state == "BASE_TASK_MOVE" or self.state == "BASE_TASK_WORK"
        or self.state == "BASE_TASK_PATROL_WAIT"
        or self.state == "BASE_TASK_ACTION"
        or self.state == "BASE_TASK_SUPPLY_MOVE"
        or self.state == "BASE_TASK_SUPPLY_TRANSFER"
        or self.state == "WAITING_TO_RECOVER"
        or self.state == "SLEEPING_RECOVERY"
        or self.state == "INVENTORY_CLEANUP"
        or self.state == "MOVING_TO_DEPOSIT"
    if self.state == "PLAYER_CONVERSATION" or self.state == "BASE_RECREATION" or self.state == "BASE_COOKING" then safe = true end
    if not safe then
        return false
    end
    self.playerConversation = nil
    self:releaseBaseRecreation()
    if self.state == "INVENTORY_CLEANUP" then
        ISTimedActionQueue.clear(self.character)
        self.pendingCleanup = nil
    end
    self.bridge:cancelNpcMove(self.id)
    self.pendingDepositTrip = nil
    self:abandonBaseTask("directive_changed")
    self:releaseSupply()
    self:releaseRestSpot()
    self:leaveRecoveryPosture()
    self.selfCareInterrupted = self.selfCareIntent ~= nil
        and self.activeDecision or self.selfCareInterrupted
    self.selfCareIntent = nil
    self.activeDecision = nil
    self.state = "IDLE"
    self.nextThink = 0
    return true
end

function Controller:setCompanionOrder(ownerId, player, order, formationSlot)
    local normalized = order == "hold" and "hold"
        or (order == "relax" and "relax" or "follow")
    local normalizedSlot = math.max(1, tonumber(formationSlot) or 1)
    local changed = self.companionOwnerId ~= ownerId
        or self.companionTarget ~= player
        or self.companionOrder ~= normalized
        or self.companionFormationSlot ~= normalizedSlot
    self.companionOwnerId = ownerId
    self.companionTarget = player
    self.companionOrder = normalized
    self.companionFormationSlot = normalizedSlot
    if changed then
        self:clearLifeIntent()
        self:interruptForDirective()
    end
end

function Controller:setCompanionCombatStance(stance)
    local normalized = stance == "passive" and "passive"
        or (stance == "aggressive" and "aggressive" or "defensive")
    if self.companionCombatStance == normalized then
        return
    end
    self.companionCombatStance = normalized
    if normalized == "passive" and self.state == "COMBAT" then
        self.bridge:resetNpcCombat(self.id)
        self:releaseCombat()
        self.activeDecision = nil
        self.state = "IDLE"
        self.nextThink = 0
    end
end

function Controller:setWeaponPreference(preference)
    local normalized = (preference == "melee" or preference == "ranged") and preference or "auto"
    if self.weaponPreference == normalized then return end
    self.weaponPreference = normalized
    -- Persistent policies remain authoritative; this mirror only detects a
    -- changed order. End native attack/reload ownership before another weapon.
    local cancelledReload = KnoxFirearmSupport.cancelPreparation(self.character)
    if self.state == "COMBAT" then
        self.bridge:resetNpcCombat(self.id)
        self:releaseCombat()
        self.activeDecision = nil
        self.state = "IDLE"
        self.nextThink = 0
    elseif cancelledReload then
        self.bridge:cancelNpcMove(self.id)
        self:abandonBaseTask("weapon_preference_changed")
        self:releaseSupply()
        self.activeDecision = nil
        self.state = "IDLE"
        self.nextThink = 0
    end
end

function Controller:allowsCompanionThreat(target)
    if target == nil then
        return false
    end
    if not withinCombatRoleLeash(self, target) then
        return false
    end
    if self.companionOrder == nil then
        return true
    end
    if self.companionCombatStance == "passive" then
        return false
    end
    if self.companionCombatStance == "aggressive" then
        return true
    end
    local square = self.character:getCurrentSquare()
    local targetSquare = target:getCurrentSquare()
    if square == nil or targetSquare == nil
        or not targetsGroupMember(self, target:getTarget()) then
        return false
    end
    return distanceSquared(square, targetSquare) <= THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS
end

function Controller:setCompanionPolicy(allowClimbing)
    self.allowClimbing = allowClimbing ~= false
    self.bridge:setNpcClimbingAllowed(self.id, self.allowClimbing)
end

function Controller:setCompanionDirective(directive)
    if directive ~= nil and KnoxPersistence.isValidCompanionDirective ~= nil
        and not KnoxPersistence.isValidCompanionDirective(directive) then
        -- A malformed directive may exist only in an old/corrupt save. Clear
        -- its durable copy once, then let the primary Follow/Hold duty resume.
        KnoxPersistence.clearCompanionDirective(
            self.id,
            self.companionOwnerId,
            getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
        )
        directive = nil
    end
    local current = self.companionDirective
    local changed = (current == nil) ~= (directive == nil)
        or (current ~= nil and directive ~= nil
            and (current.kind ~= directive.kind
                or current.issuedAtHours ~= directive.issuedAtHours
                or current.minX ~= directive.minX
                or current.minY ~= directive.minY
                or current.maxX ~= directive.maxX
                or current.maxY ~= directive.maxY
                or current.z ~= directive.z))
    self.companionDirective = directive
    if changed then
        self.directiveMisses = 0
        self.securityContext,self.securityRoute,self.securityRetryAt=nil,nil,nil
        self:interruptForDirective()
    end
end

function Controller:clearCompanionOrder()
    local changed = self.companionOrder ~= nil or self.companionDirective ~= nil
    if changed then
        self:interruptForDirective()
    end
    self.companionOwnerId = nil
    self.companionTarget = nil
    self.companionOrder = nil
    self.companionCombatStance = "defensive"
    self.companionFormationSlot = 1
    self.companionDirective = nil
end

function Controller:syncBaseSupplyOrder()
    local duty = KnoxPersistence ~= nil and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(self.id) or nil
    local request = duty ~= nil and duty.mode == "base"
        and tostring(duty.baseId or "") == tostring(self.baseId or "")
        and type(duty.baseSupplyOrder) == "table"
        and duty.baseSupplyOrder or nil
    local current = self.baseSupplyOrder
    local changed = (current == nil) ~= (request == nil)
        or (current ~= nil and request ~= nil
            and (current.kind ~= request.kind
                or current.issuedAtHours ~= request.issuedAtHours
                or current.expiresAtHours ~= request.expiresAtHours))
    if changed then
        self.baseSupplyOrder = request
        self.baseSupplyOrderAttempts = request ~= nil
            and math.max(0, math.floor(tonumber(request.attempts) or 0)) or 0
        self.nextThink = 0
    elseif request ~= nil then
        self.baseSupplyOrderAttempts = math.max(
            tonumber(self.baseSupplyOrderAttempts) or 0,
            math.max(0, math.floor(tonumber(request.attempts) or 0))
        )
    end
    return changed
end

function Controller:syncBaseSupplyRun()
    local duty = KnoxPersistence ~= nil and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(self.id) or nil
    local active = duty ~= nil and duty.mode == "base"
        and tostring(duty.baseId or "") == tostring(self.baseId or "")
        and type(duty.activeSupplyRun) == "table"
        and duty.activeSupplyRun or nil
    local kind = active ~= nil and tostring(active.kind or "") or nil
    local changed = kind ~= self.baseSupplyKind
        or (active ~= nil) ~= (self.baseSupplyTrip == true)
    if active ~= nil then
        self.baseSupplyTrip = true
        self.baseSupplyKind = kind
        restoreSupplyClaim(self.baseId, kind, self.id)
    elseif self.pendingBaseSupplyDeposit == nil then
        self.baseSupplyTrip = nil
        self.baseSupplyKind = nil
    end
    return changed
end

function Controller:setBaseAssignment(baseId, base)
    local changed = self.baseId ~= baseId or self.base ~= base
    self.baseId = baseId
    self.base = base
    local supplyOrderChanged = self:syncBaseSupplyOrder()
    self:syncBaseSupplyRun()
    local continuingSupplyOrder = self.baseSupplyOrder ~= nil
        and self.baseSupplyTrip == true
        and self.baseSupplyOrder.kind == self.baseSupplyKind
    if supplyOrderChanged and not continuingSupplyOrder then
        self:releaseSupply()
        self:clearLifeIntent()
        self:interruptForDirective()
    end
    if changed then
        if baseId ~= nil and self.baseSupplyTrip ~= true
            and self.pendingBaseSupplyDeposit == nil then
            self:clearLifeIntent()
        end
        self:interruptForDirective()
    end
end

function Controller:clearBaseAssignment()
    if self.baseId ~= nil then
        self:interruptForDirective()
    end
    if self.baseSupplyKind ~= nil then
        self:releaseBaseSupplyClaim(self.baseSupplyKind)
    end
    self.baseId = nil
    self.base = nil
    self.baseSupplyTrip = nil
    self.baseSupplyKind = nil
end

-- Persistence is authoritative when an order or base preference changes. The
-- runtime notification clears only a stale automatic task pointer immediately;
-- manual Notebook work remains active until its normal completion/cancellation
-- boundary. This keeps the loaded controller aligned with the task board in the
-- same tick as the player-facing change.
function Controller:onDutyChanged()
    if self.pendingRecreation ~= nil then self:interruptForDirective() end
    local duty = KnoxPersistence ~= nil and KnoxPersistence.getSurvivorDuty ~= nil
        and KnoxPersistence.getSurvivorDuty(self.id) or nil
    if duty == nil or duty.mode ~= "base" then
        local hadBaseSupply = self.baseSupplyOrder ~= nil
            or self.baseSupplyTrip == true
            or self.pendingBaseSupplyDeposit ~= nil
        -- Manual work is protected from preference changes while the resident
        -- remains in the same base, but ownership ends when the survivor leaves
        -- base duty altogether. Never carry a stale base task into companion or
        -- independent autonomy.
        if self.baseTask ~= nil then
            self:releaseSupply()
            self.baseTask = nil
            self.baseTaskStartedAt = nil
            self.baseTaskRetryAt = 0
            self:interruptForDirective()
        end
        self.baseSupplyOrder = nil
        self.baseSupplyOrderAttempts = 0
        if hadBaseSupply then
            if self.baseSupplyKind ~= nil then
                self:releaseBaseSupplyClaim(self.baseSupplyKind)
            end
            self:releaseSupply()
            self.pendingBaseSupplyDeposit = nil
            self:clearLifeIntent()
            self:interruptForDirective()
        end
        return true
    end
    local supplyOrderChanged = self:syncBaseSupplyOrder()
    self:syncBaseSupplyRun()
    local continuingSupplyOrder = self.baseSupplyOrder ~= nil
        and self.baseSupplyTrip == true
        and self.baseSupplyOrder.kind == self.baseSupplyKind
    if supplyOrderChanged and not continuingSupplyOrder then
        self:releaseSupply()
        self:clearLifeIntent()
        self:interruptForDirective()
    end
    if self.baseTask ~= nil and self.baseTask.manual ~= true then
        local claimed = KnoxPersistence.getClaimedBaseTaskForSurvivor ~= nil
            and KnoxPersistence.getClaimedBaseTaskForSurvivor(self.id, duty.baseId) or nil
        if claimed == nil or tostring(claimed.id or "") ~= tostring(self.baseTask.id or "") then
            self:releaseSupply()
            self.baseTask = nil
            self.baseTaskStartedAt = nil
            self.baseTaskRetryAt = 0
            self:interruptForDirective()
        end
    end
    self.nextThink = 0
    return true
end

function Controller:setEventAssignment(assignment)
    local old = self.eventAssignment
    local a, b = old ~= nil and old.destination or nil, assignment ~= nil and assignment.destination or nil
    local changed = (old == nil) ~= (assignment == nil)
        or (old ~= nil and assignment ~= nil and (old.id ~= assignment.id or old.phase ~= assignment.phase))
        or (a == nil) ~= (b == nil)
        or (a ~= nil and b ~= nil and (a.x ~= b.x or a.y ~= b.y or a.z ~= b.z))
    self.eventAssignment = assignment
    if changed then
        self.eventMoveFailures = 0
        self:interruptForDirective()
        if assignment == nil then self:clearGroupLeader(); self:setGroupMembers({}) end
    end
end

function Controller:beginEventTravel(ticks)
    local assignment = self.eventAssignment
    if assignment == nil then return false end
    if assignment.phase == "objective" then
        return KnoxEventRuntime.beginObjectiveWork(self, ticks)
    end
    local goal, cell, current = assignment.destination, getCell(), self.character:getCurrentSquare()
    self.activeDecision = assignment.phase == "withdrawing" and "event_return" or "event_travel"
    if goal == nil or cell == nil or current == nil then
        self.state, self.nextThink = "EVENT_WAIT", math.max(self.nextThink or 0, ticks + 120)
        return true
    end
    local dx, dy = goal.x - current:getX(), goal.y - current:getY()
    local distance = dx * dx + dy * dy
    if current:getZ() == goal.z and distance <= 9 then
        self:resetMovementRecovery()
        self.eventMoveFailures = 0
        self.state, self.nextThink = "EVENT_WAIT", ticks + 90
        return true
    end
    if self.groupLeader ~= nil and distance > 36 then
        self:beginGroupFollow(ticks)
        return true
    end
    local distant, separation = self:findDistantGroupMember()
    if distant ~= nil and separation > GROUP_RETRIEVE_LEASH_SQUARED then
        self:beginGroupRegroup(distant, ticks)
        return true
    end
    local target = cell:getGridSquare(math.floor(goal.x), math.floor(goal.y), goal.z)
    local x, y, z = goal.x, goal.y, goal.z
    if target == nil then
        -- Native movement toward the next loaded segment; the population
        -- lifecycle still owns capture and hibernation at the streaming edge.
        local fraction = math.min(1, 12 / math.max(1, math.sqrt(distance)))
        x, y, z = current:getX() + dx * fraction, current:getY() + dy * fraction, current:getZ()
    end
    target = nil
    for radius = 0, 2 do
        for ox = -radius, radius do
            for oy = -radius, radius do
                local square = cell:getGridSquare(math.floor(x) + ox, math.floor(y) + oy, z)
                if square ~= nil and square:canStand() then target = square; break end
            end
            if target ~= nil then break end
        end
        if target ~= nil then break end
    end
    local result = target ~= nil and tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target, "directed"))) or "event_route_unloaded"
    if string.find(result, "MOVE_STARTED", 1, true) == 1 then
        self.state = "EVENT_TRAVEL"
    else
        self.eventMoveFailures = (self.eventMoveFailures or 0) + 1
        self:recordMovementFailure("event_travel", result, ticks, 120)
        self.state = "EVENT_WAIT"
    end
    return true
end

function Controller:releaseCampPosition()
    release(
        self.reservations,
        "campPositions",
        self.campPosition,
        self.id
    )
    self.campPosition = nil
end

function Controller:setCampAssignment(campId, camp, slot)
    local normalizedSlot = math.max(1, tonumber(slot) or 1)
    local changed = self.campId ~= campId or self.camp ~= camp
        or self.campSlot ~= normalizedSlot
    if changed then
        self:releaseCampPosition()
    end
    self.campId = campId
    self.camp = camp
    self.campSlot = normalizedSlot
    if changed then
        self.campPositionCycle = 0
        self.campExcursion = false
        self.campExcursionExplored = false
        self.nextCampExcursion = 0
        if campId ~= nil then self:clearLifeIntent() end
        self:interruptForDirective()
    end
end

function Controller:clearCampAssignment()
    if self.campId == nil then
        return
    end
    self:releaseCampPosition()
    self.campId = nil
    self.camp = nil
    self.campSlot = 1
    self.campPositionCycle = 0
    self.campExcursion = false
    self.campExcursionExplored = false
    self:interruptForDirective()
end

function Controller:setAwayTeam(teamId)
    self.awayTeamId = type(teamId) == "string" and teamId ~= "" and teamId or nil
    self.awayCollected = false
    self.awaySearchMisses = 0
    if self.awayTeamId ~= nil then
        self.activeDecision = "away_mission"
        self.state = "IDLE"
        self.nextThink = 0
    end
end

function Controller:beginAwayReturn(ticks)
    if self.awayTeamId == nil then return false end
    local target = KnoxAwayTeamExecutor.returnDestination(self.awayTeamId)
    if target == nil or getCell == nil or getCell() == nil then
        self:recordFailure("away_return_target_unavailable", ticks, EXPLORATION_RETRY_TICKS)
        return false
    end
    local square = getCell():getGridSquare(
        math.floor(tonumber(target.x) or 0),
        math.floor(tonumber(target.y) or 0),
        math.floor(tonumber(target.z) or 0)
    )
    local canStand = square ~= nil
    if canStand and square.canStand ~= nil then
        local ok, value = pcall(square.canStand, square)
        canStand = ok and value == true
    end
    if not canStand then
        self:recordFailure("away_return_square_unloaded", ticks, EXPLORATION_RETRY_TICKS)
        return false
    end
    local current = self.character:getCurrentSquare()
    if current ~= nil and navigationDistanceSquared(current, square) <= 2.25 then
        local result = KnoxPersistence.completeAwayTeamMember(
            self.awayTeamId, self.id, true, "returned_to_owner", currentWorldAgeHours()
        )
        if result ~= nil then
            self.awayTeamId = nil
            self.awayCollected = false
            self.activeDecision = nil
            self.state = "IDLE"
            self.nextThink = ticks + THINK_MIN_TICKS
            return true
        end
    end
    local movement = tostring(moveWithTravelPace(
        self.bridge, self.id, self.character, square, "return_home"
    ))
    if string.find(movement, "MOVE_STARTED", 1, true) ~= 1 then
        self:recordMovementFailure("away_return", movement, ticks, EXPLORATION_RETRY_TICKS)
        return false
    end
    self.activeDecision = "away_return"
    self.state = "AWAY_RETURN"
    return true
end

function Controller:beginAwayMission(ticks)
    if self.awayTeamId == nil then return false end
    local team = KnoxPersistence.getAwayTeam(self.awayTeamId)
    if team == nil then
        self.awayTeamId = nil
        return false
    end
    if team.state == "returning" then
        return self:beginAwayReturn(ticks)
    end
    if team.state ~= "awaiting_collection" and team.state ~= "collecting" then
        return false
    end
    if self.awayCollected then
        self.activeDecision = "away_waiting_for_team"
        self.state = "GROUP_WAIT"
        self.nextThink = ticks + 120
        return true
    end
    local _, beginResult = KnoxAwayTeamExecutor.beginCollection(
        self.awayTeamId, currentWorldAgeHours()
    )
    if beginResult == "not_collectible" then return false end
    local directive = KnoxAwayTeamExecutor.destinationDirective(team)
    if directive == nil then
        self:recordFailure("away_destination_unavailable", ticks, EXPLORATION_RETRY_TICKS)
        return true
    end
    if self:beginExploration(ticks, directive) then
        self.awaySearchMisses = 0
        return true
    end
    self.awaySearchMisses = (self.awaySearchMisses or 0) + 1
    if self.awaySearchMisses >= 3 then
        KnoxAwayTeamExecutor.recordCollection(
            self.awayTeamId, self.id, {}, self.character, currentWorldAgeHours()
        )
        self.awayCollected = true
        self.awaySearchMisses = 0
        self.nextThink = ticks + 120
    end
    return true
end

-- A loaded away member acknowledges a destination only after the ordinary
-- search/transfer action has finished.  This keeps mission results tied to
-- real inventory state and lets the persistence layer hold the group until
-- every member has completed the same boundary.
function Controller:finishAwayCollection(ticks)
    if self.awayTeamId == nil then return false end
    local supply = self.pendingSupply
    local recorded, detail = KnoxAwayTeamExecutor.recordCollection(
        self.awayTeamId,
        self.id,
        supply,
        self.character,
        currentWorldAgeHours()
    )
    self:releaseSupply()
    if recorded == nil then
        self:recordFailure(
            "away_collection_record:" .. tostring(detail),
            ticks,
            EXPLORATION_RETRY_TICKS
        )
        self.state = "IDLE"
        self.activeDecision = "away_collection_retry"
        self.nextThink = ticks + EXPLORATION_RETRY_TICKS
        return true
    end
    self.awayCollected = true
    self.awaySearchMisses = 0
    if KnoxAwayTeamExecutor.collectionReady(self.awayTeamId) then
        local _, returnResult = KnoxAwayTeamExecutor.beginReturn(
            self.awayTeamId,
            currentWorldAgeHours()
        )
        if returnResult == "returning" then
            self.awayCollected = false
            self.activeDecision = "away_return_pending"
            self.state = "IDLE"
            self.nextThink = ticks
            return true
        end
        self:recordFailure(
            "away_return_begin:" .. tostring(returnResult),
            ticks,
            EXPLORATION_RETRY_TICKS
        )
    end
    self.activeDecision = "away_waiting_for_team"
    self.state = "GROUP_WAIT"
    self.nextThink = ticks + 120
    return true
end

function Controller:setFactionBaseCandidate(factionId, candidate)
    self.factionId = factionId
    self.factionBaseCandidate = candidate
end

function Controller:clearFactionBaseCandidate()
    self.factionId = nil
    self.factionBaseCandidate = nil
end

function Controller:rejectFactionBaseCandidate(ticks, reason)
    local candidate = self.factionBaseCandidate
    local worldAge = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    if candidate ~= nil then
        KnoxPersistence.rejectFactionBaseCandidate(
            self.factionId,
            candidate.buildingId,
            worldAge
        )
    end
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " faction-base-rejected reason=" .. tostring(reason)
    )
    self:clearFactionBaseCandidate()
end

function Controller:findDistantGroupMember()
    local square = self.character:getCurrentSquare()
    if square == nil then
        return nil, nil
    end
    local farthest = nil
    local farthestDistance = GROUP_SOFT_LEASH_SQUARED
    for _, member in ipairs(self.groupMembers or {}) do
        local dead = member ~= nil and member.isDead ~= nil and member:isDead()
        if member ~= nil and not dead and member ~= self.character
            and member:getCurrentSquare() ~= nil then
            local memberSquare = member:getCurrentSquare()
            local distance = memberSquare:getZ() == square:getZ()
                and distanceSquared(square, memberSquare)
                or GROUP_RETRIEVE_LEASH_SQUARED + 1
            if distance > farthestDistance then
                farthest = member
                farthestDistance = distance
            end
        end
    end
    return farthest, farthest ~= nil and farthestDistance or nil
end

function Controller:sayNeedIfGrouped(decision, ticks)
    local grouped = self.companionTarget ~= nil
        or self.groupLeader ~= nil
        or #(self.groupMembers or {}) > 1
    if not grouped or ticks < self.nextNeedCallout then
        return
    end
    local lines = {
        find_food = "I'm nearly out of food.",
        find_water = "I need water soon.",
        find_medical = "I need something for this wound.",
        eat = "Give me a second to eat.",
        drink = "I need a second to drink.",
        bandage = "Hold on, I need to patch this up.",
        improvise_medical = "I need to make something for this wound.",
        rest = "I need to sit down for a minute.",
        sleep = "I need to get some sleep.",
    }
    local line = lines[decision]
    if line ~= nil then
        KnoxActivityFeed.speak(self.character, line)
        self.nextNeedCallout = ticks + 1800
    end
end

function Controller:sayAction(lines, ticks, cooldown)
    local spoken = sayDialogue(self.character, self.id, "action",
        ticks, cooldown, lines)
    if spoken then
        self.nextActionCallout = ticks + math.max(900, tonumber(cooldown) or 1800)
    end
    return spoken
end

function Controller:canInterruptForMeeting()
    if self.character == nil or self.baseTask ~= nil or self.tradeAction ~= nil
        or nativeTraversalBusy(self.character) then return false end
    local resting = (self.state == "WAITING_TO_RECOVER" or self.state == "BASE_AMBIENT_REST")
        and (self.activeDecision == "rest" or self.activeDecision == "sleep"
            or self.activeDecision == "base_ambient_rest")
    if not self.character:getCharacterActions():isEmpty() and not resting then return false end
    return self.state == "IDLE"
        or self.state == "ROAMING"
        or self.state == "MOVING_TO_SUPPLY"
        or self.state == "MOVING_TO_EXPLORE"
        or self.state == "WAITING_TO_RECOVER"
        or self.state == "GROUP_WAIT"
        or self.state == "GROUP_FOLLOW"
        or self.state == "BASE_IDLE"
        or self.state == "BASE_AMBIENT_REST"
end

-- Player conversation takes a short, interruptible attention lease. It does
-- not rewrite Follow/Hold/base/group duty or take over an active native job.
function Controller:beginPlayerConversation(player)
    local ticks = self.currentTicks or 0
    local extraState = self.state == "COMPANION_FOLLOW" or self.state == "COMPANION_WAIT"
        or self.state == "COMPANION_HOLD" or self.state == "COMPANION_GUARD"
        or self.state == "CAMP_IDLE" or self.state == "CAMP_REPOSITION"
        or self.state == "BASE_PATROL"
    if player == nil or self.character == nil or self.baseTask ~= nil
        or self.tradeAction ~= nil or nativeTraversalBusy(self.character)
        or not (self:canInterruptForMeeting() or extraState)
        or not self.character:getCharacterActions():isEmpty()
        or safeMethod(self.character, "getVehicle", nil) ~= nil
        or safeMethod(player, "getVehicle", nil) ~= nil then return false, "survivor_busy" end
    local current, target = self.character:getCurrentSquare(), player:getCurrentSquare()
    if current == nil or target == nil or current:getZ() ~= target:getZ()
        or distanceSquared(current, target) > 16 then return false, "too_far_away" end
    if safeMethod(self.character, "CanSee", false, player) ~= true then
        return false, "not_visible"
    end
    if fleeAssessment(self) or nearestThreat(self, ticks) ~= nil then return false, "danger" end
    self.bridge:cancelNpcMove(self.id)
    self:releaseSupply()
    self:leaveRecoveryPosture()
    self.playerConversation = { player = player, untilTick = ticks + 600 }
    self.state, self.activeDecision = "PLAYER_CONVERSATION", "talk_to_player"
    self.nextThreatScan = 0
    safeMethod(self.character, "faceThisObject", nil, player)
    return true, "talking"
end

function Controller:endPlayerConversation(player)
    if self.playerConversation == nil or self.playerConversation.player ~= player then return false end
    self.playerConversation = nil
    if self.state == "PLAYER_CONVERSATION" then
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, 0
    end
    return true
end

function Controller:updatePlayerConversation(ticks)
    local conversation = self.playerConversation
    if conversation == nil then
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, 0
        return
    end
    local player = conversation.player
    local square = player ~= nil and player:getCurrentSquare() or nil
    local current = self.character:getCurrentSquare()
    local ended = ticks >= conversation.untilTick or square == nil or current == nil
        or safeMethod(player, "isDead", true) == true
        or safeMethod(player, "getVehicle", nil) ~= nil
        or square:getZ() ~= current:getZ() or distanceSquared(current, square) > 25
    if not ended and ticks >= (conversation.nextNeedsCheck or 0) then
        conversation.nextNeedsCheck = ticks + 60
        local decision = KnoxSurvivorNeeds.decide(self.character, nil)
        ended = decision ~= nil and decision.kind ~= "roam"
    end
    if ended then self:endPlayerConversation(player) end
end

function Controller:beginTrade(action)
    if type(action) ~= "table" or action.npc ~= self.character
        or self.tradeAction ~= nil or self.character == nil or nativeTraversalBusy(self.character)
        or not self.character:getCharacterActions():isEmpty() or self.baseTask ~= nil
        or not (self:canInterruptForMeeting() or self.state == "BASE_IDLE" or self.state == "CAMP_IDLE") then
        return false
    end
    if fleeAssessment(self) or nearestThreat(self, self.nextThreatScan or 0) ~= nil then return false end
    self.bridge:cancelNpcMove(self.id)
    self:releaseSupply()
    self:leaveRecoveryPosture()
    self.tradeAction, self.tradeTicksRemaining = action, action.browsing and 7200 or 1800
    self.state, self.activeDecision = "TRADING", "trade"
    self.nextThreatScan = 0
    return true
end

function Controller:releaseTrade(action)
    if self.tradeAction ~= action then return false end
    self.tradeAction, self.tradeTicksRemaining = nil, nil
    if self.state == "TRADING" then
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, 0
    end
    return true
end

function Controller:cancelTrade(reason)
    local action = self.tradeAction
    if action == nil then return end
    self:releaseTrade(action)
    action.cancelled = reason
end

function Controller:interruptForMeeting()
    if not self:canInterruptForMeeting() then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self:releaseSupply()
    if self.activeDecision == "rest" or self.activeDecision == "sleep"
        or self.activeDecision == "base_ambient_rest" then
        -- This state owns the queued rest action. Stop it before releasing its
        -- furniture reservation, so the subsequent approach can actually move.
        if not self.character:getCharacterActions():isEmpty() then
            ISTimedActionQueue.clear(self.character)
        end
        self:leaveRecoveryPosture()
    end
    self.selfCareInterrupted = self.selfCareIntent ~= nil
        and self.activeDecision or self.selfCareInterrupted
    self.selfCareIntent = nil
    self.activeDecision = "meet_survivor"
    self.state = "MEETING_WAIT"
    return true
end

function Controller:beginMeetingApproach(otherCharacter)
    if self.state ~= "MEETING_WAIT" or otherCharacter == nil
        or otherCharacter:getCurrentSquare() == nil then
        return false
    end
    local approach = AdjacentFreeTileFinder.Find(
        otherCharacter:getCurrentSquare(),
        self.character
    )
    if approach == nil then
        return false
    end
    local result = tostring(self.bridge:moveNpc(self.id, approach))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    self.state = "MEETING_APPROACH"
    return true
end

function Controller:beginGreeting()
    self.bridge:cancelNpcMove(self.id)
    self.state = "GREETING"
end

function Controller:resumeAfterGreeting(ticks)
    self.activeDecision = nil
    self.state = "IDLE"
    self.nextThink = ticks + THINK_MIN_TICKS
end

function Controller:holdForRobbery(ticks)
    self.activeDecision = nil
    self.state = "GROUP_WAIT"
    self.nextThink = ticks + 300
end

function Controller:beginRobbery(victim, ticks)
    if victim == nil or victim:getInventory() == nil then
        return false
    end
    local candidates = {}
    -- Robbers use the same needs/upgrades filter as ordinary looting. This keeps
    -- the encounter grounded and prevents filler such as grass or trash from
    -- winning a transfer slot merely because the victim happened to carry it.
    for _, candidate in ipairs(KnoxSurvivorLooting.plan(
        self.character,
        victim:getInventory(),
        4
    )) do
        if not victim:isEquipped(candidate.item) and not candidate.item:isFavorite() then
            candidates[#candidates + 1] = candidate
        end
    end
    local queued = {}
    for index = 1, math.min(2, #candidates) do
        local candidate = candidates[index]
        local action = KnoxInventoryActions.queueTransfer(
            self.character,
            candidate.item,
            victim:getInventory(),
            self.character:getInventory(),
            nil
        )
        if action ~= nil then
            queued[#queued + 1] = candidate.item:getFullType()
        end
    end
    if #queued == 0 then
        return false
    end
    self.pendingRobbery = { victim = victim, items = queued }
    self.activeDecision = "rob_survivor"
    self.state = "ROBBING"
    self.stateStartedAt = ticks
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=ROBBING items=" .. table.concat(queued, ",")
    )
    return true
end

function Controller:beginGroupFollow(ticks)
    if self.groupLeader == nil or self.groupLeader:getCurrentSquare() == nil then
        return false
    end
    local approach = findFormationTarget(
        self.groupLeader,
        self.character,
        self.groupFormationSlot, self.id
    )
    if approach == nil then
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        return false
    end
    local moveResult, pace = moveWithFormationPace(
        self.bridge,
        self.id,
        approach,
        self.groupLeader,
        self.character
    )
    local result = tostring(moveResult)
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:handleFormationMovementFailure(result, ticks, false)
        return false
    end
    self.activeDecision = "follow_group"
    self.state = "GROUP_FOLLOW"
    self.stateStartedAt = ticks
    self.formationTargetX = approach:getX()
    self.formationTargetY = approach:getY()
    self.formationTargetZ = approach:getZ()
    self.formationMovementPace = pace
    self.formationCommitUntil = ticks + FORMATION_ROUTE_COMMIT_TICKS
    self.nextFormationRefresh = ticks + FORMATION_REFRESH_TICKS
        + formationRefreshDelay(self.groupFormationSlot)
    return true
end

function Controller:beginGroupRegroup(member, ticks)
    local memberSquare = member ~= nil and member:getCurrentSquare() or nil
    if memberSquare == nil then
        return false
    end
    local approach = AdjacentFreeTileFinder.Find(memberSquare, self.character)
    if approach == nil then
        return false
    end
    local moveResult = moveWithFormationPace(
        self.bridge,
        self.id,
        approach,
        member,
        self.character
    )
    local result = tostring(moveResult)
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:handleFormationMovementFailure(result, ticks, false)
        return false
    end
    self:signalFollowers("comehere", ticks)
    self.regroupMember = member
    self.activeDecision = "retrieve_group_member"
    self.state = "GROUP_REGROUP"
    self.stateStartedAt = ticks
    if ticks >= self.nextRegroupCallout then
        sayDialogue(self.character, self.id, "regroup", ticks, 1800)
        self.nextRegroupCallout = ticks + 1800
    end
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=GROUP_REGROUP target=" .. tostring(member)
    )
    return true
end

function Controller:beginCompanionFollow(ticks)
    if self.companionOrder ~= "follow" then
        return false
    end
    if self.companionTarget == nil
        or self.companionTarget:getCurrentSquare() == nil then
        self.state = "COMPANION_WAIT"
        self.nextThink = ticks + 60
        return false
    end
    local approach = findFormationTarget(
        self.companionTarget,
        self.character,
        self.companionFormationSlot, self.id
    )
    if approach == nil then
        self.state = "COMPANION_WAIT"
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        return false
    end
    local moveResult, pace = moveWithFormationPace(
        self.bridge,
        self.id,
        approach,
        self.companionTarget,
        self.character
    )
    local result = tostring(moveResult)
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:handleFormationMovementFailure(result, ticks, true)
        return false
    end
    self.activeDecision = "follow_player"
    self.state = "COMPANION_FOLLOW"
    self.stateStartedAt = ticks
    self.formationTargetX = approach:getX()
    self.formationTargetY = approach:getY()
    self.formationTargetZ = approach:getZ()
    self.formationMovementPace = pace
    self.formationCommitUntil = ticks + FORMATION_ROUTE_COMMIT_TICKS
    self.nextFormationRefresh = ticks + FORMATION_REFRESH_TICKS
    return true
end

function Controller:refreshFormationFollow(ticks)
    if ticks < self.nextFormationRefresh then
        return false
    end
    local groupFollow = self.state == "GROUP_FOLLOW"
    local slot = groupFollow and self.groupFormationSlot or self.companionFormationSlot
    if not groupFollow and self.companionOrder ~= "follow" then
        self.bridge:cancelNpcMove(self.id)
        self.formationMovementPace = nil
        self.activeDecision = self.companionOrder == "hold"
            and "hold_position" or nil
        self.state = self.companionOrder == "hold"
            and "COMPANION_HOLD" or "COMPANION_WAIT"
        self.nextThink = ticks + FORMATION_REFRESH_TICKS
            + formationRefreshDelay(slot)
        return true
    end
    local anchor = groupFollow and self.groupLeader or self.companionTarget
    local target = findFormationTarget(anchor, self.character, slot, self.id)
    local current = self.character:getCurrentSquare()
    self.nextFormationRefresh = ticks + FORMATION_REFRESH_TICKS
        + (groupFollow and formationRefreshDelay(slot) or 0)
    if target == nil or current == nil then
        return false
    end
    if navigationDistanceSquared(current, target)
        <= FORMATION_ARRIVAL_TOLERANCE_SQUARED then
        self.bridge:cancelNpcMove(self.id)
        self:resetMovementRecovery()
        self.formationMovementPace = nil
        self.formationCommitUntil = 0
        self.activeDecision = groupFollow and "follow_group" or "follow_player"
        self.state = groupFollow and "GROUP_WAIT" or "COMPANION_WAIT"
        self.nextThink = ticks + FORMATION_REFRESH_TICKS
            + (groupFollow and formationRefreshDelay(slot) or 0)
        return true
    end
    self:updateFormationMovementPace(anchor)
    local shifted = self.formationTargetZ ~= target:getZ()
        or self.formationTargetX == nil or self.formationTargetY == nil
        or (self.formationTargetX - target:getX()) ^ 2
            + (self.formationTargetY - target:getY()) ^ 2
                > FORMATION_REPATH_SHIFT_SQUARED
    if not shifted then
        return false
    end
    if ticks < (self.formationCommitUntil or 0) and self.formationTargetZ == target:getZ() then
        return false
    end
    local restarted
    if groupFollow then
        restarted = self:beginGroupFollow(ticks)
    else
        restarted = self:beginCompanionFollow(ticks)
    end
    if not restarted then
        self.state = groupFollow and "GROUP_WAIT" or "COMPANION_WAIT"
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
    end
    return true
end

function Controller:findBaseMovementTarget(returning, ticks)
    local home = self.base ~= nil and self.base.home or nil
    local cell = getCell()
    if home == nil or cell == nil then
        return nil
    end
    local z = tonumber(home.z) or 0
    if returning then
        local centerX = math.floor((tonumber(home.minX) or 0)
            + (tonumber(home.width) or 1) / 2)
        local centerY = math.floor((tonumber(home.minY) or 0)
            + (tonumber(home.height) or 1) / 2)
        local anchors = {
            { x = math.floor(tonumber(home.x) or centerX),
                y = math.floor(tonumber(home.y) or centerY) },
            { x = centerX, y = centerY },
        }
        for _, anchor in ipairs(anchors) do
            for radius = 0, 8 do
                for dx = -radius, radius do
                    for dy = -radius, radius do
                        if radius == 0 or math.max(math.abs(dx), math.abs(dy)) == radius then
                            local square = cell:getGridSquare(
                                anchor.x + dx,
                                anchor.y + dy,
                                z
                            )
                            if square ~= nil and square:canStand() then
                                return square
                            end
                        end
                    end
                end
            end
        end
        return nil
    end
    local current = self.character:getCurrentSquare()
    if current==nil or not KnoxBaseManager.containsSquare(self.base,current) then return nil end
    local hour = getGameTime ~= nil and getGameTime():getTimeOfDay() or 12
    local daylight = hour >= 7 and hour < 20
    local area = self.base.territory or home
    local minX,minY=tonumber(area.minX),tonumber(area.minY)
    if minX==nil or minY==nil then return nil end
    local maxX=tonumber(area.maxX) or (minX+math.max(1,tonumber(area.width) or 1)-1)
    local maxY=tonumber(area.maxY) or (minY+math.max(1,tonumber(area.height) or 1)-1)
    z=current:getZ()
    self.ambientMovementArea={minX=minX,minY=minY,maxX=maxX,maxY=maxY,z=z}
    -- A leisure walk is a short change of spot. It must not choose the other
    -- side of a large territory or use a different floor just to pass time.
    minX,maxX=math.max(minX,current:getX()-6),math.min(maxX,current:getX()+6)
    minY,maxY=math.max(minY,current:getY()-6),math.min(maxY,current:getY()+6)
    local width,height=math.floor(maxX-minX+1),math.floor(maxY-minY+1)
    if width<1 or height<1 then return nil end
    ticks=tonumber(ticks) or 0
    -- Keep the indoor/yard preference for two minutes, staggered per resident.
    -- It is a preference: a blocked yard does not force repeated door attempts.
    local preferOutside=daylight and (math.floor(ticks/7200)+Controller.baseIdleJitter(self.id))%4==0
    local currentOutside=safeMethod(current,"getRoom",nil)==nil
    local best,bestScore=nil,-math.huge
    for _=1,24 do
        local square=cell:getGridSquare(minX+ZombRand(width),minY+ZombRand(height),z)
        local distance=square~=nil and navigationDistanceSquared(current,square) or math.huge
        local moving=safeMethod(square,"getMovingObjects",nil)
        local outside=safeMethod(square,"getRoom",nil)==nil
        local suitable=square~=nil and square:canStand() and distance>=4 and distance<=36
            and KnoxBaseManager.containsSquare(self.base,square)
            and moving~=nil and moving:size()==0 and (daylight or not outside)
        if suitable and self.lastAmbientOrigin~=nil and ticks<(self.lastAmbientOriginUntil or 0)
            and navigationDistanceSquared(square,self.lastAmbientOrigin)==0 then suitable=false end
        if suitable then
            -- Reuse perceived danger; no extra world/zombie scan per idle tile.
            for threat,memory in pairs(self.perceivedThreats or {}) do
                local threatSquare=safeMethod(threat,"getCurrentSquare",nil)
                if ticks-(memory.lastSeen or 0)<=THREAT_MEMORY_TICKS
                    and not safeMethod(threat,"isDead",true)
                    and navigationDistanceSquared(square,threatSquare)<=36 then suitable=false;break end
            end
        end
        if suitable then
            local score=(outside==preferOutside and 100 or 0)+(outside==currentOutside and 20 or 0)
                - math.abs(distance-16)
            if score>bestScore then best,bestScore=square,score end
        end
    end
    return best
end

function Controller:beginBaseMovement(ticks, returning)
    if not returning and ticks < (self.nextAmbientMoveAt or 0) then
        self.activeDecision, self.state = "base_idle", "BASE_IDLE"
        self.nextThink = ticks + 180
        return false
    end
    if not returning then self.nextAmbientMoveAt = ticks + 1800 end
    local target = self:findBaseMovementTarget(returning,ticks)
    if target == nil then
        self.activeDecision = "base_idle"
        self.state = "BASE_IDLE"
        self.nextThink = ticks + 120
        return false
    end
    if not returning then
        self.reservations = self.reservations or {}
        self.reservations.ambientSpots = self.reservations.ambientSpots or {}
        local spotKey = ambientSpotKey(target)
        if spotKey == nil or not reserve(
            self.reservations, "ambientSpots", spotKey, self.id
        ) then
            self.activeDecision = "base_idle"
            self.state = "BASE_IDLE"
            self.nextThink = ticks + 120
            return false
        end
        self.ambientMovementTarget = spotKey
    end
    if self.character:isSitOnGround() or self.character:isSittingOnFurniture() then
        self:leaveRecoveryPosture()
    end
    local result
    if returning then
        result=tostring((moveWithTravelPace(self.bridge,self.id,self.character,target,"return_home")))
    else
        result=tostring(KnoxCompanionPatrol.move(self.bridge,self.id,target,self.ambientMovementArea))
    end
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        if not returning then
            release(self.reservations, "ambientSpots",
                self.ambientMovementTarget, self.id)
            self.ambientMovementTarget = nil
        end
        self.activeDecision = "base_idle"
        self.state = "BASE_IDLE"
        self.nextThink = ticks + 120
        return false
    end
    if not returning then
        self.lastAmbientOrigin=self.character:getCurrentSquare()
        self.lastAmbientOriginUntil=ticks+7200
    end
    self.activeDecision = returning and "return_to_base" or "patrol_base"
    self.state = returning and "BASE_RETURN" or "BASE_PATROL"
    return true
end

function Controller:releaseAmbientMovement()
    if self.ambientMovementTarget ~= nil then
        self.reservations = self.reservations or {}
        self.reservations.ambientSpots = self.reservations.ambientSpots or {}
        release(self.reservations, "ambientSpots",
            self.ambientMovementTarget, self.id)
        self.ambientMovementTarget = nil
    end
end

function Controller:finishBaseTask(succeeded, reason)
    self.securityRoute=nil
    self:releaseBaseCooking()
    local task = self.baseTask
    if task == nil then
        return false
    end
    local baseId = task.baseId or self.baseId
    local finished, result = KnoxBaseTaskBoard.finish(
        baseId,
        task.id,
        self.id,
        succeeded == true,
        reason
    )
    if finished == nil then
        print("[KnoxSurvivors][BaseJobs] finish-failed id=" .. tostring(self.id)
            .. " task=" .. tostring(task.id) .. " result=" .. tostring(result))
    end
    self.baseTask = nil
    self.baseTaskStartedAt = nil
    self.baseTaskSupplyTransfer = nil
    self.baseResupplyAttempts = 0
    self.baseTaskActionQueued = false
    self.baseTaskBarricadeTarget = nil
    self.baseTaskBarricadeBefore = 0
    self.baseTaskFarmingTarget = nil
    self.baseTaskFarmingBefore = nil
    self.baseTaskWoodcuttingTarget = nil
    self.baseTaskWoodcuttingBefore = nil
    self.baseTaskCorpseTarget = nil
    self.baseTaskCorpsePhase = nil
    self.baseTaskCorpseGrabVerifyUntil = nil
    self.baseTaskCorpseGrabRetryIssued = nil
    self.baseTaskCorpseDropVerifyUntil = nil
    self.baseTaskCorpseDropRetryIssued = nil
    self.baseTaskAnimalTarget = nil
    self.baseTaskAnimalBefore = nil
    self.baseTaskRepairTarget = nil
    self.baseTaskRepairBefore = nil
    self.baseTaskConstructionTarget = nil
    return finished ~= nil
end

function Controller:abandonBaseTask(reason)
    self:releaseBaseCooking()
    if self.baseTask == nil then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    if self.character ~= nil and KnoxBaseCorpseHandling.isDragging(self.character) then
        pcall(function() self.character:setDoGrappleLetGo() end)
    end
    local abandoned = self:finishBaseTask(false, reason or "interrupted")
    self.activeDecision = nil
    return abandoned
end

-- Combat and retreat are temporary preemptions, not task failures. Keep the
-- claimed task attached to this controller so the resident can resume it once
-- danger clears; the persisted claim is still recovered normally if the body
-- unloads or dies. Explicit cancellation, invalid targets, and real action
-- failures continue through abandonBaseTask/finishBaseTask as before.
function Controller:suspendBaseTaskForThreat(reason)
    self.securityRoute=nil
    self:releaseBaseCooking()
    if self.baseTask == nil then return false end
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self:releaseSupply()
    self.baseTaskRetryAt = 0
    self.baseTaskStartedAt = nil
    self.baseTaskActionQueued = false
    if self.character ~= nil and KnoxBaseCorpseHandling.isDragging(self.character) then
        pcall(function() self.character:setDoGrappleLetGo() end)
    end
    self.baseTaskBarricadeTarget = nil
    self.baseTaskFarmingTarget = nil
    self.baseTaskFarmingBefore = nil
    self.baseTaskWoodcuttingTarget = nil
    self.baseTaskWoodcuttingBefore = nil
    self.baseTaskCorpseTarget = nil
    self.baseTaskCorpsePhase = nil
    self.baseTaskCorpseGrabVerifyUntil = nil
    self.baseTaskCorpseGrabRetryIssued = nil
    self.baseTaskCorpseDropVerifyUntil = nil
    self.baseTaskCorpseDropRetryIssued = nil
    self.baseTaskAnimalTarget = nil
    self.baseTaskAnimalBefore = nil
    self.baseTaskRepairTarget = nil
    self.baseTaskRepairBefore = nil
    self.baseTaskConstructionTarget = nil
    if self.baseTask ~= nil then
        self.baseTask.interruptedReason = tostring(reason or "threat")
    end
    return true
end

function Controller:updateBaseSecurityDuty(ticks)
    local task = self.baseTask
    if task == nil or (task.type ~= "guard" and task.type ~= "patrol") then return end
    if ticks < (self.nextSecurityCheck or 0) then return end
    self.nextSecurityCheck = ticks + 90
    local target = task.target or {}
    local zoneId = target.autoZoneId or target.zoneId
    local zone = zoneId ~= nil and self.base ~= nil and self.base.zones ~= nil
        and self.base.zones[zoneId] or nil
    if task.state ~= "claimed" or task.claimedBy ~= self.id then
        self.bridge:cancelNpcMove(self.id)
        self.baseTask = nil
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, ticks
        return
    end
    if zoneId ~= nil and (zone == nil or zone.enabled == false) then
        self:abandonBaseTask("security_area_released")
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, ticks
        return
    end
    local decision = KnoxSurvivorNeeds.decide(self.character, nil)
    if decision ~= nil and decision.kind ~= "roam" then
        self:suspendBaseTaskForThreat("needs_interrupt")
        self.state, self.activeDecision, self.nextThink = "IDLE", nil, ticks
        return
    end
    if task.type == "guard" and self.state~="BASE_SECURITY_WAIT" then
        local post = KnoxBaseJobs.resolveTaskSquare(task, self.character)
        local current = self.character:getCurrentSquare()
        if post ~= nil and navigationDistanceSquared(current, post) > 2.25 then
            self:beginBaseTaskWorkMove(ticks)
        end
    end
end

function Controller:beginBaseTaskWorkMove(ticks)
    local task = canonicalBaseTask(self.baseTask)
    self.baseTask = task
    if task~=nil and (task.type=="guard" or task.type=="patrol") then
        return self:beginSecurityRoute(ticks,task,true)
    end
    local target = task ~= nil and KnoxBaseJobs.resolveTaskSquare(task, self.character) or nil
    if target == nil then
        self:finishBaseTask(false, "no_loaded_work_square")
        self:recordFailure("base_task_target", ticks, 180)
        return false
    end
    local moveResult = tostring(self.bridge:moveNpc(self.id, target))
    if string.find(moveResult, "MOVE_STARTED", 1, true) ~= 1 then
        self:finishBaseTask(false, "task_move_start_failed:" .. moveResult)
        self:recordMovementFailure("base_task_move", moveResult, ticks)
        return false
    end
    self.baseTaskStartedAt = nil
    self.activeDecision = "base_task_" .. tostring(task.type)
    self.state = "BASE_TASK_MOVE"
    print("[KnoxSurvivors][BaseJobs] id=" .. tostring(self.id)
        .. " task=" .. tostring(task.id) .. " type=" .. tostring(task.type)
        .. " target=" .. tostring(target:getX()) .. "," .. tostring(target:getY()))
    return true
end

-- A resident first gathers one required item at a time from assigned, currently
-- loaded base storage.  The actual move remains a normal inventory transfer;
-- missing or streamed-out material blocks the task instead of inventing stock.
function Controller:beginBaseTaskSupplyOrWork(ticks)
    if self.baseTask ~= nil and self.baseTask.type == "cook" then
        if self:beginBaseCooking(ticks,self.baseTask.target,false) then return true end
        self:finishBaseTask(false,"cooking_start_unavailable")
        return false
    end
    local transfer, result = KnoxBaseStorage.findRequiredTransfer(
        self.base,
        self.character,
        self.baseTask ~= nil and self.baseTask.requirements or nil
    )
    if transfer == nil then
        if result == "requirements_ready" then
            return self:beginBaseTaskWorkMove(ticks)
        end
        if self:beginBaseResourceRun(ticks, tostring(result)) then
            return true
        end
        if (self.baseResupplyAttempts or 0) < 3 then
            self.baseTaskRetryAt = ticks + SUPPLY_RETRY_TICKS
            self.activeDecision = "base_task_supply_wait"
            self.state = "BASE_TASK_SUPPLY_WAIT"
            self.nextThink = self.baseTaskRetryAt
            return true
        end
        self:finishBaseTask(false, tostring(result))
        KnoxActivityFeed.speak(self.character, "We're missing supplies for that job.")
        KnoxActivityFeed.event("Base job blocked: " .. tostring(result) .. ".")
        self:recordFailure("base_task_supply:" .. tostring(result), ticks, 300)
        return false
    end
    local approach = KnoxBaseStorage.approachSquare(transfer, self.character)
    if approach == nil then
        self:finishBaseTask(false, "storage_approach_unavailable")
        self:recordFailure("base_task_supply:storage_approach_unavailable", ticks, 300)
        return false
    end
    local moveResult = tostring(self.bridge:moveNpc(self.id, approach))
    if string.find(moveResult, "MOVE_STARTED", 1, true) ~= 1 then
        self:finishBaseTask(false, "storage_move_start_failed:" .. moveResult)
        self:recordMovementFailure("base_task_supply_move", moveResult, ticks, 300)
        return false
    end
    self.baseTaskSupplyTransfer = transfer
    self.baseTaskStartedAt = nil
    self.activeDecision = "base_task_collect_supplies"
    self.state = "BASE_TASK_SUPPLY_MOVE"
    return true
end

-- A blocked base task must not become a generic world scavenging mission.
-- Supplies for a claimed base job come from the assigned central storage; if
-- they are absent, keep the claim briefly and let the normal retry window give
-- the player or another worker time to stock it.  Sending the worker to the
-- nearest matching container was a major source of apparently random trips,
-- especially when a tool or part was missing from the cupboard.
function Controller:beginBaseResourceRun(ticks, reason)
    local task = self.baseTask
    if task == nil or self.base == nil or (self.baseResupplyAttempts or 0) >= 3 then
        return false
    end
    self.baseResupplyAttempts = (self.baseResupplyAttempts or 0) + 1
    self.baseTaskRetryAt = ticks + SUPPLY_RETRY_TICKS
    self.activeDecision = "base_task_supply_wait"
    self.state = "BASE_TASK_SUPPLY_WAIT"
    self.nextThink = self.baseTaskRetryAt
    if ticks >= (self.nextSupplySpeech or 0) then
        KnoxActivityFeed.speak(self.character, "I need the supplies brought to the base cupboard first.")
        self.nextSupplySpeech = ticks + 3600
    end
    return true
end

function Controller:continueBaseResourceRun(ticks, succeeded)
    self:releaseSupply()
    if not succeeded then
        self.baseResupplyAttempts = (self.baseResupplyAttempts or 0) + 1
    end
    if self.baseTask == nil then
        self:finishDecision(ticks)
        return false
    end
    if (self.baseResupplyAttempts or 0) >= 3 then
        self:finishBaseTask(false, "missing_required_materials_after_search")
        KnoxActivityFeed.speak(self.character, "I couldn't find the supplies for that job.")
        self:finishDecision(ticks)
        return false
    end
    if self:beginBaseTaskSupplyOrWork(ticks) then return true end
    self:finishDecision(ticks)
    return false
end

-- Resume the same duty after danger, or chain work while already in a work
-- area. Pending deliveries and explicit supply orders retain their home trip.
function Controller:resumeExternalBaseWork(ticks)
    if self.pendingBaseSupplyDeposit ~= nil or self.baseSupplyOrder ~= nil then return false end
    local claimed = self.baseTask
    if claimed == nil and KnoxPersistence.getClaimedBaseTaskForSurvivor ~= nil then
        claimed = KnoxPersistence.getClaimedBaseTaskForSurvivor(self.id, self.baseId)
    end
    if claimed == nil and (KnoxBaseJobs.containsWorkSquare == nil
        or not KnoxBaseJobs.containsWorkSquare(self.base, self.character:getCurrentSquare())) then
        return false
    end
    if self:beginBaseTask(ticks) then return true end
    -- A failed start may install a retry deadline. Do not replace that recovery
    -- with a fresh home route in the very same decision.
    return (self.nextThink or 0) > ticks
end

function Controller:beginBaseTask(ticks)
    if self.base == nil or self.baseId == nil
        or self.base.settings == nil
        then
        return false
    end
    local duty = KnoxPersistence.getSurvivorDuty(self.id) or {}
    local profile = KnoxPersistence.getSurvivorCapabilities(self.id) or {}
    local preference = KnoxBaseJobs.effectivePreference ~= nil
        and KnoxBaseJobs.effectivePreference(duty, profile)
        or duty.jobPreference
    -- Restore an existing claim before evaluating Rest. Explicit player
    -- assignments carry `manual=true` and remain authoritative; automatic
    -- claims are still released when the resident is intentionally rested.
    if self.baseTask == nil then
        local restored = KnoxPersistence.getClaimedBaseTaskForSurvivor ~= nil
            and KnoxPersistence.getClaimedBaseTaskForSurvivor(self.id, self.baseId) or nil
        if restored ~= nil then
            self.baseTask = canonicalBaseTask(restored)
            self.baseTask.baseId = self.baseId
            -- The resident is loaded again, so the physical task has a fresh
            -- opportunity to run natively. Do not carry an old streamed-out
            -- wait budget into the next unload cycle.
            self.baseTask.offscreenWaitHours = 0
            self.baseResupplyAttempts = 0
            self.baseTaskRetryAt = 0
        end
    end
    if preference == "rest" and not (self.baseTask ~= nil and self.baseTask.manual == true) then
        if self.baseTask ~= nil then
            self:releaseSupply()
            self:interruptForDirective()
            self.baseTask = nil
        end
        -- A resident can be switched to Rest while a persisted task claim is
        -- still present (for example after a menu change or a reload).  Do
        -- not merely drop the loaded pointer: that would leave the task
        -- permanently owned by a resting survivor.  Requeue the claim through
        -- the existing persistence boundary so another resident can perform
        -- it and the original task identity/requirements remain intact.
        local requeueRestTask = KnoxPersistence.requeueAutomaticBaseTasksForSurvivor
            or KnoxPersistence.requeueBaseTasksForSurvivor
        if requeueRestTask ~= nil then
            requeueRestTask(
                self.id,
                self.baseId,
                "resident_requested_rest"
            )
        end
        self.activeDecision = "base_recover"
        return false
    end
    if self.baseTask ~= nil then
        if ticks >= (self.baseTaskRetryAt or 0) then
            return self:beginBaseTaskSupplyOrWork(ticks)
        end
        -- A claimed task can survive a threat, failed supply transfer, or
        -- streamed-out target with a future retry deadline. Keep the state
        -- explicit while waiting; returning true from the old path without
        -- changing state left the controller free to re-enter decision logic
        -- against the same deferred task.
        self.activeDecision = "base_task_supply_wait"
        self.state = "BASE_TASK_SUPPLY_WAIT"
        self.nextThink = self.baseTaskRetryAt
        return true
    end
    -- Automatic scheduling is optional, but it must not block a task the
    -- player explicitly assigned through the Notebook. At this point there is
    -- no restored/active claim, so only automatic selection should be gated.
    if self.base.settings.automaticJobs == false then
        return false
    end
    local task, result = KnoxBaseJobs.ensureAutomaticTask(
        self.base,
        self.character,
        self.id,
        preference
    )
    if task == nil then
        return false
    end
    if task.state == "queued" then
        task.baseId = self.baseId
        local eligible, eligibilityResult = KnoxBaseManager.canPerformTask(
            self.id,
            self.baseId,
            task
        )
        if not eligible then
            return false
        end
        task, result = KnoxPersistence.claimBaseTask(
            self.baseId,
            task.id,
            self.id,
            getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
        )
    elseif task.state ~= "claimed" or task.claimedBy ~= self.id then
        return false
    end
    if task == nil then
        return false
    end
    self.baseTask = canonicalBaseTask(task)
    task.baseId = self.baseId
    task.offscreenWaitHours = 0
    sayDialogue(self.character, self.id, "base_work", ticks, 2400)
    return self:beginBaseTaskSupplyOrWork(ticks)
end

-- A resident with no executable base task may still be useful outside the
-- property when shared stores are genuinely short on essentials. Keep this a
-- small bridge into the existing real-item search rather than creating a
-- second mission system: the survivor searches nearby containers, takes only
-- an actual matching item, and returns to the same persisted base duty.
function Controller:baseSupplyNeed(ticks)
    if self.base == nil or self.baseId == nil
        or ticks < (self.nextBaseSupplySearch or 0) then
        return nil
    end
    if KnoxBaseStorage == nil or KnoxBaseStorage.summarize == nil then
        return nil
    end
    local success, summary = pcall(function()
        return KnoxBaseStorage.summarize(self.base)
    end)
    if not success or type(summary) ~= "table" then
        self.nextBaseSupplySearch = ticks + SUPPLY_RETRY_TICKS
        return nil
    end
    local totals = summary.totals or {}
    local residentIds = KnoxPersistence.getBaseResidentIds ~= nil
        and KnoxPersistence.getBaseResidentIds(self.baseId) or {}
    local residents = math.max(1, type(residentIds) == "table" and #residentIds or 1)
    local nowHours = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
    -- Remove a development-era persisted copy if this base came from an older
    -- save. Loaded lease ownership lives only in `baseSupplyClaimsByBase`.
    self.base.supplySearchClaims = nil
    local claims = supplyClaimsFor(self.baseId)
    if claims == nil then return nil end
    -- Supply trips are shared settlement work.  Keep one short-lived claimant
    -- per shortage type so every resident does not leave the property to hunt
    -- for the same food, water, or medicine.  Claims expire naturally if the
    -- worker fails, unloads, or the shortage remains after a trip.
    for kind, claim in pairs(claims) do
        local claimantDuty = type(claim) == "table"
            and KnoxPersistence.getSurvivorDuty ~= nil
            and KnoxPersistence.getSurvivorDuty(claim.survivorId) or nil
        local claimantStillBelongs = claimantDuty ~= nil
            and claimantDuty.mode == "base"
            and tostring(claimantDuty.baseId or "") == tostring(self.baseId or "")
            and (KnoxPersistence.isSurvivorAlive == nil
                or KnoxPersistence.isSurvivorAlive(claim.survivorId))
        if type(claim) ~= "table"
            or (tonumber(claim.untilHours) or 0) <= nowHours
            or not claimantStillBelongs then
            claims[kind] = nil
        end
    end
    local goal = nil
    if KnoxBaseSupplyPlanner.chooseAvailableShortage ~= nil then
        goal = KnoxBaseSupplyPlanner.chooseAvailableShortage(
            totals, residents, claims, self.id
        )
    elseif KnoxBaseSupplyPlanner.chooseShortage ~= nil then
        goal = KnoxBaseSupplyPlanner.chooseShortage(totals, residents)
    end
    if goal ~= nil then
        local claim = claims[goal]
        if claim ~= nil and claim.survivorId ~= self.id then
            self.nextBaseSupplySearch = ticks + 600
            return nil
        end
        if claim == nil and KnoxBaseSupplyPlanner.chooseWorker ~= nil
            and KnoxSurvivorRuntime ~= nil then
            local candidates = {}
            for _, residentId in ipairs(residentIds) do
                local duty = KnoxPersistence.getSurvivorDuty ~= nil
                    and KnoxPersistence.getSurvivorDuty(residentId) or nil
                local character = KnoxSurvivorRuntime.getCharacter ~= nil
                    and KnoxSurvivorRuntime.getCharacter(residentId) or nil
                local snapshot = KnoxSurvivorRuntime.snapshot ~= nil
                    and KnoxSurvivorRuntime.snapshot(residentId) or nil
                local square = character ~= nil and character:getCurrentSquare() or nil
                local state = snapshot ~= nil and tostring(snapshot.state or "") or ""
                local claimedTask = duty ~= nil
                    and KnoxPersistence.getClaimedBaseTaskForSurvivor ~= nil
                    and KnoxPersistence.getClaimedBaseTaskForSurvivor(
                        residentId, self.baseId
                    ) or nil
                candidates[#candidates + 1] = {
                    id = residentId,
                    ready = duty ~= nil and duty.mode == "base"
                        and tostring(duty.baseId or "") == tostring(self.baseId or "")
                        and duty.eventId == nil
                        and snapshot ~= nil and snapshot.loaded == true
                        and (state == "IDLE" or state == "BASE_IDLE")
                        and square ~= nil
                        and KnoxBaseManager.containsSquare(self.base, square),
                    resting = duty ~= nil and duty.jobPreference == "rest",
                    hasTask = claimedTask ~= nil,
                    explicitOrder = duty ~= nil
                        and type(duty.baseSupplyOrder) == "table",
                    lastSupplyRunAtHours = duty ~= nil
                        and duty.lastSupplyRunAtHours or nil,
                    lastSupplyKind = duty ~= nil and duty.lastSupplyKind or nil,
                }
            end
            local selected = KnoxBaseSupplyPlanner.chooseWorker(candidates, goal)
            if selected ~= self.id then
                self.nextBaseSupplySearch = ticks + 600
                return nil
            end
        end
        claims[goal] = {
            survivorId = self.id,
            untilHours = nowHours + 1.5,
        }
        self.baseSupplyTrip = true
        self.baseSupplyKind = goal
        if KnoxPersistence.recordBaseSupplyRun ~= nil then
            KnoxPersistence.recordBaseSupplyRun(
                self.id, self.baseId, goal, "selected", nowHours
            )
        end
    else
        -- Once the stores are healthy, let another shortage claim immediately
        -- instead of waiting for the previous worker's lease to expire.
        for kind, claim in pairs(claims) do
            if type(claim) == "table" and claim.survivorId == self.id then
                claims[kind] = nil
            end
        end
    end
    self.nextBaseSupplySearch = ticks + (goal ~= nil and 1800 or 600)
    return goal
end

function Controller:releaseBaseSupplyClaim(kind)
    local claims = supplyClaimsFor(self.baseId)
    local claim = type(claims) == "table" and claims[kind] or nil
    if type(claim) == "table" and claim.survivorId == self.id then
        claims[kind] = nil
        return true
    end
    return false
end

function Controller:beginBaseSupplyRun(kind)
    self.baseSupplyTrip = true
    self.baseSupplyKind = kind
    if KnoxPersistence.beginBaseSupplyRun ~= nil then
        return KnoxPersistence.beginBaseSupplyRun(
            self.id, self.baseId, kind, currentWorldAgeHours()
        )
    end
    return true
end

function Controller:finishBaseSupplyRun(outcome)
    local kind = self.baseSupplyKind
        or (self.baseSupplyOrder ~= nil and self.baseSupplyOrder.kind or nil)
    if kind == nil then return false end
    self:releaseBaseSupplyClaim(kind)
    local saved = KnoxPersistence.finishBaseSupplyRun ~= nil
        and KnoxPersistence.finishBaseSupplyRun(
            self.id, self.baseId, kind, outcome, currentWorldAgeHours()
        ) or false
    return saved
end

function Controller:clearExplicitBaseSupplyOrder()
    if self.baseSupplyOrder == nil then return false end
    local duty = KnoxPersistence.getSurvivorDuty(self.id) or {}
    local cleared = KnoxPersistence.clearBaseSupplyOrder ~= nil
        and KnoxPersistence.clearBaseSupplyOrder(
            self.id, duty.ownerId, self.baseId, currentWorldAgeHours()
        ) or false
    if cleared then
        self.baseSupplyOrder = nil
        self.baseSupplyOrderAttempts = 0
    end
    return cleared
end

function Controller:recordExplicitBaseSupplyFailure(ticks)
    if self.baseSupplyOrder == nil then return false end
    local attempts = KnoxPersistence.recordBaseSupplyOrderAttempt ~= nil
        and KnoxPersistence.recordBaseSupplyOrderAttempt(
            self.id, self.baseId, currentWorldAgeHours()
        ) or nil
    self.baseSupplyOrderAttempts = tonumber(attempts)
        or ((tonumber(self.baseSupplyOrderAttempts) or 0) + 1)
    if self.baseSupplyOrderAttempts < 3 then
        self.nextThink = math.max(self.nextThink or 0, ticks + SUPPLY_RETRY_TICKS)
        return false
    end
    self:clearExplicitBaseSupplyOrder()
    self.baseSupplyTrip = nil
    self:clearLifeIntent()
    sayDialogue(self.character, self.id, "base_supply_failed", ticks, 2400)
    return true
end

function Controller:releaseSupply()
    self:releaseBaseRecreation()
    if self.pendingSupply ~= nil then
        release(self.reservations, "items", self.pendingSupply.item, self.id)
        for _, candidate in ipairs(self.pendingSupply.items or {}) do
            release(self.reservations, "items", candidate.item, self.id)
        end
        release(self.reservations, "containers", self.pendingSupply.container, self.id)
        self.pendingSupply = nil
    end
    self.baseSupplyTrip = nil
    self.baseSupplyKind = nil
    self.entryDetour = nil
end

function Controller:releaseGroupSupport()
    local plan = self.pendingGroupSupport
    if plan ~= nil then
        release(self.reservations, "supportRecipients", plan.recipient, self.id)
        release(self.reservations, "supportItems", plan.item, self.id)
    end
    self.pendingGroupSupport = nil
end

function Controller:beginGroupSupport(ticks)
    if ticks < (self.nextGroupSupportAt or 0) or self.companionOrder ~= nil
        or self.baseId ~= nil or self.campId ~= nil
        or (self.groupLeader == nil and #(self.groupMembers or {}) <= 1)
        or not self.character:getCharacterActions():isEmpty() then
        return false
    end
    self.reservations.supportRecipients = self.reservations.supportRecipients or {}
    self.reservations.supportItems = self.reservations.supportItems or {}
    local recipients = {}
    if self.groupLeader ~= nil then recipients[#recipients + 1] = self.groupLeader end
    for _, member in ipairs(self.groupMembers or {}) do
        recipients[#recipients + 1] = member
    end
    local plan = KnoxGroupSupport.plan(
        self.character,
        recipients,
        self.reservations.supportRecipients,
        self.reservations.supportItems
    )
    if plan == nil
        or not reserve(self.reservations, "supportRecipients", plan.recipient, self.id)
        or not reserve(self.reservations, "supportItems", plan.item, self.id) then
        if plan ~= nil then
            release(self.reservations, "supportRecipients", plan.recipient, self.id)
        end
        self.nextGroupSupportAt = ticks + GROUP_SUPPORT_RETRY_TICKS
        return false
    end
    local action, result = KnoxGroupSupport.queue(self.character, plan)
    if action == nil then
        release(self.reservations, "supportRecipients", plan.recipient, self.id)
        release(self.reservations, "supportItems", plan.item, self.id)
        self.nextGroupSupportAt = ticks + GROUP_SUPPORT_RETRY_TICKS
        self:recordFailure("group_support:" .. tostring(result), ticks,
            GROUP_SUPPORT_RETRY_TICKS)
        return false
    end
    self.pendingGroupSupport = plan
    self.activeDecision = "share_" .. tostring(plan.kind)
    self.state = "GROUP_SUPPORT"
    self.stateStartedAt = ticks
    self.nextGroupSupportAt = ticks + GROUP_SUPPORT_COOLDOWN_TICKS
    sayDialogue(self.character, self.id, "share_supply", ticks, 1800)
    return true
end

function Controller:completeGroupSupport(ticks)
    local plan = self.pendingGroupSupport
    local completed = KnoxGroupSupport.verify(plan)
    if not completed then
        self.nextGroupSupportAt = ticks + GROUP_SUPPORT_RETRY_TICKS
        self:recordFailure("group_support_no_transfer", ticks,
            GROUP_SUPPORT_RETRY_TICKS)
    end
    self:releaseGroupSupport()
    self:finishDecision(ticks)
    return completed
end

function Controller:beginWindowDetour(ticks, resumeState)
    if self.pendingSupply == nil or (self.pendingSupply.entryAttemptCount or 0) >= 8 then
        return false
    end
    self.pendingSupply.entryAttempts = self.pendingSupply.entryAttempts or {}
    local entry = findAlternateEntry(self, self.pendingSupply, ticks)
    if entry == nil then
        return false
    end
    self.pendingSupply.entryAttemptCount = (self.pendingSupply.entryAttemptCount or 0) + 1
    self.pendingSupply.entryAttempts[entry.object] = "attempted"
    self.bridge:cancelNpcMove(self.id)
    local result = tostring(self.bridge:moveNpc(self.id, entry.outside))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    entry.resumeState = resumeState
    self.entryDetour = entry
    self.state = "MOVING_TO_WINDOW_ENTRY"
    self.stateStartedAt = ticks
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " alternate-entry=" .. tostring(entry.kind) .. " outside="
            .. entry.outside:getX() .. "," .. entry.outside:getY()
    )
    return true
end

function Controller:beginLockedDoorBreak(ticks, resumeState)
    if self.pendingSupply == nil or self.pendingSupply.doorBreakAttempted == true then
        return false
    end
    -- Forced entry is justified only by an actual survival shortage. Optional
    -- upgrades and curiosity should make the survivor choose another location.
    local urgent = self.activeDecision == "find_food"
        or self.activeDecision == "find_water"
        or self.activeDecision == "find_medical"
    local endurance = KnoxSurvivorNeeds.snapshot(self.character).endurance
    local structureSquare = self.pendingSupply.container ~= nil
        and self.pendingSupply.container:getSourceGrid() or nil
    if not KnoxBaseManager.canDamageStructure(self.id, structureSquare) then
        markPendingAreaBlocked(self, ticks, "protected_player_base")
        return false
    end
    if not urgent or endurance < LOCKED_DOOR_MIN_ENDURANCE then
        markPendingAreaBlocked(
            self,
            ticks,
            not urgent and "optional_locked_entry" or "too_tired_for_forced_entry"
        )
        return false
    end
    self.pendingSupply.doorBreakAttempted = true
    local result = tostring(self.bridge:beginNpcLockedDoorCombat(self.id))
    if string.find(result, "COMBAT_STARTED", 1, true) ~= 1 then
        markPendingAreaBlocked(self, ticks, "door_break_failed:" .. tostring(result))
        return false
    end
    self.entryDetour = { resumeState = resumeState, doorFallback = true }
    self.state = "BREAKING_LOCKED_DOOR"
    self.stateStartedAt = ticks
    print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " alternate-entry=break-door")
    return true
end

function Controller:crossWindowDetour(ticks)
    if self.entryDetour == nil then
        return false
    end
    if self.entryDetour.force then
        -- Revalidate protection and the real world object at the action boundary.
        local window = self.entryDetour.object
        if not KnoxBaseManager.canDamageStructure(self.id, self.entryDetour.inside)
            or KnoxSurvivorNeeds.snapshot(self.character).endurance < LOCKED_DOOR_MIN_ENDURANCE
            or safeObjectBoolean(window, "isBarricaded", true) then return false end
        self.entryDetour.force = false
        if not safeObjectBoolean(window, "IsOpen", false)
            and not safeObjectBoolean(window, "isSmashed", false) then
            self.bridge:cancelNpcMove(self.id)
            ISTimedActionQueue.add(ISSmashWindow:new(self.character, window))
            self.state = "OPENING_ENTRY_WINDOW"
            self.stateStartedAt = ticks
            return true
        end
    end
    local result = tostring(self.bridge:crossNpc(self.id, self.entryDetour.inside))
    if string.find(result, "CROSS_STARTED", 1, true) ~= 1 then
        return false
    end
    self.state = "CROSSING_WINDOW_ENTRY"
    self.stateStartedAt = ticks
    return true
end

function Controller:retryWindowDetour(ticks, movement)
    local entry = self.entryDetour
    if entry == nil or self.pendingSupply == nil then return false end
    local attempts = self.pendingSupply.entryAttempts or {}
    self.pendingSupply.entryAttempts = attempts
    if entry.kind == "window" and not entry.smashedAttempt
        and string.find(tostring(movement), "FAILED_LOCKED_OR_UNUSABLE_WINDOW", 1, true)
        and not safeObjectBoolean(entry.object, "IsOpen", false)
        and not safeObjectBoolean(entry.object, "isSmashed", false) then
        attempts[entry.object] = "closed"
    end
    return self:beginWindowDetour(ticks, entry.resumeState)
end

function Controller:updateEntryWindow(ticks)
    if not self.character:getCharacterActions():isEmpty() then return end
    local entry = self.entryDetour
    if entry ~= nil and safeObjectBoolean(entry.object, "isSmashed", false) then
        entry.smashedAttempt = true
        if self:crossWindowDetour(ticks) then return end
    end
    if not self:retryWindowDetour(ticks, "smash_failed") then
        self:abandonCurrentDecision(ticks, "window_smash_failed")
    end
end

function Controller:resumeAfterWindowDetour(ticks)
    if self.entryDetour == nil or self.pendingSupply == nil then
        return false
    end
    local resumeState = self.entryDetour.resumeState
    local result = tostring(self.bridge:moveNpc(self.id, self.pendingSupply.approach))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        return false
    end
    self.entryDetour = nil
    self.state = resumeState
    self.stateStartedAt = ticks
    print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " alternate-entry=completed")
    return true
end

function Controller:abandonCurrentDecision(ticks, reason)
    if self.pendingDepositTrip ~= nil then self:deferDepositTrip(ticks) end
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    self:releaseAmbientMovement()
    self:abandonBaseTask(reason or "decision_abandoned")
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    if self.selfCareIntent ~= nil then
        local kind = tostring(self.selfCareIntent.kind or self.activeDecision)
        self.selfCareRetryAt[kind] = ticks + SELF_CARE_RETRY_TICKS
    end
    if self.pendingSupply ~= nil and self.pendingSupply.container ~= nil then
        self.inspectedContainers[self.pendingSupply.container] = ticks + SUPPLY_RETRY_TICKS
    end
    if self.state == "ROAMING" then
        rememberRoamDestination(
            self,
            self.roamGoalKey,
            ticks,
            ROAM_FAILURE_COOLDOWN_TICKS
        )
        self.roamGoalKey = nil
        self.roamGoalKind = nil
    end
    if self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION" then
        self:releaseCampPosition()
    end
    self:releaseCombat()
    self:releaseSupply()
    self.counts.failures = self.counts.failures + 1
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " abandoned=" .. tostring(self.activeDecision)
            .. " reason=" .. tostring(reason)
    )
    self:finishDecision(ticks)
end


function Controller:beginExploration(ticks, directive)
    if ticks < self.nextExplorationSearch then
        return false
    end
    local target = findExploration(self, ticks, directive)
    if target == nil then
        self.nextExplorationSearch = ticks + EXPLORATION_RETRY_TICKS
        if directive ~= nil and directive.eventId ~= nil then
            KnoxEvents.recordEmptySearch(directive.eventId, self.id)
        elseif directive ~= nil then
            self.directiveMisses = self.directiveMisses + 1
            if self.directiveMisses >= 3 then
                KnoxPersistence.clearCompanionDirective(
                    self.id,
                    self.companionOwnerId,
                    getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                )
                self.companionDirective = nil
                self.directiveMisses = 0
                KnoxActivityFeed.speak(self.character, "I've checked the area.")
            end
        end
        return false
    end
    if not reserve(self.reservations, "containers", target.container, self.id) then
        return false
    end
    local reservedItems = {}
    for _, candidate in ipairs(target.items or {}) do
        if not reserve(self.reservations, "items", candidate.item, self.id) then
            for _, reservedItem in ipairs(reservedItems) do
                release(self.reservations, "items", reservedItem, self.id)
            end
            release(self.reservations, "containers", target.container, self.id)
            return false
        end
        reservedItems[#reservedItems + 1] = candidate.item
    end
    local context = directive ~= nil and directive.kind == "go_to"
        and "directed" or "travel"
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target.approach, context
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        for _, candidate in ipairs(target.items or {}) do
            release(self.reservations, "items", candidate.item, self.id)
        end
        release(self.reservations, "containers", target.container, self.id)
        self.inspectedContainers[target.container] = ticks + EXPLORATION_RETRY_TICKS
        self:recordFailure(
            "exploration_move:" .. result,
            ticks,
            EXPLORATION_RETRY_TICKS
        )
        return false
    end
    self.pendingSupply = target
    target.eventId = directive ~= nil and directive.eventId or nil
    self.activeDecision = directive ~= nil and tostring(directive.kind)
        or (target.items ~= nil and #target.items > 0
            and "loot_useful_items_" .. tostring(#target.items)
            or "inspect_container")
    if directive == nil and self.companionOrder == nil
        and self.groupLeaderId == nil and self.baseId == nil and self.campId == nil then
        self:setLifeIntent(
            "scavenge",
            "traveling",
            target.approach,
            roamDestinationKey(target.container:getSourceGrid())
        )
    end
    self.state = "MOVING_TO_EXPLORE"
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=MOVING_TO_EXPLORE goal=" .. tostring(self.activeDecision)
    )
    return true
end

function Controller:prepareSecurityContext(duty)
    if self.securityContext~=duty then
        self.securityContext,self.securityRoute,self.securityRetryAt=duty,nil,0
        self.securityFailedSquares,self.securityMisses={},0
    end
end

function Controller:advanceSecurityPatrol(route,arrived)
    if route==nil or not route.patrol then return false end
    local duty=route.duty
    if route.base then
        duty.patrolStep=route.step
        if arrived then
            local complete=KnoxCompanionPatrol.recordTaskArrival(duty)
            if complete then duty.patrolLaps=math.min(1000000,(tonumber(duty.patrolLaps) or 0)+1) end
        else duty.patrolStep=(route.step+1)%math.max(1,route.count) end
        return true
    end
    return KnoxPersistence.advanceCompanionPatrol(self.id,self.companionOwnerId,duty,route.step,arrived)
end

function Controller:deferSecurityRoute(ticks,reason,base)
    local route=self.securityRoute
    self.bridge:cancelNpcMove(self.id)
    self.securityFailedSquares=self.securityFailedSquares or {}
    if route~=nil and route.square~=nil then
        self.securityFailedSquares[KnoxCompanionPatrol.squareKey(route.square)]=ticks+1800
        self:advanceSecurityPatrol(route,false)
    end
    self.securityMisses=math.min(4,(self.securityMisses or 0)+1)
    local delay=math.min(1800,150*2^self.securityMisses)
    self.securityRetryAt,self.nextThink=ticks+delay,ticks+delay
    self.lastFailure={reason="security_route:"..tostring(reason)
        .." destination="..(route~=nil and route.square~=nil and KnoxCompanionPatrol.squareKey(route.square) or "unavailable"),ticks=ticks}
    self.state=base and "BASE_SECURITY_WAIT" or "COMPANION_DUTY_WAIT"
    self.activeDecision="security_route_blocked"
    self.securityRoute=nil
    if ticks>=(self.nextSecuritySpeech or 0) then
        KnoxActivityFeed.speak(self.character,"The route is blocked. I'll keep watch and try again.")
        self.nextSecuritySpeech=ticks+3600
    end
    return true
end

function Controller:beginSecurityRoute(ticks,duty,base)
    self:prepareSecurityContext(duty)
    if ticks<(self.securityRetryAt or 0) then
        self.state=base and "BASE_SECURITY_WAIT" or "COMPANION_DUTY_WAIT"
        self.activeDecision="security_route_blocked"
        return true
    end
    for key,untilTick in pairs(self.securityFailedSquares) do
        if untilTick<=ticks then self.securityFailedSquares[key]=nil end
    end
    local area=base and duty.target or duty
    local patrol=(base and duty.type=="patrol") or (not base and duty.kind=="patrol_area")
    local identity=base and (duty.id or self.id) or self.id
    local square,step,count=KnoxCompanionPatrol.resolveWaypoint(area,identity,duty.patrolStep,
        getCell(),self.character:getCurrentSquare(),self.securityFailedSquares,ticks,not patrol)
    if square==nil then return self:deferSecurityRoute(ticks,"no_loaded_standing_tile",base) end
    self.securityRoute={duty=duty,base=base==true,patrol=patrol,step=step,count=count,square=square}
    if not patrol and KnoxCompanionPatrol.contains(area,self.character:getCurrentSquare())
        and navigationDistanceSquared(self.character:getCurrentSquare(),square)<=2.25 then
        self.securityMisses=0
        self.state=base and "BASE_TASK_WORK" or "COMPANION_GUARD"
        self.activeDecision=base and "base_task_guard" or "guard_location"
        self.nextThink=ticks+90
        return true
    end
    local result=KnoxCompanionPatrol.move(self.bridge,self.id,square,area)
    if result:find("MOVE_STARTED",1,true)~=1 then return self:deferSecurityRoute(ticks,result,base) end
    self.state=base and "BASE_TASK_MOVE" or (patrol and "MOVING_TO_COMPANION_PATROL" or "MOVING_TO_COMPANION_POINT")
    self.activeDecision=base and ("base_task_"..duty.type) or (patrol and "patrol_area" or "guard_location")
    self.baseTaskStartedAt=nil
    return true
end

function Controller:completeSecurityArrival(ticks,base)
    local route=self.securityRoute
    if route==nil then return false end
    local area=base and route.duty.target or route.duty
    if not KnoxCompanionPatrol.contains(area,self.character:getCurrentSquare())
        or navigationDistanceSquared(self.character:getCurrentSquare(),route.square)>(route.patrol and 0 or 2.25) then
        return self:deferSecurityRoute(ticks,"arrival_outside_post",base)
    end
    if route.patrol and not self:advanceSecurityPatrol(route,true) then
        self.securityRoute=nil
        self:finishDecision(ticks)
        return true
    end
    self.securityMisses,self.securityRetryAt=0,0
    self.state=base and (route.patrol and "BASE_TASK_PATROL_WAIT" or "BASE_TASK_WORK")
        or (route.patrol and "COMPANION_PATROL_WAIT" or "COMPANION_GUARD")
    self.activeDecision=base and ("base_task_"..route.duty.type) or (route.patrol and "patrol_area" or "guard_location")
    self.baseTaskStartedAt=ticks
    self.nextThink=ticks+(route.patrol and 180 or 90)
    return true
end

function Controller:updateSecurityRouteWait(ticks,base)
    if base then
        self:updateBaseSecurityDuty(ticks)
        if self.state~="BASE_SECURITY_WAIT" then return end
    elseif ticks>=(self.nextSecurityNeedCheck or 0) then
        self.nextSecurityNeedCheck=ticks+90
        local decision=KnoxSurvivorNeeds.decide(self.character,nil)
        if decision~=nil and decision.kind~="roam" then
            self.state,self.activeDecision,self.nextThink="IDLE",nil,ticks
            return
        end
    end
    if ticks>=(self.securityRetryAt or 0) then
        if base and self.baseTask~=nil then self:beginBaseTaskWorkMove(ticks)
        else self.state,self.nextThink="IDLE",ticks end
    end
end

function Controller:beginCompanionPointDirective(ticks, directive)
    if directive~=nil and directive.kind=="guard" then return self:beginSecurityRoute(ticks,directive,false) end
    local cell = getCell()
    local x = tonumber(directive ~= nil and directive.minX)
    local y = tonumber(directive ~= nil and directive.minY)
    local z = tonumber(directive ~= nil and directive.z) or 0
    if cell == nil or x == nil or y == nil then
        return false
    end
    local target = cell:getGridSquare(x, y, z)
    if target == nil then
        self:recordFailure("companion_point_unloaded", ticks, EXPLORATION_RETRY_TICKS)
        return false
    end
    local current = self.character:getCurrentSquare()
    if current ~= nil and navigationDistanceSquared(current, target) <= 2.25 then
        self.activeDecision = directive.kind == "guard" and "guard_location" or "go_to_location"
        self.state = directive.kind == "guard" and "COMPANION_GUARD" or "COMPANION_WAIT"
        self.nextThink = ticks + 90
        if directive.kind == "go_to" then
            KnoxPersistence.clearCompanionDirective(
                self.id, self.companionOwnerId,
                getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
            )
            self.companionDirective = nil
            KnoxActivityFeed.speak(self.character, "I'm here.")
        end
        return true
    end
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target, "directed"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:recordMovementFailure(
            "companion_point_move", result, ticks, EXPLORATION_RETRY_TICKS
        )
        return false
    end
    self.activeDecision = directive.kind == "guard" and "guard_location" or "go_to_location"
    self.state = "MOVING_TO_COMPANION_POINT"
    return true
end

function Controller:beginCompanionPatrolDirective(ticks,directive)
    return self:beginSecurityRoute(ticks,directive,false)
end

function Controller:releaseCombat()
    releaseThreat(self.reservations, self.combatTarget, self.id)
    self.combatTarget = nil
end

function Controller:releaseRestSpot()
    if self.pendingRest ~= nil and self.pendingRest.object ~= nil then
        release(self.reservations, "restSpots", self.pendingRest.object, self.id)
    end
    self.pendingRest = nil
end

function Controller:leaveRecoveryPosture()
    KnoxSurvivorNeeds.wakeForDanger(self.character)
    if self.character:isSitOnGround() or self.character:isSittingOnFurniture() then
        self.character:setVariable("forceGetUp", true)
    end
    self.character:setIsResting(false)
    self.character:setBed(nil)
    self:releaseRestSpot()
end

function Controller:startRecoveryPosture(ticks, useFurniture, ambient)
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    if self.activeDecision == "sleep" and ambient ~= true then
        local bed = useFurniture and self.pendingRest ~= nil
            and self.pendingRest.object or nil
        local bedType = bed ~= nil and self.pendingRest.bedType or "floor"
        if bed == nil then
            self:releaseRestSpot()
        end
        local sleeping, result = KnoxSurvivorNeeds.startSleep(
            self.character,
            bed,
            bedType
        )
        if sleeping then
            self.state = "SLEEPING_RECOVERY"
            self.recoveryStarted = ticks
            self.recoveryPostureStarted = ticks
            self.nextThink = ticks + RECOVERY_RECHECK_TICKS
            self.selfCareIntent = self.selfCareIntent or {
                kind = "sleep",
                before = KnoxSurvivorNeeds.snapshot(self.character),
            }
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " recovery-posture=sleep:" .. tostring(bedType)
                    .. " result=" .. tostring(result)
            )
            return true
        end
        self.selfCareRetryAt.sleep = ticks + SELF_CARE_RETRY_TICKS
        self:recordFailure("needs_action:sleep:" .. tostring(result), ticks,
            SELF_CARE_RETRY_TICKS)
        self:finishDecision(ticks)
        return false
    end
    local action = nil
    local posture = "ground"
    if useFurniture and self.pendingRest ~= nil and self.pendingRest.object ~= nil
        and usableRestFurniture(
            self,
            self.pendingRest.object,
            self.activeDecision == "sleep"
        ) then
        action = ISRestAction:new(self.character, self.pendingRest.object, true)
        posture = "furniture:" .. tostring(self.pendingRest.bedType)
    else
        self:releaseRestSpot()
        action = ISSitOnGround:new(self.character, nil)
    end
    ISTimedActionQueue.add(action)
    self.state = ambient == true
        and (self.activeDecision == "camp_ambient_rest" and "CAMP_AMBIENT_REST"
            or (self.activeDecision == "companion_relax" and "COMPANION_RELAX"
                or "BASE_AMBIENT_REST"))
        or "WAITING_TO_RECOVER"
    self.recoveryStarted = ticks
    self.recoveryPostureStarted = ticks
    self.nextThink = ticks + (ambient == true
        and BASE_AMBIENT_REST_TICKS or RECOVERY_RECHECK_TICKS)
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " recovery-posture=" .. posture
            .. " endurance=" .. tostring(KnoxSurvivorNeeds.snapshot(self.character).endurance)
    )
end

function Controller:releaseBaseCooking()
    local plan=self.pendingCooking
    if plan==nil then return end
    KnoxBaseCooking.cancel(plan,self.character)
    if plan.phase=="move" then self.bridge:cancelNpcMove(self.id) end
    self.pendingCooking=nil
end

function Controller:beginBaseCooking(ticks,target,personal)
    if KnoxBaseCooking==nil or self.base==nil or self.pendingCooking~=nil
        or ticks<(self.nextCookingAt or 0) or not self.character:getCharacterActions():isEmpty() then return false end
    if personal then
        if self:hasNeedEscort() or not KnoxBaseManager.containsSquare(self.base,self.character:getCurrentSquare())
            or KnoxBaseCooking.hasReadyMeal(self.base) then return false end
        target=KnoxBaseCooking.findTask(self.base,self.character)
    end
    if target==nil then self.nextCookingAt=ticks+1800;return false end
    local plan,reason=KnoxBaseCooking.begin(self.base,target,self.character,self.id)
    if plan==nil then
        self.nextCookingAt=ticks+1800
        self.lastFailure={reason=tostring(reason),ticks=ticks}
        return false
    end
    plan.personal=personal==true
    self.pendingCooking,self.cookingStartedAt=plan,ticks
    self.state,self.activeDecision="BASE_COOKING","cooking_collect"
    return true
end

function Controller:updateBaseCooking(ticks)
    local plan=self.pendingCooking
    if plan==nil then self:finishDecision(ticks);return end
    if ticks>=(self.nextCookingNeedCheck or 0) then
        self.nextCookingNeedCheck=ticks+90
        local decision=KnoxSurvivorNeeds.decide(self.character,nil)
        -- Cooking is a real response to missing meals. Do not interrupt it every
        -- second because the same hunger still needs the food being prepared.
        if decision~=nil and decision.kind~="roam" and decision.kind~="find_food" then
            local mealReady=decision.kind=="eat" and self.character:getInventory():contains(plan.item)
                and plan.item:isCooked() and KnoxSurvivorNeeds.isSafeFood(plan.item)
                and not plan.object:getContainer():contains(plan.item)
            if mealReady and not plan.personal then
                self:finishBaseTask(true,"meal_prepared_for_resident")
            else
                self:suspendBaseTaskForThreat("cooking_needs_interrupt")
            end
            self:finishDecision(ticks)
            return
        end
    end
    local outcome,reason=KnoxBaseCooking.step(plan,self.character,self.base,self.bridge,ticks)
    if ticks-(self.cookingStartedAt or ticks)>10800 then outcome,reason="failed","cooking_session_timeout" end
    self.activeDecision="cooking_"..tostring(plan.phase)
    if outcome~="working" then
        local personal=plan.personal
        self:releaseBaseCooking()
        if not personal then self:finishBaseTask(outcome=="done",reason) end
        self.nextCookingAt=ticks+(outcome=="done" and 0 or 1800)
        if outcome=="failed" then self.lastFailure={reason=tostring(reason),ticks=ticks} end
        self:finishDecision(ticks)
    end
end

function Controller:releaseBaseRecreation()
    local plan=self.pendingRecreation
    if plan==nil then return end
    if KnoxBaseRecreation~=nil then KnoxBaseRecreation.cancelAction(self.character,plan) end
    if plan.phase=="borrow_move" or plan.phase=="return_move" then self.bridge:cancelNpcMove(self.id) end
    release(self.reservations,"items",plan.item,self.id)
    self.pendingRecreation=nil
end

function Controller:beginBaseRecreation(ticks)
    if KnoxBaseRecreation==nil or self.base==nil or self.baseTask~=nil
        or not KnoxBaseManager.containsSquare(self.base,self.character:getCurrentSquare())
        or ticks<(self.nextRecreationAt or 0) or not self.character:getCharacterActions():isEmpty()
        or ISTimedActionQueue.getTimedActionQueue(self.character).current~=nil then return false end
    self.nextRecreationAt=ticks+1800
    self.recentReading=self.recentReading or setmetatable({}, {__mode="k"})
    local readingEnabled=KnoxSettings==nil or KnoxSettings.baseReadingEnabled==nil or KnoxSettings.baseReadingEnabled()
    local plan=KnoxBaseRecreation.find(self.character,self.base,function(item,returning)
        return (returning or (self.recentReading[item] or 0)<=ticks) and not reservedByOther(self.reservations,"items",item,self.id)
    end,readingEnabled)
    if plan==nil or not reserve(self.reservations,"items",plan.item,self.id) then return false end
    self.pendingRecreation=plan
    self.recreationStartedAt=ticks
    self.nextRecreationNeedsCheck=ticks
    self.state,self.activeDecision="BASE_RECREATION","reading"
    return true
end

function Controller:updateBaseRecreation(ticks)
    if self.pendingRecreation==nil then self:finishDecision(ticks);return end
    if ticks>=(self.nextRecreationNeedsCheck or 0) then
        self.nextRecreationNeedsCheck=ticks+90
        local need=KnoxSurvivorNeeds.decide(self.character,nil)
        if need~=nil and need.kind~="roam" then
            self:releaseBaseRecreation()
            self:finishDecision(ticks)
            self.nextThink=ticks
            return
        end
    end
    local plan=self.pendingRecreation
    local outcome,reason=KnoxBaseRecreation.step(plan,self.character,self.base,self.bridge,self.id,ticks)
    if ticks-(self.recreationStartedAt or ticks)>7200 then outcome,reason="failed","recreation_timeout" end
    self.activeDecision=(plan.phase=="borrow_move" or plan.phase=="borrowing") and "collecting_book"
        or ((plan.phase=="return_move" or plan.phase=="returning" or plan.phase=="return") and "returning_book" or "reading")
    if outcome~="working" then
        self.recentReading[plan.item]=ticks+(outcome=="done" and 18000 or 1800)
        self:releaseBaseRecreation()
        self.nextRecreationAt=ticks+1800
        if outcome=="failed" then self:recordFailure("recreation:"..tostring(reason),ticks,1800) end
        self:finishDecision(ticks)
    end
end

-- Native rest remains the fallback when there is no suitable readable book.
-- Use the best available chair or bed through the game's sit/rest actions.
function Controller:beginAmbientBaseRest(ticks)
    if self:beginBaseRecreation(ticks) then return true end
    self.activeDecision = "base_ambient_rest"
    self.ambientRest = true
    local spot = findBestRestSpot(self)
    if spot ~= nil and reserve(self.reservations, "restSpots", spot.object, self.id) then
        self.pendingRest = spot
        if spot.approach == self.character:getCurrentSquare() then
            self:startRecoveryPosture(ticks, true, true)
            return true
        end
        local result = tostring(self.bridge:moveNpc(self.id, spot.approach))
        if string.find(result, "MOVE_STARTED", 1, true) == 1 then
            self.state = "MOVING_TO_REST"
            return true
        end
        self:releaseRestSpot()
    end
    self:startRecoveryPosture(ticks, false, true)
    return true
end

function Controller:beginCompanionRelax(ticks)
    self.activeDecision = "companion_relax"
    self.ambientRest = true
    local spot = findBestRestSpot(self)
    if spot ~= nil and reserve(self.reservations, "restSpots", spot.object, self.id) then
        self.pendingRest = spot
        if spot.approach == self.character:getCurrentSquare() then
            self:startRecoveryPosture(ticks, true, true)
            return true
        end
        local result = tostring(self.bridge:moveNpc(self.id, spot.approach))
        if string.find(result, "MOVE_STARTED", 1, true) == 1 then
            self.state = "MOVING_TO_REST"
            return true
        end
        self:releaseRestSpot()
    end
    self:startRecoveryPosture(ticks, false, true)
    return true
end

function Controller:updateCompanionRelax(ticks)
    if self.companionOrder ~= "relax" then
        self:finishDecision(ticks)
        return
    end
    if ticks < self.nextThink then return end
    self.nextThink = ticks + RECOVERY_RECHECK_TICKS
    local decision = KnoxSurvivorNeeds.decide(self.character, nil)
    local kind = decision.kind
    if (kind == "eat" or kind == "drink" or kind == "bandage"
        or kind == "improvise_medical" or kind == "sleep")
        and Controller.selfCareReady(self.selfCareRetryAt, kind, ticks) then
        self:finishDecision(ticks)
        self.nextThink = ticks
    end
    -- Sitting is persistent native posture, not a timed action to restart.
    -- Combat is checked before this state; ordinary rechecks leave it intact.
end

function Controller:beginRecovery(decision, ticks)
    self.activeDecision = decision
    self.recoveryStarted = ticks
    self.selfCareIntent = {
        kind = decision,
        before = KnoxSurvivorNeeds.snapshot(self.character),
    }
    local spot = findBestRestSpot(self, decision == "sleep", function(square)
        return self:allowNeedDetour(square, ticks, false)
    end)
    if spot ~= nil and not self:allowNeedDetour(spot.approach, ticks) then spot = nil end
    if spot ~= nil and reserve(
        self.reservations,
        "restSpots",
        spot.object,
        self.id
    ) then
        self.pendingRest = spot
        if spot.approach == self.character:getCurrentSquare() then
            self:startRecoveryPosture(ticks, true)
            return true
        end
        local result = tostring(self.bridge:moveNpc(self.id, spot.approach))
        if string.find(result, "MOVE_STARTED", 1, true) == 1 then
            self.state = "MOVING_TO_REST"
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " state=MOVING_TO_REST furniture=" .. spot.bedType
                    .. " quality=" .. tostring(spot.quality)
            )
            return true
        end
        self:releaseRestSpot()
    end
    self:startRecoveryPosture(ticks, false)
    return true
end

function Controller:finishDecision(ticks)
    self:releaseBaseCooking()
    self:releaseBaseRecreation()
    self:releaseGroupSupport()
    self:releaseAmbientMovement()
    self.pendingCleanup = nil
    self.pendingDepositTrip = nil
    if self.activeDecision == "rest" or self.activeDecision == "sleep"
        or self.activeDecision == "base_ambient_rest"
        or self.activeDecision == "camp_ambient_rest"
        or self.activeDecision == "companion_relax" then
        self:leaveRecoveryPosture()
    end
    self.ambientRest = nil
    self.selfCareIntent = nil
    KnoxPersistence.captureActiveSurvivor(self.id)
    self.regroupMember = nil
    self.activeDecision = nil
    self.state = "IDLE"
    local stayingWithGroup = self.companionOrder == "follow"
        or self.groupLeader ~= nil
        or #(self.groupMembers or {}) > 1
    local proposedThink = stayingWithGroup
        and (ticks + 5)
        or (ticks + THINK_MIN_TICKS + ZombRand(THINK_JITTER_TICKS))
    -- A failure handler may already have installed a longer retry delay. Keep
    -- that delay so a group route cannot hammer the same cooled-down edge.
    self.nextThink = math.max(self.nextThink or 0, proposedThink)
end

-- Streaming can briefly remove a shell's current square before the population
-- owner captures it. If the square returns first, do not leave the controller in
-- DETACHED with stale route/combat/action ownership. Persistent duty is held in
-- the companion/group/base/camp fields and is deliberately not changed here.
function Controller:recoverFromDetached(ticks)
    if self.state ~= "DETACHED" or self.character == nil
        or self.character:getCurrentSquare() == nil then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    if self.selfCareIntent ~= nil then
        local kind = tostring(self.selfCareIntent.kind or self.activeDecision or "unknown")
        self.selfCareRetryAt = self.selfCareRetryAt or {}
        self.selfCareRetryAt[kind] = math.max(
            self.selfCareRetryAt[kind] or 0,
            ticks + SELF_CARE_RETRY_TICKS
        )
    end
    self:abandonBaseTask("detached_recovered")
    self:releaseCombat()
    self:releaseSupply()
    self:releaseGroupSupport()
    self:releaseRestSpot()
    self.selfCareIntent = nil
    self.pendingCleanup = nil
    self.pendingDepositTrip = nil
    self.activeDecision = nil
    self.regroupMember = nil
    self.formationMovementPace = nil
    self.state = "IDLE"
    self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
    print("[KnoxSurvivors][Autonomy] id=" .. self.id
        .. " detached-recovered=true")
    return true
end

function Controller:interruptSelfCareForDanger(ticks)
    if self.pendingRecreation~=nil then
        self:releaseBaseRecreation()
        self.activeDecision,self.state=nil,"IDLE"
        return true
    end
    if self.state == "INVENTORY_CLEANUP" or self.state == "MOVING_TO_DEPOSIT" then
        if self.state == "MOVING_TO_DEPOSIT" then self.bridge:cancelNpcMove(self.id) end
        ISTimedActionQueue.clear(self.character)
        self.pendingCleanup = nil
        self.pendingDepositTrip = nil
        self.nextCleanupAt = ticks + 600
        self.activeDecision = nil
        self.state = "IDLE"
        return true
    end
    local selfCare = self.state == "TIMED_ACTION"
        or self.state == "MOVING_TO_REST"
        or self.state == "WAITING_TO_RECOVER"
        or self.state == "SLEEPING_RECOVERY"
    if not selfCare then
        return false
    end
    local interrupted = self.activeDecision
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self.bridge:cancelNpcMove(self.id)
    self:leaveRecoveryPosture()
    self.selfCareInterrupted = interrupted
    self.selfCareIntent = nil
    self.activeDecision = nil
    self.state = "IDLE"
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " self-care-interrupted=" .. tostring(interrupted)
            .. " reason=immediate_danger tick=" .. tostring(ticks)
    )
    return true
end

function Controller:beginCombat(target)
    local awareness = self.pendingThreatAwareness
    if target == nil or target:getCurrentSquare() == nil then
        return false
    end
    local now = self.currentTicks or self.nextThreatScan or 0
    local heldItem = self.character:getPrimaryHandItem()
    if self.unarmedRetryUntil ~= nil then
        if heldItem == self.rejectedCombatItem and now < self.unarmedRetryUntil then
            return false
        end
        self.unarmedRetryUntil = nil
        self.rejectedCombatItem = nil
        if self.unarmedRejectedTarget ~= nil then
            self.failedThreats[self.unarmedRejectedTarget] = nil
            self.unarmedRejectedTarget = nil
        end
    end
    self:cancelTrade("combat")
    if awareness == nil then
        awareness = evaluateThreat(self, target, self.nextThreatScan or 0)
    end
    if awareness == nil or not reserveThreat(
        self.reservations,
        target,
        self.id,
        awareness.attackerLimit
    ) then
        return false
    end
    self:interruptSelfCareForDanger(self.nextThreatScan or 0)
    -- Firearms use the game's timed reload action.  Do this before clearing other
    -- actions so an already-running reload is allowed to finish instead of being
    -- cancelled and restarted every threat scan.
    local firearmState, firearmResult
    if self.rangedFallbackUntil ~= nil
        and (self.rangedFallbackUntil[target] or 0) > (self.currentTicks or 0) then
        -- Keep the close-range fallback long enough to finish a melee attempt.
        -- Otherwise the next threat scan immediately selects the same gun again.
        firearmState = "melee"
        firearmResult = KnoxFirearmSupport.fallbackToMelee(self.id, self.bridge)
    else
        firearmState, firearmResult = KnoxFirearmSupport.prepareForThreat(
            self.id, self.character, self.bridge, target
        )
    end
    if firearmState == "reloading" then
        releaseThreat(self.reservations, target, self.id)
        self.nextThreatScan = self.nextThreatScan + THREAT_SCAN_TICKS
        print(
            "[KnoxSurvivors][Autonomy] id=" .. self.id
                .. " firearm=" .. tostring(firearmState)
                .. " result=" .. tostring(firearmResult)
        )
        return false
    end
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self:releaseGroupSupport()
    self:suspendBaseTaskForThreat("combat_interrupt")
    if self.activeDecision == "rest" or self.activeDecision == "sleep" then
        self:leaveRecoveryPosture()
    end
    local approach = combatApproachSquare(self.character, target)
    if approach == nil then
        releaseThreat(self.reservations, target, self.id)
        return false
    end
    local result = tostring(self.bridge:beginNpcLiveCombat(self.id, target, approach))
    if string.find(result, "COMBAT_STARTED", 1, true) ~= 1 then
        self.bridge:resetNpcCombat(self.id)
        local noWeapon = string.find(result, "NO_EQUIPPED_WEAPON", 1, true) ~= nil
        if noWeapon then
            self.unarmedCombatBlocked = true
            self.rejectedCombatItem = self.character:getPrimaryHandItem()
            self.unarmedRejectedTarget = target
            self.unarmedRetryUntil = now + THREAT_FAILURE_COOLDOWN_TICKS
        end
        local retry = THREAT_FAILURE_COOLDOWN_TICKS
        self.failedThreats[target] = self.nextThreatScan + retry
        releaseThreat(self.reservations, target, self.id)
        self:recordFailure(
            "combat_start:" .. result,
            self.nextThreatScan,
            retry
        )
        -- An unarmed survivor must immediately change survival mode after the
        -- native combat bridge rejects the attack. Waiting for another threat
        -- scan leaves them stationary in the bite zone.
        if noWeapon then
            local flee, assessment = self:assessFlee()
            if flee then
                self:beginFlee(now, assessment)
            end
        end
        return false
    end
    self.unarmedCombatBlocked = nil
    self:releaseSupply()
    self.combatTarget = target
    self.activeDecision = "fight"
    self.state = "COMBAT"
    sayDialogue(self.character, self.id, "combat", self.nextThreatScan or 0, 900)
    awareness = awareness or {}
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id .. " state=COMBAT " .. result
            .. " awareness=" .. tostring(awareness.reason or "unknown")
            .. " distance=" .. tostring(awareness.distance or "unknown")
    )
    self.pendingThreatAwareness = nil
    return true
end

function Controller:beginWorldSearch(goal, ticks)
    self:setLifeIntent(goal, "seeking", nil, nil)
    if ticks < self.nextWorldSearch then
        return false
    end
    local supply = findSupply(self, goal, ticks)
    if supply == nil then
        self.nextWorldSearch = ticks + SUPPLY_RETRY_TICKS
        return false
    end
    if not reserve(self.reservations, "items", supply.item, self.id) then
        return false
    end
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, supply.approach, "urgent"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        release(self.reservations, "items", supply.item, self.id)
        self.inspectedContainers[supply.container] = ticks + SUPPLY_RETRY_TICKS
        self.nextWorldSearch = ticks + SUPPLY_RETRY_TICKS
        self:recordMovementFailure("supply_move", result, ticks, SUPPLY_RETRY_TICKS)
        return false
    end
    self.pendingSupply = supply
    self.activeDecision = goal
    self.state = "MOVING_TO_SUPPLY"
    self:setLifeIntent(
        goal,
        "traveling",
        supply.approach,
        roamDestinationKey(supply.container:getSourceGrid())
    )
    local dialogueEvent = goal == "find_food" and "need_food"
        or (goal == "find_water" and "need_water"
            or (goal == "find_medical" and "need_medical" or "search"))
    sayDialogue(self.character, self.id, dialogueEvent, ticks, 1800)
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=MOVING_TO_SUPPLY goal=" .. goal
            .. " item=" .. tostring(supply.item:getFullType())
    )
    return true
end

function Controller:beginCompanionNeedDirective(ticks, directive)
    local kind = tostring(directive ~= nil and directive.kind or "")
    if kind ~= "find_food" and kind ~= "find_water" and kind ~= "find_medical"
        and kind ~= "find_weapon" and kind ~= "find_tools" and kind ~= "clean_inventory" then
        return false
    end
    if kind == "clean_inventory" then
        if self:beginInventoryCleanup(ticks) then return true end
        self.directiveMisses = (self.directiveMisses or 0) + 1
        if self.directiveMisses >= 3 then
            KnoxPersistence.clearCompanionDirective(
                self.id, self.companionOwnerId, currentWorldAgeHours()
            )
            self.companionDirective = nil
            self.directiveMisses = 0
            KnoxActivityFeed.speak(self.character, "My pack is in order.")
        else
            self.nextThink = math.max(self.nextThink or 0, ticks + SUPPLY_RETRY_TICKS)
        end
        return true
    end
    if self:beginWorldSearch(kind, ticks) then
        return true
    end
    if ticks >= (self.nextWorldSearch or 0) then
        self.directiveMisses = (self.directiveMisses or 0) + 1
        if self.directiveMisses >= 3 then
            KnoxPersistence.clearCompanionDirective(
                self.id,
                self.companionOwnerId,
                currentWorldAgeHours()
            )
            self.companionDirective = nil
            self.directiveMisses = 0
            KnoxActivityFeed.speak(self.character,
                kind == "find_food" and "I couldn't find food here."
                    or (kind == "find_water" and "I couldn't find water here."
                        or (kind == "find_medical"
                            and "I couldn't find medical supplies here."
                            or (kind == "find_tools"
                                and "I couldn't find any useful tools here."
                                or "I couldn't find a better weapon here."))))
        else
            self.nextThink = math.max(self.nextThink or 0, ticks + SUPPLY_RETRY_TICKS)
        end
    end
    return true
end

function Controller.campIdleChoice(ticks, slot, canExcursion)
    local phase = (math.floor((ticks or 0) / CAMP_DECISION_TICKS)
        + math.max(1, tonumber(slot) or 1) * 3) % 10
    if phase <= 1 then
        return "rest"
    end
    if phase <= 3 then
        return "reposition"
    end
    if phase <= 5 and canExcursion then
        return "excursion"
    end
    return "wait"
end

-- Keep idle residents from making identical random choices on the same tick.
-- The phase is deterministic per survivor, so save/load and controller refresh
-- do not synchronize an entire base into simultaneous pacing or resting.
function Controller.baseIdleJitter(id)
    local value = 17
    local text = tostring(id or "")
    for index = 1, #text do
        value = (value * 31 + string.byte(text, index)) % 2147483647
    end
    return value % 120
end

function Controller.baseIdleChoice(ticks, id, residentCount)
    local phase = math.floor((tonumber(ticks) or 0) / 900)
        + Controller.baseIdleJitter(id)
        + math.max(0, tonumber(residentCount) or 0) * 2
    phase = phase % 10
    if phase <= 3 then return "move" end
    if phase <= 6 then return "rest" end
    return "wait"
end

function Controller:beginCampMovement(ticks, returning)
    if self.camp == nil then
        return false
    end
    self:releaseCampPosition()
    local target = KnoxFactionCamps.positionFor(
        self.camp,
        self.campSlot + (self.campPositionCycle or 0),
        function(square)
            return reservedByOther(
                self.reservations,
                "campPositions",
                square,
                self.id
            )
        end
    )
    if target == nil or not reserve(
        self.reservations,
        "campPositions",
        target,
        self.id
    ) then
        self:recordFailure("camp_position_unavailable", ticks, CAMP_POSITION_FAILURE_TICKS)
        return false
    end
    self.campPosition = target
    local current = self.character:getCurrentSquare()
    if current == target then
        self.activeDecision = "camp_idle"
        self.state = "CAMP_IDLE"
        self.nextThink = ticks + CAMP_DECISION_TICKS
        return true
    end
    local result = tostring((moveWithTravelPace(
        self.bridge,
        self.id,
        self.character,
        target,
        returning and "return_home" or "local"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:releaseCampPosition()
        self:recordMovementFailure(
            returning and "camp_return" or "camp_reposition",
            result,
            ticks,
            CAMP_POSITION_FAILURE_TICKS
        )
        return false
    end
    self.activeDecision = returning and "return_to_camp" or "camp_reposition"
    self.state = returning and "CAMP_RETURN" or "CAMP_REPOSITION"
    if returning then
        sayDialogue(self.character, self.id, "camp", ticks, 3600)
    end
    return true
end

function Controller:beginCampAmbientRest(ticks)
    self:releaseCampPosition()
    self.activeDecision = "camp_ambient_rest"
    self.ambientRest = true
    local spot = findBestRestSpot(self, false, function(square)
        return KnoxFactionCamps.contains(self.camp, square)
    end)
    if spot ~= nil and reserve(self.reservations, "restSpots", spot.object, self.id) then
        self.pendingRest = spot
        if spot.approach == self.character:getCurrentSquare() then
            self:startRecoveryPosture(ticks, true, true)
            return true
        end
        local result = tostring(self.bridge:moveNpc(self.id, spot.approach))
        if string.find(result, "MOVE_STARTED", 1, true) == 1 then
            self.state = "MOVING_TO_REST"
            return true
        end
        self:releaseRestSpot()
    end
    self:startRecoveryPosture(ticks, false, true)
    return true
end

function Controller:beginCampExcursion(ticks)
    self:releaseCampPosition()
    self.campExcursion = true
    self.campExcursionExplored = false
    self.nextCampExcursion = ticks + CAMP_EXCURSION_COOLDOWN_TICKS
    if self:beginRoam(ticks) then
        return true
    end
    self.campExcursion = false
    self.nextThink = math.max(
        self.nextThink or 0,
        ticks + CAMP_POSITION_FAILURE_TICKS
    )
    return false
end

function Controller:signalFollowers(emote, ticks)
    if self.groupLeader ~= nil or #(self.groupMembers or {}) <= 1
        or ticks < (self.nextLeaderEmoteAt or 0)
        or self.character.playEmote == nil
        or not self.character:getCharacterActions():isEmpty() then return false end
    local signals = rawget(_G, "KnoxOrderSignals")
    local ok = signals ~= nil and signals.play(self.character, emote) == true
    if ok then self.nextLeaderEmoteAt = ticks + 900 end
    return ok
end

function Controller:beginRoam(ticks, inheritedIntent)
    local current = self.character:getCurrentSquare()
    if current ~= nil then
        rememberRoamDestination(
            self,
            roamDestinationKey(current),
            ticks,
            ROAM_GOAL_COOLDOWN_TICKS
        )
    end
    local target, key, kind = findRoamTarget(self, ticks)
    if target == nil then
        self.nextThink = ticks + ROAM_NO_GOAL_RETRY_TICKS
        return false
    end
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target, "travel"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        rememberRoamDestination(self, key, ticks, ROAM_FAILURE_COOLDOWN_TICKS)
        self:recordMovementFailure("roam_move", result, ticks)
        return false
    end
    self:signalFollowers("followme", ticks)
    self.activeDecision = "roam"
    self.state = "ROAMING"
    self.roamGoalKey = key
    self.roamGoalKind = kind
    self:setLifeIntent(
        Controller.roamIntentKind(
            kind,
            inheritedIntent or (self.lifeIntent ~= nil and self.lifeIntent.kind or nil)
        ),
        "traveling",
        target,
        key
    )
    self.nextRoamNeedsCheck = ticks + ROAM_NEEDS_RECHECK_TICKS
    self.forceTravel = false
    local dx, dy = target:getX() - current:getX(), target:getY() - current:getY()
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then self.roamHeading = { x = dx / length, y = dy / length } end
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=ROAMING goal=" .. tostring(kind)
            .. " target=" .. target:getX() .. "," .. target:getY()
    )
    sayDialogue(self.character, self.id,
        kind == "building" and "roam_building" or "roam_area", ticks, 3600)
    return true
end

function Controller:recoverFleeMovement(result, ticks)
    self.bridge:cancelNpcMove(self.id)
    if self.fleeTarget ~= nil then
        self.failedFleeTarget = { x = self.fleeTarget:getX(), y = self.fleeTarget:getY(),
            z = self.fleeTarget:getZ(), untilTick = ticks + FLEE_PLAN_TICKS }
    end
    self.fleeTarget = nil
    self.fleeDirectionUntil = 0
    -- Normal travel's long backoff is unsafe while being pursued. Still bounded,
    -- but retry another clear escape lane rather than standing for many seconds.
    local cooldown = self:recordMovementFailure("flee_move", result, ticks, 15, 60)
    self.fleeRecoveryUntil = ticks + cooldown
    self.activeDecision = "flee"
    self.state = "FLEEING"
    self.stateStartedAt = ticks
end

function Controller.fleePace(assessment)
    if assessment == nil then return "run" end
    -- Sprint only to break close contact; sustained sprinting through a distant
    -- crowd burns the endurance needed when a real escape becomes urgent.
    return (assessment.endurance or 0) >= 0.48 and (assessment.health or 0) > 25
        and ((assessment.immediate or 0) > 0 or (assessment.close or 0) > 0)
        and "sprint" or "run"
end

function Controller:beginFlee(ticks, assessment)
    local settings = rawget(_G, "KnoxSettings")
    if settings ~= nil and settings.allowSurvivorFleeing ~= nil
        and not settings.allowSurvivorFleeing() then
        return false
    end
    self:cancelTrade("danger")
    self.combatDisengageUntil = ticks + FLEE_DISENGAGE_TICKS
    local target, hadGroupPlan = groupFleeTarget(self, ticks)
    local emergency = false
    if target == nil then
        target = findFleeTarget(self, ticks)
        local key = groupFleeKey(self)
        if target ~= nil and key ~= nil and (not hadGroupPlan or key == self.id) then
            fleePlans[key] = {
                x = target:getX(), y = target:getY(), z = target:getZ(),
                expiresAt = ticks + FLEE_PLAN_TICKS,
            }
        end
    end
    if target == nil then
        -- Passive followers and other non-combat survivors need a final
        -- movement attempt when every checked lane is blocked.  Do not use
        -- this branch for a survivor who can legally engage the adjacent
        -- attacker; that existing combat handoff is safer than forcing a
        -- route through an obstruction.
        local threat = nearestThreat(self, ticks)
        if threat == nil or not self:allowsCompanionThreat(threat) then
            target = findEmergencyFleeTarget(self, ticks)
            emergency = target ~= nil
        end
    end
    if target == nil then
        self.nextThink = ticks + FLEE_RECHECK_TICKS
        if self.state == "FLEEING" then self.fleeRecoveryUntil = self.nextThink end
        self.nextThreatScan = math.max(
            self.nextThreatScan or 0,
            ticks + FLEE_RECHECK_TICKS
        )
        -- If every escape lane is blocked, do not wait helplessly for a bite.
        -- Reuse native combat against an adjacent reachable threat only; this
        -- is not permission to chase a target back into the crowd.
        if self.state ~= "COMBAT" then
            local threat = nearestThreat(self, ticks)
            local origin = self.character:getCurrentSquare()
            local threatSquare = threat ~= nil and threat:getCurrentSquare() or nil
            if threatSquare ~= nil and origin ~= nil
                and distanceSquared(origin, threatSquare) <= 3.0625
                and fleeLaneClear(origin, threatSquare)
                and self:allowsCompanionThreat(threat)
                and not self.unarmedCombatBlocked then
                if self:beginCombat(threat) then
                    self.fleeRecoveryUntil = nil
                    self.fleeTarget = nil
                end
            end
        end
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    self:suspendBaseTaskForThreat("survival_flee")
    self:interruptSelfCareForDanger(ticks)
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self:releaseCombat()
    self:releaseSupply()
    self:leaveRecoveryPosture()
    local origin = self.character:getCurrentSquare()
    if origin ~= nil then
        local dx = target:getX() - origin:getX()
        local dy = target:getY() - origin:getY()
        local length = math.sqrt(dx * dx + dy * dy)
        if length >= 0.01 then
            self.lastFleeDirectionX = dx / length
            self.lastFleeDirectionY = dy / length
            self.fleeDirectionUntil = ticks + FLEE_PLAN_TICKS
        end
    end
    self.fleeSafeScans = 0
    self.fleeTarget = target
    self.fleeRecoveryUntil = nil
    local pace = emergency and "sprint" or Controller.fleePace(assessment)
    local result = tostring(self.bridge:moveNpcWithPace(self.id, target, pace))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:recoverFleeMovement(result, ticks)
        return false
    end
    self.activeDecision = "flee"
    self.state = "FLEEING"
    self.stateStartedAt = ticks
    self.nextThink = ticks + FLEE_RECHECK_TICKS
    sayDialogue(self.character, self.id, "flee", ticks, 900)
    print("[KnoxSurvivors][Autonomy] id=" .. self.id
        .. " state=FLEEING reason=" .. tostring(assessment and assessment.reason)
        .. " zombies=" .. tostring(assessment and assessment.zombies or 0)
        .. " humans=" .. tostring(assessment and assessment.humans or 0)
        .. " allies=" .. tostring(assessment and assessment.allies or 1)
        .. " health=" .. tostring(assessment and assessment.health or 100)
        .. " risk=" .. tostring(assessment and assessment.risk or 0)
        .. " immediate=" .. tostring(assessment and assessment.immediate or 0)
        .. " escapeLanes=" .. tostring(assessment and assessment.escapeLanes or 0)
        .. " pace=" .. pace
        .. " target=" .. target:getX() .. "," .. target:getY())
    return true
end

function Controller:beginFactionBaseScout(ticks)
    local candidate = self.factionBaseCandidate
    local target = KnoxFactionBaseScouting.resolveTarget(candidate)
    if candidate == nil then
        return false
    end
    if target == nil then
        self:rejectFactionBaseCandidate(ticks, "target_unloaded")
        return false
    end
    local result = tostring((moveWithTravelPace(
        self.bridge, self.id, self.character, target, "travel"
    )))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:rejectFactionBaseCandidate(ticks, result)
        return false
    end
    self.activeDecision = "scout_faction_base"
    self.state = "MOVING_TO_BASE_CANDIDATE"
    if self.announcedFactionBaseCandidate ~= candidate.buildingId then
        self.announcedFactionBaseCandidate = candidate.buildingId
        KnoxActivityFeed.speak(self.character, "Let's check that place out.")
        KnoxActivityFeed.event(
            "Possible base near " .. tostring(candidate.x) .. ", "
                .. tostring(candidate.y) .. ". Not claimed yet."
        )
    end
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=MOVING_TO_BASE_CANDIDATE faction=" .. tostring(self.factionId)
            .. " building=" .. tostring(candidate.buildingId)
            .. " score=" .. tostring(candidate.score)
    )
    return true
end

local function cleanupContext(self)
    local base, requirements = nil, {}
    local duty = KnoxPersistence.getSurvivorDuty(self.id)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(self.id) or {}
    if duty ~= nil and duty.baseId ~= nil then base = KnoxPersistence.getBase(duty.baseId)
    elseif affiliation.kind == "player" and affiliation.ownerId ~= nil then
        base = KnoxPersistence.getBaseForOwner("player", affiliation.ownerId)
    elseif affiliation.factionId ~= nil then
        base = KnoxPersistence.getBaseForOwner("faction", affiliation.factionId)
    end
    for _, task in pairs(base ~= nil and base.tasks or {}) do
        if task.state == "queued" or task.state == "claimed" then
            for itemType, count in pairs(task.requirements ~= nil and task.requirements.items or {}) do
                requirements[itemType] = math.max(requirements[itemType] or 0, tonumber(count) or 0)
            end
        end
    end
    return base, requirements, duty
end

function Controller:canMakeDepositTrip(duty)
    if self.baseTask ~= nil or self.companionOrder ~= nil or self.companionDirective ~= nil then return false end
    -- Faction membership does not bind a resident to the leader during base life.
    if duty ~= nil and duty.mode == "base" and duty.baseId == self.baseId then return true end
    return self.groupLeader == nil and #(self.groupMembers or {}) <= 1
        and (duty == nil or duty.mode == "base" or duty.mode == "autonomous")
end

function Controller:deferDepositTrip(ticks)
    self.depositRetryAt = self.depositRetryAt or {}
    for key, deadline in pairs(self.depositRetryAt) do
        if deadline <= ticks then self.depositRetryAt[key] = nil end
    end
    local trip = self.pendingDepositTrip
    if trip ~= nil then self.depositRetryAt[trip.policyKey] = ticks + 1800 end
    -- Bounded transient memory, even for bases with many assigned containers.
    local count, oldest, deadline = 0, nil, math.huge
    for key, expires in pairs(self.depositRetryAt) do
        count = count + 1
        if expires < deadline then oldest, deadline = key, expires end
    end
    if count > 16 then self.depositRetryAt[oldest] = nil end
    self.nextCleanupAt = ticks + 600
end

function Controller:beginDepositTrip(base, plan, duty, ticks)
    if base == nil or not self:canMakeDepositTrip(duty)
        or KnoxBaseStorage.findDepositTrip == nil then return false end
    for _, entry in ipairs(plan) do
        if not entry.canDrop or entry.value >= 15 then
            local storage = KnoxBaseStorage.findDepositTrip(base, self.character, entry.item,
                self.depositRetryAt, ticks)
            if storage ~= nil then
                self.pendingDepositTrip = { baseId = base.id, policyKey = storage.policy.key,
                    item = entry.item, baseSupply = entry.baseSupply == true }
                self:leaveRecoveryPosture()
                local result = tostring(moveWithTravelPace(self.bridge, self.id, self.character,
                    storage.approach, "return_home"))
                if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
                    self.bridge:cancelNpcMove(self.id)
                    self:deferDepositTrip(ticks)
                    self.pendingDepositTrip = nil
                    self:recordMovementFailure("deposit_move", result, ticks)
                    return false
                end
                self.activeDecision = entry.baseSupply == true and "base_supply_deposit" or "deposit_surplus"
                self.state = "MOVING_TO_DEPOSIT"
                self.stateStartedAt = ticks
                return true
            end
        end
    end
    return false
end

function Controller:completeDepositTrip(ticks)
    local trip = self.pendingDepositTrip
    local base, requirements, duty = cleanupContext(self)
    -- Recompute utility and ownership at arrival. Equipment, jobs, the base,
    -- container capacity and even the item may have changed during travel.
    if trip ~= nil and base ~= nil and base.id == trip.baseId and self:canMakeDepositTrip(duty) then
        local plan
        if trip.baseSupply == true then
            local inventory = self.character:getInventory()
            plan = {}
            if self.pendingBaseSupplyDeposit ~= nil and self.pendingBaseSupplyDeposit.item == trip.item
                and inventory ~= nil and inventory:contains(trip.item) then
                plan[1] = {item=trip.item, source=inventory, reason="base_supply", baseSupply=true}
            end
        else
            plan = KnoxSurvivorLooting.cleanupPlan(self.character, requirements, true, true)
        end
        for _, entry in ipairs(plan) do
            if entry.item == trip.item then
                local storage = KnoxBaseStorage.findNearbyDeposit(base, self.character, entry.item, trip.policyKey)
                if storage ~= nil then
                    local action = KnoxInventoryActions.queueTransfer(self.character, entry.item,
                        entry.source, storage.container, nil)
                    if action ~= nil then
                        self.pendingCleanup = { item = entry.item, source = entry.source,
                            destination = storage.container, reason = entry.reason,
                            baseSupply = entry.baseSupply == true }
                        self.state = "INVENTORY_CLEANUP"
                        self.stateStartedAt = ticks
                        return true
                    end
                end
                break
            end
        end
    end
    self:deferDepositTrip(ticks)
    self:finishDecision(ticks)
    return false
end

-- A base-supply run is different from ordinary inventory cleanup: the item was
-- deliberately recovered for the settlement, so it must be handed to the
-- assigned storage even when it is not considered personal surplus. Keep the
-- transfer on the same native inventory path and clear the marker only after
-- the destination contains the real item.
function Controller:beginBaseSupplyDeposit(ticks)
    local pending = self.pendingBaseSupplyDeposit
    local base = self.base
    if pending == nil or pending.item == nil or base == nil
        or self.baseId == nil or self.character == nil
        or not KnoxBaseManager.containsSquare(base, self.character:getCurrentSquare())
        or not self.character:getCharacterActions():isEmpty()
        or KnoxBaseStorage.findNearbyDeposit == nil then
        return false
    end
    local item = pending.item
    local inventory = self.character:getInventory()
    if inventory == nil or not inventory:contains(item) then
        self.pendingBaseSupplyDeposit = nil
        self:clearLifeIntent()
        return false
    end
    local target = KnoxBaseStorage.findDepositTrip(base, self.character, item, self.depositRetryAt, ticks)
    local storage = target ~= nil and KnoxBaseStorage.findNearbyDeposit(base, self.character, item, target.policy.key) or nil
    if storage == nil then
        local duty = KnoxPersistence.getSurvivorDuty(self.id)
        if target ~= nil and self:beginDepositTrip(base,
            {{item=item, source=inventory, canDrop=false, baseSupply=true}}, duty, ticks) then return true end
        self.nextThink = math.max(self.nextThink or 0, ticks + 600)
        return false
    end
    local action, result = KnoxInventoryActions.queueTransfer(
        self.character, item, inventory, storage.container, nil
    )
    if action == nil then
        self.nextThink = math.max(self.nextThink or 0, ticks + 180)
        self:recordFailure("base_supply_deposit:" .. tostring(result), ticks, 180)
        return false
    end
    self.pendingCleanup = {
        item = item,
        source = inventory,
        destination = storage.container,
        reason = "base_supply",
        baseSupply = true,
    }
    self.activeDecision = "base_supply_deposit"
    self.state = "INVENTORY_CLEANUP"
    self.stateStartedAt = ticks
    return true
end

function Controller:beginInventoryCleanup(ticks)
    if rawget(_G, "KnoxSurvivorLooting") == nil or KnoxSurvivorLooting.cleanupPlan == nil then return false end
    if self.state ~= "IDLE" or ticks < (self.nextCleanupAt or 0) or self.baseTask ~= nil
        or not self.character:getCharacterActions():isEmpty() then return false end
    self.nextCleanupAt = ticks + 300
    local base, requirements, duty = cleanupContext(self)
    local atBase = base ~= nil and KnoxBaseManager ~= nil
        and KnoxBaseManager.containsSquare(base, self.character:getCurrentSquare())
    local plan, result = KnoxSurvivorLooting.cleanupPlan(self.character, requirements, self.cleanupInProgress, atBase)
    self.cleanupInProgress = result == "heavy_load"
    if #plan == 0 then return false end
    local candidate, destination
    -- Prefer a real nearby deposit for any surplus before dropping a lower-value
    -- item. No autonomous detour may override Follow/Hold/Guard or a base job.
    for _, entry in ipairs(plan) do
        local preferred = self:canMakeDepositTrip(duty) and KnoxBaseStorage.findDepositTrip ~= nil
            and KnoxBaseStorage.findDepositTrip(base, self.character, entry.item, self.depositRetryAt, ticks) or nil
        local storage = KnoxBaseStorage.findNearbyDeposit(base, self.character, entry.item,
            preferred ~= nil and preferred.policy.key or nil)
        if storage ~= nil then candidate, destination = entry, storage.container break end
    end
    if candidate == nil and self:beginDepositTrip(base, plan, duty, ticks) then return true end
    if candidate == nil and atBase then return false end
    if candidate == nil then
        for _, entry in ipairs(plan) do
            if entry.canDrop then candidate = entry break end
        end
    end
    if candidate == nil then return false end
    local action, reason
    if destination ~= nil then
        action, reason = KnoxInventoryActions.queueTransfer(self.character, candidate.item,
            candidate.source, destination, nil)
    else action, reason = KnoxInventoryActions.queueDrop(self.character, candidate.item) end
    if action == nil then
        self.nextCleanupAt = ticks + 600
        return false
    end
    self.pendingCleanup = { item = candidate.item, source = candidate.source,
        destination = destination, reason = candidate.reason }
    self.activeDecision = destination ~= nil and "deposit_surplus" or "drop_surplus"
    self.state = "INVENTORY_CLEANUP"
    self.stateStartedAt = ticks
    return true
end

function Controller:updateInventoryCleanup(ticks)
    if not self.character:getCharacterActions():isEmpty() then return end
    local transfer = self.pendingCleanup
    local completed = transfer ~= nil and not transfer.source:contains(transfer.item)
        and ((transfer.destination ~= nil and transfer.destination:contains(transfer.item))
            or (transfer.destination == nil and transfer.item:getWorldItem() ~= nil))
    if not completed then
        if self.pendingDepositTrip ~= nil then self:deferDepositTrip(ticks) end
        self.nextCleanupAt = ticks + 600
        self:recordFailure("cleanup_transfer_not_completed", ticks, 60)
    else
        if transfer ~= nil and transfer.baseSupply == true then
            self.pendingBaseSupplyDeposit = nil
            self:clearLifeIntent()
        end
        print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " inventory-cleanup="
            .. tostring(self.activeDecision) .. " reason=" .. tostring(transfer.reason))
    end
    if self.companionDirective ~= nil
        and self.companionDirective.kind == "clean_inventory" then
        KnoxPersistence.clearCompanionDirective(
            self.id, self.companionOwnerId, currentWorldAgeHours()
        )
        self.companionDirective = nil
        self.directiveMisses = 0
    end
    self:finishDecision(ticks)
end

function Controller:think(ticks)
    -- The decision boundary agrees with the intervening threat scans: unseen-by-
    -- zombies travel can continue quietly, but contact/active danger always wins.
    local quiet = shouldRemainStealthy(self)
    if not quiet then
        local flee, assessment = fleeAssessment(self)
        if flee and self:beginFlee(ticks, assessment) then return end
    end
    local threat = not quiet and nearestThreat(self, ticks) or nil
    if not self:allowsCompanionThreat(threat) then
        threat = nil
    end
    local decision = KnoxSurvivorNeeds.decide(self.character, threat)
    if decision.kind == "fight" then
        if not self:beginCombat(decision.target) then
            self.nextThink = ticks + THINK_MIN_TICKS
        end
        return
    end
    if (decision.kind == "eat" or decision.kind == "drink"
        or decision.kind == "bandage" or decision.kind == "improvise_medical"
        or decision.kind == "rest" or decision.kind == "sleep"
        or decision.kind == "find_food" or decision.kind == "find_water"
        or decision.kind == "find_medical")
        and not Controller.selfCareReady(
            self.selfCareRetryAt,
            decision.kind,
            ticks
        ) then
        -- The need remains real, but a failed native action must not monopolize
        -- every think cycle. Preserve the underlying Follow/Hold/roam activity
        -- until this one bounded retry expires.
        decision = { kind = "roam", state = decision.state }
    end
    if decision.kind == "eat" or decision.kind == "drink"
        or decision.kind == "bandage" or decision.kind == "improvise_medical" then
        local action, result, intent = KnoxSurvivorNeeds.execute(
            self.character,
            decision
        )
        if action ~= nil and action ~= false then
            self:sayNeedIfGrouped(decision.kind, ticks)
            self.activeDecision = decision.kind
            self.selfCareIntent = intent
            self.selfCareInterrupted = nil
            self.state = "TIMED_ACTION"
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " state=TIMED_ACTION kind=" .. decision.kind
            )
        else
            self.selfCareRetryAt[decision.kind] = ticks + SELF_CARE_RETRY_TICKS
            self:recordFailure(
                "needs_action:" .. decision.kind .. ":" .. tostring(result),
                ticks,
                SELF_CARE_RETRY_TICKS
            )
        end
        return
    end
    if decision.kind == "find_food" and self:beginBaseCooking(ticks,nil,true) then return end
    if decision.kind == "find_food" or decision.kind == "find_water"
        or decision.kind == "find_medical" then
        self:sayNeedIfGrouped(decision.kind, ticks)
        if self:hasNeedEscort() then
            -- Only a short clear detour is automatic. If none is safe, retain
            -- the real shortage and regroup instead of starting a roam search.
            if self:beginWorldSearch(decision.kind, ticks) then return end
            self.selfCareRetryAt[decision.kind] = ticks + SELF_CARE_RETRY_TICKS
            decision = { kind = "roam", state = decision.state }
        else
        if self.groupLeader ~= nil and self.groupLeader:getCurrentSquare() ~= nil
            and Controller.shouldDelegateNeedToGroup(
                decision.kind,
                navigationDistanceSquared(
                self.character:getCurrentSquare(),
                self.groupLeader:getCurrentSquare()
                )
            ) then
            -- The leader will either share a real spare or own one group search.
            -- A nearby follower must not split off and create a competing route.
            self.activeDecision = "await_group_" .. decision.kind
            self.state = "GROUP_WAIT"
            self.nextThink = ticks + 60
            return
        end
        if not self:beginWorldSearch(decision.kind, ticks) then
            self:beginRoam(ticks, decision.kind)
        end
        return
        end
    end
    if decision.kind == "rest" or decision.kind == "sleep" then
        self:sayNeedIfGrouped(decision.kind, ticks)
        self:beginRecovery(decision.kind, ticks)
        return
    end
    if self.lifeIntent ~= nil
        and (self.lifeIntent.kind == "find_food"
            or self.lifeIntent.kind == "find_water"
            or self.lifeIntent.kind == "find_medical") then
        -- The real need evaluator no longer requests this resource. End the
        -- durable purpose here instead of letting a satisfied survivor keep
        -- searching because an older intent survived an interruption/reload.
        self:clearLifeIntent()
    end
    if self:beginGroupSupport(ticks) then return end
    if self.groupLeader == nil and #(self.groupMembers or {}) > 1 then
        local groupNeed = KnoxGroupSupport.mostUrgentNeed(
            self.character,
            self.groupMembers
        )
        if groupNeed ~= nil then
            if not self:beginWorldSearch(groupNeed.kind, ticks) then
                self:beginRoam(ticks, groupNeed.kind)
            end
            return
        end
    end
    if self:beginInventoryCleanup(ticks) then return end
    if self:beginEventTravel(ticks) then return end
    if self.awayTeamId ~= nil then
        local awayTeam = KnoxPersistence.getAwayTeam(self.awayTeamId)
        if awayTeam ~= nil and (awayTeam.state == "awaiting_collection"
            or awayTeam.state == "collecting" or awayTeam.state == "returning") then
            if self:beginAwayMission(ticks) then
                return
            end
            -- A mission-owned survivor must not fall through into roaming,
            -- companion or base logic when its destination is temporarily
            -- unavailable. Keep the durable away duty authoritative and retry
            -- through this same bounded boundary.
            self.nextThink = math.max(self.nextThink or 0,
                ticks + EXPLORATION_RETRY_TICKS)
            return
        end
    end
    if self.companionOrder ~= nil then
        if self.companionDirective ~= nil then
            local kind = self.companionDirective.kind
            if kind == "go_to" or kind == "guard" then
                if self:beginCompanionPointDirective(ticks, self.companionDirective) then
                    return
                end
                self.nextThink = math.max(self.nextThink or 0, ticks + EXPLORATION_RETRY_TICKS)
                return
            end
            if kind == "patrol_area" then
                if self:beginCompanionPatrolDirective(ticks, self.companionDirective) then
                    return
                end
                self.nextThink = math.max(self.nextThink or 0,
                    ticks + EXPLORATION_RETRY_TICKS)
                return
            end
            if kind == "find_food" or kind == "find_water" or kind == "find_medical"
                or kind == "find_weapon" or kind == "find_tools" then
                self:beginCompanionNeedDirective(ticks, self.companionDirective)
                return
            end
            if self:beginExploration(ticks, self.companionDirective) then
                return
            end
            if self.companionDirective ~= nil then
                self.nextThink = ticks + EXPLORATION_RETRY_TICKS
                return
            end
        end
        if self.companionOrder == "hold" then
            self.activeDecision = "hold_position"
            self.state = "COMPANION_HOLD"
            self.nextThink = ticks + 90
            return
        end
        if self.companionOrder == "relax" then
            self:beginCompanionRelax(ticks)
            return
        end
        if self.companionTarget == nil
            or self.companionTarget:getCurrentSquare() == nil then
            self.activeDecision = "follow_player"
            self.state = "COMPANION_WAIT"
            self.nextThink = ticks + 60
            return
        end
        local formationTarget = findFormationTarget(
            self.companionTarget,
            self.character,
            self.companionFormationSlot, self.id
        )
        local distance = formationTarget ~= nil and navigationDistanceSquared(
            self.character:getCurrentSquare(),
            formationTarget
        ) or math.huge
        if distance > FORMATION_ARRIVAL_TOLERANCE_SQUARED then
            self:beginCompanionFollow(ticks)
        else
            self:resetMovementRecovery()
            self.formationMovementPace = nil
            self.activeDecision = "follow_player"
            self.state = "COMPANION_WAIT"
            self.nextThink = ticks + 45
        end
        return
    end
    if self.baseId ~= nil and self.base ~= nil then
        self:syncBaseSupplyRun()
        local atBase = KnoxBaseManager.containsSquare(
            self.base,
            self.character:getCurrentSquare()
        )
        if self.baseSupplyTrip == true and self.pendingBaseSupplyDeposit == nil
            and self.baseSupplyKind ~= nil then
            local resumedKind = self.baseSupplyKind
            if self:beginWorldSearch(resumedKind, ticks) then
                self:beginBaseSupplyRun(resumedKind)
                return
            end
            self:finishBaseSupplyRun("unavailable")
            if self.baseSupplyOrder ~= nil then
                self:recordExplicitBaseSupplyFailure(ticks)
            end
            self:releaseSupply()
            if not atBase then
                self:beginBaseMovement(ticks, true)
            else
                self.activeDecision = "base_supply_retry"
                self.state = "BASE_IDLE"
                self.nextThink = ticks + SUPPLY_RETRY_TICKS
            end
            return
        elseif not atBase then
            if not self:resumeExternalBaseWork(ticks) then
                self:beginBaseMovement(ticks, true)
            end
        elseif self.pendingBaseSupplyDeposit ~= nil
            and self:beginBaseSupplyDeposit(ticks) then
            return
        elseif self.baseTask == nil then
            local explicit = self.baseSupplyOrder
            local explicitKind = explicit ~= nil and tostring(explicit.kind or "") or nil
            local explicitExpired = explicit ~= nil
                and tonumber(explicit.expiresAtHours) ~= nil
                and tonumber(explicit.expiresAtHours) <= currentWorldAgeHours()
            if explicitExpired then
                if KnoxPersistence.clearBaseSupplyOrder ~= nil then
                    local duty = KnoxPersistence.getSurvivorDuty(self.id) or {}
                    KnoxPersistence.clearBaseSupplyOrder(
                        self.id, duty.ownerId, self.baseId, currentWorldAgeHours()
                    )
                end
                self.baseSupplyOrder = nil
                self.baseSupplyOrderAttempts = 0
                explicit = nil
                explicitKind = nil
            end
            if explicitKind ~= nil and explicitKind ~= "" then
                self.baseSupplyTrip = true
                self.baseSupplyKind = explicitKind
                if self:beginWorldSearch(explicitKind, ticks) then
                    self:beginBaseSupplyRun(explicitKind)
                    return
                end
                self:recordExplicitBaseSupplyFailure(ticks)
                self:releaseSupply()
                self.nextThink = ticks + SUPPLY_RETRY_TICKS
                return
            end
            -- A resident without an already-claimed native task should answer
            -- a real settlement shortage before accepting ordinary work. This
            -- keeps food/water/medical recovery aligned with the existing
            -- priority model without interrupting a job already in progress.
            local supplyGoal = self:baseSupplyNeed(ticks)
            if supplyGoal ~= nil then
                if self:beginWorldSearch(supplyGoal, ticks) then
                    self:beginBaseSupplyRun(supplyGoal)
                    return
                end
                self:finishBaseSupplyRun("unavailable")
                self:releaseSupply()
                self.nextBaseSupplySearch = ticks + SUPPLY_RETRY_TICKS
            end
            if self:beginBaseTask(ticks) then
                return
            end
            local residentIds = KnoxPersistence.getBaseResidentIds ~= nil
                and KnoxPersistence.getBaseResidentIds(self.baseId) or {}
            local choice = Controller.baseIdleChoice(
                ticks,
                self.id,
                type(residentIds) == "table" and #residentIds or 1
            )
            if choice == "move" then
                self:beginBaseMovement(ticks, false)
            elseif choice == "rest" then
                self:beginAmbientBaseRest(ticks)
            else
                self.activeDecision = "base_idle"
                self.state = "BASE_IDLE"
                self.nextThink = ticks + 600 + Controller.baseIdleJitter(self.id)
            end
        elseif self:beginBaseTask(ticks) then
            return
        end
        return
    end
    if self.factionBaseCandidate ~= nil then
        if not self:beginFactionBaseScout(ticks) then
            self.nextThink = ticks + THINK_MIN_TICKS
        end
        return
    end
    if self.campId ~= nil and self.camp ~= nil then
        local atCamp = KnoxFactionCamps.contains(
            self.camp,
            self.character:getCurrentSquare()
        )
        if not atCamp then
            if self.campExcursion and not self.campExcursionExplored then
                self.campExcursionExplored = true
                if self:beginExploration(ticks) then
                    return
                end
            end
            if not self:beginCampMovement(ticks, true) then
                self.nextThink = math.max(
                    self.nextThink or 0,
                    ticks + CAMP_POSITION_FAILURE_TICKS
                )
            end
            return
        end
        if self.campExcursion then
            self.campExcursion = false
            self.campExcursionExplored = false
        end
        if self.campPosition == nil then
            if not self:beginCampMovement(ticks, false) then
                self.nextThink = math.max(
                    self.nextThink or 0,
                    ticks + CAMP_POSITION_FAILURE_TICKS
                )
            end
            return
        end
        local choice = Controller.campIdleChoice(
            ticks,
            self.campSlot,
            ticks >= (self.nextCampExcursion or 0)
        )
        if choice == "rest" then
            self:beginCampAmbientRest(ticks)
        elseif choice == "reposition" then
            self.campPositionCycle = (self.campPositionCycle or 0) + 1
            self:beginCampMovement(ticks, false)
        elseif choice == "excursion" then
            self:beginCampExcursion(ticks)
        else
            self.activeDecision = "camp_idle"
            self.state = "CAMP_IDLE"
            self.nextThink = ticks + CAMP_DECISION_TICKS
        end
        return
    end
    if self.groupLeader ~= nil and self.groupLeader:getCurrentSquare() ~= nil then
        local formationTarget = findFormationTarget(
            self.groupLeader,
            self.character,
            self.groupFormationSlot, self.id
        )
        local distance = formationTarget ~= nil and navigationDistanceSquared(
            self.character:getCurrentSquare(),
            formationTarget
        ) or math.huge
        if distance > FORMATION_ARRIVAL_TOLERANCE_SQUARED then
            self:beginGroupFollow(ticks)
        else
            self:resetMovementRecovery()
            self.formationMovementPace = nil
            if self.groupObjectiveChanged then
                self.groupObjectiveChanged = false
                self.nextGroupObjectiveAssist = math.max(
                    self.nextGroupObjectiveAssist or 0,
                    ticks + self.groupFormationSlot * 45
                )
            elseif ticks >= (self.nextGroupObjectiveAssist or 0)
                and Controller.shouldAssistGroupObjective(
                    self.groupObjective,
                    navigationDistanceSquared(
                        self.character:getCurrentSquare(),
                        self.groupLeader:getCurrentSquare()
                    )
                ) then
                self.nextGroupObjectiveAssist = ticks
                    + GROUP_OBJECTIVE_ASSIST_COOLDOWN_TICKS
                    + self.groupFormationSlot * 120
                if self:beginExploration(ticks) then
                    return
                end
                self.nextGroupObjectiveAssist = ticks
                    + GROUP_OBJECTIVE_ASSIST_RETRY_TICKS
                    + self.groupFormationSlot * 30
            end
            self.state = "GROUP_WAIT"
            self.nextThink = ticks + 60
        end
        return
    end
    local distantMember, distantDistance = self:findDistantGroupMember()
    if distantMember ~= nil then
        if distantDistance > GROUP_RETRIEVE_LEASH_SQUARED
            and self:beginGroupRegroup(distantMember, ticks) then
            return
        end
        self.state = "GROUP_WAIT"
        self.nextThink = math.max(self.nextThink or 0, ticks + 90)
        return
    end
    if self.forceTravel then
        if not self:beginRoam(ticks) then
            self.nextThink = ticks + THINK_MIN_TICKS
        end
        return
    end
    if not self:beginExploration(ticks) then
        self:beginRoam(ticks)
    end
end

function Controller:tick(ticks)
    self.currentTicks = ticks
    if self.state ~= "PLAYER_CONVERSATION" then self.playerConversation = nil end
    local vehicles = rawget(_G, "KnoxCompanionVehicles")
    if self.character ~= nil and vehicles ~= nil and vehicles.isBusy ~= nil then
        -- Native passenger actions own their route and inputs until completion.
        local busy, result = vehicles.isBusy(self.character)
        if busy then return end
        if result == "interrupted" then self.nextThreatScan = 0; self.nextThink = 0 end
        if self.character.getVehicle ~= nil and self.character:getVehicle() ~= nil then return end
    end
    if self.tradeAction ~= nil and self.state ~= "TRADING" then self:cancelTrade("behavior_changed") end
    if self.character == nil or self.character:getCurrentSquare() == nil then
        self:cancelTrade("detached")
        -- The population owner, not the behavior controller, decides when an NPC is
        -- actually stored. A streamed-out shell can temporarily lose its square before
        -- the hibernation pass captures/removes it, so keep that state explicit.
        self.state = "DETACHED"
        return
    end

    if self:recoverFromDetached(ticks) then
        return
    end

    -- Sandbox settings can be changed between sessions while a survivor was
    -- captured in retreat. Release that temporary ownership immediately; the
    -- durable Follow/Hold/group/camp intent remains intact and will resume.
    local settings = rawget(_G, "KnoxSettings")
    if self.state == "FLEEING" and settings ~= nil
        and settings.allowSurvivorFleeing ~= nil
        and not settings.allowSurvivorFleeing() then
        self.bridge:cancelNpcMove(self.id)
        self:resetMovementRecovery()
        self.fleeRecoveryUntil = nil
        self.fleeTarget = nil
        self.failedFleeTarget = nil
        self.fleeSafeScans = 0
        self.combatDisengageUntil = 0
        self:finishDecision(ticks)
        self.nextThink = ticks + 5
        return
    end

    if self.observedState ~= self.state then
        self.observedState = self.state
        self.stateStartedAt = ticks
    end

    if self.state == "BASE_TASK_MOVE" and self.baseTask ~= nil
        and (self.baseTask.type == "guard" or self.baseTask.type == "patrol")
        and (self.baseTask.state ~= "claimed" or self.baseTask.claimedBy ~= self.id) then
        self.nextSecurityCheck = ticks
        self:updateBaseSecurityDuty(ticks)
        return
    end

    -- Gear is reconsidered only while the survivor is otherwise idle. Combat owns
    -- firearm/melee transitions, and timed actions must never be interrupted just
    -- to swap a marginal item.
    if self.state == "IDLE" then
        KnoxEquipmentIntelligence.reconsider(self.id, self.character, self.bridge, ticks, false)
    end

    local stateAge = ticks - (self.stateStartedAt or ticks)
    local movementState = self.state == "MOVING_TO_SUPPLY"
        or self.state == "EVENT_TRAVEL"
        or self.state == "MOVING_TO_DEPOSIT"
        or self.state == "MOVING_TO_EXPLORE"
        or self.state == "ROAMING"
        or self.state == "GROUP_FOLLOW" or self.state == "GROUP_REGROUP"
        or self.state == "COMPANION_FOLLOW"
        or self.state == "MOVING_TO_COMPANION_POINT"
        or self.state == "MOVING_TO_COMPANION_PATROL"
        or self.state == "BASE_RETURN" or self.state == "BASE_PATROL"
        or self.state == "BASE_TASK_MOVE"
        or self.state == "BASE_TASK_SUPPLY_MOVE"
        or self.state == "MEETING_APPROACH"
        or self.state == "MOVING_TO_WINDOW_ENTRY"
        or self.state == "CROSSING_WINDOW_ENTRY"
        or self.state == "MOVING_TO_REST"
        or self.state == "MOVING_TO_BASE_CANDIDATE"
        or self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION"
        or self.state == "AWAY_RETURN"
        or self.state == "FLEEING"
    local actionState = self.state == "LOOTING"
        or self.state == "OPENING_ENTRY_WINDOW"
        or self.state == "INVENTORY_CLEANUP"
        or self.state == "SEARCHING"
        or self.state == "TIMED_ACTION"
        or self.state == "ROBBING"
        or (self.state == "BASE_TASK_WORK"
            and (self.baseTask == nil or self.baseTask.type ~= "guard"))
        or self.state == "BASE_TASK_ACTION"
        or self.state == "BASE_TASK_SUPPLY_TRANSFER"
        or self.state == "GROUP_SUPPORT"
    if (movementState and stateAge > MOVEMENT_TIMEOUT_TICKS)
        or (actionState and stateAge > ACTION_TIMEOUT_TICKS)
        or (self.state == "BREAKING_LOCKED_DOOR"
            and stateAge > MOVEMENT_TIMEOUT_TICKS) then
        if self.securityRoute~=nil and (self.state=="BASE_TASK_MOVE"
            or self.state=="MOVING_TO_COMPANION_PATROL" or self.state=="MOVING_TO_COMPANION_POINT") then
            self:deferSecurityRoute(ticks,"state_timeout",self.securityRoute.base)
            return
        end
        if self.state == "FLEEING" then
            self:recoverFleeMovement("state_timeout", ticks)
            return
        elseif self.state == "COMPANION_FOLLOW" or self.state == "BASE_RETURN"
            or self.state == "BASE_PATROL" or self.state == "AWAY_RETURN" then
            self.bridge:cancelNpcMove(self.id)
            self.activeDecision = nil
            self.state = "IDLE"
            self.nextThink = ticks + THINK_MIN_TICKS
            return
        elseif self.state == "MOVING_TO_BASE_CANDIDATE" then
            self:rejectFactionBaseCandidate(ticks, "state_timeout")
        end
        self:abandonCurrentDecision(ticks, "state_timeout_" .. tostring(self.state))
        return
    end

    local traversalBusy = movementState and nativeTraversalBusy(self.character)
    -- Both danger evaluation and active-combat decisions consume this scheduled
    -- observation. Advancing the deadline must not starve the combat branch.
    local threatScanDue = ticks >= self.nextThreatScan and not traversalBusy
    if threatScanDue then
        self.nextThreatScan = ticks + THREAT_SCAN_TICKS
        local stealthCrowd = self.state ~= "COMBAT" and self.state ~= "FLEEING"
            and shouldRemainStealthy(self)
        if not stealthCrowd then
            local flee, assessment = fleeAssessment(self)
            if self.state ~= "FLEEING" and flee then
                self:beginFlee(ticks, assessment)
                -- Whether route acquisition succeeded or entered bounded recovery,
                -- do not reacquire an attack in this same danger scan.
                return
            end
            if self.state == "FLEEING" and retreatIsSafelyClear(self, flee, assessment, ticks) then
                self.bridge:cancelNpcMove(self.id)
                self:resetMovementRecovery()
                self.fleeRecoveryUntil = nil
                self.fleeTarget = nil
                self.failedFleeTarget = nil
                self.combatDisengageUntil = ticks + FLEE_DISENGAGE_TICKS
                self:finishDecision(ticks)
                self.nextThink = ticks + 5
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " retreat-complete safe_scans=" .. tostring(self.fleeSafeScans)
                )
                return
            end
            if self.state ~= "COMBAT" and self.state ~= "FLEEING" then
                local threat = nearestThreat(self, ticks)
                if not self:allowsCompanionThreat(threat) then
                    threat = nil
                end
                -- A corpse carrier is committed to the native grapple/drag
                -- lifecycle.  Do not let a close zombie turn the next scan
                -- into an attack attempt while the survivor is still holding
                -- the body; that produces the visible swing/loot/repeat loop.
                -- The existing flee interruption releases the corpse safely,
                -- suspends the claimed job, and can then hand off to native
                -- defense if every escape lane is blocked.
                local haulingCorpse = self.baseTask ~= nil
                    and self.baseTask.type == "haul_corpse"
                    and KnoxBaseCorpseHandling ~= nil
                    and KnoxBaseCorpseHandling.isDragging ~= nil
                    and KnoxBaseCorpseHandling.isDragging(self.character)
                if threat ~= nil and haulingCorpse then
                    local origin = self.character:getCurrentSquare()
                    local threatSquare = threat:getCurrentSquare()
                    if origin ~= nil and threatSquare ~= nil
                        and distanceSquared(origin, threatSquare) <= 36 then
                        local needs = KnoxSurvivorNeeds.snapshot(self.character)
                        self:beginFlee(ticks, {
                            reason = "corpse_carrier_threat",
                            immediate = 1,
                            close = 1,
                            endurance = needs ~= nil and needs.endurance or 0,
                            health = needs ~= nil and needs.health or 0,
                        })
                        return
                    end
                end
                if threat ~= nil and self:beginCombat(threat) then
                    return
                end
            end
        end
    end

    if self.state == "PLAYER_CONVERSATION" then
        self:updatePlayerConversation(ticks)
        return
    end

    if self.state == "TRADING" then
        self.tradeTicksRemaining = (self.tradeTicksRemaining or 0) - 1
        if self.tradeAction == nil then
            self.state, self.activeDecision, self.nextThink = "IDLE", nil, 0
        elseif self.tradeTicksRemaining <= 0 or not self.tradeAction:isValid() then
            self:cancelTrade("trade_interrupted_or_expired")
        end
        return
    end

    if self.state == "MEETING_WAIT" or self.state == "MEETING_READY"
        or self.state == "GREETING" then
        return
    end

    if self.state == "ROAMING" and ticks >= (self.nextRoamNeedsCheck or 0) then
        self.nextRoamNeedsCheck = ticks + ROAM_NEEDS_RECHECK_TICKS
        local roamingNeed = KnoxSurvivorNeeds.decide(self.character, nil)
        if Controller.shouldInterruptRoamingForNeed(roamingNeed.kind)
            and Controller.selfCareReady(
                self.selfCareRetryAt,
                roamingNeed.kind,
                ticks
            ) then
            self.bridge:cancelNpcMove(self.id)
            self.roamGoalKey = nil
            self.roamGoalKind = nil
            self.activeDecision = nil
            self.state = "IDLE"
            self.nextThink = ticks
            return
        end
    end

    if self.state == "GROUP_WAIT" then
        if ticks >= self.nextThink then
            self.state = "IDLE"
        end
        return
    end

    if self.state == "COMPANION_HOLD" or self.state == "COMPANION_GUARD" then
        -- Keep the persistent order, while allowing the same needs boundary as
        -- base guards. Previously this state never returned to think(), so a
        -- stationary companion could starve with food in their inventory.
        if ticks >= self.nextThink then
            self.nextThink = ticks + 90
            local need = KnoxSurvivorNeeds.decide(self.character, nil)
            if need ~= nil and need.kind ~= "roam" then
                self.state = "IDLE"
                self.nextThink = ticks
            elseif self.state == "COMPANION_GUARD" and self.companionDirective ~= nil then
                -- Re-resolve the assigned post after a shove or displacement.
                self:beginCompanionPointDirective(ticks, self.companionDirective)
            end
        end
        return
    end

    if self.state == "COMPANION_DUTY_WAIT" or self.state == "BASE_SECURITY_WAIT" then
        self:updateSecurityRouteWait(ticks,self.state=="BASE_SECURITY_WAIT")
        return
    end

    if self.state == "COMPANION_WAIT" or self.state == "COMPANION_PATROL_WAIT" then
        if ticks >= self.nextThink then
            self.state = "IDLE"
        end
        return
    end

    if self.state == "BASE_IDLE" or self.state == "EVENT_WAIT" then
        if ticks >= self.nextThink then
            self.activeDecision = nil
            self.state = "IDLE"
        end
        return
    end

    if self.state == "CAMP_IDLE" then
        if ticks >= self.nextThink then
            self.activeDecision = nil
            self.state = "IDLE"
        end
        return
    end

    if self.state == "BASE_RECREATION" then
        self:updateBaseRecreation(ticks)
        return
    end

    if self.state == "BASE_AMBIENT_REST" then
        if ticks >= self.nextThink then
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "CAMP_AMBIENT_REST" then
        if ticks >= self.nextThink then
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "COMPANION_RELAX" then
        self:updateCompanionRelax(ticks)
        return
    end

    if self.state == "BASE_TASK_SUPPLY_WAIT" then
        if self.baseTask == nil then
            self:finishDecision(ticks)
        elseif ticks >= (self.nextThink or 0) then
            self:beginBaseTaskSupplyOrWork(ticks)
        end
        return
    end

    if self.state == "BASE_TASK_PATROL_WAIT" then
        self:updateBaseSecurityDuty(ticks)
        if self.state ~= "BASE_TASK_PATROL_WAIT" then return end
        if self.baseTask == nil then
            self:finishDecision(ticks)
        elseif ticks >= (self.nextThink or 0) then
            self:beginBaseTaskWorkMove(ticks)
        end
        return
    end

    if self.state == "BASE_TASK_WORK" then
        if self.baseTask == nil then
            self.state = "IDLE"
            self.activeDecision = nil
            self.nextThink = ticks + THINK_MIN_TICKS
            return
        end
        if self.baseTask.type == "guard" then
            self:updateBaseSecurityDuty(ticks)
            return
        end
        local started = self.baseTaskStartedAt or ticks
        if ticks - started >= KnoxBaseJobs.workDuration(self.baseTask) then
            local taskType = self.baseTask.type
            self:finishBaseTask(true, "completed_" .. tostring(taskType))
            local completionLines = {
                guard = "All clear here.", patrol = "Patrol route is clear.",
                barricade = "That opening is secured.", construct_defense = "The defense work is done.",
                repair = "That repair is finished.",
                haul_corpse = "The body is out of the way.", animal_water = "The animals have water.",
                animal_feed = "The animals are fed.", farm_water = "The crops are watered.",
                farm_harvest = "The harvest is gathered.", farm_plow = "The soil is ready.",
                farm_seed = "The plot is planted.", chop_tree = "The tree is down.",
                saw_logs = "The logs are cut.",
            }
            KnoxActivityFeed.speak(self.character,
                completionLines[taskType] or "That job is finished."
            )
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "BASE_COOKING" then
        self:updateBaseCooking(ticks)
        return
    end

    if self.state == "BASE_TASK_SUPPLY_TRANSFER" then
        if self.baseTask == nil or self.baseTaskSupplyTransfer == nil then
            self.state = "IDLE"
            self.activeDecision = nil
            self.nextThink = ticks + THINK_MIN_TICKS
            return
        end
        if hasPendingTimedActions(self.character) then
            return
        end
        self.baseTaskSupplyTransfer = nil
        self:beginBaseTaskSupplyOrWork(ticks)
        return
    end

    if self.state == "BASE_TASK_ACTION" then
        if self.baseTask == nil
            or (self.baseTask.type ~= "barricade"
                and self.baseTask.type ~= "farm_water"
                and self.baseTask.type ~= "farm_harvest"
                and self.baseTask.type ~= "farm_plow"
                and self.baseTask.type ~= "farm_seed"
                and self.baseTask.type ~= "chop_tree"
                and self.baseTask.type ~= "saw_logs"
                and self.baseTask.type ~= "haul_corpse"
                and self.baseTask.type ~= "animal_water"
                and self.baseTask.type ~= "animal_feed"
                and self.baseTask.type ~= "repair"
                and self.baseTask.type ~= "construct_defense") then
            self:finishBaseTask(false, "unsupported_base_action")
            self:finishDecision(ticks)
            return
        end
        if hasPendingTimedActions(self.character) then return end
        if self.baseTask.type == "barricade" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskBarricadeTarget
                if target == nil then
                    target = KnoxBaseBarricades.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskBarricadeTarget = target
                end
                if target == nil then
                    self:finishBaseTask(false, "barricade_target_invalid")
                    self:finishDecision(ticks)
                    return
                end
                local action, actionResult = KnoxBaseBarricades.queueAction(
                    self.character,
                    target
                )
                if action == nil then
                    self:finishBaseTask(false, "barricade_queue:" .. tostring(actionResult))
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return
            end
            if not self.character:getCharacterActions():isEmpty() then
                return
            end
            local target = self.baseTaskBarricadeTarget
            local complete = KnoxBaseBarricades.isComplete(
                target,
                self.character,
                self.baseTaskBarricadeBefore
            )
            self:finishBaseTask(
                complete,
                complete and "barricade_plank_added" or "barricade_not_completed"
            )
            if complete then
                KnoxActivityFeed.speak(self.character, "One more layer on the windows.")
            end
            self:finishDecision(ticks)
            return
        end
        if self.baseTask.type == "haul_corpse" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskCorpseTarget
                if target == nil then
                    target = KnoxBaseCorpseHandling.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskCorpseTarget = target
                end
                if target == nil then
                    self:finishBaseTask(false, "corpse_target_invalid")
                    self:finishDecision(ticks)
                    return
                end
                local action, actionResult
                if self.baseTaskCorpsePhase == "drop" then
                    action, actionResult = KnoxBaseCorpseHandling.queueDrop(
                        self.character,
                        target
                    )
                else
                    self.baseTaskCorpsePhase = "grab"
                    action, actionResult = KnoxBaseCorpseHandling.queueGrab(
                        self.character,
                        target
                    )
                end
                if action == nil then
                    self:finishBaseTask(false, "corpse_queue:" .. tostring(actionResult))
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return
            end
            if not self.character:getCharacterActions():isEmpty() then
                return
            end
            if self.baseTaskCorpsePhase == "grab" then
                local step, transition, verifyUntil =
                    KnoxBaseCorpseHandling.nextGrabStep(
                        self.character,
                        self.baseTaskCorpseGrabRetryIssued,
                        self.baseTaskCorpseGrabVerifyUntil,
                        ticks
                    )
                self.baseTaskCorpseGrabVerifyUntil = verifyUntil
                if step == "wait" then
                    return
                end
                if step == "retry" then
                    local requested, retryResult =
                        KnoxBaseCorpseHandling.requestGrabRetry(
                            self.character,
                            self.baseTaskCorpseTarget
                        )
                    if not requested then
                        self:finishBaseTask(false,
                            "corpse_grab_retry:" .. tostring(retryResult))
                        self:finishDecision(ticks)
                        return
                    end
                    self.baseTaskCorpseGrabRetryIssued = true
                    print("[KnoxSurvivors][BaseJobs] id=" .. tostring(self.id)
                        .. " corpse-grab-retry=" .. tostring(retryResult)
                        .. " transition=" .. tostring(transition))
                    return
                end
                if step ~= "ready" then
                    self:finishBaseTask(false,
                        "corpse_grab_not_attached:" .. tostring(transition))
                    self:finishDecision(ticks)
                    return
                end
                local target = self.baseTaskCorpseTarget
                local moveResult = tostring(self.bridge:moveNpc(
                    self.id,
                    target ~= nil and target.dropSquare or nil
                ))
                if string.find(moveResult, "MOVE_STARTED", 1, true) ~= 1 then
                    pcall(function() self.character:setDoGrappleLetGo() end)
                    self:finishBaseTask(false, "corpse_drop_move:" .. moveResult)
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskCorpsePhase = "drop"
                self.baseTaskActionQueued = false
                self.baseTaskCorpseDropVerifyUntil = nil
                self.baseTaskCorpseDropRetryIssued = nil
                self.baseTaskStartedAt = ticks
                self.state = "BASE_TASK_MOVE"
                return
            end
            local step, transition, verifyUntil =
                KnoxBaseCorpseHandling.nextDropStep(
                    self.character,
                    self.baseTaskCorpseDropRetryIssued,
                    self.baseTaskCorpseDropVerifyUntil,
                    ticks
                )
            self.baseTaskCorpseDropVerifyUntil = verifyUntil
            if step == "wait" then
                return
            end
            if step == "retry" then
                local requested, retryResult =
                    KnoxBaseCorpseHandling.requestDropRetry(self.character)
                if not requested then
                    self:finishBaseTask(false,
                        "corpse_drop_retry:" .. tostring(retryResult))
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskCorpseDropRetryIssued = true
                print("[KnoxSurvivors][BaseJobs] id=" .. tostring(self.id)
                    .. " corpse-drop-retry=" .. tostring(retryResult)
                    .. " transition=" .. tostring(transition))
                return
            end
            if step ~= "ready" then
                pcall(function() self.character:setDoGrappleLetGo() end)
                self:finishBaseTask(false,
                    "corpse_drop_not_released:" .. tostring(transition))
                self:finishDecision(ticks)
                return
            end
            self:finishBaseTask(true, "corpse_hauled")
            KnoxActivityFeed.speak(self.character, "The body is out of the way.")
            self:finishDecision(ticks)
            return
        end
        if self.baseTask.type == "animal_water"
            or self.baseTask.type == "animal_feed" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskAnimalTarget
                if target == nil then
                    target = KnoxBaseAnimalCare.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskAnimalTarget = target
                    self.baseTaskAnimalBefore = target ~= nil
                        and KnoxBaseAnimalCare.snapshot(target) or nil
                end
                if target == nil then
                    self:finishBaseTask(false, "animal_care_target_invalid")
                    self:finishDecision(ticks)
                    return
                end
                local action, actionResult = KnoxBaseAnimalCare.queueAction(
                    self.character,
                    target
                )
                if action == nil then
                    if actionResult == "turning_to_trough" then
                        return
                    end
                    self:finishBaseTask(false,
                        "animal_care_queue:" .. tostring(actionResult))
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return
            end
            if not self.character:getCharacterActions():isEmpty() then
                return
            end
            local complete = KnoxBaseAnimalCare.isComplete(
                self.baseTaskAnimalTarget,
                self.baseTaskAnimalBefore
            )
            local taskType = self.baseTask.type
            self:finishBaseTask(
                complete,
                complete and "animal_care_complete" or "animal_care_not_completed"
            )
            if complete then
                KnoxActivityFeed.speak(self.character,
                    taskType == "animal_water"
                        and "The trough has water." or "The animals have feed."
                )
            end
            self:finishDecision(ticks)
            return
        end
        if self.baseTask.type == "construct_defense" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskConstructionTarget
                if target == nil then
                    target = KnoxBaseConstruction.resolveTarget(
                        self.base, self.baseTask.target, self.character
                    )
                    self.baseTaskConstructionTarget = target
                end
                if target == nil then
                    self:finishBaseTask(false, "construction_target_invalid")
                    self:finishDecision(ticks)
                    return
                end
                local action, actionResult = KnoxBaseConstruction.queueAction(
                    self.character, target
                )
                if action == nil then
                    self:finishBaseTask(false, "construction_queue:" .. tostring(actionResult))
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return
            end
            if not self.character:getCharacterActions():isEmpty() then return end
            local complete = KnoxBaseConstruction.isComplete(self.baseTaskConstructionTarget)
            self:finishBaseTask(complete, complete and "defense_constructed"
                or "construction_not_completed")
            if complete then KnoxActivityFeed.speak(self.character, "That should make this place safer.") end
            self:finishDecision(ticks)
            return
        end
        if self.baseTask.type == "repair" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskRepairTarget
                if target == nil then
                    target = KnoxBaseRepairs.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskRepairTarget = target
                    self.baseTaskRepairBefore = target ~= nil
                        and KnoxBaseRepairs.snapshot(target) or nil
                end
                if target == nil then
                    self:finishBaseTask(false, "repair_target_invalid")
                    self:finishDecision(ticks)
                    return
                end
                local action, actionResult = KnoxBaseRepairs.queueAction(
                    self.character,
                    target
                )
                if action == nil then
                    self:finishBaseTask(false,
                        "repair_queue:" .. tostring(actionResult))
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return
            end
            if not self.character:getCharacterActions():isEmpty() then
                return
            end
            local complete = KnoxBaseRepairs.isComplete(
                self.baseTaskRepairTarget,
                self.baseTaskRepairBefore
            )
            self:finishBaseTask(
                complete,
                complete and "structure_repaired" or "repair_not_completed"
            )
            if complete then
                KnoxActivityFeed.speak(self.character, "That should hold now.")
            end
            self:finishDecision(ticks)
            return
        end
        if self.baseTask.type == "chop_tree" or self.baseTask.type == "saw_logs" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskWoodcuttingTarget
                if target == nil then
                    target = KnoxBaseWoodcutting.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskWoodcuttingTarget = target
                end
                if target == nil then
                    self:finishBaseTask(false, "tree_target_invalid")
                    self:finishDecision(ticks)
                    return
                end
                local action, actionResult = KnoxBaseWoodcutting.queueAction(
                    self.character,
                    target
                )
                if action == nil then
                    self:finishBaseTask(false, "tree_queue:" .. tostring(actionResult))
                    self:finishDecision(ticks)
                    return
                end
                if self.baseTask.type == "chop_tree" then
                    self.baseTaskWoodcuttingBefore = target.tree:getObjectIndex()
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return
            end
            if not self.character:getCharacterActions():isEmpty() then
                return
            end
            local complete = KnoxBaseWoodcutting.isComplete(
                self.baseTaskWoodcuttingTarget,
                self.baseTaskWoodcuttingBefore
            )
            local taskType = self.baseTask.type
            local finishReason = complete
                and (taskType == "saw_logs" and "logs_sawn" or "tree_chopped")
                or (taskType == "saw_logs" and "logs_not_sawn" or "tree_not_chopped")
            self:finishBaseTask(
                complete,
                finishReason
            )
            if complete then
                KnoxActivityFeed.speak(self.character,
                    taskType == "saw_logs"
                        and "The logs are ready." or "That tree is down."
                )
            end
            self:finishDecision(ticks)
            return
        end
        if self.baseTask.type == "farm_water"
            or self.baseTask.type == "farm_harvest"
            or self.baseTask.type == "farm_plow"
            or self.baseTask.type == "farm_seed" then
            if not self.baseTaskActionQueued then
                local target = self.baseTaskFarmingTarget
                if target == nil then
                    target = KnoxBaseFarming.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    self.baseTaskFarmingTarget = target
                end
                if target == nil then
                    self:finishBaseTask(false, "farming_target_invalid")
                    self:finishDecision(ticks)
                    return
                end
                local water = nil
                if self.baseTask.type == "farm_water" then
                    local item, uses = KnoxBaseFarming.findWaterItem(
                        self.character,
                        self.baseTask.target.waterItemType
                    )
                    if item ~= nil then
                        water = {
                            item = item,
                            uses = math.min(
                                tonumber(uses) or 0,
                                tonumber(self.baseTask.target.waterUses) or 0
                            ),
                        }
                    end
                end
                local action, actionResult = KnoxBaseFarming.queueAction(
                    self.character,
                    target,
                    water
                )
                if action == nil then
                    self:finishBaseTask(false, "farming_queue:" .. tostring(actionResult))
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskActionQueued = true
                self.baseTaskStartedAt = ticks
                return
            end
            if not self.character:getCharacterActions():isEmpty() then
                return
            end
            local complete = KnoxBaseFarming.isComplete(
                self.baseTaskFarmingTarget,
                self.baseTaskFarmingBefore
            )
            local taskType = self.baseTask.type
            self:finishBaseTask(
                complete,
                complete and "farming_action_complete" or "farming_action_not_completed"
            )
                if complete then
                    KnoxActivityFeed.speak(self.character,
                        taskType == "farm_harvest" and "Harvest is in."
                        or taskType == "farm_water" and "Crops are watered."
                        or taskType == "farm_seed" and "Seeds are in."
                        or "The furrow is ready."
                    )
            end
            self:finishDecision(ticks)
            return
        end
    end

    if (self.state == "MOVING_TO_SUPPLY" or self.state == "MOVING_TO_REST") and self:hasNeedEscort()
        and ticks >= (self.nextNeedEscortCheck or 0) then
        self.nextNeedEscortCheck = ticks + 30
        local destination = self.state == "MOVING_TO_SUPPLY" and self.pendingSupply or self.pendingRest
        if destination ~= nil and not self:allowNeedDetour(destination.approach, ticks) then
            self.bridge:cancelNpcMove(self.id)
            if self.state == "MOVING_TO_SUPPLY" then self:releaseSupply()
            else self:releaseRestSpot() end
            self:finishDecision(ticks)
            self.nextThink = ticks + 1
            return
        end
    end
    if self.state == "OPENING_ENTRY_WINDOW" then
        self:updateEntryWindow(ticks)
        return
    end
    if self.state == "COMBAT" then
        if threatScanDue then
            local firearmState, firearmResult = KnoxFirearmSupport.currentCombatState(
                self.character
            )
            if firearmState == "needs_preparation" or firearmState == "reloading" then
                local preparationTarget = self.combatTarget
                self.bridge:resetNpcCombat(self.id)
                self:releaseCombat()
                if firearmState == "needs_preparation" then
                    firearmState, firearmResult = KnoxFirearmSupport.prepareForThreat(
                        self.id,
                        self.character,
                        self.bridge,
                        preparationTarget
                    )
                end
                self:finishDecision(ticks)
                self.nextThreatScan = ticks + THREAT_SCAN_TICKS
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " ranged-combat-yield state=" .. tostring(firearmState)
                        .. " result=" .. tostring(firearmResult)
                )
                return
            end
            if shouldDropCombatTarget(self, ticks) then
                self.bridge:resetNpcCombat(self.id)
                self:releaseCombat()
                self.pendingThreatAwareness = nil
                self:finishDecision(ticks)
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " combat-disengaged reason=invalid_or_irrelevant"
                )
                return
            end
            local replacement = nearestThreat(self, ticks)
            if not self:allowsCompanionThreat(replacement) then
                replacement = nil
            end
            local replacementAwareness = self.pendingThreatAwareness
            if shouldReplaceCombatTarget(self, replacement, replacementAwareness, ticks) then
                local previous = self.combatTarget
                self.lastCombatRetarget = ticks
                self.bridge:resetNpcCombat(self.id)
                self:releaseCombat()
                self.state = "IDLE"
                self.activeDecision = nil
                if self:beginCombat(replacement) then
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " combat-retarget reason="
                            .. tostring(replacementAwareness ~= nil
                                and replacementAwareness.reason or "closer")
                    )
                    return
                end
                -- A failed replacement must not leave the controller permanently in
                -- COMBAT with no target. The normal decision loop can reacquire either
                -- threat on the next scan.
                self.failedThreats[replacement] = ticks + THREAT_SCAN_TICKS
                self.state = "IDLE"
                self.nextThink = ticks + THINK_MIN_TICKS
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " combat-retarget-failed previous=" .. tostring(previous)
                )
                return
            end
            self.pendingThreatAwareness = nil
        end
        local result = tostring(self.bridge:tickNpcCombat(self.id))
        if string.find(result, "COMBAT_FIREARM_REQUEST", 1, true) == 1 then
            local fired, fireResult = KnoxFirearmSupport.fireNative(self.character)
            if not fired then
                local preparationTarget = self.combatTarget
                self.bridge:resetNpcCombat(self.id)
                self:releaseCombat()
                local preparation, preparationResult = KnoxFirearmSupport.prepareForThreat(
                    self.id,
                    self.character,
                    self.bridge,
                    preparationTarget
                )
                self:finishDecision(ticks)
                self.nextThreatScan = ticks + THREAT_SCAN_TICKS
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " firearm-request-yield result=" .. tostring(fireResult)
                        .. " preparation=" .. tostring(preparation)
                        .. " detail=" .. tostring(preparationResult)
                )
            end
        elseif string.find(result, "COMBAT_FIREARM_FALLBACK", 1, true) == 1 then
            if self.combatTarget ~= nil then
                self.rangedFallbackUntil = self.rangedFallbackUntil
                    or setmetatable({}, { __mode = "k" })
                self.rangedFallbackUntil[self.combatTarget] = ticks
                    + THREAT_FAILURE_COOLDOWN_TICKS
            end
            self.bridge:resetNpcCombat(self.id)
            local fallbackResult = KnoxFirearmSupport.fallbackToMelee(
                self.id,
                self.bridge
            )
            self:releaseCombat()
            self:finishDecision(ticks)
            self.nextThreatScan = ticks + THREAT_SCAN_TICKS
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " firearm-close-fallback result=" .. tostring(result)
                    .. " melee=" .. tostring(fallbackResult)
            )
        elseif string.find(result, "COMBAT_SUCCEEDED", 1, true) == 1 then
            self.counts.combat = self.counts.combat + 1
            self.bridge:resetNpcCombat(self.id)
            self:releaseCombat()
            self:finishDecision(ticks)
        elseif string.find(result, "COMBAT_FAILED", 1, true) == 1 then
            self.bridge:resetNpcCombat(self.id)
            self.counts.failures = self.counts.failures + 1
            if self.combatTarget ~= nil then
                self.failedThreats[self.combatTarget] = ticks
                    + THREAT_FAILURE_COOLDOWN_TICKS
            end
            self:releaseCombat()
            self:finishDecision(ticks)
        end
        return
    end


    if self.state == "BREAKING_LOCKED_DOOR" then
        local result = tostring(self.bridge:tickNpcCombat(self.id))
        if string.find(result, "COMBAT_SUCCEEDED", 1, true) == 1 then
            self.bridge:resetNpcCombat(self.id)
            if not self:resumeAfterWindowDetour(ticks) then
                self:abandonCurrentDecision(ticks, "door_break_resume_failed")
            end
        elseif string.find(result, "COMBAT_FAILED", 1, true) == 1 then
            self.bridge:resetNpcCombat(self.id)
            markPendingAreaBlocked(self, ticks, "door_break_failed")
            self:abandonCurrentDecision(ticks, "door_break_failed")
        end
        return
    end

    if self.state == "INVENTORY_CLEANUP" then
        self:updateInventoryCleanup(ticks)
        return
    end

    if self.state == "GROUP_SUPPORT" then
        if not hasPendingTimedActions(self.character) then
            self:completeGroupSupport(ticks)
        end
        return
    end

    if self.state == "TIMED_ACTION" then
        if not hasPendingTimedActions(self.character) then
            local completed, detail = KnoxSurvivorNeeds.verify(
                self.character,
                self.selfCareIntent
            )
            -- A meal or bottle in a bag requires a native transfer first.
            -- Chain the real eat/drink action immediately after that transfer;
            -- otherwise the survivor reports hunger forever while carrying the
            -- food that the planner already fetched.
            if completed and self.selfCareIntent ~= nil
                and self.selfCareIntent.kind == "prepare_supply" then
                local intent = self.selfCareIntent
                local followup = {
                    kind = intent.needKind,
                    state = KnoxSurvivorNeeds.snapshot(self.character),
                    item = intent.item,
                }
                local action, result, nextIntent = KnoxSurvivorNeeds.execute(
                    self.character, followup)
                if action ~= nil and action ~= false then
                    self.selfCareIntent = nextIntent
                    self.activeDecision = intent.needKind
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " self-care-supply-ready kind=" .. tostring(intent.needKind)
                    )
                    return
                end
                completed = false
                detail = "supply_ready_action=" .. tostring(result)
            end
            local kind = self.selfCareIntent ~= nil
                and self.selfCareIntent.kind or tostring(self.activeDecision)
            if completed then
                self.counts.needs = self.counts.needs + 1
                self.selfCareRetryAt[kind] = nil
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " self-care-complete=" .. tostring(kind)
                        .. " " .. tostring(detail)
                )
            else
                self.selfCareRetryAt[kind] = ticks + SELF_CARE_RETRY_TICKS
                self:recordFailure(
                    "needs_no_change:" .. tostring(kind) .. ":" .. tostring(detail),
                    ticks,
                    SELF_CARE_RETRY_TICKS
                )
            end
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "ROBBING" then
        if self.character:getCharacterActions():isEmpty() then
            self.counts.robberies = self.counts.robberies + 1
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " robbery-complete items="
                    .. table.concat(self.pendingRobbery ~= nil
                        and self.pendingRobbery.items or {}, ",")
            )
            self.pendingRobbery = nil
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "MOVING_TO_SUPPLY" or self.state == "MOVING_TO_EXPLORE"
        or self.state == "EVENT_TRAVEL"
        or self.state == "MOVING_TO_DEPOSIT"
        or self.state == "ROAMING" or self.state == "GROUP_FOLLOW"
        or self.state == "GROUP_REGROUP"
        or self.state == "COMPANION_FOLLOW"
        or self.state == "MOVING_TO_COMPANION_POINT"
        or self.state == "MOVING_TO_COMPANION_PATROL"
        or self.state == "BASE_RETURN" or self.state == "BASE_PATROL"
        or self.state == "BASE_TASK_MOVE"
        or self.state == "MEETING_APPROACH"
        or self.state == "MOVING_TO_WINDOW_ENTRY"
        or self.state == "CROSSING_WINDOW_ENTRY" or self.state == "MOVING_TO_REST"
        or self.state == "MOVING_TO_BASE_CANDIDATE"
        or self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION"
        or self.state == "AWAY_RETURN"
        or self.state == "FLEEING" then
        if (self.state == "GROUP_FOLLOW" or self.state == "COMPANION_FOLLOW")
            and self:refreshFormationFollow(ticks) then
            return
        end
        if self.state == "FLEEING" and self.fleeRecoveryUntil ~= nil then
            if ticks >= self.fleeRecoveryUntil then
                local _, assessment = fleeAssessment(self)
                self:beginFlee(ticks, assessment)
            end
            return
        end
        local movement = tostring(self.bridge:tickNpc(self.id))
        if movement == "Succeeded" then
            self:resetMovementRecovery()
            if self.state == "EVENT_TRAVEL" then
                self.eventMoveFailures = 0
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_DEPOSIT" then
                self:completeDepositTrip(ticks)
                return
            end
            if self.state == "MOVING_TO_REST" then
                self:startRecoveryPosture(ticks, true, self.ambientRest == true)
                return
            end
            if self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION" then
                self.campExcursion = false
                self.campExcursionExplored = false
                self.activeDecision = "camp_idle"
                self.state = "CAMP_IDLE"
                self.nextThink = ticks + CAMP_DECISION_TICKS
                return
            end
            if self.state == "AWAY_RETURN" then
                local completed, detail = KnoxPersistence.completeAwayTeamMember(
                    self.awayTeamId,
                    self.id,
                    true,
                    "returned_to_owner",
                    currentWorldAgeHours()
                )
                if completed ~= nil then
                    KnoxActivityFeed.speak(self.character, "Back home.")
                    self.awayTeamId = nil
                    self.awayCollected = false
                    self.awaySearchMisses = 0
                    self.activeDecision = nil
                    self:finishDecision(ticks)
                    self.nextThink = ticks
                else
                    self:recordFailure(
                        "away_return_complete:" .. tostring(detail),
                        ticks,
                        EXPLORATION_RETRY_TICKS
                    )
                    self.state = "IDLE"
                    self.nextThink = ticks + EXPLORATION_RETRY_TICKS
                end
                return
            end
            if self.state == "MOVING_TO_BASE_CANDIDATE" then
                local candidate = self.factionBaseCandidate
                local worldAge = getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                local home, result = KnoxPersistence.confirmFactionHomeBase(
                    self.factionId,
                    candidate ~= nil and candidate.buildingId or nil,
                    worldAge
                )
                if home ~= nil then
                    self.counts.baseScout = self.counts.baseScout + 1
                    KnoxActivityFeed.speak(self.character, "This place could work.")
                    KnoxActivityFeed.event(
                        "Home base claimed near " .. tostring(home.x)
                            .. ", " .. tostring(home.y) .. "."
                    )
                    local _, safehouseResult = KnoxFactionSafehouse.ensure(
                        KnoxPersistence.getFaction(self.factionId)
                    )
                    local base, baseResult = KnoxBaseManager.ensureFactionBase(
                        KnoxPersistence.getFaction(self.factionId)
                    )
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " faction-base-selected=" .. tostring(self.factionId)
                            .. " building=" .. tostring(home.buildingId)
                            .. " bounds=" .. tostring(home.minX) .. "," .. tostring(home.minY)
                                .. "," .. tostring(home.width) .. "," .. tostring(home.height)
                            .. " safehouse=" .. tostring(safehouseResult)
                            .. " base=" .. tostring(base ~= nil and base.id or baseResult)
                    )
                else
                    self.counts.failures = self.counts.failures + 1
                    -- Confirmation can fail after the route itself succeeds
                    -- (ownership conflict, stale building metadata, or a
                    -- changed safehouse). Keep this candidate in the existing
                    -- bounded rejection memory so the next scouting pass does
                    -- not immediately select the same unusable shelter.
                    self:rejectFactionBaseCandidate(ticks, result)
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " faction-base-selection-failed=" .. tostring(result)
                    )
                end
                self:clearFactionBaseCandidate()
                self:finishDecision(ticks)
                return
            end
            if self.state == "CAMP_RETURN" or self.state == "CAMP_REPOSITION" then
                self:releaseCampPosition()
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_WINDOW_ENTRY" then
                if not self:crossWindowDetour(ticks) then
                    if not self:retryWindowDetour(ticks, "cross_start_failed") then
                        self:abandonCurrentDecision(ticks, "window_cross_failed")
                    end
                end
                return
            end
            if self.state == "CROSSING_WINDOW_ENTRY" then
                if not self:resumeAfterWindowDetour(ticks) then
                    self:abandonCurrentDecision(ticks, "window_resume_failed")
                end
                return
            end
            if self.state == "MEETING_APPROACH" then
                self.state = "MEETING_READY"
                return
            end
            if self.state == "GROUP_FOLLOW" then
                self.counts.groupTravel = self.counts.groupTravel + 1
                self:resetMovementRecovery()
                self.formationMovementPace = nil
                self.activeDecision = "follow_group"
                self.state = "GROUP_WAIT"
                self.nextThink = ticks + FORMATION_REFRESH_TICKS
                return
            end
            if self.state == "GROUP_REGROUP" then
                self.counts.groupTravel = self.counts.groupTravel + 1
                self:resetMovementRecovery()
                self.formationMovementPace = nil
                self:finishDecision(ticks)
                return
            end
            if self.state == "COMPANION_FOLLOW" then
                self:resetMovementRecovery()
                self.formationMovementPace = nil
                self.activeDecision = "follow_player"
                self.state = "COMPANION_WAIT"
                self.nextThink = ticks + FORMATION_REFRESH_TICKS
                return
            end
            if self.state == "FLEEING" then
                local unsafe, assessment = fleeAssessment(self)
                if retreatIsSafelyClear(self, unsafe, assessment, ticks) then
                    self.fleeTarget = nil
                    self.failedFleeTarget = nil
                    self.combatDisengageUntil = ticks + FLEE_DISENGAGE_TICKS
                    self:finishDecision(ticks)
                    self.nextThink = ticks + 5
                else
                    self.fleeTarget = nil
                    -- Give the second safe observation time to occur. Starting
                    -- another route immediately resets fleeSafeScans and can
                    -- keep a survivor fleeing after useful separation exists.
                    self.fleeRecoveryUntil = ticks + (unsafe and 5 or FLEE_RECHECK_TICKS)
                end
                return
            end
            if self.securityRoute~=nil and (self.state=="BASE_TASK_MOVE"
                or self.state=="MOVING_TO_COMPANION_PATROL" or self.state=="MOVING_TO_COMPANION_POINT") then
                if self:completeSecurityArrival(ticks,self.securityRoute.base) then return end
            end
            if self.state == "MOVING_TO_COMPANION_POINT" then
                local directive = self.companionDirective
                if directive == nil then
                    self:finishDecision(ticks)
                    return
                end
                self.state = directive.kind == "guard" and "COMPANION_GUARD"
                    or "COMPANION_WAIT"
                self.nextThink = ticks + 90
                if directive.kind == "go_to" then
                    KnoxPersistence.clearCompanionDirective(
                        self.id, self.companionOwnerId,
                        getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                    )
                    self.companionDirective = nil
                    KnoxActivityFeed.speak(self.character, "I'm here.")
                else
                    KnoxActivityFeed.speak(self.character, "I'll keep watch.")
                end
                return
            end
            if self.state == "MOVING_TO_COMPANION_PATROL" then
                self.activeDecision = "patrol_area"
                self.state = "COMPANION_PATROL_WAIT"
                self.nextThink = ticks + 120
                return
            end
            if self.state == "AWAY_RETURN" then
                self:recordMovementFailure("away_return", movement, ticks,
                    EXPLORATION_RETRY_TICKS)
                self.bridge:cancelNpcMove(self.id)
                self.state = "IDLE"
                self.activeDecision = "away_return_retry"
                self.nextThink = ticks + EXPLORATION_RETRY_TICKS
                return
            end
            if self.state == "BASE_RETURN" or self.state == "BASE_PATROL" then
                self:finishDecision(ticks)
                return
            end
            if self.state == "BASE_TASK_SUPPLY_MOVE" then
                local transfer = self.baseTaskSupplyTransfer
                local source = transfer ~= nil and transfer.source ~= nil
                    and transfer.source.container or nil
                if self.baseTask == nil or transfer == nil or source == nil
                    or source:contains(transfer.item) == false then
                    self:finishBaseTask(false, "assigned_supply_no_longer_available")
                    self:finishDecision(ticks)
                    return
                end
                local action, actionResult = KnoxInventoryActions.queueTransfer(
                    self.character,
                    transfer.item,
                    source,
                    self.character:getInventory(),
                    nil
                )
                if action == nil then
                    self:finishBaseTask(false,
                        "assigned_supply_transfer_queue:" .. tostring(actionResult))
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskStartedAt = ticks
                self.activeDecision = "base_task_collect_supplies"
                self.state = "BASE_TASK_SUPPLY_TRANSFER"
                return
            end
            if self.state == "BASE_TASK_MOVE" then
                if self.baseTask ~= nil and self.baseTask.type == "patrol" then
                    local complete, _, stopCount = KnoxCompanionPatrol.recordTaskArrival(
                        self.baseTask
                    )
                    if complete then
                        self.baseTask.patrolLaps = (tonumber(self.baseTask.patrolLaps) or 0) + 1
                    end
                    self.activeDecision = "base_task_patrol"
                    self.state = "BASE_TASK_PATROL_WAIT"
                    self.nextThink = ticks + (complete and 180 or 90)
                    print("[KnoxSurvivors][BaseJobs] id=" .. tostring(self.id)
                        .. " patrol-stop=" .. tostring(self.baseTask.patrolStopsCompleted)
                        .. "/" .. tostring(stopCount)
                        .. " laps=" .. tostring(self.baseTask.patrolLaps or 0))
                    return
                end
                if self.baseTask ~= nil and self.baseTask.type == "haul_corpse" then
                    if self.baseTaskCorpsePhase == "drop" then
                        self.baseTaskStartedAt = ticks
                        self.baseTaskActionQueued = false
                        self.activeDecision = "base_task_haul_corpse_drop"
                        self.state = "BASE_TASK_ACTION"
                        return
                    end
                    self.baseTaskCorpseTarget = KnoxBaseCorpseHandling.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskCorpseTarget == nil then
                        self:finishBaseTask(false, "corpse_target_invalid")
                        self:finishDecision(ticks)
                        return
                    end
                    self.baseTaskCorpsePhase = "grab"
                    self.baseTaskCorpseGrabVerifyUntil = nil
                    self.baseTaskCorpseGrabRetryIssued = nil
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_haul_corpse_grab"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil and self.baseTask.type == "barricade" then
                    self.baseTaskBarricadeTarget = KnoxBaseBarricades.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskBarricadeTarget == nil then
                        self:finishBaseTask(false, "barricade_target_invalid")
                        self:finishDecision(ticks)
                        return
                    end
                    self.baseTaskBarricadeBefore = KnoxBaseBarricades.plankCount(
                        self.baseTaskBarricadeTarget,
                        self.character
                    )
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_barricade"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil and self.baseTask.type == "construct_defense" then
                    self.baseTaskConstructionTarget = KnoxBaseConstruction.resolveTarget(
                        self.base, self.baseTask.target, self.character
                    )
                    if self.baseTaskConstructionTarget == nil then
                        self:finishBaseTask(false, "construction_target_invalid")
                        self:finishDecision(ticks)
                        return
                    end
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_construct_defense"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil
                    and self.baseTask.type == "repair" then
                    self.baseTaskRepairTarget = KnoxBaseRepairs.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskRepairTarget == nil then
                        self:finishBaseTask(false, "repair_target_invalid")
                        self:finishDecision(ticks)
                        return
                    end
                    self.baseTaskRepairBefore = KnoxBaseRepairs.snapshot(
                        self.baseTaskRepairTarget
                    )
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_repair"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil
                    and (self.baseTask.type == "animal_water"
                        or self.baseTask.type == "animal_feed") then
                    self.baseTaskAnimalTarget = KnoxBaseAnimalCare.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskAnimalTarget == nil then
                        self:finishBaseTask(false, "animal_care_target_invalid")
                        self:finishDecision(ticks)
                        return
                    end
                    self.baseTaskAnimalBefore = KnoxBaseAnimalCare.snapshot(
                        self.baseTaskAnimalTarget
                    )
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_" .. tostring(self.baseTask.type)
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil
                    and (self.baseTask.type == "farm_water"
                        or self.baseTask.type == "farm_harvest"
                        or self.baseTask.type == "farm_plow"
                        or self.baseTask.type == "farm_seed") then
                    self.baseTaskFarmingTarget = KnoxBaseFarming.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskFarmingTarget == nil then
                        self:finishBaseTask(false, "farming_target_invalid")
                        self:finishDecision(ticks)
                        return
                    end
                    self.baseTaskFarmingBefore = KnoxBaseFarming.snapshot(
                        self.baseTaskFarmingTarget
                    )
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_" .. tostring(self.baseTask.type)
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil
                    and (self.baseTask.type == "chop_tree"
                        or self.baseTask.type == "saw_logs") then
                    self.baseTaskWoodcuttingTarget = KnoxBaseWoodcutting.resolveTarget(
                        self.base,
                        self.baseTask.target,
                        self.character
                    )
                    if self.baseTaskWoodcuttingTarget == nil then
                        self:finishBaseTask(false, "tree_target_invalid")
                        self:finishDecision(ticks)
                        return
                    end
                    if self.baseTask.type == "chop_tree" then
                        self.baseTaskWoodcuttingBefore =
                            self.baseTaskWoodcuttingTarget.tree:getObjectIndex()
                    end
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_chop_tree"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil and self.baseTask.type == "sort_depot" then
                    self:finishBaseTask(false, "central_cupboard_storage_retired")
                    self:finishDecision(ticks)
                    return
                end
                self.baseTaskStartedAt = ticks
                self.activeDecision = "base_task_work"
                self.state = "BASE_TASK_WORK"
                KnoxActivityFeed.speak(self.character,
                    self.baseTask ~= nil and self.baseTask.type == "guard"
                        and "I'll keep watch here." or "I'll make a patrol."
                )
                return
            end
            if (self.state == "MOVING_TO_SUPPLY" or self.state == "MOVING_TO_EXPLORE")
                and self.pendingSupply ~= nil then
                local supply = self.pendingSupply
                self.inspectedContainers[supply.container] = ticks
                    + (supply.items ~= nil and #supply.items > 0
                        and LOOT_TRAVEL_COOLDOWN_TICKS or EMPTY_SEARCH_COOLDOWN_TICKS)
                local action = nil
                if supply.items ~= nil and #supply.items > 0 then
                    for _, candidate in ipairs(supply.items) do
                        if supply.container:contains(candidate.item) then
                            local queued = KnoxInventoryActions.queueTransfer(
                                self.character,
                                candidate.item,
                                supply.container,
                                self.character:getInventory(),
                                nil
                            )
                            action = action or queued
                        end
                    end
                elseif supply.item ~= nil and supply.container:contains(supply.item) then
                    action = KnoxInventoryActions.queueTransfer(
                        self.character,
                        supply.item,
                        supply.container,
                        self.character:getInventory(),
                        nil
                    )
                else
                    action = KnoxInventoryActions.queueSearch(
                        self.character,
                        supply.container,
                        90
                    )
                end
                if action ~= nil then
                    self.state = (supply.item ~= nil
                        or (supply.items ~= nil and #supply.items > 0))
                        and "LOOTING"
                        or "SEARCHING"
                    if self.state == "LOOTING" then
                        self:sayAction({ "I'll take what we can use.",
                            "Found something useful.", "I'll grab a few things." }, ticks, 1800)
                    else
                        self:sayAction({ "Let me check this.", "I'll have a quick look.",
                            "Give me a second to search this." }, ticks, 1800)
                    end
                else
                    self:recordFailure("loot_action_queue", ticks, 180)
                    self:releaseSupply()
                    self:finishDecision(ticks)
                end
            else
                if self.state == "ROAMING" then
                    if self.lifeIntent ~= nil then
                        self:setLifeIntent(
                            self.lifeIntent.kind,
                            "arrived",
                            nil,
                            self.roamGoalKey
                        )
                    end
                    rememberRoamDestination(
                        self,
                        self.roamGoalKey,
                        ticks,
                        ROAM_GOAL_COOLDOWN_TICKS
                    )
                    self.roamGoalKey = nil
                    self.roamGoalKind = nil
                end
                self.counts.roam = self.counts.roam + 1
                self:finishDecision(ticks)
            end
        elseif string.find(movement, "Failed", 1, true) == 1
            or string.find(movement, "TICK_FAILED", 1, true) == 1 then
            if self.state == "GROUP_FOLLOW"
                or self.state == "GROUP_REGROUP"
                or self.state == "COMPANION_FOLLOW" then
                if (self.state == "GROUP_FOLLOW" or self.state == "GROUP_REGROUP")
                    and Controller.isEntryTraversalFailure(movement) then
                    self:waitForFormationBottleneck(movement, ticks)
                    return
                end
                self:handleFormationMovementFailure(movement, ticks)
                return
            end
            if self.state == "FLEEING" then
                self:recoverFleeMovement(movement, ticks)
                return
            end
            if (self.state=="BASE_TASK_MOVE" and self.baseTask~=nil
                and (self.baseTask.type=="guard" or self.baseTask.type=="patrol"))
                or self.state=="MOVING_TO_COMPANION_PATROL"
                or (self.state=="MOVING_TO_COMPANION_POINT" and self.companionDirective~=nil
                    and self.companionDirective.kind=="guard") then
                self:deferSecurityRoute(ticks,movement,self.state=="BASE_TASK_MOVE")
                return
            end
            self:recordMovementFailure("movement", movement, ticks)
            if self.state == "EVENT_TRAVEL" then
                self.eventMoveFailures = (self.eventMoveFailures or 0) + 1
                self.bridge:cancelNpcMove(self.id)
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_DEPOSIT" then
                self.bridge:cancelNpcMove(self.id)
                self:deferDepositTrip(ticks)
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_COMPANION_POINT"
                or self.state == "MOVING_TO_COMPANION_PATROL" then
                self.directiveMisses = self.directiveMisses + 1
                if self.directiveMisses >= 3 then
                    KnoxPersistence.clearCompanionDirective(
                        self.id, self.companionOwnerId,
                        getGameTime() ~= nil and getGameTime():getWorldAgeHours() or 0
                    )
                    self.companionDirective = nil
                    self.directiveMisses = 0
                    KnoxActivityFeed.speak(self.character, "I can't get there from here.")
                end
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_REST" then
                self:startRecoveryPosture(ticks, false, self.ambientRest == true)
                return
            end
            if self.state == "MOVING_TO_BASE_CANDIDATE" then
                self:rejectFactionBaseCandidate(ticks, movement)
                self.counts.failures = self.counts.failures + 1
                self:finishDecision(ticks)
                return
            end
            if self.state == "BASE_RETURN" or self.state == "BASE_PATROL" then
                self.bridge:cancelNpcMove(self.id)
                self.activeDecision = "base_idle"
                self.state = "BASE_IDLE"
                self.nextThink = math.max(self.nextThink or 0, ticks + 180)
                return
            end
            if self.state == "BASE_TASK_SUPPLY_MOVE" then
                self:finishBaseTask(false, "assigned_supply_movement_failed:" .. movement)
                self:finishDecision(ticks)
                return
            end
            if self.state == "BASE_TASK_MOVE" then
                if self.baseTask ~= nil and self.baseTask.type == "haul_corpse" then
                    if self.baseTaskCorpsePhase == "drop"
                        and KnoxBaseCorpseHandling.isDragging(self.character) then
                        pcall(function() self.character:setDoGrappleLetGo() end)
                    end
                    self:finishBaseTask(false, "corpse_movement_failed:" .. movement)
                    self:finishDecision(ticks)
                    return
                end
                self:finishBaseTask(false, "movement_failed:" .. movement)
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_SUPPLY" and self.pendingSupply ~= nil
                and self.pendingSupply.baseResupply == true then
                self.inspectedContainers[self.pendingSupply.container] = ticks + SUPPLY_RETRY_TICKS
                self:continueBaseResourceRun(ticks, false)
                return
            end
            if (self.state == "MOVING_TO_WINDOW_ENTRY" or self.state == "CROSSING_WINDOW_ENTRY")
                and self:retryWindowDetour(ticks, movement) then return end
            if Controller.isEntryTraversalFailure(movement)
                and (self.state == "MOVING_TO_SUPPLY"
                    or self.state == "MOVING_TO_EXPLORE") then
                local resumeState = self.state
                local lockedDoor = string.find(
                    movement,
                    "FAILED_LOCKED_DOOR",
                    1,
                    true
                ) ~= nil
                if self:beginWindowDetour(ticks, resumeState)
                    or (lockedDoor and self:beginLockedDoorBreak(ticks, resumeState)) then
                    return
                end
                markPendingAreaBlocked(self, ticks, "alternate_entry_unavailable")
            end
            if self.pendingSupply ~= nil and self.pendingSupply.container ~= nil then
                self.inspectedContainers[self.pendingSupply.container] = ticks + SUPPLY_RETRY_TICKS
                local failedSquare = self.pendingSupply.container:getSourceGrid()
                rememberRoamDestination(self, roamDestinationKey(failedSquare), ticks, ROAM_FAILURE_COOLDOWN_TICKS)
                markPendingAreaBlocked(self, ticks, "unreachable_supply")
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " skipped-unreachable-container movement=" .. movement
                )
            end
            if self.state == "ROAMING" then
                rememberRoamDestination(
                    self,
                    self.roamGoalKey,
                    ticks,
                    ROAM_FAILURE_COOLDOWN_TICKS
                )
                self.roamGoalKey = nil
                self.roamGoalKind = nil
                if self.lifeIntent ~= nil then
                    self:setLifeIntent(self.lifeIntent.kind, "reassess", nil, nil)
                end
            end
            self:releaseSupply()
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "LOOTING" then
        if self.character:getCharacterActions():isEmpty() then
            if self.pendingSupply ~= nil and self.pendingSupply.baseResupply == true then
                self:continueBaseResourceRun(ticks, true)
                return
            end
            if self.awayTeamId ~= nil then
                self:finishAwayCollection(ticks)
                return
            end
            self.counts.loot = self.counts.loot + 1
            local changed, equipment = KnoxEquipmentIntelligence.reconsider(
                self.id, self.character, self.bridge, ticks, true
            )
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " loot-complete=" .. tostring(self.activeDecision)
                    .. " equipmentChanged=" .. tostring(changed)
                    .. " equipment=" .. tostring(equipment)
            )
            self.nextExplorationSearch = ticks + LOOT_TRAVEL_COOLDOWN_TICKS
            self.forceTravel = true
            if self.lifeIntent ~= nil and self.lifeIntent.kind == "scavenge" then
                self:clearLifeIntent()
            elseif self.lifeIntent ~= nil then
                self:setLifeIntent(self.lifeIntent.kind, "reassess", nil, nil)
            end
            if self.companionDirective ~= nil
                and (self.companionDirective.kind == "find_food"
                    or self.companionDirective.kind == "find_water"
                    or self.companionDirective.kind == "find_medical"
                    or self.companionDirective.kind == "find_weapon"
                    or self.companionDirective.kind == "find_tools") then
                KnoxPersistence.clearCompanionDirective(
                    self.id, self.companionOwnerId, currentWorldAgeHours()
                )
                self.companionDirective = nil
                self.directiveMisses = 0
            end
            local returnToBase = self.baseSupplyTrip == true
            local explicitBaseSupply = self.baseSupplyOrder ~= nil
            local recoveredBaseItem = returnToBase
                and self.pendingSupply ~= nil and self.pendingSupply.item or nil
            if returnToBase then
                self:finishBaseSupplyRun(
                    recoveredBaseItem ~= nil and "collected" or "empty"
                )
            end
            if explicitBaseSupply then self:clearExplicitBaseSupplyOrder() end
            self:releaseSupply()
            if returnToBase and recoveredBaseItem ~= nil then
                self.pendingBaseSupplyDeposit = { item = recoveredBaseItem }
                local ok, recoveredType = pcall(function()
                    return recoveredBaseItem:getFullType()
                end)
                if ok and type(recoveredType) == "string" and recoveredType ~= "" then
                    self:setLifeIntent("base_supply_deposit", "returning", nil, recoveredType)
                end
            end
            self:finishDecision(ticks)
            if returnToBase then
                -- The next normal decision sees the resident outside its
                -- assigned territory and uses the existing native base-return
                -- movement path. No second mission/order is created.
                self.nextThink = ticks
            end
        end
        return
    end


    if self.state == "SEARCHING" then
        if self.character:getCharacterActions():isEmpty() then
            if self.pendingSupply ~= nil and self.pendingSupply.baseResupply == true then
                self:continueBaseResourceRun(ticks, false)
                return
            end
            if self.awayTeamId ~= nil then
                self:finishAwayCollection(ticks)
                return
            end
            if self.pendingSupply ~= nil and self.pendingSupply.eventId ~= nil then
                KnoxEvents.recordEmptySearch(self.pendingSupply.eventId, self.id)
            end
            self.counts.search = self.counts.search + 1
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " search-complete=container_no_upgrade"
            )
            self.nextExplorationSearch = ticks + EMPTY_SEARCH_COOLDOWN_TICKS
            self.forceTravel = true
            if self.lifeIntent ~= nil and self.lifeIntent.kind == "scavenge" then
                self:clearLifeIntent()
            end
            if self.companionDirective ~= nil
                and (self.companionDirective.kind == "find_food"
                    or self.companionDirective.kind == "find_water"
                    or self.companionDirective.kind == "find_medical"
                    or self.companionDirective.kind == "find_weapon"
                    or self.companionDirective.kind == "find_tools") then
                KnoxPersistence.clearCompanionDirective(
                    self.id, self.companionOwnerId, currentWorldAgeHours()
                )
                self.companionDirective = nil
                self.directiveMisses = 0
            end
            local returnToBase = self.baseSupplyTrip == true
            local explicitBaseSupply = self.baseSupplyOrder ~= nil
            if returnToBase then
                self:finishBaseSupplyRun("empty")
            end
            if explicitBaseSupply then
                self:recordExplicitBaseSupplyFailure(ticks)
            end
            self:releaseSupply()
            self:finishDecision(ticks)
            if returnToBase then
                self.nextThink = ticks
            end
        end
        return
    end

    if self.state == "SLEEPING_RECOVERY" then
        if self.character:isAsleep() then
            if ticks - self.recoveryStarted < SLEEP_RECOVERY_TIMEOUT_TICKS then
                return
            end
            KnoxSurvivorNeeds.wakeForDanger(self.character)
        end
        local recovered, detail = KnoxSurvivorNeeds.verifyRecovery(
            self.character,
            self.selfCareIntent
        )
        if recovered then
            self.counts.needs = self.counts.needs + 1
            self.selfCareRetryAt.sleep = nil
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " self-care-complete=sleep " .. tostring(detail)
            )
        else
            self.selfCareRetryAt.sleep = ticks + SELF_CARE_RETRY_TICKS
            self:recordFailure(
                "needs_no_change:sleep:" .. tostring(detail),
                ticks,
                SELF_CARE_RETRY_TICKS
            )
        end
        self:finishDecision(ticks)
        return
    end

    if self.state == "WAITING_TO_RECOVER" then
        local sitting = self.character:isSitOnGround()
            or self.character:isSittingOnFurniture()
        if self.pendingRest ~= nil and not sitting
            and ticks - self.recoveryPostureStarted >= RECOVERY_POSTURE_TIMEOUT_TICKS then
            self:startRecoveryPosture(ticks, false)
            return
        end
        -- Vanilla IsoPlayer checks sitting before its isPlayerMoving flag when it
        -- updates endurance. Entering a real sitting state therefore restores the
        -- native recovery path without maintaining a second Knox stamina formula.
        if ticks < self.nextThink then
            return
        end
        local snapshot = KnoxSurvivorNeeds.snapshot(self.character)
        local recovered = snapshot.endurance > KnoxSurvivorNeeds.thresholds.lowEndurance
            and (self.activeDecision ~= "sleep"
                or snapshot.fatigue < KnoxSurvivorNeeds.thresholds.fatigue)
        print(
            "[KnoxSurvivors][Autonomy] id=" .. self.id
                .. " recovery-progress endurance=" .. tostring(snapshot.endurance)
                .. " posture=" .. (self.character:isSittingOnFurniture()
                    and "furniture" or (self.character:isSitOnGround() and "ground" or "standing"))
        )
        if recovered then
            local changed, detail = KnoxSurvivorNeeds.verifyRecovery(
                self.character,
                self.selfCareIntent
            )
            if changed then
                self.counts.needs = self.counts.needs + 1
                self.selfCareRetryAt.rest = nil
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " self-care-complete=rest " .. tostring(detail)
                )
            end
            self:finishDecision(ticks)
        elseif ticks - self.recoveryStarted >= RECOVERY_TIMEOUT_TICKS then
            local _, detail = KnoxSurvivorNeeds.verifyRecovery(
                self.character,
                self.selfCareIntent
            )
            self.selfCareRetryAt.rest = ticks + SELF_CARE_RETRY_TICKS
            self:recordFailure(
                "needs_no_change:rest:" .. tostring(detail),
                ticks,
                SELF_CARE_RETRY_TICKS
            )
            self:finishDecision(ticks)
        else
            self.nextThink = ticks + RECOVERY_RECHECK_TICKS
        end
        return
    end

    if self.state == "IDLE" and ticks >= self.nextThink then
        self:think(ticks)
    end
end

function Controller:status()
    return "id=" .. self.id
        .. " state=" .. tostring(self.state)
        .. " decision=" .. tostring(self.activeDecision or "none")
        .. " base=" .. tostring(self.baseId or "none")
        .. " lastFailure=" .. tostring(self.lastFailure~=nil and self.lastFailure.reason or "none")
        .. " failureTick=" .. tostring(self.lastFailure~=nil and self.lastFailure.ticks or "none")
        .. " roam=" .. tostring(self.counts.roam)
        .. " loot=" .. tostring(self.counts.loot)
        .. " search=" .. tostring(self.counts.search)
        .. " needs=" .. tostring(self.counts.needs)
        .. " combat=" .. tostring(self.counts.combat)
        .. " groupTravel=" .. tostring(self.counts.groupTravel)
        .. " baseScout=" .. tostring(self.counts.baseScout)
        .. " robberies=" .. tostring(self.counts.robberies)
        .. " failures=" .. tostring(self.counts.failures)
        .. " baseTask=" .. tostring(self.baseTask ~= nil
            and self.baseTask.type or "none")
        .. " camp=" .. tostring(self.campId or "none")
        .. " groupLeader=" .. tostring(self.groupLeaderId)
        .. " formationSlot=" .. tostring(self.groupFormationSlot)
        .. " formationFailures=" .. tostring(self.formationFailureCount or 0)
        .. " retryAt=" .. tostring(self.nextThink or 0)
        .. " " .. KnoxSurvivorNeeds.describe(KnoxSurvivorNeeds.snapshot(self.character))
end

function Controller:shutdown()
    self:cancelTrade("shutdown")
    self.pendingDepositTrip = nil
    self.pendingCleanup = nil
    self:abandonBaseTask("shutdown")
    self:releaseCampPosition()
    if hasPendingTimedActions(self.character) then
        ISTimedActionQueue.clear(self.character)
    end
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    self:releaseCombat()
    self:releaseSupply()
    return KnoxPersistence.captureActiveSurvivor(self.id)
end
