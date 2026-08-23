require "KS_Persistence"

local Relationships = rawget(_G, "KnoxSurvivorRelationships") or {}
_G.KnoxSurvivorRelationships = Relationships

local TAG = "[KnoxSurvivors][Relationships]"
local AWARENESS_RADIUS = 12
local pairStates = {}
local pendingMeetings = {}
local lastGroupAssignmentTick = -60
local lastFactionEvaluationTick = -600

local function pairKey(firstId, secondId)
    return firstId < secondId
        and firstId .. "::" .. secondId
        or secondId .. "::" .. firstId
end

local function fullName(character)
    local descriptor = character:getDescriptor()
    local forename = tostring(descriptor:getForename() or "")
    local surname = tostring(descriptor:getSurname() or "")
    return forename, surname, forename .. " " .. surname
end

local function distanceSquared(first, second)
    local dx = first:getX() - second:getX()
    local dy = first:getY() - second:getY()
    return dx * dx + dy * dy
end

local function counterDelta(current, previous, name)
    return math.max(0, (current[name] or 0) - (previous[name] or 0))
end

local function copyCounters(controller)
    return {
        roam = controller.counts.roam,
        loot = controller.counts.loot,
        combat = controller.counts.combat,
    }
end

local function observePair(first, second, worldAge, ticks)
    local key = pairKey(first.id, second.id)
    local state = pairStates[key] or {
        near = false,
        lastWorldAge = worldAge,
        firstCounters = copyCounters(first),
        secondCounters = copyCounters(second),
    }
    local firstSquare = first.character:getCurrentSquare()
    local secondSquare = second.character:getCurrentSquare()
    local near = firstSquare ~= nil and secondSquare ~= nil
        and firstSquare:getZ() == secondSquare:getZ()
        and distanceSquared(firstSquare, secondSquare) <= AWARENESS_RADIUS * AWARENESS_RADIUS
    local elapsed = math.max(0, worldAge - state.lastWorldAge)

    if near then
        local firstRoam = counterDelta(first.counts, state.firstCounters, "roam")
        local secondRoam = counterDelta(second.counts, state.secondCounters, "roam")
        local firstLoot = counterDelta(first.counts, state.firstCounters, "loot")
        local secondLoot = counterDelta(second.counts, state.secondCounters, "loot")
        local firstCombat = counterDelta(first.counts, state.firstCounters, "combat")
        local secondCombat = counterDelta(second.counts, state.secondCounters, "combat")
        local began = not state.near
        local record = KnoxPersistence.recordEncounter(first.id, second.id, {
            worldAgeHours = worldAge,
            began = began,
            nearbyHours = state.near and elapsed or 0,
            sharedRoam = math.min(firstRoam, secondRoam),
            sharedLoot = math.min(firstLoot, secondLoot),
            sharedCombat = math.min(firstCombat, secondCombat),
        })
        if began then
            local _, _, firstName = fullName(first.character)
            local _, _, secondName = fullName(second.character)
            print(
                TAG .. " meeting=" .. first.id .. "," .. second.id
                    .. " names=\"" .. firstName .. "\",\"" .. secondName .. "\""
                    .. " meetings=" .. tostring(record.meetings)
            )
            local firstGroup = KnoxPersistence.getTravelGroupFor(first.id)
            local secondGroup = KnoxPersistence.getTravelGroupFor(second.id)
            local canMeet = (firstGroup == nil and secondGroup == nil)
                or (firstGroup ~= nil and secondGroup == nil)
                or (firstGroup == nil and secondGroup ~= nil)
            if canMeet and not (firstGroup ~= nil and secondGroup ~= nil) then
                pendingMeetings[key] = pendingMeetings[key] or {
                    firstId = first.id,
                    secondId = second.id,
                    phase = "REQUESTED",
                    startedAt = ticks,
                    joinGroupId = firstGroup ~= nil and firstGroup.id
                        or (secondGroup ~= nil and secondGroup.id or nil),
                    lonerId = firstGroup ~= nil and second.id
                        or (secondGroup ~= nil and first.id or nil),
                }
            end
        end
    elseif state.near then
        local record = KnoxPersistence.getRelationship(first.id, second.id)
        print(
            TAG .. " separated=" .. first.id .. "," .. second.id
                .. " nearbyHours=" .. tostring(record ~= nil and record.nearbyHours or 0)
        )
    end

    state.near = near
    state.lastWorldAge = worldAge
    state.firstCounters = copyCounters(first)
    state.secondCounters = copyCounters(second)
    pairStates[key] = state
end

function Relationships.observe(controllers, orderedIds, ticks)
    if getGameTime() == nil then
        return
    end
    local worldAge = getGameTime():getWorldAgeHours()
    for index = 1, #orderedIds do
        local first = controllers[orderedIds[index]]
        if first ~= nil and first.character ~= nil then
            local forename, surname = fullName(first.character)
            KnoxPersistence.ensureSurvivorIdentity(first.id, forename, surname, worldAge)
            for otherIndex = index + 1, #orderedIds do
                local second = controllers[orderedIds[otherIndex]]
                if second ~= nil and second.character ~= nil then
                    local secondForename, secondSurname = fullName(second.character)
                    KnoxPersistence.ensureSurvivorIdentity(
                        second.id,
                        secondForename,
                        secondSurname,
                        worldAge
                    )
                    observePair(first, second, worldAge, ticks or 0)
                end
            end
        end
    end
end

local function resumeMeetingController(controller, ticks)
    if controller ~= nil and (controller.state == "MEETING_WAIT"
        or controller.state == "MEETING_APPROACH"
        or controller.state == "MEETING_READY"
        or controller.state == "GREETING") then
        controller:resumeAfterGreeting(ticks)
    end
end

local function abortMeeting(key, meeting, first, second, ticks, reason)
    resumeMeetingController(first, ticks)
    resumeMeetingController(second, ticks)
    pendingMeetings[key] = nil
    if pairStates[key] ~= nil then
        pairStates[key].near = false
    end
    print(TAG .. " greeting-aborted=" .. meeting.firstId .. "," .. meeting.secondId
        .. " reason=" .. tostring(reason))
end

local function assignGroupLeaders(controllers, orderedIds, ticks)
    if ticks - lastGroupAssignmentTick < 60 then
        return
    end
    lastGroupAssignmentTick = ticks
    for _, id in ipairs(orderedIds) do
        local controller = controllers[id]
        if controller ~= nil then
            local group = KnoxPersistence.getTravelGroupFor(id)
            if group ~= nil and group.leaderId ~= id then
                local leader = controllers[group.leaderId]
                controller:setGroupLeader(
                    group.leaderId,
                    leader ~= nil and leader.character or nil
                )
                controller:setGroupMembers({})
            elseif group ~= nil then
                local members = {}
                for _, memberId in ipairs(group.memberIds or {}) do
                    local member = controllers[memberId]
                    if member ~= nil and member.character ~= nil then
                        members[#members + 1] = member.character
                    end
                end
                controller:clearGroupLeader()
                controller:setGroupMembers(members)
            else
                controller:clearGroupLeader()
                controller:setGroupMembers({})
            end
        end
    end
end

function Relationships.coordinate(controllers, orderedIds, ticks)
    assignGroupLeaders(controllers, orderedIds, ticks)
    if ticks - lastFactionEvaluationTick >= 600 and getGameTime() ~= nil then
        lastFactionEvaluationTick = ticks
        local evaluated = {}
        for _, id in ipairs(orderedIds) do
            local group = KnoxPersistence.getTravelGroupFor(id)
            if group ~= nil and not evaluated[group.id] then
                evaluated[group.id] = true
                local faction, result = KnoxPersistence.evaluateTravelGroupFaction(
                    group.id,
                    getGameTime():getWorldAgeHours()
                )
                if faction ~= nil and result == "created" then
                    print(
                        TAG .. " faction-formed=" .. faction.id
                            .. " group=" .. group.id
                            .. " members=" .. table.concat(group.memberIds, ",")
                    )
                end
            end
        end
    end
    for key, meeting in pairs(pendingMeetings) do
        local first = controllers[meeting.firstId]
        local second = controllers[meeting.secondId]
        local firstGroup = first ~= nil and KnoxPersistence.getTravelGroupFor(first.id) or nil
        local secondGroup = second ~= nil and KnoxPersistence.getTravelGroupFor(second.id) or nil
        local invalidMembership = meeting.joinGroupId == nil
            and (firstGroup ~= nil or secondGroup ~= nil)
            or meeting.joinGroupId ~= nil
                and ((firstGroup ~= nil and firstGroup.id ~= meeting.joinGroupId)
                    or (secondGroup ~= nil and secondGroup.id ~= meeting.joinGroupId)
                    or (meeting.lonerId == meeting.firstId and firstGroup ~= nil)
                    or (meeting.lonerId == meeting.secondId and secondGroup ~= nil)
                    or (firstGroup == nil and secondGroup == nil))
        if first == nil or second == nil then
            pendingMeetings[key] = nil
        elseif invalidMembership then
            pendingMeetings[key] = nil
        elseif ticks - meeting.startedAt > 1200 then
            abortMeeting(key, meeting, first, second, ticks, "timeout")
        elseif meeting.phase ~= "REQUESTED"
            and (first.state == "COMBAT" or second.state == "COMBAT") then
            abortMeeting(key, meeting, first, second, ticks, "combat")
        elseif meeting.phase == "REQUESTED" then
            if first:canInterruptForMeeting() and second:canInterruptForMeeting()
                and first:interruptForMeeting() and second:interruptForMeeting() then
                if first:beginMeetingApproach(second.character) then
                    meeting.phase = "APPROACHING"
                    print(TAG .. " greeting-approach=" .. first.id .. "->" .. second.id)
                else
                    abortMeeting(key, meeting, first, second, ticks, "no_approach")
                end
            end
        elseif meeting.phase == "APPROACHING" and first.state == "MEETING_READY" then
            first:beginGreeting()
            second:beginGreeting()
            first.character:faceLocationF(second.character:getX(), second.character:getY())
            second.character:faceLocationF(first.character:getX(), first.character:getY())
            if meeting.joinGroupId ~= nil then
                local recruiter = meeting.lonerId == first.id and second or first
                recruiter.character:Say("We've got room, if you can pull your weight.")
            else
                first.character:Say("Hey. You travelling alone?")
            end
            meeting.phase = "GREETING"
            meeting.greetingAt = ticks
            print(TAG .. " greeting-started=" .. first.id .. "," .. second.id)
        elseif meeting.phase == "GREETING" then
            if not meeting.responseSpoken and ticks - meeting.greetingAt >= 90 then
                if meeting.joinGroupId ~= nil then
                    local loner = meeting.lonerId == first.id and first or second
                    loner.character:Say("I can. Let's move.")
                else
                    second.character:Say("Yeah. Safer if we stick together.")
                end
                meeting.responseSpoken = true
            end
            if ticks - meeting.greetingAt >= 240 then
                local group = nil
                if meeting.joinGroupId ~= nil then
                    group = KnoxPersistence.addTravelGroupMember(
                        meeting.joinGroupId,
                        meeting.lonerId
                    )
                else
                    group = KnoxPersistence.createTravelGroup(
                        { first.id, second.id },
                        getGameTime():getWorldAgeHours()
                    )
                end
                first:resumeAfterGreeting(ticks)
                second:resumeAfterGreeting(ticks)
                pendingMeetings[key] = nil
                print(
                    TAG .. " travel-group=" .. tostring(group ~= nil and group.id or "none")
                        .. " members=" .. first.id .. "," .. second.id
                        .. " faction=" .. tostring(group ~= nil and group.factionId or false)
                        .. (group ~= nil and group.factionId == nil and " requires=3" or "")
                )
                lastGroupAssignmentTick = ticks - 60
            end
        end
    end
end

function Relationships.resetRuntime()
    pairStates = {}
    pendingMeetings = {}
    lastGroupAssignmentTick = -60
    lastFactionEvaluationTick = -600
end
