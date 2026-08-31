require "KS_Persistence"

local KnoxEvents = rawget(_G, "KnoxEvents") or {}
_G.KnoxEvents = KnoxEvents

-- Durable event bookkeeping only. The runtime dispatcher will own travel and
-- objectives through existing NPC controllers; this service never spawns gear,
-- allocates survivors, simulates raid victories, or overwrites a survivor duty.
local NEXT = {
    scheduled = { spawning = true, failed = true },
    spawning = { approaching = true, withdrawing = true, failed = true },
    approaching = { active = true, withdrawing = true, failed = true },
    active = { objective = true, withdrawing = true, failed = true },
    objective = { withdrawing = true, failed = true },
    withdrawing = { completed = true, failed = true },
    completed = {}, failed = {},
}
local RAID_COOLDOWN_HOURS = 24
local RETAIN_HOURS = 168
local HISTORY_LIMIT = 128
local MAX_SERIAL = 9007199254740990 -- leave room for an exact integer increment

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function serial(value)
    return finite(value) and value >= 1 and value <= MAX_SERIAL and value % 1 == 0
end

local function memberList(value)
    if type(value) ~= "table" or #value == 0 then return false end
    local count, seen = 0, {}
    for index, id in pairs(value) do
        if not serial(index) or index > #value or type(id) ~= "string" or id == "" or seen[id] then
            return false
        end
        count, seen[id] = count + 1, true
    end
    return count == #value
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

local function terminal(event)
    return event.phase == "completed" or event.phase == "failed"
end

local function records()
    return KnoxPersistence.getKnoxEventState().records
end

local function retainCooldown(event)
    if type(event.sourceFactionId) ~= "string" or not finite(event.lastChangedAtHours) then return end
    local cooldowns = KnoxPersistence.getKnoxEventState().cooldowns
    local untilHours = event.lastChangedAtHours + RAID_COOLDOWN_HOURS
    cooldowns[event.sourceFactionId] = math.max(untilHours,
        finite(cooldowns[event.sourceFactionId]) and cooldowns[event.sourceFactionId] or 0)
end

local function targetFaction(base)
    if base == nil then return nil end
    if base.ownerKind == "faction" then return KnoxPersistence.getFaction(base.ownerId) end
    if base.ownerKind == "player" then return KnoxPersistence.getPlayerFaction(base.ownerId) end
end

local function locationKey(base)
    local home = base ~= nil and base.home or nil
    if type(home) ~= "table" then return nil end
    for _, key in ipairs({ "minX", "minY", "width", "height" }) do
        if not finite(home[key]) then return nil end
    end
    if home.width <= 0 or home.height <= 0 or not finite(home.z or 0)
        or not finite(base.relocatedAtHours or 0) then return nil end
    return table.concat({ home.minX, home.minY, home.width, home.height,
        home.z or 0, base.relocatedAtHours or 0 }, ":")
end

local function raidOwners(factionId, baseId)
    local faction = KnoxPersistence.getFaction(factionId)
    local target = KnoxPersistence.getBase(baseId)
    local other = targetFaction(target)
    if faction == nil or faction.kind == "player" or other == nil or faction.id == other.id then
        return nil, "invalid_raid_owners"
    end
    local relation = KnoxPersistence.getFactionRelationship(faction.id, other.id)
    if relation == nil or relation.disposition ~= "hostile" then return nil, "not_hostile" end
    local home = KnoxPersistence.getBaseForOwner("faction", faction.id)
    if locationKey(home) == nil or locationKey(target) == nil then return nil, "missing_base" end
    return { faction = faction, home = home, target = target, targetFactionId = other.id }
end

local function livingRoster(faction)
    local result, seen = {}, {}
    for _, id in ipairs(faction.memberIds or {}) do
        if type(id) == "string" and not seen[id] and KnoxPersistence.isSurvivorAlive(id) then
            local affiliation = KnoxPersistence.getSurvivorAffiliation(id)
            if affiliation ~= nil and affiliation.kind == "faction" and affiliation.factionId == faction.id then
                result[#result + 1], seen[id] = id, true
            end
        end
    end
    table.sort(result)
    return result
end

local function availableMember(id, home)
    local duty = KnoxPersistence.getSurvivorDuty(id)
    if duty == nil or duty.mode ~= "base" or duty.baseId ~= home.id
        or KnoxPersistence.getAwayTeamForSurvivor(id) ~= nil then return false end
    -- Do not silently steal a worker's in-progress task at the proposal boundary.
    for _, task in pairs(home.tasks or {}) do
        if type(task) == "table" and task.state == "claimed" and task.claimedBy == id then return false end
    end
    local snapshot = KnoxPersistence.getRecord(id)
    return type(snapshot) == "string" and snapshot ~= ""
end

function KnoxEvents.get(id)
    local event = type(id) == "string" and records()[id] or nil
    return type(event) == "table" and copy(event) or nil
end

function KnoxEvents.memberEvent(id)
    for _, event in pairs(records()) do
        if type(event) == "table" and not terminal(event) then
            for _, member in pairs(type(event.memberIds) == "table" and event.memberIds or {}) do
                if member == id then return copy(event) end
            end
        end
    end
    return nil
end

-- Planning does not change duties or inventories. Eligibility must be checked
-- again by dispatch when live loadout/health and actual entrance space are known.
function KnoxEvents.proposeRaid(factionId, baseId, hours)
    if not finite(hours) or hours < 0 then return nil, "invalid_time" end
    local owners, reason = raidOwners(factionId, baseId)
    if owners == nil then return nil, reason end
    local cooldown = KnoxPersistence.getKnoxEventState().cooldowns[factionId]
    if finite(cooldown) and hours < cooldown then return nil, "faction_event_cooldown" end
    for _, event in pairs(records()) do
        if type(event) == "table" and event.sourceFactionId == factionId then
            if not terminal(event) then return nil, "faction_event_active" end
            if finite(event.lastChangedAtHours) and hours < event.lastChangedAtHours + RAID_COOLDOWN_HOURS then
                return nil, "faction_event_cooldown"
            end
        end
    end
    local living, available = livingRoster(owners.faction), {}
    for _, id in ipairs(living) do
        if availableMember(id, owners.home) and KnoxEvents.memberEvent(id) == nil then
            available[#available + 1] = id
        end
    end
    -- Five established residents may send two, never all five. Two available
    -- residents stay home even if most of the faction is already away working.
    local count = math.min(math.floor(#living * 0.4), #available - 2)
    if count < 1 then return nil, "insufficient_home_strength" end
    local members = {}
    for index = 1, count do members[index] = available[index] end
    return { kind = "faction_raid", sourceFactionId = factionId, targetBaseId = baseId,
        sourceBaseId = owners.home.id, targetFactionId = owners.targetFactionId,
        sourceLocation = locationKey(owners.home), targetLocation = locationKey(owners.target),
        memberIds = members, livingAtProposal = #living, defendersAtProposal = #available - count }
end

function KnoxEvents.scheduleRaid(factionId, baseId, hours, delayHours)
    delayHours = delayHours == nil and 1 or delayHours
    if not finite(delayHours) or delayHours < 0 or delayHours > 168 then return nil, "invalid_delay" end
    local proposal, reason = KnoxEvents.proposeRaid(factionId, baseId, hours)
    if proposal == nil then return nil, reason end
    local state = KnoxPersistence.getKnoxEventState()
    local number = serial(state.nextId) and state.nextId or 1
    while state.records["knox-event-" .. string.format("%.0f", number)] ~= nil do
        number = number < MAX_SERIAL and number + 1 or 1
    end
    state.nextId = number < MAX_SERIAL and number + 1 or 1
    proposal.id = "knox-event-" .. string.format("%.0f", number)
    proposal.phase, proposal.revision = "scheduled", 1
    proposal.createdAtHours, proposal.lastChangedAtHours = hours, hours
    proposal.dueAtHours, proposal.deadlineHours = hours + delayHours, hours + delayHours + 24
    proposal.reason = "awaiting_dispatch"
    state.records[proposal.id] = proposal
    return copy(proposal), "scheduled"
end

function KnoxEvents.validate(event)
    if type(event) ~= "table" or event.kind ~= "faction_raid" or NEXT[event.phase] == nil
        or not memberList(event.memberIds) or not serial(event.revision)
        or not finite(event.dueAtHours) or not finite(event.lastChangedAtHours)
        or not finite(event.deadlineHours) or event.deadlineHours < event.dueAtHours then
        return false, "invalid_event_record"
    end
    local owners, reason = raidOwners(event.sourceFactionId, event.targetBaseId)
    if owners == nil then return false, reason end
    if owners.targetFactionId ~= event.targetFactionId or owners.home.id ~= event.sourceBaseId
        or locationKey(owners.home) ~= event.sourceLocation
        or locationKey(owners.target) ~= event.targetLocation then return false, "base_changed" end
    local roster, members, living = {}, {}, livingRoster(owners.faction)
    for _, id in ipairs(living) do roster[id] = true end
    local available = 0
    for id in pairs(roster) do if availableMember(id, owners.home) then available = available + 1 end end
    for _, id in ipairs(event.memberIds) do
        if members[id] or not roster[id] then return false, "member_lost" end
        members[id] = true
        if event.phase == "scheduled" and not availableMember(id, owners.home) then
            return false, "member_unavailable"
        end
    end
    if event.phase == "scheduled" and (available - #event.memberIds < 2
        or #event.memberIds > math.floor(#living * 0.4)) then
        return false, "insufficient_home_strength"
    end
    return true, "valid"
end

-- Compare-and-set transitions prevent a late callback from overwriting a newer
-- phase. The dispatcher (not a timer) must report arrival/objective/return results.
function KnoxEvents.transition(id, revision, phase, hours, reason)
    local event = records()[id]
    if type(event) ~= "table" or event.id ~= id or NEXT[event.phase] == nil then return nil, "unknown_event" end
    if not serial(event.revision) then return nil, "invalid_event_record" end
    if not finite(hours) or not finite(event.lastChangedAtHours)
        or hours < event.lastChangedAtHours then return nil, "invalid_time" end
    if event.phase == phase then return copy(event), "unchanged" end
    if event.revision ~= revision then return nil, "stale_revision" end
    if not NEXT[event.phase][phase] then return nil, "invalid_transition" end
    if phase ~= "failed" and phase ~= "withdrawing" and phase ~= "completed" then
        local valid, why = KnoxEvents.validate(event)
        if not valid then return nil, why end
    end
    if event.phase == "scheduled" and phase == "spawning" and hours < event.dueAtHours then
        return nil, "not_due"
    end
    event.phase, event.revision = phase, event.revision + 1
    event.lastChangedAtHours = hours
    event.reason = type(reason) == "string" and string.sub(reason, 1, 120) or phase
    if terminal(event) then retainCooldown(event) end
    return copy(event), "changed"
end

function KnoxEvents.maintain(hours, budget)
    if not finite(hours) or hours < 0 then return 0 end
    local state = KnoxPersistence.getKnoxEventState()
    local ids, history = {}, {}
    for id, event in pairs(state.records) do
        if type(id) == "string" then
            ids[#ids + 1] = id
            if type(event) == "table" and terminal(event) then
                history[#history + 1] = id
                retainCooldown(event)
            end
        else
            state.records[id] = nil
        end
    end
    table.sort(ids)
    table.sort(history, function(a, b)
        local first, second = state.records[a].lastChangedAtHours, state.records[b].lastChangedAtHours
        first, second = finite(first) and first or 0, finite(second) and second or 0
        return first == second and a < b or first < second
    end)
    budget = finite(budget) and math.max(1, math.min(32, math.floor(budget))) or 16
    local cursor, processed = finite(state.cursor) and math.max(0, math.floor(state.cursor)) or 0, 0
    for step = 1, math.min(budget, #ids) do
        cursor = cursor % #ids + 1
        local id = ids[cursor]
        local event = state.records[id]
        if type(event) ~= "table" or event.id ~= id or NEXT[event.phase] == nil
            or not serial(event.revision) or not finite(event.lastChangedAtHours)
            or (not terminal(event) and not finite(event.deadlineHours)) then
            -- Corrupt deployed bookkeeping must not erase a possibly live party.
            -- Retain its roster/owners for the dispatcher's actual return cleanup.
            local recovered = type(event) == "table" and event or {}
            local deployed = not terminal(recovered) and recovered.phase ~= "scheduled"
                and type(recovered.memberIds) == "table" and next(recovered.memberIds) ~= nil
            recovered.id, recovered.phase = id, deployed and "withdrawing" or "failed"
            recovered.revision, recovered.lastChangedAtHours = 1, hours
            recovered.deadlineHours, recovered.reason = hours, "invalid_event_record"
            state.records[id] = recovered
            if terminal(recovered) then retainCooldown(recovered) end
        elseif not terminal(event) then
            local valid, reason = KnoxEvents.validate(event)
            if not valid or hours >= event.deadlineHours then
                local phase = event.phase == "scheduled" and "failed" or "withdrawing"
                if event.phase ~= "withdrawing" then
                    KnoxEvents.transition(id, event.revision, phase, hours,
                        valid and "event_deadline" or reason)
                end
            end
        elseif hours - (event.lastChangedAtHours or hours) >= RETAIN_HOURS then
            state.records[id] = nil
        end
        processed = processed + 1
    end
    state.cursor = cursor
    -- Prune only finished history. Never discard an active withdrawal to hide a
    -- stalled dispatcher or recreate its members as a fresh event.
    for index = 1, math.min(budget, math.max(0, #history - HISTORY_LIMIT)) do
        state.records[history[index]] = nil
    end
    local expired = 0
    for factionId, untilHours in pairs(state.cooldowns) do
        if not finite(untilHours) or hours >= untilHours or KnoxPersistence.getFaction(factionId) == nil then
            state.cooldowns[factionId] = nil
            expired = expired + 1
            if expired >= budget then break end
        end
    end
    return processed
end

return KnoxEvents
