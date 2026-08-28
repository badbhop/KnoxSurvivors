require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISRestAction"
require "TimedActions/ISSitOnGround"
require "Util/AdjacentFreeTileFinder"
require "KS_SurvivorNeeds"
require "KS_FirearmSupport"
require "KS_SurvivorInventoryActions"
require "KS_Persistence"
require "KS_ActivityFeed"
require "KS_SurvivorLooting"
require "KS_FactionBaseScouting"
require "KS_FactionSafehouse"
require "KS_BaseManager"
require "KS_BaseTaskBoard"
require "KS_BaseJobs"
require "KS_BaseStorage"
require "KS_BaseBarricades"
require "KS_BaseFarming"
require "KS_BaseWoodcutting"
require "KS_BaseCorpseHandling"
require "KS_BaseAnimalCare"
require "KS_BaseRepairs"
require "KS_BaseConstruction"

local Controller = rawget(_G, "KnoxAutonomyController") or {}
_G.KnoxAutonomyController = Controller
Controller.__index = Controller

local THINK_MIN_TICKS = 30
local THINK_JITTER_TICKS = 45
local THREAT_SCAN_TICKS = 15
local COMBAT_RETARGET_COOLDOWN_TICKS = 90
local THREAT_IMMEDIATE_RADIUS = 7
local THREAT_VISIBLE_RADIUS = 16
local THREAT_SELF_TARGET_RADIUS = 20
local THREAT_GROUP_ASSIST_RADIUS = 10
local MAX_ATTACKERS_PER_THREAT = 3
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
local ROAM_MAX_RADIUS = 18
local RECOVERY_RECHECK_TICKS = 180
local RECOVERY_TIMEOUT_TICKS = 900
local RECOVERY_SEAT_SCAN_RADIUS = 8
local RECOVERY_POSTURE_TIMEOUT_TICKS = 180
local BASE_AMBIENT_REST_TICKS = 180
local MOVEMENT_TIMEOUT_TICKS = 1500
local ACTION_TIMEOUT_TICKS = 1200
local GROUP_SOFT_LEASH_SQUARED = 100
local GROUP_RETRIEVE_LEASH_SQUARED = 196
local FORMATION_TOLERANCE_SQUARED = 2
local FORMATION_REFRESH_TICKS = 30
local FORMATION_FAILURE_COOLDOWN_TICKS = 180
local FORMATION_FAILURE_MAX_COOLDOWN_TICKS = 720
local ENTRY_SCAN_RADIUS = 16
local FLEE_SCAN_RADIUS = 12
local FLEE_TARGET_DISTANCE = 12
local FLEE_RECHECK_TICKS = 45
local FLEE_PLAN_TICKS = 240

-- Short-lived, loaded-world coordination only.  This is deliberately not
-- persistence: a flee route is a reaction to the zombies visible right now,
-- not a mission or a world-state change that should survive save/load.
local fleePlans = rawget(_G, "KnoxFleePlans") or {}
_G.KnoxFleePlans = fleePlans

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
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

local function findFormationTarget(anchor, follower, slotIndex)
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
    local lateralX = -forwardY
    local lateralY = forwardX
    local target = cell:getGridSquare(
        anchorSquare:getX() - forwardX * row + lateralX * side,
        anchorSquare:getY() - forwardY * row + lateralY * side,
        anchorSquare:getZ()
    )
    if target ~= nil and (target == followerSquare or target:canStand()) then
        return target
    end
    return AdjacentFreeTileFinder.Find(anchorSquare, follower)
end

local function formationPace(anchor, follower)
    if anchor == nil or follower == nil
        or anchor:getCurrentSquare() == nil or follower:getCurrentSquare() == nil then
        return "normal"
    end
    local distance = distanceSquared(anchor, follower)
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
    return bridge:moveNpcWithPace(
        id,
        target,
        formationPace(anchor, follower)
    )
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

local function threatUnavailable(self, zombie, ticks)
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

local function reserveThreat(reservations, zombie, id)
    if zombie == nil or threatReservationCount(reservations, zombie, id)
        >= MAX_ATTACKERS_PER_THREAT then
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

local function nearestThreat(self, ticks)
    local square = self.character:getCurrentSquare()
    local cell = getCell()
    if square == nil or cell == nil then
        return nil
    end
    local nearest = nil
    local nearestScore = math.huge
    local nearestAwareness = nil
    local zombies = cell:getZombieList()
    -- First pass: respect reservation limit (max 3 stacking)
    for pass = 1, 2 do
        local useReservationFilter = (pass == 1)
        for index = 0, zombies:size() - 1 do
            local zombie = zombies:get(index)
            local zombieSquare = zombie:getCurrentSquare()
            local scenarioOwner = rawget(_G, "KnoxCombatTestScenarios") ~= nil
                and KnoxCombatTestScenarios.preferredNpcId ~= nil
                and KnoxCombatTestScenarios.preferredNpcId(zombie) or nil
            if not zombie:isDead() and zombieSquare ~= nil and zombieSquare:getZ() == square:getZ()
                and not threatUnavailable(self, zombie, ticks)
                and (scenarioOwner == nil or scenarioOwner == self.id) then
                local distance = distanceSquared(square, zombieSquare)
                local target = zombie:getTarget()
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
                local reservationCount = threatReservationCount(self.reservations, zombie, self.id)
                local reservationOk = not useReservationFilter or reservationCount < MAX_ATTACKERS_PER_THREAT
                -- second pass allows stacking even if all have 3, but still respects max
                if useReservationFilter and reservationCount >= MAX_ATTACKERS_PER_THREAT then
                    reservationOk = false
                end
                if not useReservationFilter then
                    reservationOk = reservationCount < MAX_ATTACKERS_PER_THREAT
                end
                if (immediate or visible or targetingSelf or targetingGroup or targetingPlayer) and reservationOk then
                    -- Survival relevance outranks simple visibility. A zombie already
                    -- attacking this survivor must beat one chasing the player or a
                    -- distant reserved target, even when the old target was selected first.
                    local urgentSelfTarget = targetingSelf and immediate
                    local bonus = scenarioOwner == self.id and 10000
                        or (urgentSelfTarget and 5000
                        or (immediate and 3500
                            or (targetingGroup and 2500
                                or (targetingSelf and 2000
                                    or (targetingPlayer and 1000 or 0)))))
                    -- penalize heavily reserved threats to spread, but allow stack when all reserved
                    local score = distance - bonus + (reservationCount * 15)
                    if score < nearestScore then
                        nearest = zombie
                        nearestScore = score
                        nearestAwareness = {
                            reason = targetingSelf and "active_target"
                                or (immediate and "immediate"
                                    or (targetingGroup and "group_target"
                                        or (targetingPlayer and "player_target" or "visible"))),
                            distance = math.sqrt(distance),
                        }
                    end
                end
            end
        end
        if nearest ~= nil then
            break
        end
    end
    self.pendingThreatAwareness = nearestAwareness
    return nearest
end

local function shouldReplaceCombatTarget(self, candidate, awareness, ticks)
    if candidate == nil or candidate == self.combatTarget then
        return false
    end
    local candidateSquare = candidate:getCurrentSquare()
    local current = self.combatTarget
    local currentSquare = current ~= nil and current:getCurrentSquare() or nil
    local survivorSquare = self.character:getCurrentSquare()
    if candidateSquare == nil or survivorSquare == nil then
        return false
    end
    if current == nil or current:isDead() or currentSquare == nil then
        return true
    end

    local candidateDistance = distanceSquared(survivorSquare, candidateSquare)
    local currentDistance = distanceSquared(survivorSquare, currentSquare)
    if ticks - (self.lastCombatRetarget or -COMBAT_RETARGET_COOLDOWN_TICKS)
        < COMBAT_RETARGET_COOLDOWN_TICKS
        and candidateDistance > 4 then
        return false
    end

    local candidateTargetsSelf = candidate:getTarget() == self.character
    local currentTargetsSelf = current:getTarget() == self.character
    if candidateTargetsSelf ~= currentTargetsSelf then
        if candidateTargetsSelf then
            return candidateDistance <= THREAT_IMMEDIATE_RADIUS * THREAT_IMMEDIATE_RADIUS
                or candidateDistance + 16 < currentDistance
        end
        return awareness ~= nil and awareness.reason == "immediate"
            and currentDistance > THREAT_IMMEDIATE_RADIUS * THREAT_IMMEDIATE_RADIUS
    end

    if awareness ~= nil and awareness.reason == "immediate"
        and currentDistance > THREAT_IMMEDIATE_RADIUS * THREAT_IMMEDIATE_RADIUS then
        return true
    end
    -- One-tile hysteresis prevents two equally relevant zombies from causing target
    -- thrashing while still allowing a materially closer attacker to take priority.
    return candidateDistance + 1 < currentDistance
end

local function nearbyZombieCount(self, radius)
    local square = self.character:getCurrentSquare()
    local cell = getCell()
    if square == nil or cell == nil then
        return 0
    end
    local count = 0
    local zombies = cell:getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if z ~= nil and not z:isDead() and z:getCurrentSquare() ~= nil and z:getCurrentSquare():getZ() == square:getZ() then
            if distanceSquared(square, z:getCurrentSquare()) <= radius * radius then
                count = count + 1
            end
        end
    end
    return count
end

local function nearbyAllyCount(self, radius)
    local square = self.character:getCurrentSquare()
    if square == nil then return 1 end
    local seen = { [self.character] = true }
    local count = 1
    local function include(character)
        if character ~= nil and not seen[character]
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

local function fleeAssessment(self)
    local count = nearbyZombieCount(self, FLEE_SCAN_RADIUS)
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
    local endurance = 1
    local okE, e = pcall(function()
        return self.character:getStats():get(CharacterStat.ENDURANCE)
    end)
    if okE and type(e) == "number" then
        endurance = e
    end
    local allies = nearbyAllyCount(self, FLEE_SCAN_RADIUS)
    local outnumbered = count >= math.max(3, allies * 3)
    local critical = health <= 25 and count > 0
    return critical or outnumbered, {
        zombies = count,
        allies = allies,
        health = health,
        endurance = endurance,
        reason = critical and "critical_health" or (outnumbered and "outnumbered" or nil),
    }
end

-- Kept as a controller method so the policy can be verified without starting a
-- move or mutating combat state. Runtime decisions still use the same helper.
function Controller:assessFlee()
    return fleeAssessment(self)
end

local function findFleeTarget(self)
    local origin = self.character:getCurrentSquare()
    local cell = getCell()
    if origin == nil or cell == nil then return nil end
    local awayX, awayY = 0, 0
    local zombies = cell:getZombieList()
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local zs = zombie ~= nil and zombie:getCurrentSquare() or nil
        if zombie ~= nil and not zombie:isDead() and zs ~= nil
            and zs:getZ() == origin:getZ() then
            local dx = origin:getX() - zs:getX()
            local dy = origin:getY() - zs:getY()
            local distance2 = dx * dx + dy * dy
            if distance2 <= (FLEE_SCAN_RADIUS + 4) ^ 2 and distance2 > 0 then
                local weight = 1 / math.sqrt(distance2)
                awayX = awayX + dx * weight
                awayY = awayY + dy * weight
            end
        end
    end
    local length = math.sqrt(awayX * awayX + awayY * awayY)
    if length < 0.01 then
        local angle = ZombRand(628) / 100
        awayX, awayY, length = math.cos(angle), math.sin(angle), 1
    end
    awayX, awayY = awayX / length, awayY / length
    local best, bestScore = nil, -math.huge
    for distance = FLEE_TARGET_DISTANCE, 5, -1 do
        for lateral = -3, 3 do
            local x = math.floor(origin:getX() + awayX * distance - awayY * lateral + 0.5)
            local y = math.floor(origin:getY() + awayY * distance + awayX * lateral + 0.5)
            local square = cell:getGridSquare(x, y, origin:getZ())
            if square ~= nil and square:canStand() then
                local nearest = math.huge
                for index = 0, zombies:size() - 1 do
                    local zombie = zombies:get(index)
                    local zs = zombie ~= nil and zombie:getCurrentSquare() or nil
                    if zombie ~= nil and not zombie:isDead() and zs ~= nil
                        and zs:getZ() == square:getZ() then
                        nearest = math.min(nearest, distanceSquared(square, zs))
                    end
                end
                local score = nearest - math.abs(lateral) * 2
                if score > bestScore then best, bestScore = square, score end
            end
        end
        if best ~= nil then return best end
    end
    return nil
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
    if key == nil then return nil end
    local plan = fleePlans[key]
    if plan == nil or (tonumber(plan.expiresAt) or -1) < ticks then
        fleePlans[key] = nil
        return nil
    end
    local cell = getCell()
    if cell == nil then return nil end
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
        return square
    end
    return cell:getGridSquare(plan.x, plan.y, plan.z)
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

local function findSupply(self, goal, ticks)
    local origin = self.character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
    for radius = 0, SUPPLY_SCAN_RADIUS do
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
                                    and not containerUnavailable(self, container, ticks)
                                    and not areaUnavailable(self, container, ticks) then
                                    local items = container:getItems()
                                    for itemIndex = 0, items:size() - 1 do
                                        local item = items:get(itemIndex)
                                        if itemMatchesGoal(item, goal, self.character)
                                            and not reservedByOther(
                                                self.reservations,
                                                "items",
                                                item,
                                                self.id
                                            ) then
                                            local approach = AdjacentFreeTileFinder.Find(
                                                square,
                                                self.character
                                            )
                                            if approach ~= nil then
                                                return {
                                                    goal = goal,
                                                    item = item,
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

local function findRoamTarget(character)
    local origin = character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
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
            if square ~= nil and square:canStand() then
                return square
            end
        end
    end
    return nil
end

local REST_QUALITY = {
    goodBed = 5,
    averageBed = 4,
    averageChair = 3,
    badBed = 2,
    badChair = 1,
}

local function furnitureQuality(object)
    local properties = object ~= nil and object:getProperties() or nil
    local bedType = properties ~= nil and properties:get("BedType") or nil
    return REST_QUALITY[tostring(bedType)] or 3, tostring(bedType or "seat")
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

local function findBestRestSpot(self)
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
                    if square ~= nil then
                        local objects = square:getObjects()
                        for index = 0, objects:size() - 1 do
                            local object = objects:get(index)
                            if usableSeat(self, object) then
                                local approach = AdjacentFreeTileFinder.Find(
                                    square,
                                    self.character,
                                    nil
                                )
                                if approach ~= nil then
                                    local quality, bedType = furnitureQuality(object)
                                    local distance = distanceSquared(origin, approach)
                                    if best == nil or quality > best.quality
                                        or (quality == best.quality and distance < best.distance) then
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

local CARDINAL_OFFSETS = {
    { x = 1, y = 0 },
    { x = -1, y = 0 },
    { x = 0, y = 1 },
    { x = 0, y = -1 },
}

local function findAlternateWindowEntry(self, supply)
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
    local bestDistance = math.huge
    local roomSquares = targetRoom:getSquares()
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
                    local window = inside:getWindowTo(outside)
                    if window == nil then
                        window = outside:getWindowTo(inside)
                    end
                    if window ~= nil and not window:isBarricaded() then
                        local distance = distanceSquared(origin, outside)
                        if distance < bestDistance then
                            best = { outside = outside, inside = inside, window = window }
                            bestDistance = distance
                        end
                    end
                end
            end
        end
    end
    return best
end

function Controller.new(id, character, bridge, reservations, ticks)
    local self = setmetatable({}, Controller)
    self.id = id
    self.character = character
    self.bridge = bridge
    self.reservations = reservations
    self.state = "IDLE"
    self.pendingSupply = nil
    self.activeDecision = nil
    self.combatTarget = nil
    self.failedThreats = {}
    self.nextThink = ticks + 15 + ZombRand(30)
    self.nextThreatScan = ticks
    self.lastCombatRetarget = -COMBAT_RETARGET_COOLDOWN_TICKS
    self.nextWorldSearch = 0
    self.nextExplorationSearch = 0
    self.recoveryStarted = 0
    self.recoveryPostureStarted = 0
    self.pendingRest = nil
    self.inspectedContainers = {}
    self.blockedAreas = {}
    self.forceTravel = false
    self.stateStartedAt = ticks
    self.observedState = self.state
    self.entryDetour = nil
    self.nextNeedCallout = 0
    self.groupLeaderId = nil
    self.groupLeader = nil
    self.groupFormationSlot = 1
    self.groupSize = 1
    self.groupMembers = {}
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
    self.nextFormationRefresh = 0
    self.formationFailureCount = 0
    self.regroupMember = nil
    self.nextRegroupCallout = 0
    self.baseId = nil
    self.base = nil
    self.baseTask = nil
    self.baseTaskStartedAt = nil
    self.baseTaskTransfer = nil
    self.baseTaskSupplyTransfer = nil
    self.baseTaskActionQueued = false
    self.baseTaskBarricadeTarget = nil
    self.baseTaskBarricadeBefore = 0
    self.baseTaskFarmingTarget = nil
    self.baseTaskFarmingBefore = nil
    self.baseTaskWoodcuttingTarget = nil
    self.baseTaskWoodcuttingBefore = nil
    self.baseTaskCorpseTarget = nil
    self.baseTaskCorpsePhase = nil
    self.baseTaskAnimalTarget = nil
    self.baseTaskAnimalBefore = nil
    self.baseTaskRepairTarget = nil
    self.baseTaskRepairBefore = nil
    self.baseTaskConstructionTarget = nil
    self.factionId = nil
    self.factionBaseCandidate = nil
    self.announcedFactionBaseCandidate = nil
    self.pendingRobbery = nil
    self.pendingThreatAwareness = nil
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

function Controller:recordFailure(reason, ticks, cooldown)
    local key = tostring(reason or "unknown")
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

function Controller:handleFormationMovementFailure(movement, ticks, companionFollow)
    self.bridge:cancelNpcMove(self.id)
    self.formationFailureCount = (self.formationFailureCount or 0) + 1
    local cooldown = math.min(
        FORMATION_FAILURE_COOLDOWN_TICKS * self.formationFailureCount,
        FORMATION_FAILURE_MAX_COOLDOWN_TICKS
    )
    self:recordFailure("formation_movement:" .. tostring(movement), ticks, cooldown)
    if companionFollow == nil then
        companionFollow = self.state == "COMPANION_FOLLOW"
    end
    self.regroupMember = nil
    self.activeDecision = companionFollow and "follow_player" or "follow_group"
    self.state = companionFollow and "COMPANION_WAIT" or "GROUP_WAIT"
    -- recordFailure owns the retry time. Do not let the ordinary grouped
    -- finishDecision fast path replace this with its five-tick refresh.
    self.nextFormationRefresh = self.nextThink
end


function Controller:setGroupLeader(id, character, formationSlot, groupSize)
    self.groupLeaderId = id
    self.groupLeader = character
    self.groupFormationSlot = math.max(1, tonumber(formationSlot) or 1)
    self.groupSize = math.max(1, tonumber(groupSize) or 1)
end

function Controller:clearGroupLeader()
    self.groupLeaderId = nil
    self.groupLeader = nil
    self.groupFormationSlot = 1
    self.groupSize = 1
end

function Controller:setGroupMembers(members)
    self.groupMembers = members or {}
end

function Controller:interruptForDirective()
    local safe = self.state == "IDLE" or self.state == "ROAMING"
        or self.state == "MOVING_TO_SUPPLY"
        or self.state == "MOVING_TO_EXPLORE"
        or self.state == "GROUP_FOLLOW" or self.state == "GROUP_WAIT"
        or self.state == "GROUP_REGROUP"
        or self.state == "COMPANION_FOLLOW"
        or self.state == "COMPANION_WAIT" or self.state == "COMPANION_HOLD"
        or self.state == "COMPANION_GUARD"
        or self.state == "MOVING_TO_COMPANION_POINT"
        or self.state == "BASE_RETURN" or self.state == "BASE_PATROL"
        or self.state == "BASE_IDLE" or self.state == "BASE_AMBIENT_REST"
        or self.state == "BASE_TASK_MOVE" or self.state == "BASE_TASK_WORK"
        or self.state == "BASE_TASK_ACTION"
        or self.state == "BASE_TASK_SUPPLY_MOVE"
        or self.state == "BASE_TASK_SUPPLY_TRANSFER"
        or self.state == "WAITING_TO_RECOVER"
    if not safe then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self:abandonBaseTask("directive_changed")
    self:releaseSupply()
    self:releaseRestSpot()
    self:leaveRecoveryPosture()
    self.activeDecision = nil
    self.state = "IDLE"
    self.nextThink = 0
    return true
end

function Controller:setCompanionOrder(ownerId, player, order, formationSlot)
    local normalized = order == "hold" and "hold" or "follow"
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

function Controller:allowsCompanionThreat(target)
    if self.companionOrder == nil then
        return true
    end
    if self.companionCombatStance == "passive" then
        return false
    end
    if self.companionCombatStance == "aggressive" then
        return true
    end
    if target == nil then
        return false
    end
    if target:getTarget() == self.character then
        return true
    end
    local owner = self.companionTarget
    local square = self.character:getCurrentSquare()
    local targetSquare = target:getCurrentSquare()
    if owner == nil or square == nil or targetSquare == nil or target:getTarget() ~= owner then
        return false
    end
    return distanceSquared(square, targetSquare) <= THREAT_GROUP_ASSIST_RADIUS * THREAT_GROUP_ASSIST_RADIUS
end

function Controller:setCompanionPolicy(allowClimbing)
    self.allowClimbing = allowClimbing ~= false
    self.bridge:setNpcClimbingAllowed(self.id, self.allowClimbing)
end

function Controller:setCompanionDirective(directive)
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
        self:interruptForDirective()
    end
end

function Controller:clearCompanionOrder()
    if self.companionOrder ~= nil then
        self:interruptForDirective()
    end
    self.companionOwnerId = nil
    self.companionTarget = nil
    self.companionOrder = nil
    self.companionCombatStance = "defensive"
    self.companionFormationSlot = 1
end

function Controller:setBaseAssignment(baseId, base)
    local changed = self.baseId ~= baseId or self.base ~= base
    self.baseId = baseId
    self.base = base
    if changed then
        self:interruptForDirective()
    end
end

function Controller:clearBaseAssignment()
    if self.baseId ~= nil then
        self:interruptForDirective()
    end
    self.baseId = nil
    self.base = nil
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
        if member ~= nil and member ~= self.character and member:getCurrentSquare() ~= nil then
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

function Controller:canInterruptForMeeting()
    return self.state == "IDLE"
        or self.state == "ROAMING"
        or self.state == "MOVING_TO_SUPPLY"
        or self.state == "MOVING_TO_EXPLORE"
        or self.state == "WAITING_TO_RECOVER"
        or self.state == "GROUP_WAIT"
        or self.state == "GROUP_FOLLOW"
end

function Controller:interruptForMeeting()
    if not self:canInterruptForMeeting() then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self:releaseSupply()
    if self.activeDecision == "rest" or self.activeDecision == "sleep" then
        self:leaveRecoveryPosture()
    end
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
        self.groupFormationSlot
    )
    if approach == nil then
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        return false
    end
    local result = tostring(moveWithFormationPace(
        self.bridge,
        self.id,
        approach,
        self.groupLeader,
        self.character
    ))
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
    self.nextFormationRefresh = ticks + FORMATION_REFRESH_TICKS
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
    local result = tostring(moveWithFormationPace(
        self.bridge,
        self.id,
        approach,
        member,
        self.character
    ))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:handleFormationMovementFailure(result, ticks, false)
        return false
    end
    self.regroupMember = member
    self.activeDecision = "retrieve_group_member"
    self.state = "GROUP_REGROUP"
    self.stateStartedAt = ticks
    if ticks >= self.nextRegroupCallout then
        KnoxActivityFeed.speak(self.character, "Hold up. We're missing someone.")
        self.nextRegroupCallout = ticks + 1800
    end
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=GROUP_REGROUP target=" .. tostring(member)
    )
    return true
end

function Controller:beginCompanionFollow(ticks)
    if self.companionTarget == nil
        or self.companionTarget:getCurrentSquare() == nil then
        self.state = "COMPANION_WAIT"
        self.nextThink = ticks + 60
        return false
    end
    local approach = findFormationTarget(
        self.companionTarget,
        self.character,
        self.companionFormationSlot
    )
    if approach == nil then
        self.state = "COMPANION_WAIT"
        self.nextThink = math.max(self.nextThink or 0, ticks + THINK_MIN_TICKS)
        return false
    end
    local result = tostring(moveWithFormationPace(
        self.bridge,
        self.id,
        approach,
        self.companionTarget,
        self.character
    ))
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
    self.nextFormationRefresh = ticks + FORMATION_REFRESH_TICKS
    return true
end

function Controller:refreshFormationFollow(ticks)
    if ticks < self.nextFormationRefresh then
        return false
    end
    local groupFollow = self.state == "GROUP_FOLLOW"
    local anchor = groupFollow and self.groupLeader or self.companionTarget
    local slot = groupFollow and self.groupFormationSlot or self.companionFormationSlot
    local target = findFormationTarget(anchor, self.character, slot)
    local current = self.character:getCurrentSquare()
    self.nextFormationRefresh = ticks + FORMATION_REFRESH_TICKS
    if target == nil or current == nil then
        return false
    end
    if distanceSquared(current, target) <= FORMATION_TOLERANCE_SQUARED then
        self.bridge:cancelNpcMove(self.id)
        self.activeDecision = groupFollow and "follow_group" or "follow_player"
        self.state = groupFollow and "GROUP_WAIT" or "COMPANION_WAIT"
        self.nextThink = ticks + FORMATION_REFRESH_TICKS
        return true
    end
    local shifted = self.formationTargetZ ~= target:getZ()
        or self.formationTargetX == nil or self.formationTargetY == nil
        or (self.formationTargetX - target:getX()) ^ 2
            + (self.formationTargetY - target:getY()) ^ 2 > FORMATION_TOLERANCE_SQUARED
    if not shifted then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
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

function Controller:findBaseMovementTarget(returning)
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
    local width = math.max(1, math.floor(tonumber(home.width) or 1))
    local height = math.max(1, math.floor(tonumber(home.height) or 1))
    for _ = 1, 12 do
        local square = cell:getGridSquare(
            math.floor(tonumber(home.minX) or 0) + ZombRand(width),
            math.floor(tonumber(home.minY) or 0) + ZombRand(height),
            z
        )
        if square ~= nil and square:canStand()
            and square ~= self.character:getCurrentSquare() then
            return square
        end
    end
    return nil
end

function Controller:beginBaseMovement(ticks, returning)
    local target = self:findBaseMovementTarget(returning)
    if target == nil then
        self.activeDecision = "base_idle"
        self.state = "BASE_IDLE"
        self.nextThink = ticks + 120
        return false
    end
    if self.character:isSitOnGround() or self.character:isSittingOnFurniture() then
        self:leaveRecoveryPosture()
    end
    local result = tostring(self.bridge:moveNpc(self.id, target))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self.activeDecision = "base_idle"
        self.state = "BASE_IDLE"
        self.nextThink = ticks + 120
        return false
    end
    self.activeDecision = returning and "return_to_base" or "patrol_base"
    self.state = returning and "BASE_RETURN" or "BASE_PATROL"
    return true
end

function Controller:finishBaseTask(succeeded, reason)
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
    self.baseTaskTransfer = nil
    self.baseTaskSupplyTransfer = nil
    self.baseTaskActionQueued = false
    self.baseTaskBarricadeTarget = nil
    self.baseTaskBarricadeBefore = 0
    self.baseTaskFarmingTarget = nil
    self.baseTaskFarmingBefore = nil
    self.baseTaskWoodcuttingTarget = nil
    self.baseTaskWoodcuttingBefore = nil
    self.baseTaskCorpseTarget = nil
    self.baseTaskCorpsePhase = nil
    self.baseTaskAnimalTarget = nil
    self.baseTaskAnimalBefore = nil
    self.baseTaskRepairTarget = nil
    self.baseTaskRepairBefore = nil
    self.baseTaskConstructionTarget = nil
    return finished ~= nil
end

function Controller:abandonBaseTask(reason)
    if self.baseTask == nil then
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    if self.character ~= nil and not self.character:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(self.character)
    end
    if self.character ~= nil and KnoxBaseCorpseHandling.isDragging(self.character) then
        pcall(function() self.character:setDoGrappleLetGo() end)
    end
    local abandoned = self:finishBaseTask(false, reason or "interrupted")
    self.activeDecision = nil
    return abandoned
end

function Controller:beginBaseTaskWorkMove(ticks)
    local task = self.baseTask
    local target = task ~= nil and KnoxBaseJobs.resolveTaskSquare(task, self.character) or nil
    if target == nil then
        self:finishBaseTask(false, "no_loaded_work_square")
        self:recordFailure("base_task_target", ticks, 180)
        return false
    end
    local moveResult = tostring(self.bridge:moveNpc(self.id, target))
    if string.find(moveResult, "MOVE_STARTED", 1, true) ~= 1 then
        self:finishBaseTask(false, "task_move_start_failed:" .. moveResult)
        self:recordFailure("base_task_move:" .. moveResult, ticks, 180)
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
    local transfer, result = KnoxBaseStorage.findRequiredTransfer(
        self.base,
        self.character,
        self.baseTask ~= nil and self.baseTask.requirements or nil
    )
    if transfer == nil then
        if result == "requirements_ready" then
            return self:beginBaseTaskWorkMove(ticks)
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
        self:recordFailure("base_task_supply_move:" .. moveResult, ticks, 300)
        return false
    end
    self.baseTaskSupplyTransfer = transfer
    self.baseTaskStartedAt = nil
    self.activeDecision = "base_task_collect_supplies"
    self.state = "BASE_TASK_SUPPLY_MOVE"
    return true
end

function Controller:beginBaseTask(ticks)
    if self.base == nil or self.baseId == nil
        or self.base.settings == nil or self.base.settings.automaticJobs == false
        or self.baseTask ~= nil then
        return false
    end
    local task, result = KnoxBaseJobs.ensureAutomaticTask(
        self.base,
        self.character,
        self.id,
        (KnoxPersistence.getSurvivorDuty(self.id) or {}).jobPreference
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
    self.baseTask = task
    task.baseId = self.baseId
    return self:beginBaseTaskSupplyOrWork(ticks)
end

function Controller:releaseSupply()
    if self.pendingSupply ~= nil then
        release(self.reservations, "items", self.pendingSupply.item, self.id)
        for _, candidate in ipairs(self.pendingSupply.items or {}) do
            release(self.reservations, "items", candidate.item, self.id)
        end
        release(self.reservations, "containers", self.pendingSupply.container, self.id)
        self.pendingSupply = nil
    end
    self.entryDetour = nil
end

function Controller:beginWindowDetour(ticks, resumeState)
    if self.pendingSupply == nil or self.pendingSupply.entryAttempted == true then
        return false
    end
    self.pendingSupply.entryAttempted = true
    local entry = findAlternateWindowEntry(self, self.pendingSupply)
    if entry == nil then
        return false
    end
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
            .. " alternate-entry=window outside="
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
    local result = tostring(self.bridge:crossNpc(self.id, self.entryDetour.inside))
    if string.find(result, "CROSS_STARTED", 1, true) ~= 1 then
        return false
    end
    self.state = "CROSSING_WINDOW_ENTRY"
    self.stateStartedAt = ticks
    return true
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
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    self:abandonBaseTask(reason or "decision_abandoned")
    if not self.character:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(self.character)
    end
    if self.pendingSupply ~= nil and self.pendingSupply.container ~= nil then
        self.inspectedContainers[self.pendingSupply.container] = ticks + SUPPLY_RETRY_TICKS
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
        if directive ~= nil then
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
    local result = tostring(self.bridge:moveNpc(self.id, target.approach))
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
    self.activeDecision = directive ~= nil and tostring(directive.kind)
        or (target.items ~= nil and #target.items > 0
            and "loot_useful_items_" .. tostring(#target.items)
            or "inspect_container")
    self.state = "MOVING_TO_EXPLORE"
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=MOVING_TO_EXPLORE goal=" .. tostring(self.activeDecision)
    )
    return true
end

function Controller:beginCompanionPointDirective(ticks, directive)
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
    if current ~= nil and distanceSquared(current, target) <= 2.25 then
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
    local result = tostring(self.bridge:moveNpc(self.id, target))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:recordFailure("companion_point_move:" .. result, ticks, EXPLORATION_RETRY_TICKS)
        return false
    end
    self.activeDecision = directive.kind == "guard" and "guard_location" or "go_to_location"
    self.state = "MOVING_TO_COMPANION_POINT"
    return true
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
    if self.character:isSitOnGround() or self.character:isSittingOnFurniture() then
        self.character:setVariable("forceGetUp", true)
    end
    self.character:setIsResting(false)
    self.character:setBed(nil)
    self:releaseRestSpot()
end

function Controller:startRecoveryPosture(ticks, useFurniture, ambient)
    if not self.character:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(self.character)
    end
    local action = nil
    local posture = "ground"
    if useFurniture and self.pendingRest ~= nil and self.pendingRest.object ~= nil
        and usableSeat(self, self.pendingRest.object) then
        action = ISRestAction:new(self.character, self.pendingRest.object, true)
        posture = "furniture:" .. tostring(self.pendingRest.bedType)
    else
        self:releaseRestSpot()
        action = ISSitOnGround:new(self.character, nil)
    end
    ISTimedActionQueue.add(action)
    self.state = ambient == true and "BASE_AMBIENT_REST" or "WAITING_TO_RECOVER"
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

-- Light base-life behavior is intentionally just the game's existing sit/rest
-- actions. It makes an idle resident use the best available chair or bed
-- without inventing a fake work/reading animation or changing needs.
function Controller:beginAmbientBaseRest(ticks)
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

function Controller:beginRecovery(decision, ticks)
    self.activeDecision = decision
    self.recoveryStarted = ticks
    local spot = findBestRestSpot(self)
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
    if self.activeDecision == "rest" or self.activeDecision == "sleep"
        or self.activeDecision == "base_ambient_rest" then
        self:leaveRecoveryPosture()
    end
    self.ambientRest = nil
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

function Controller:beginCombat(target)
    if target == nil or target:getCurrentSquare() == nil
        or not reserveThreat(self.reservations, target, self.id) then
        return false
    end
    -- Firearms use the game's timed reload action.  Do this before clearing other
    -- actions so an already-running reload is allowed to finish instead of being
    -- cancelled and restarted every threat scan.
    local firearmState, firearmResult = KnoxFirearmSupport.prepareForThreat(
        self.id,
        self.character,
        self.bridge
    )
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
    if not self.character:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(self.character)
    end
    self:abandonBaseTask("combat_interrupt")
    if self.activeDecision == "rest" or self.activeDecision == "sleep" then
        self:leaveRecoveryPosture()
    end
    local approach = AdjacentFreeTileFinder.Find(target:getCurrentSquare(), self.character)
    if approach == nil then
        releaseThreat(self.reservations, target, self.id)
        return false
    end
    local result = tostring(self.bridge:beginNpcLiveCombat(self.id, target, approach))
    if string.find(result, "COMBAT_STARTED", 1, true) ~= 1 then
        self.bridge:resetNpcCombat(self.id)
        self.failedThreats[target] = self.nextThreatScan + THREAT_FAILURE_COOLDOWN_TICKS
        releaseThreat(self.reservations, target, self.id)
        self:recordFailure(
            "combat_start:" .. result,
            self.nextThreatScan,
            THREAT_FAILURE_COOLDOWN_TICKS
        )
        return false
    end
    self:releaseSupply()
    self.combatTarget = target
    self.activeDecision = "fight"
    self.state = "COMBAT"
    local awareness = self.pendingThreatAwareness or {}
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id .. " state=COMBAT " .. result
            .. " awareness=" .. tostring(awareness.reason or "unknown")
            .. " distance=" .. tostring(awareness.distance or "unknown")
    )
    self.pendingThreatAwareness = nil
    return true
end

function Controller:beginWorldSearch(goal, ticks)
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
    local result = tostring(self.bridge:moveNpc(self.id, supply.approach))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        release(self.reservations, "items", supply.item, self.id)
        self.inspectedContainers[supply.container] = ticks + SUPPLY_RETRY_TICKS
        self.nextWorldSearch = ticks + SUPPLY_RETRY_TICKS
        self:recordFailure("supply_move:" .. result, ticks, SUPPLY_RETRY_TICKS)
        return false
    end
    self.pendingSupply = supply
    self.activeDecision = goal
    self.state = "MOVING_TO_SUPPLY"
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=MOVING_TO_SUPPLY goal=" .. goal
            .. " item=" .. tostring(supply.item:getFullType())
    )
    return true
end

function Controller:beginRoam(ticks)
    local target = findRoamTarget(self.character)
    if target == nil then
        self.nextThink = ticks + THINK_MIN_TICKS
        return false
    end
    local result = tostring(self.bridge:moveNpc(self.id, target))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:recordFailure("roam_move:" .. result, ticks, 180)
        return false
    end
    self.activeDecision = "roam"
    self.state = "ROAMING"
    self.forceTravel = false
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=ROAMING target=" .. target:getX() .. "," .. target:getY()
    )
    return true
end

function Controller:beginFlee(ticks, assessment)
    local target = groupFleeTarget(self, ticks)
    if target == nil then
        target = findFleeTarget(self)
        local key = groupFleeKey(self)
        if target ~= nil and key ~= nil then
            fleePlans[key] = {
                x = target:getX(), y = target:getY(), z = target:getZ(),
                expiresAt = ticks + FLEE_PLAN_TICKS,
            }
        end
    end
    if target == nil then
        self.nextThink = ticks + FLEE_RECHECK_TICKS
        return false
    end
    self.bridge:cancelNpcMove(self.id)
    self.bridge:resetNpcCombat(self.id)
    self:abandonBaseTask("survival_flee")
    if not self.character:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(self.character)
    end
    self:releaseCombat()
    self:releaseSupply()
    self:leaveRecoveryPosture()
    local pace = assessment ~= nil and assessment.endurance >= 0.48
        and assessment.health > 25 and "sprint" or "run"
    local result = tostring(self.bridge:moveNpcWithPace(self.id, target, pace))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self:recordFailure("flee_move:" .. result, ticks, FLEE_RECHECK_TICKS)
        return false
    end
    self.activeDecision = "flee"
    self.state = "FLEEING"
    self.stateStartedAt = ticks
    self.nextThink = ticks + FLEE_RECHECK_TICKS
    print("[KnoxSurvivors][Autonomy] id=" .. self.id
        .. " state=FLEEING reason=" .. tostring(assessment and assessment.reason)
        .. " zombies=" .. tostring(assessment and assessment.zombies or 0)
        .. " allies=" .. tostring(assessment and assessment.allies or 1)
        .. " health=" .. tostring(assessment and assessment.health or 100)
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
    local result = tostring(self.bridge:moveNpc(self.id, target))
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

function Controller:think(ticks)
    local flee, assessment = fleeAssessment(self)
    if flee and self:beginFlee(ticks, assessment) then
        return
    end
    local threat = nearestThreat(self, ticks)
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
    if decision.kind == "eat" or decision.kind == "drink"
        or decision.kind == "bandage" or decision.kind == "improvise_medical" then
        local action = KnoxSurvivorNeeds.execute(self.character, decision)
        if action ~= nil and action ~= false then
            self:sayNeedIfGrouped(decision.kind, ticks)
            self.activeDecision = decision.kind
            self.state = "TIMED_ACTION"
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " state=TIMED_ACTION kind=" .. decision.kind
            )
        else
            self:recordFailure("needs_action:" .. decision.kind, ticks, 120)
        end
        return
    end
    if decision.kind == "find_food" or decision.kind == "find_water"
        or decision.kind == "find_medical" then
        self:sayNeedIfGrouped(decision.kind, ticks)
        if not self:beginWorldSearch(decision.kind, ticks) then
            self:beginRoam(ticks)
        end
        return
    end
    if decision.kind == "rest" or decision.kind == "sleep" then
        self:sayNeedIfGrouped(decision.kind, ticks)
        self:beginRecovery(decision.kind, ticks)
        return
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
            self.companionFormationSlot
        )
        local distance = formationTarget ~= nil and distanceSquared(
            self.character:getCurrentSquare(),
            formationTarget
        ) or math.huge
        if distance > FORMATION_TOLERANCE_SQUARED then
            self:beginCompanionFollow(ticks)
        else
            self.formationFailureCount = 0
            self.activeDecision = "follow_player"
            self.state = "COMPANION_WAIT"
            self.nextThink = ticks + 45
        end
        return
    end
    if self.baseId ~= nil and self.base ~= nil then
        local atBase = KnoxBaseManager.containsSquare(
            self.base,
            self.character:getCurrentSquare()
        )
        if not atBase then
            self:beginBaseMovement(ticks, true)
        elseif self:beginBaseTask(ticks) then
            return
        elseif ZombRand(100) < 45 then
            self:beginBaseMovement(ticks, false)
        elseif ZombRand(100) < 55 then
            self:beginAmbientBaseRest(ticks)
        else
            self.activeDecision = "base_idle"
            self.state = "BASE_IDLE"
            self.nextThink = ticks + 90 + ZombRand(120)
        end
        return
    end
    if self.groupLeader ~= nil and self.groupLeader:getCurrentSquare() ~= nil then
        local formationTarget = findFormationTarget(
            self.groupLeader,
            self.character,
            self.groupFormationSlot
        )
        local distance = formationTarget ~= nil and distanceSquared(
            self.character:getCurrentSquare(),
            formationTarget
        ) or math.huge
        if distance > FORMATION_TOLERANCE_SQUARED then
            self:beginGroupFollow(ticks)
        else
            self.formationFailureCount = 0
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
    if self.factionBaseCandidate ~= nil then
        if not self:beginFactionBaseScout(ticks) then
            self.nextThink = ticks + THINK_MIN_TICKS
        end
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
    if self.character == nil or self.character:getCurrentSquare() == nil then
        -- The population owner, not the behavior controller, decides when an NPC is
        -- actually stored. A streamed-out shell can temporarily lose its square before
        -- the hibernation pass captures/removes it, so keep that state explicit.
        self.state = "DETACHED"
        return
    end

    if self.observedState ~= self.state then
        self.observedState = self.state
        self.stateStartedAt = ticks
    end

    local stateAge = ticks - (self.stateStartedAt or ticks)
    local movementState = self.state == "MOVING_TO_SUPPLY"
        or self.state == "MOVING_TO_EXPLORE"
        or self.state == "ROAMING"
        or self.state == "GROUP_FOLLOW" or self.state == "GROUP_REGROUP"
        or self.state == "COMPANION_FOLLOW"
        or self.state == "MOVING_TO_COMPANION_POINT"
        or self.state == "BASE_RETURN" or self.state == "BASE_PATROL"
        or self.state == "BASE_TASK_MOVE"
        or self.state == "BASE_TASK_SUPPLY_MOVE"
        or self.state == "MEETING_APPROACH"
        or self.state == "MOVING_TO_WINDOW_ENTRY"
        or self.state == "CROSSING_WINDOW_ENTRY"
        or self.state == "MOVING_TO_REST"
        or self.state == "MOVING_TO_BASE_CANDIDATE"
        or self.state == "FLEEING"
    local actionState = self.state == "LOOTING"
        or self.state == "SEARCHING"
        or self.state == "TIMED_ACTION"
        or self.state == "ROBBING"
        or self.state == "BASE_TASK_WORK"
        or self.state == "BASE_TASK_ACTION"
        or self.state == "BASE_TASK_SUPPLY_TRANSFER"
    if (movementState and stateAge > MOVEMENT_TIMEOUT_TICKS)
        or (actionState and stateAge > ACTION_TIMEOUT_TICKS)
        or (self.state == "BREAKING_LOCKED_DOOR"
            and stateAge > MOVEMENT_TIMEOUT_TICKS) then
        if self.state == "COMPANION_FOLLOW" or self.state == "BASE_RETURN"
            or self.state == "BASE_PATROL" then
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

    if ticks >= self.nextThreatScan then
        self.nextThreatScan = ticks + THREAT_SCAN_TICKS
        local flee, assessment = fleeAssessment(self)
        if self.state ~= "FLEEING" and flee then
            if self:beginFlee(ticks, assessment) then
                return
            end
        end
        if self.state ~= "COMBAT" and self.state ~= "FLEEING" then
            local threat = nearestThreat(self, ticks)
            if not self:allowsCompanionThreat(threat) then
                threat = nil
            end
            if threat ~= nil and self:beginCombat(threat) then
                return
            end
        end
    end

    if self.state == "MEETING_WAIT" or self.state == "MEETING_READY"
        or self.state == "GREETING" then
        return
    end

    if self.state == "GROUP_WAIT" then
        if ticks >= self.nextThink then
            self.state = "IDLE"
        end
        return
    end

    if self.state == "COMPANION_WAIT" or self.state == "COMPANION_HOLD"
        or self.state == "COMPANION_GUARD" then
        if ticks >= self.nextThink then
            self.state = "IDLE"
        end
        return
    end

    if self.state == "BASE_IDLE" then
        if ticks >= self.nextThink then
            self.activeDecision = nil
            self.state = "IDLE"
        end
        return
    end

    if self.state == "BASE_AMBIENT_REST" then
        if ticks >= self.nextThink then
            self:finishDecision(ticks)
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
        local started = self.baseTaskStartedAt or ticks
        if ticks - started >= KnoxBaseJobs.workDuration(self.baseTask) then
            local taskType = self.baseTask.type
            self:finishBaseTask(true, "completed_" .. tostring(taskType))
            KnoxActivityFeed.speak(self.character,
                taskType == "guard" and "All clear here." or "Patrol done."
            )
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "BASE_TASK_SUPPLY_TRANSFER" then
        if self.baseTask == nil or self.baseTaskSupplyTransfer == nil then
            self.state = "IDLE"
            self.activeDecision = nil
            self.nextThink = ticks + THINK_MIN_TICKS
            return
        end
        if not self.character:getCharacterActions():isEmpty() then
            return
        end
        self.baseTaskSupplyTransfer = nil
        self:beginBaseTaskSupplyOrWork(ticks)
        return
    end

    if self.state == "BASE_TASK_ACTION" then
        if self.baseTask == nil
            or (self.baseTask.type ~= "sort_depot"
                and self.baseTask.type ~= "barricade"
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
                if not KnoxBaseCorpseHandling.isDragging(self.character) then
                    local recovered, retryResult = KnoxBaseCorpseHandling.retryGrab(
                        self.character,
                        self.baseTaskCorpseTarget
                    )
                    if not recovered then
                        self:finishBaseTask(false, "corpse_grab_not_completed:" .. tostring(retryResult))
                        self:finishDecision(ticks)
                        return
                    end
                    print("[KnoxSurvivors][BaseJobs] id=" .. tostring(self.id)
                        .. " corpse-grab-fallback=" .. tostring(retryResult))
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
                self.baseTaskStartedAt = ticks
                self.state = "BASE_TASK_MOVE"
                return
            end
            local complete = not KnoxBaseCorpseHandling.isDragging(self.character)
            self:finishBaseTask(
                complete,
                complete and "corpse_hauled" or "corpse_drop_not_completed"
            )
            if complete then
                KnoxActivityFeed.speak(self.character, "The body is out of the way.")
            end
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
        if not self.baseTaskActionQueued then
            local transfer = self.baseTaskTransfer
            if transfer == nil then
                transfer = KnoxBaseStorage.resolveTransfer(
                    self.base,
                    self.baseTask.target
                )
                self.baseTaskTransfer = transfer
            end
            if transfer == nil then
                self:finishBaseTask(false, "item_no_longer_available")
                self:finishDecision(ticks)
                return
            end
            local action, actionResult = KnoxBaseStorage.queueTransfer(
                self.character,
                transfer
            )
            if action == nil then
                if actionResult == "turning_to_storage" then
                    return
                end
                self:finishBaseTask(false, "storage_transfer_queue:" .. tostring(actionResult))
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
        local transfer = self.baseTaskTransfer
        local source = transfer ~= nil and transfer.source ~= nil
            and transfer.source.container or nil
        local item = transfer ~= nil and transfer.item or nil
        local moved = source ~= nil and item ~= nil and not source:contains(item)
        self:finishBaseTask(moved, moved and "sorted_depot" or "transfer_not_completed")
        if moved then
            KnoxActivityFeed.speak(self.character, "That belongs in storage.")
        end
        self:finishDecision(ticks)
        return
    end

    if self.state == "COMBAT" then
        if ticks >= self.nextThreatScan then
            self.nextThreatScan = ticks + THREAT_SCAN_TICKS
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
        if string.find(result, "COMBAT_SUCCEEDED", 1, true) == 1 then
            self.counts.combat = self.counts.combat + 1
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

    if self.state == "TIMED_ACTION" then
        if self.character:getCharacterActions():isEmpty() then
            self.counts.needs = self.counts.needs + 1
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
        or self.state == "ROAMING" or self.state == "GROUP_FOLLOW"
        or self.state == "GROUP_REGROUP"
        or self.state == "COMPANION_FOLLOW"
        or self.state == "MOVING_TO_COMPANION_POINT"
        or self.state == "BASE_RETURN" or self.state == "BASE_PATROL"
        or self.state == "BASE_TASK_MOVE"
        or self.state == "MEETING_APPROACH"
        or self.state == "MOVING_TO_WINDOW_ENTRY"
        or self.state == "CROSSING_WINDOW_ENTRY" or self.state == "MOVING_TO_REST"
        or self.state == "MOVING_TO_BASE_CANDIDATE" then
        if (self.state == "GROUP_FOLLOW" or self.state == "COMPANION_FOLLOW")
            and self:refreshFormationFollow(ticks) then
            return
        end
        local movement = tostring(self.bridge:tickNpc(self.id))
        if movement == "Succeeded" then
            if self.state == "MOVING_TO_REST" then
                self:startRecoveryPosture(ticks, true, self.ambientRest == true)
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
                    print(
                        "[KnoxSurvivors][Autonomy] id=" .. self.id
                            .. " faction-base-selection-failed=" .. tostring(result)
                    )
                end
                self:clearFactionBaseCandidate()
                self:finishDecision(ticks)
                return
            end
            if self.state == "MOVING_TO_WINDOW_ENTRY" then
                if not self:crossWindowDetour(ticks) then
                    self:abandonCurrentDecision(ticks, "window_cross_failed")
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
                self.formationFailureCount = 0
                self.activeDecision = "follow_group"
                self.state = "GROUP_WAIT"
                self.nextThink = ticks + FORMATION_REFRESH_TICKS
                return
            end
            if self.state == "GROUP_REGROUP" then
                self.counts.groupTravel = self.counts.groupTravel + 1
                self.formationFailureCount = 0
                self:finishDecision(ticks)
                return
            end
            if self.state == "COMPANION_FOLLOW" then
                self.formationFailureCount = 0
                self.activeDecision = "follow_player"
                self.state = "COMPANION_WAIT"
                self.nextThink = ticks + FORMATION_REFRESH_TICKS
                return
            end
            if self.state == "FLEEING" then
                self.activeDecision = nil
                self.state = "IDLE"
                self.nextThink = ticks + FLEE_RECHECK_TICKS
                return
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
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_haul_corpse_grab"
                    self.state = "BASE_TASK_ACTION"
                    return
                end
                if self.baseTask ~= nil and self.baseTask.type == "sort_depot" then
                    self.baseTaskTransfer = KnoxBaseStorage.resolveTransfer(
                        self.base,
                        self.baseTask.target
                    )
                    if self.baseTaskTransfer == nil then
                        self:finishBaseTask(false, "item_no_longer_available")
                        self:finishDecision(ticks)
                        return
                    end
                    self.baseTaskStartedAt = ticks
                    self.baseTaskActionQueued = false
                    self.activeDecision = "base_task_sort_depot"
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
                self.inspectedContainers[supply.container] = true
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
                else
                    self:recordFailure("loot_action_queue", ticks, 180)
                    self:releaseSupply()
                    self:finishDecision(ticks)
                end
            else
                self.counts.roam = self.counts.roam + 1
                self:finishDecision(ticks)
            end
        elseif string.find(movement, "Failed", 1, true) == 1
            or string.find(movement, "TICK_FAILED", 1, true) == 1 then
            if self.state == "GROUP_FOLLOW"
                or self.state == "GROUP_REGROUP"
                or self.state == "COMPANION_FOLLOW" then
                self:handleFormationMovementFailure(movement, ticks)
                return
            end
            if self.state == "MOVING_TO_COMPANION_POINT" then
                self.directiveMisses = self.directiveMisses + 1
                self:recordFailure("companion_point:" .. movement, ticks, EXPLORATION_RETRY_TICKS)
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
                self.nextThink = ticks + 180
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
            if string.find(movement, "FAILED_LOCKED_DOOR", 1, true) ~= nil
                and (self.state == "MOVING_TO_SUPPLY"
                    or self.state == "MOVING_TO_EXPLORE") then
                local resumeState = self.state
                if self:beginWindowDetour(ticks, resumeState)
                    or self:beginLockedDoorBreak(ticks, resumeState) then
                    return
                end
                markPendingAreaBlocked(self, ticks, "locked_entry_unavailable")
            end
            self:recordFailure("movement:" .. movement, ticks, 180)
            if self.pendingSupply ~= nil and self.pendingSupply.container ~= nil then
                self.inspectedContainers[self.pendingSupply.container] = ticks + SUPPLY_RETRY_TICKS
                print(
                    "[KnoxSurvivors][Autonomy] id=" .. self.id
                        .. " skipped-unreachable-container movement=" .. movement
                )
            end
            self:releaseSupply()
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "LOOTING" then
        if self.character:getCharacterActions():isEmpty() then
            self.counts.loot = self.counts.loot + 1
            local worn = false
            if self.pendingSupply ~= nil then
                worn = KnoxSurvivorLooting.equipUpgrade(
                    self.character,
                    self.pendingSupply.item
                ) or worn
                for _, candidate in ipairs(self.pendingSupply.items or {}) do
                    worn = KnoxSurvivorLooting.equipUpgrade(
                        self.character,
                        candidate.item
                    ) or worn
                end
            end
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " loot-complete=" .. tostring(self.activeDecision)
                    .. " worn=" .. tostring(worn)
                    .. " equipment=" .. tostring(self.bridge:equipBestNpc(self.id))
            )
            self.nextExplorationSearch = ticks + LOOT_TRAVEL_COOLDOWN_TICKS
            self.forceTravel = true
            self:releaseSupply()
            self:finishDecision(ticks)
        end
        return
    end


    if self.state == "SEARCHING" then
        if self.character:getCharacterActions():isEmpty() then
            self.counts.search = self.counts.search + 1
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " search-complete=container_no_upgrade"
            )
            self.nextExplorationSearch = ticks + EMPTY_SEARCH_COOLDOWN_TICKS
            self.forceTravel = true
            self:releaseSupply()
            self:finishDecision(ticks)
        end
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
        if recovered or ticks - self.recoveryStarted >= RECOVERY_TIMEOUT_TICKS then
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
        .. " groupLeader=" .. tostring(self.groupLeaderId)
        .. " formationSlot=" .. tostring(self.groupFormationSlot)
        .. " formationFailures=" .. tostring(self.formationFailureCount or 0)
        .. " retryAt=" .. tostring(self.nextThink or 0)
        .. " " .. KnoxSurvivorNeeds.describe(KnoxSurvivorNeeds.snapshot(self.character))
end

function Controller:shutdown()
    self:abandonBaseTask("shutdown")
    if self.character ~= nil and not self.character:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(self.character)
    end
    self.bridge:resetNpcCombat(self.id)
    self:releaseCombat()
    self:releaseSupply()
    return KnoxPersistence.captureActiveSurvivor(self.id)
end
