require "KS_Persistence"
require "KS_FactionBaseScouting"
require "KS_FactionSafehouse"
require "KS_ActivityFeed"

local Relationships = rawget(_G, "KnoxSurvivorRelationships") or {}
_G.KnoxSurvivorRelationships = Relationships

local TAG = "[KnoxSurvivors][Relationships]"
local AWARENESS_RADIUS = 14
local ATTRACTION_RADIUS = 24
local pairStates = {}
local pendingMeetings = {}
local lastGroupAssignmentTick = -60
local lastFactionEvaluationTick = -600
local lastBaseScoutingTick = -600

local function availableForNpcSocial(id)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(id)
    return affiliation == nil or affiliation.kind ~= "player"
end

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
        roam = controller.counts.roam + controller.counts.groupTravel,
        loot = controller.counts.loot,
        combat = controller.counts.combat,
    }
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function pairRoll(firstId, secondId, meetingNumber)
    local text = pairKey(firstId, secondId) .. ":" .. tostring(meetingNumber or 0)
    local value = 23
    for index = 1, #text do
        value = (value * 37 + string.byte(text, index)) % 10007
    end
    return value % 100
end

local function decideEncounterOutcome(firstId, secondId, record)
    if record ~= nil and record.disposition == "hostile" then
        return "hostile"
    end
    local firstIdentity = KnoxPersistence.getSurvivorIdentity(firstId) or {}
    local secondIdentity = KnoxPersistence.getSurvivorIdentity(secondId) or {}
    local sociability = ((firstIdentity.sociability or 50)
        + (secondIdentity.sociability or 50)) / 2
    local aggression = ((firstIdentity.aggression or 35)
        + (secondIdentity.aggression or 35)) / 2
    local hostileChance = clamp(7 + (aggression - 45) * 0.35, 4, 22)
    local joinChance = clamp(48 + (sociability - 50) * 0.45, 35, 68)
    local roll = pairRoll(firstId, secondId, record ~= nil and record.meetings or 0)
    if roll < hostileChance then
        return "hostile"
    end
    if roll < hostileChance + joinChance then
        return "join"
    end
    return "decline"
end

local function aggressionFor(id)
    local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
    return tonumber(identity.aggression) or 35
end

local function coordinateFactionBaseScouting(controllers, orderedIds, ticks)
    if ticks - lastBaseScoutingTick < 600 or getGameTime() == nil then
        return
    end
    lastBaseScoutingTick = ticks
    local handled = {}
    for _, id in ipairs(orderedIds) do
        local controller = controllers[id]
        local group = KnoxPersistence.getTravelGroupFor(id)
        local faction = group ~= nil and group.factionId ~= nil
            and KnoxPersistence.getFaction(group.factionId)
            or nil
        if controller ~= nil and (faction == nil or faction.kind == "player"
            or faction.leaderId ~= id) then
            controller:clearFactionBaseCandidate()
        end
        if faction ~= nil and faction.kind ~= "player" and not handled[faction.id] then
            handled[faction.id] = true
            local leader = controllers[faction.leaderId]
            if faction.homeBase == nil and leader ~= nil and leader.character ~= nil then
                local candidate = KnoxPersistence.getFactionBaseCandidate(faction.id)
                if candidate == nil then
                    local found = KnoxFactionBaseScouting.findBestCandidate(
                        leader.character,
                        faction.id,
                        getGameTime():getWorldAgeHours()
                    )
                    if found ~= nil then
                        candidate = KnoxPersistence.recordFactionBaseCandidate(
                            faction.id,
                            found,
                            getGameTime():getWorldAgeHours()
                        )
                        print(
                            TAG .. " faction-base-candidate=" .. faction.id
                                .. " building=" .. tostring(found.buildingId)
                                .. " score=" .. tostring(found.score)
                                .. " rooms=" .. tostring(found.rooms)
                                .. " area=" .. tostring(found.area)
                                .. " water=" .. tostring(found.water)
                        )
                    end
                end
                if candidate ~= nil then
                    leader:setFactionBaseCandidate(faction.id, candidate)
                end
            elseif leader ~= nil then
                leader:clearFactionBaseCandidate()
                if faction.homeBase ~= nil then
                    KnoxFactionSafehouse.ensure(faction)
                end
            end
        end
    end
end

local function observePair(first, second, worldAge, ticks)
    local key = pairKey(first.id, second.id)
    local state = pairStates[key] or {
        near = false,
        lastWorldAge = worldAge,
        firstCounters = copyCounters(first),
        secondCounters = copyCounters(second),
        firstPending = { roam = 0, loot = 0, combat = 0 },
        secondPending = { roam = 0, loot = 0, combat = 0 },
    }
    local firstSquare = first.character:getCurrentSquare()
    local secondSquare = second.character:getCurrentSquare()
    local sameLevel = firstSquare ~= nil and secondSquare ~= nil
        and firstSquare:getZ() == secondSquare:getZ()
    local pairDistance = sameLevel and distanceSquared(firstSquare, secondSquare) or math.huge
    local near = pairDistance <= AWARENESS_RADIUS * AWARENESS_RADIUS
    local attracted = pairDistance <= ATTRACTION_RADIUS * ATTRACTION_RADIUS
    local elapsed = math.max(0, worldAge - state.lastWorldAge)

    if near then
        local firstCurrent = copyCounters(first)
        local secondCurrent = copyCounters(second)
        local firstRoam = counterDelta(firstCurrent, state.firstCounters, "roam")
        local secondRoam = counterDelta(secondCurrent, state.secondCounters, "roam")
        local firstLoot = counterDelta(firstCurrent, state.firstCounters, "loot")
        local secondLoot = counterDelta(secondCurrent, state.secondCounters, "loot")
        local firstCombat = counterDelta(firstCurrent, state.firstCounters, "combat")
        local secondCombat = counterDelta(secondCurrent, state.secondCounters, "combat")
        state.firstPending = state.firstPending or { roam = 0, loot = 0, combat = 0 }
        state.secondPending = state.secondPending or { roam = 0, loot = 0, combat = 0 }
        state.firstPending.roam = state.firstPending.roam + firstRoam
        state.secondPending.roam = state.secondPending.roam + secondRoam
        state.firstPending.loot = state.firstPending.loot + firstLoot
        state.secondPending.loot = state.secondPending.loot + secondLoot
        state.firstPending.combat = state.firstPending.combat + firstCombat
        state.secondPending.combat = state.secondPending.combat + secondCombat
        local sharedRoam = math.min(state.firstPending.roam, state.secondPending.roam)
        local sharedLoot = math.min(state.firstPending.loot, state.secondPending.loot)
        local sharedCombat = math.min(state.firstPending.combat, state.secondPending.combat)
        state.firstPending.roam = state.firstPending.roam - sharedRoam
        state.secondPending.roam = state.secondPending.roam - sharedRoam
        state.firstPending.loot = state.firstPending.loot - sharedLoot
        state.secondPending.loot = state.secondPending.loot - sharedLoot
        state.firstPending.combat = state.firstPending.combat - sharedCombat
        state.secondPending.combat = state.secondPending.combat - sharedCombat
        local began = not state.near
        local record = KnoxPersistence.recordEncounter(first.id, second.id, {
            worldAgeHours = worldAge,
            began = began,
            nearbyHours = state.near and elapsed or 0,
            sharedRoam = sharedRoam,
            sharedLoot = sharedLoot,
            sharedCombat = sharedCombat,
        })
        if began then
            local _, _, firstName = fullName(first.character)
            local _, _, secondName = fullName(second.character)
            print(
                TAG .. " meeting=" .. first.id .. "," .. second.id
                    .. " names=\"" .. firstName .. "\",\"" .. secondName .. "\""
                    .. " meetings=" .. tostring(record.meetings)
            )
        end
    elseif state.near then
        local record = KnoxPersistence.getRelationship(first.id, second.id)
        print(
            TAG .. " separated=" .. first.id .. "," .. second.id
                .. " nearbyHours=" .. tostring(record ~= nil and record.nearbyHours or 0)
        )
    end

    if attracted and pendingMeetings[key] == nil then
        local firstGroup = KnoxPersistence.getTravelGroupFor(first.id)
        local secondGroup = KnoxPersistence.getTravelGroupFor(second.id)
        local canMeet = (firstGroup == nil and secondGroup == nil)
            or (firstGroup ~= nil and secondGroup == nil)
            or (firstGroup == nil and secondGroup ~= nil)
        local record = KnoxPersistence.getRelationship(first.id, second.id)
        local cooldownComplete = record == nil
            or (tonumber(record.nextEncounterHours) or 0) <= worldAge
        if canMeet and cooldownComplete then
            local outcome = decideEncounterOutcome(first.id, second.id, record)
            local aggressorId = aggressionFor(first.id) >= aggressionFor(second.id)
                and first.id or second.id
            pendingMeetings[key] = {
                firstId = first.id,
                secondId = second.id,
                phase = "REQUESTED",
                startedAt = ticks,
                outcome = outcome,
                aggressorId = aggressorId,
                joinGroupId = firstGroup ~= nil and firstGroup.id
                    or (secondGroup ~= nil and secondGroup.id or nil),
                lonerId = firstGroup ~= nil and second.id
                    or (secondGroup ~= nil and first.id or nil),
            }
            print(
                TAG .. " noticed=" .. first.id .. "," .. second.id
                    .. " distance=" .. tostring(math.sqrt(pairDistance))
                    .. " outcome=" .. outcome
            )
        end
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
        if first ~= nil and first.character ~= nil
            and availableForNpcSocial(first.id) then
            local forename, surname = fullName(first.character)
            KnoxPersistence.ensureSurvivorIdentity(first.id, forename, surname, worldAge)
            for otherIndex = index + 1, #orderedIds do
                local second = controllers[orderedIds[otherIndex]]
                if second ~= nil and second.character ~= nil
                    and availableForNpcSocial(second.id) then
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
            if not availableForNpcSocial(id) then
                controller:clearGroupLeader()
                controller:setGroupMembers({})
            else
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
end

function Relationships.coordinate(controllers, orderedIds, ticks)
    assignGroupLeaders(controllers, orderedIds, ticks)
    if ticks - lastFactionEvaluationTick >= 600 and getGameTime() ~= nil then
        lastFactionEvaluationTick = ticks
        local evaluated = {}
        for _, id in ipairs(orderedIds) do
            if availableForNpcSocial(id) then
            local group = KnoxPersistence.getTravelGroupFor(id)
            if group ~= nil and not evaluated[group.id] then
                evaluated[group.id] = true
                local faction, result = KnoxPersistence.evaluateTravelGroupFaction(
                    group.id,
                    getGameTime():getWorldAgeHours()
                )
                if faction ~= nil and result == "created" then
                    local leader = controllers[faction.leaderId]
                    if leader ~= nil and leader.character ~= nil
                        and leader.state ~= "COMBAT" then
                        KnoxActivityFeed.speak(leader.character, "We should find somewhere to settle.")
                    end
                    KnoxActivityFeed.event("A new survivor faction has formed.")
                    print(
                        TAG .. " faction-formed=" .. faction.id
                            .. " group=" .. group.id
                            .. " members=" .. table.concat(group.memberIds, ",")
                    )
                end
            end
            end
        end
    end
    coordinateFactionBaseScouting(controllers, orderedIds, ticks)
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
        elseif not availableForNpcSocial(first.id)
            or not availableForNpcSocial(second.id) then
            abortMeeting(key, meeting, first, second, ticks, "player_recruited")
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
            if meeting.outcome == "hostile" then
                local aggressor = meeting.aggressorId == first.id and first or second
                KnoxActivityFeed.speak(aggressor.character, "Hand over some supplies. No trouble.")
            elseif meeting.outcome == "decline" then
                KnoxActivityFeed.speak(first.character, "Just passing through.")
            elseif meeting.joinGroupId ~= nil then
                local recruiter = meeting.lonerId == first.id and second or first
                KnoxActivityFeed.speak(recruiter.character, "We've got room, if you can pull your weight.")
            else
                KnoxActivityFeed.speak(first.character, "Hey. You travelling alone?")
            end
            meeting.phase = "GREETING"
            meeting.greetingAt = ticks
            print(TAG .. " greeting-started=" .. first.id .. "," .. second.id)
        elseif meeting.phase == "GREETING" then
            if not meeting.responseSpoken and ticks - meeting.greetingAt >= 90 then
                if meeting.outcome == "hostile" then
                    local victim = meeting.aggressorId == first.id and second or first
                    KnoxActivityFeed.speak(victim.character, "Take it and leave.")
                elseif meeting.outcome == "decline" then
                    KnoxActivityFeed.speak(second.character, "Same here. Stay safe.")
                elseif meeting.joinGroupId ~= nil then
                    local loner = meeting.lonerId == first.id and first or second
                    KnoxActivityFeed.speak(loner.character, "I can. Let's move.")
                else
                    KnoxActivityFeed.speak(second.character, "Yeah. Safer if we stick together.")
                end
                meeting.responseSpoken = true
            end
            if ticks - meeting.greetingAt >= 240 then
                local group = nil
                local worldAge = getGameTime():getWorldAgeHours()
                if meeting.outcome == "hostile" then
                    local aggressor = meeting.aggressorId == first.id and first or second
                    local victim = meeting.aggressorId == first.id and second or first
                    KnoxPersistence.setRelationshipDisposition(
                        first.id,
                        second.id,
                        "hostile",
                        worldAge + 24
                    )
                    victim:holdForRobbery(ticks)
                    if not aggressor:beginRobbery(victim.character, ticks) then
                        aggressor:resumeAfterGreeting(ticks)
                    end
                    pendingMeetings[key] = nil
                    print(
                        TAG .. " encounter-outcome=hostile robber=" .. aggressor.id
                            .. " victim=" .. victim.id
                    )
                    KnoxActivityFeed.event("A survivor encounter turned hostile.")
                elseif meeting.outcome == "decline" then
                    KnoxPersistence.setRelationshipDisposition(
                        first.id,
                        second.id,
                        "declined",
                        worldAge + 6
                    )
                    first:resumeAfterGreeting(ticks)
                    second:resumeAfterGreeting(ticks)
                    pendingMeetings[key] = nil
                    print(TAG .. " encounter-outcome=decline " .. first.id .. "," .. second.id)
                    KnoxActivityFeed.event("Two survivors part ways.")
                elseif meeting.joinGroupId ~= nil then
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
                if meeting.outcome == "join" then
                    KnoxPersistence.setRelationshipDisposition(
                        first.id,
                        second.id,
                        "allied",
                        worldAge
                    )
                    first:resumeAfterGreeting(ticks)
                    second:resumeAfterGreeting(ticks)
                    pendingMeetings[key] = nil
                    print(
                        TAG .. " travel-group=" .. tostring(group ~= nil and group.id or "none")
                            .. " members=" .. first.id .. "," .. second.id
                            .. " faction=" .. tostring(group ~= nil and group.factionId or false)
                            .. (group ~= nil and group.factionId == nil and " requires=3" or "")
                    )
                    KnoxActivityFeed.event("Survivors have agreed to travel together.")
                    lastGroupAssignmentTick = ticks - 60
                end
            end
        end
    end
end

function Relationships.resetRuntime()
    pairStates = {}
    pendingMeetings = {}
    lastGroupAssignmentTick = -60
    lastFactionEvaluationTick = -600
    lastBaseScoutingTick = -600
end
