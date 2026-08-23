require "TimedActions/ISTimedActionQueue"
require "Util/AdjacentFreeTileFinder"
require "KS_SurvivorNeeds"
require "KS_SurvivorInventoryActions"
require "KS_Persistence"
require "KS_SurvivorLooting"

local Controller = rawget(_G, "KnoxAutonomyController") or {}
_G.KnoxAutonomyController = Controller
Controller.__index = Controller

local THINK_MIN_TICKS = 30
local THINK_JITTER_TICKS = 45
local THREAT_SCAN_TICKS = 15
local THREAT_RADIUS = 10
local THREAT_FAILURE_COOLDOWN_TICKS = 900
local SUPPLY_SCAN_RADIUS = 12
local SUPPLY_RETRY_TICKS = 600
local EXPLORATION_SCAN_RADIUS = 12
local EXPLORATION_RETRY_TICKS = 180
local ROAM_MIN_RADIUS = 6
local ROAM_MAX_RADIUS = 18
local RECOVERY_RECHECK_TICKS = 180
local RECOVERY_TIMEOUT_TICKS = 900
local MOVEMENT_TIMEOUT_TICKS = 1500
local ACTION_TIMEOUT_TICKS = 1200
local GROUP_SOFT_LEASH_SQUARED = 100
local ENTRY_SCAN_RADIUS = 16

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
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

local function nearestThreat(self, ticks)
    local square = self.character:getCurrentSquare()
    local cell = getCell()
    if square == nil or cell == nil then
        return nil
    end
    local nearest = nil
    local nearestDistance = THREAT_RADIUS * THREAT_RADIUS
    local zombies = cell:getZombieList()
    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        local zombieSquare = zombie:getCurrentSquare()
        if not zombie:isDead() and zombieSquare ~= nil and zombieSquare:getZ() == square:getZ()
            and not threatUnavailable(self, zombie, ticks)
            and not reservedByOther(self.reservations, "threats", zombie, self.id) then
            local distance = distanceSquared(square, zombieSquare)
            if distance <= nearestDistance then
                nearest = zombie
                nearestDistance = distance
            end
        end
    end
    return nearest
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
                                    and not containerUnavailable(self, container, ticks) then
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

local function findExploration(self, ticks)
    local origin = self.character:getCurrentSquare()
    if origin == nil or getCell() == nil then
        return nil
    end
    local fallback = nil
    for radius = 0, EXPLORATION_SCAN_RADIUS do
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
                                            3
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
    self.nextWorldSearch = 0
    self.nextExplorationSearch = 0
    self.recoveryStarted = 0
    self.inspectedContainers = {}
    self.stateStartedAt = ticks
    self.observedState = self.state
    self.entryDetour = nil
    self.nextNeedCallout = 0
    self.groupLeaderId = nil
    self.groupLeader = nil
    self.groupMembers = {}
    self.counts = {
        roam = 0,
        loot = 0,
        search = 0,
        needs = 0,
        combat = 0,
        groupTravel = 0,
        failures = 0,
    }
    character:setZombiesDontAttack(false)
    return self
end


function Controller:setGroupLeader(id, character)
    self.groupLeaderId = id
    self.groupLeader = character
end

function Controller:clearGroupLeader()
    self.groupLeaderId = nil
    self.groupLeader = nil
end

function Controller:setGroupMembers(members)
    self.groupMembers = members or {}
end

function Controller:hasDistantGroupMember()
    local square = self.character:getCurrentSquare()
    if square == nil then
        return false
    end
    for _, member in ipairs(self.groupMembers or {}) do
        if member ~= nil and member ~= self.character and member:getCurrentSquare() ~= nil
            and distanceSquared(square, member:getCurrentSquare()) > GROUP_SOFT_LEASH_SQUARED then
            return true
        end
    end
    return false
end

function Controller:sayNeedIfGrouped(decision, ticks)
    local grouped = self.groupLeader ~= nil or #(self.groupMembers or {}) > 1
    if not grouped or ticks < self.nextNeedCallout then
        return
    end
    local line = decision == "find_food" and "I'm nearly out of food."
        or (decision == "find_water" and "I need water soon."
            or (decision == "find_medical" and "I need something for this wound." or nil))
    if line ~= nil then
        self.character:Say(line)
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

function Controller:beginGroupFollow(ticks)
    if self.groupLeader == nil or self.groupLeader:getCurrentSquare() == nil then
        return false
    end
    local approach = AdjacentFreeTileFinder.Find(
        self.groupLeader:getCurrentSquare(),
        self.character
    )
    if approach == nil then
        self.nextThink = ticks + THINK_MIN_TICKS
        return false
    end
    local result = tostring(self.bridge:moveNpc(self.id, approach))
    if string.find(result, "MOVE_STARTED", 1, true) ~= 1 then
        self.nextThink = ticks + THINK_MIN_TICKS
        return false
    end
    self.activeDecision = "follow_group"
    self.state = "GROUP_FOLLOW"
    return true
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
    local result = tostring(self.bridge:beginNpcLockedDoorCombat(self.id))
    if string.find(result, "COMBAT_STARTED", 1, true) ~= 1 then
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


function Controller:beginExploration(ticks)
    if ticks < self.nextExplorationSearch then
        return false
    end
    local target = findExploration(self, ticks)
    if target == nil then
        self.nextExplorationSearch = ticks + EXPLORATION_RETRY_TICKS
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
        self.counts.failures = self.counts.failures + 1
        return false
    end
    self.pendingSupply = target
    self.activeDecision = target.items ~= nil and #target.items > 0
        and "loot_useful_items_" .. tostring(#target.items)
        or "inspect_container"
    self.state = "MOVING_TO_EXPLORE"
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=MOVING_TO_EXPLORE goal=" .. tostring(self.activeDecision)
    )
    return true
end

function Controller:releaseCombat()
    release(self.reservations, "threats", self.combatTarget, self.id)
    self.combatTarget = nil
end

function Controller:finishDecision(ticks)
    KnoxPersistence.captureActiveSurvivor(self.id)
    self.activeDecision = nil
    self.state = "IDLE"
    self.nextThink = ticks + THINK_MIN_TICKS + ZombRand(THINK_JITTER_TICKS)
end

function Controller:beginCombat(target)
    if target == nil or target:getCurrentSquare() == nil
        or not reserve(self.reservations, "threats", target, self.id) then
        return false
    end
    if not self.character:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(self.character)
    end
    local approach = AdjacentFreeTileFinder.Find(target:getCurrentSquare(), self.character)
    if approach == nil then
        release(self.reservations, "threats", target, self.id)
        return false
    end
    local result = tostring(self.bridge:beginNpcLiveCombat(self.id, target, approach))
    if string.find(result, "COMBAT_STARTED", 1, true) ~= 1 then
        self.bridge:resetNpcCombat(self.id)
        self.failedThreats[target] = self.nextThreatScan + THREAT_FAILURE_COOLDOWN_TICKS
        release(self.reservations, "threats", target, self.id)
        self.counts.failures = self.counts.failures + 1
        return false
    end
    self:releaseSupply()
    self.combatTarget = target
    self.activeDecision = "fight"
    self.state = "COMBAT"
    print("[KnoxSurvivors][Autonomy] id=" .. self.id .. " state=COMBAT " .. result)
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
        self.counts.failures = self.counts.failures + 1
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
        self.counts.failures = self.counts.failures + 1
        self.nextThink = ticks + THINK_MIN_TICKS
        return false
    end
    self.activeDecision = "roam"
    self.state = "ROAMING"
    print(
        "[KnoxSurvivors][Autonomy] id=" .. self.id
            .. " state=ROAMING target=" .. target:getX() .. "," .. target:getY()
    )
    return true
end

function Controller:think(ticks)
    local threat = nearestThreat(self, ticks)
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
            self.activeDecision = decision.kind
            self.state = "TIMED_ACTION"
            print(
                "[KnoxSurvivors][Autonomy] id=" .. self.id
                    .. " state=TIMED_ACTION kind=" .. decision.kind
            )
        else
            self.counts.failures = self.counts.failures + 1
            self.nextThink = ticks + THINK_MIN_TICKS
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
        self.activeDecision = decision.kind
        self.state = "WAITING_TO_RECOVER"
        self.recoveryStarted = ticks
        self.nextThink = ticks + RECOVERY_RECHECK_TICKS
        return
    end
    if self.groupLeader ~= nil and self.groupLeader:getCurrentSquare() ~= nil then
        local distance = distanceSquared(
            self.character:getCurrentSquare(),
            self.groupLeader:getCurrentSquare()
        )
        if distance > 9 then
            self:beginGroupFollow(ticks)
        else
            self.state = "GROUP_WAIT"
            self.nextThink = ticks + 60
        end
        return
    end
    if self:hasDistantGroupMember() then
        self.state = "GROUP_WAIT"
        self.nextThink = ticks + 90
        return
    end
    if not self:beginExploration(ticks) then
        self:beginRoam(ticks)
    end
end

function Controller:tick(ticks)
    if self.character == nil or self.character:getCurrentSquare() == nil then
        self.state = "STORED"
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
        or self.state == "GROUP_FOLLOW"
        or self.state == "MEETING_APPROACH"
        or self.state == "MOVING_TO_WINDOW_ENTRY"
        or self.state == "CROSSING_WINDOW_ENTRY"
    local actionState = self.state == "LOOTING"
        or self.state == "SEARCHING"
        or self.state == "TIMED_ACTION"
    if (movementState and stateAge > MOVEMENT_TIMEOUT_TICKS)
        or (actionState and stateAge > ACTION_TIMEOUT_TICKS)
        or (self.state == "BREAKING_LOCKED_DOOR"
            and stateAge > MOVEMENT_TIMEOUT_TICKS) then
        self:abandonCurrentDecision(ticks, "state_timeout_" .. tostring(self.state))
        return
    end

    if self.state ~= "COMBAT" and ticks >= self.nextThreatScan then
        self.nextThreatScan = ticks + THREAT_SCAN_TICKS
        local threat = nearestThreat(self, ticks)
        if threat ~= nil and self:beginCombat(threat) then
            return
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

    if self.state == "COMBAT" then
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

    if self.state == "MOVING_TO_SUPPLY" or self.state == "MOVING_TO_EXPLORE"
        or self.state == "ROAMING" or self.state == "GROUP_FOLLOW"
        or self.state == "MEETING_APPROACH"
        or self.state == "MOVING_TO_WINDOW_ENTRY"
        or self.state == "CROSSING_WINDOW_ENTRY" then
        local movement = tostring(self.bridge:tickNpc(self.id))
        if movement == "Succeeded" then
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
                self:finishDecision(ticks)
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
                    self.counts.failures = self.counts.failures + 1
                    self:releaseSupply()
                    self:finishDecision(ticks)
                end
            else
                self.counts.roam = self.counts.roam + 1
                self:finishDecision(ticks)
            end
        elseif string.find(movement, "Failed", 1, true) == 1
            or string.find(movement, "TICK_FAILED", 1, true) == 1 then
            if string.find(movement, "FAILED_LOCKED_DOOR", 1, true) ~= nil
                and (self.state == "MOVING_TO_SUPPLY"
                    or self.state == "MOVING_TO_EXPLORE") then
                local resumeState = self.state
                if self:beginWindowDetour(ticks, resumeState)
                    or self:beginLockedDoorBreak(ticks, resumeState) then
                    return
                end
            end
            self.counts.failures = self.counts.failures + 1
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
            self:releaseSupply()
            self:finishDecision(ticks)
        end
        return
    end

    if self.state == "WAITING_TO_RECOVER" then
        if ticks < self.nextThink then
            return
        end
        local snapshot = KnoxSurvivorNeeds.snapshot(self.character)
        local recovered = snapshot.endurance > KnoxSurvivorNeeds.thresholds.lowEndurance
            and (self.activeDecision ~= "sleep"
                or snapshot.fatigue < KnoxSurvivorNeeds.thresholds.fatigue)
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
        .. " failures=" .. tostring(self.counts.failures)
        .. " groupLeader=" .. tostring(self.groupLeaderId)
        .. " " .. KnoxSurvivorNeeds.describe(KnoxSurvivorNeeds.snapshot(self.character))
end

function Controller:shutdown()
    if self.character ~= nil and not self.character:getCharacterActions():isEmpty() then
        ISTimedActionQueue.clear(self.character)
    end
    self.bridge:resetNpcCombat(self.id)
    self:releaseCombat()
    self:releaseSupply()
    KnoxPersistence.captureActiveSurvivor(self.id)
end
