require "KS_Persistence"
require "KS_FactionBaseScouting"
require "KS_FactionSafehouse"
require "KS_ActivityFeed"
require "KS_Settings"

local Relationships = rawget(_G, "KnoxSurvivorRelationships") or {}
_G.KnoxSurvivorRelationships = Relationships

local TAG = "[KnoxSurvivors][Relationships]"
local AWARENESS_RADIUS = 14
local CAUTIOUS_APPROACH_RADIUS = 10
local NEUTRAL_AVOID_COOLDOWN_HOURS = 1.5
local GREETING_COOLDOWN_HOURS = 6
local ABORT_COOLDOWN_HOURS = 0.5
local pairStates = {}
local pendingMeetings = {}
local lastGroupAssignmentTick = -60
local lastFactionEvaluationTick = -600
local lastBaseScoutingTick = -600

local ENCOUNTER_LINES = {
    hostile = {
        { "Drop the bag and walk away.", "Take it. Just back off." },
        { "Leave the supplies. Nobody gets hurt.", "Fine. They're yours." },
        { "Don't make this harder than it needs to be.", "All right. Easy." },
    },
    decline = {
        { "Just passing through.", "Same here. Stay safe." },
        { "I'm better off alone for now.", "Fair enough. Take care." },
        { "Not looking for company.", "Understood. Good luck." },
    },
    greet = {
        { "You all right out here?", "Managing. Stay safe." },
        { "Haven't seen anyone alive in a while.", "Same. Keep your head down." },
        { "Area been quiet for you?", "Quiet enough. For now." },
        { "Need anything before I move on?", "I'm all right. Thanks." },
    },
    recruit = {
        { "We've got room, if you can pull your weight.", "I can. Let's move." },
        { "You'd be safer travelling with us.", "Yeah. I'll come with you." },
        { "We watch each other's backs. Interested?", "Sounds better than being alone." },
    },
    join = {
        { "Hey. You travelling alone?", "Yeah. Safer if we stick together." },
        { "Want to move together for a while?", "All right. Lead on." },
        { "Two sets of eyes beat one.", "Can't argue with that." },
    },
}

local function encounterLine(meeting, response)
    local kind = meeting.outcome
    if meeting.outcome == "join" then
        kind = meeting.joinGroupId ~= nil and "recruit" or "join"
    end
    local bank = ENCOUNTER_LINES[kind] or ENCOUNTER_LINES.greet
    local hash = 0
    local key = tostring(meeting.firstId) .. tostring(meeting.secondId)
        .. tostring(meeting.startedAt or 0)
    for index = 1, #key do hash = (hash * 31 + string.byte(key, index)) % 2147483647 end
    local pair = bank[(hash % #bank) + 1]
    return pair[response and 2 or 1]
end

local function availableForNpcSocial(id)
    local affiliation = KnoxPersistence.getSurvivorAffiliation(id)
    local duty = KnoxPersistence.getSurvivorDuty(id)
    return (affiliation == nil or affiliation.kind ~= "player")
        and (duty == nil or (duty.mode ~= "companion" and duty.mode ~= "base"))
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

local function canPerceiveHuman(first, second)
    if first == nil or second == nil then
        return false
    end
    local firstSquare = first:getCurrentSquare()
    local secondSquare = second:getCurrentSquare()
    if firstSquare == nil or secondSquare == nil
        or firstSquare:getZ() ~= secondSquare:getZ()
        or distanceSquared(firstSquare, secondSquare) > AWARENESS_RADIUS * AWARENESS_RADIUS then
        return false
    end
    local firstSuccess, firstVisible = pcall(function()
        return first:CanSee(second)
    end)
    if firstSuccess and firstVisible == true then
        return true
    end
    local secondSuccess, secondVisible = pcall(function()
        return second:CanSee(first)
    end)
    return secondSuccess and secondVisible == true
end

function Relationships.canPerceiveHuman(first, second)
    return canPerceiveHuman(first, second)
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

local function relationshipDisposition(firstId, secondId)
    if KnoxPersistence.getSurvivorDisposition ~= nil then
        return KnoxPersistence.getSurvivorDisposition(firstId, secondId)
    end
    local record = KnoxPersistence.getRelationship(firstId, secondId)
    return record ~= nil and record.disposition or "neutral"
end

-- Encounter results are intentionally modest.  First contact may be a cautious
-- greeting or no interaction at all; it must not turn every pair inside view
-- into an instant travelling party.  Existing aggression can still create the
-- established robbery outcome, while already-hostile people stop socializing.
local function decideEncounterOutcome(firstId, secondId, record)
    local disposition = relationshipDisposition(firstId, secondId)
    if disposition == "self" or disposition == "allied" then
        return "none"
    end
    if disposition == "hostile" then
        return "avoid_hostile"
    end
    local firstIdentity = KnoxPersistence.getSurvivorIdentity(firstId) or {}
    local secondIdentity = KnoxPersistence.getSurvivorIdentity(secondId) or {}
    local sociability = ((firstIdentity.sociability or 50)
        + (secondIdentity.sociability or 50)) / 2
    local aggression = ((firstIdentity.aggression or 35)
        + (secondIdentity.aggression or 35)) / 2
    local hostileChance = clamp(7 + (aggression - 45) * 0.35, 4, 22)
    local cautiousGreetingChance = clamp(42 + (sociability - 50) * 0.30, 25, 58)
    local hasFamiliarity = record ~= nil and (tonumber(record.meetings) or 0) >= 2
    local sharedActivity = record ~= nil and ((tonumber(record.sharedRoam) or 0)
        + (tonumber(record.sharedLoot) or 0) + (tonumber(record.sharedCombat) or 0))
        or 0
    local joinChance = hasFamiliarity and sharedActivity > 0
        and clamp(32 + (sociability - 50) * 0.35, 20, 50)
        or 0
    local roll = pairRoll(firstId, secondId, record ~= nil and record.meetings or 0)
    if KnoxSettings.allowHostileEncounters() and roll < hostileChance then
        return "hostile"
    end
    local socialRoll = roll - (KnoxSettings.allowHostileEncounters() and hostileChance or 0)
    if joinChance > 0 and socialRoll < joinChance then
        return "join"
    end
    if socialRoll < joinChance + cautiousGreetingChance then
        return "greet"
    end
    return "avoid"
end

function Relationships.classifyEncounter(firstId, secondId)
    return relationshipDisposition(firstId, secondId)
end

function Relationships.decideEncounterOutcome(firstId, secondId, record)
    return decideEncounterOutcome(firstId, secondId, record)
end

function Relationships.isEncounterCooldownComplete(record, worldAge)
    return record == nil or (tonumber(record.nextEncounterHours) or 0)
        <= (tonumber(worldAge) or 0)
end

local function aggressionFor(id)
    local identity = KnoxPersistence.getSurvivorIdentity(id) or {}
    return tonumber(identity.aggression) or 35
end

local function coordinateFactionBaseScouting(controllers, orderedIds, ticks)
    if not KnoxSettings.allowNPCFactions() then
        return
    end
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

local function socialInitiator(id)
    local group = KnoxPersistence.getTravelGroupFor(id)
    return group == nil or group.leaderId == id
end

local function recordEncounterCooldown(firstId, secondId, disposition, worldAge, delay)
    KnoxPersistence.setRelationshipDisposition(
        firstId,
        secondId,
        disposition,
        (tonumber(worldAge) or 0) + (tonumber(delay) or 0)
    )
end

local function observePair(first, second, worldAge, ticks, participants)
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
    local perceived = pairDistance <= AWARENESS_RADIUS * AWARENESS_RADIUS
        and canPerceiveHuman(first.character, second.character)
    local near = perceived
    local cautiouslyClose = perceived
        and pairDistance <= CAUTIOUS_APPROACH_RADIUS * CAUTIOUS_APPROACH_RADIUS
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

    if cautiouslyClose and pendingMeetings[key] == nil
        and not participants[first.id] and not participants[second.id]
        and socialInitiator(first.id) and socialInitiator(second.id) then
        local firstGroup = KnoxPersistence.getTravelGroupFor(first.id)
        local secondGroup = KnoxPersistence.getTravelGroupFor(second.id)
        local canMeet = (firstGroup == nil and secondGroup == nil)
            or (firstGroup ~= nil and secondGroup == nil)
            or (firstGroup == nil and secondGroup ~= nil)
        local record = KnoxPersistence.getRelationship(first.id, second.id)
        local cooldownComplete = Relationships.isEncounterCooldownComplete(record, worldAge)
        if canMeet and cooldownComplete then
            local outcome = decideEncounterOutcome(first.id, second.id, record)
            if outcome == "avoid" or outcome == "avoid_hostile" then
                local disposition = outcome == "avoid_hostile" and "hostile" or "neutral"
                recordEncounterCooldown(
                    first.id,
                    second.id,
                    disposition,
                    worldAge,
                    NEUTRAL_AVOID_COOLDOWN_HOURS
                )
                participants[first.id] = true
                participants[second.id] = true
                print(TAG .. " encounter-kept-distance=" .. first.id .. "," .. second.id
                    .. " disposition=" .. disposition)
            elseif outcome ~= "none" then
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
                participants[first.id] = true
                participants[second.id] = true
                print(
                    TAG .. " noticed=" .. first.id .. "," .. second.id
                        .. " distance=" .. tostring(math.sqrt(pairDistance))
                        .. " outcome=" .. outcome
                )
            end
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
    local participants = {}
    for _, meeting in pairs(pendingMeetings) do
        participants[meeting.firstId] = true
        participants[meeting.secondId] = true
    end
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
                    observePair(first, second, worldAge, ticks or 0, participants)
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
    if getGameTime() ~= nil then
        recordEncounterCooldown(
            meeting.firstId,
            meeting.secondId,
            meeting.outcome == "hostile" and "hostile" or "neutral",
            getGameTime():getWorldAgeHours(),
            ABORT_COOLDOWN_HOURS
        )
    end
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
                local formationSlot = 1
                local nextSlot = 0
                for _, memberId in ipairs(group.memberIds or {}) do
                    if memberId ~= group.leaderId then
                        nextSlot = nextSlot + 1
                        if memberId == id then
                            formationSlot = nextSlot
                            break
                        end
                    end
                end
                controller:setGroupLeader(
                    group.leaderId,
                    leader ~= nil and leader.character or nil,
                    formationSlot,
                    #(group.memberIds or {})
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
    if KnoxSettings.allowNPCFactions()
        and ticks - lastFactionEvaluationTick >= 600 and getGameTime() ~= nil then
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
            resumeMeetingController(first, ticks)
            resumeMeetingController(second, ticks)
            pendingMeetings[key] = nil
        elseif not availableForNpcSocial(first.id)
            or not availableForNpcSocial(second.id) then
            abortMeeting(key, meeting, first, second, ticks, "player_recruited")
        elseif invalidMembership then
            abortMeeting(key, meeting, first, second, ticks, "membership_changed")
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
                KnoxActivityFeed.speak(aggressor.character, encounterLine(meeting, false))
            elseif meeting.outcome == "decline" then
                KnoxActivityFeed.speak(first.character, encounterLine(meeting, false))
            elseif meeting.outcome == "greet" then
                KnoxActivityFeed.speak(first.character, encounterLine(meeting, false))
            elseif meeting.joinGroupId ~= nil then
                local recruiter = meeting.lonerId == first.id and second or first
                KnoxActivityFeed.speak(recruiter.character, encounterLine(meeting, false))
            else
                KnoxActivityFeed.speak(first.character, encounterLine(meeting, false))
            end
            meeting.phase = "GREETING"
            meeting.greetingAt = ticks
            print(TAG .. " greeting-started=" .. first.id .. "," .. second.id)
        elseif meeting.phase == "GREETING" then
            if not meeting.responseSpoken and ticks - meeting.greetingAt >= 90 then
                if meeting.outcome == "hostile" then
                    local victim = meeting.aggressorId == first.id and second or first
                    KnoxActivityFeed.speak(victim.character, encounterLine(meeting, true))
                elseif meeting.outcome == "decline" then
                    KnoxActivityFeed.speak(second.character, encounterLine(meeting, true))
                elseif meeting.outcome == "greet" then
                    KnoxActivityFeed.speak(second.character, encounterLine(meeting, true))
                elseif meeting.joinGroupId ~= nil then
                    local loner = meeting.lonerId == first.id and first or second
                    KnoxActivityFeed.speak(loner.character, encounterLine(meeting, true))
                else
                    KnoxActivityFeed.speak(second.character, encounterLine(meeting, true))
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
                elseif meeting.outcome == "greet" then
                    recordEncounterCooldown(
                        first.id,
                        second.id,
                        "neutral",
                        worldAge,
                        GREETING_COOLDOWN_HOURS
                    )
                    first:resumeAfterGreeting(ticks)
                    second:resumeAfterGreeting(ticks)
                    pendingMeetings[key] = nil
                    print(TAG .. " encounter-outcome=greet " .. first.id .. "," .. second.id)
                    KnoxActivityFeed.event("Two survivors exchange a few cautious words.")
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
