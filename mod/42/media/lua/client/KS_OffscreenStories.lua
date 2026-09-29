local Stories = rawget(_G, "KnoxOffscreenStories") or {}
_G.KnoxOffscreenStories = Stories

-- Suspends all storylet resolution while true. The packaged regression
-- suite pins exact legacy simulation numbers, so those tests set this flag
-- (it survives module reloads, unlike fields on this table). Live play
-- leaves it unset. See tools/test-offscreen-stories.lua for covered behavior
-- with the engine enabled.
--   _G.KnoxOffscreenStoriesDisabled = true

-- Offscreen storylets: the TIS-style meta in miniature. Hibernated survivors
-- do not just march and starve; once per simulation step at most one small
-- narrative event may resolve for them. Every outcome is bounded,
-- deterministic (stable across save/load), and recorded as ledger history.
--
-- Hard rules (never relaxed):
--   * No hunger/thirst relief: only real items relieve needs.
--   * No health increases and no items, loot, or supplies of any kind.
--   * No world mutation: effects land on the survivor ledger, relationship
--     records, queued scar traces, and the activity feed only.
--   * Away-team, event-owned, and non-hibernated survivors are never touched.

local HISTORY_CAP = 12
local SCAR_CAP = 4
local MEET_RADIUS_TILES = 60
local DETOUR_MAX_TILES = 10
local CANDIDATE_SCAN_CAP = 48
local RIDE_MIN_DISTANCE_TILES = 150

local function clamp(value, low, high)
    return math.max(low, math.min(high, tonumber(value) or low))
end

local function stableHash(text)
    local result = 5381
    text = tostring(text or "")
    for index = 1, #text do
        result = (result * 33 + string.byte(text, index)) % 2147483647
    end
    return result
end

local function nowHours()
    return getGameTime ~= nil and getGameTime() ~= nil
        and tonumber(getGameTime():getWorldAgeHours()) or 0
end

local function persistence()
    return rawget(_G, "KnoxPersistence")
end

local function profileFor(id)
    local fallback = {
        personality = "guarded", sociability = 30, aggression = 24,
        courage = 42, deception = 18,
    }
    local persist = persistence()
    if persist == nil then return fallback end
    local identity = {}
    if persist.getSurvivorIdentity ~= nil then
        local ok, result = pcall(persist.getSurvivorIdentity, id)
        if ok and type(result) == "table" then identity = result end
    end
    local result = {
        personality = identity.personality or fallback.personality,
        sociability = tonumber(identity.sociability) or fallback.sociability,
        aggression = tonumber(identity.aggression) or fallback.aggression,
        courage = tonumber(identity.courage) or fallback.courage,
        deception = tonumber(identity.deception) or fallback.deception,
    }
    if persist.getSurvivorPersonality ~= nil then
        local ok, profile = pcall(persist.getSurvivorPersonality, id)
        if ok and type(profile) == "table" then
            if type(profile.personality) == "string" then
                result.personality = profile.personality
            end
        end
    end
    return result
end

local function pushHistory(state, entry)
    if type(state.history) ~= "table" then state.history = {} end
    entry.t = tonumber(entry.t) or nowHours()
    state.history[#state.history + 1] = entry
    while #state.history > HISTORY_CAP do
        table.remove(state.history, 1)
    end
end

local function pushScar(state, scar)
    if type(state.scars) ~= "table" then state.scars = {} end
    scar.t = tonumber(scar.t) or nowHours()
    state.scars[#state.scars + 1] = scar
    while #state.scars > SCAR_CAP do
        table.remove(state.scars, 1)
    end
end

local function feed(text)
    print("[KnoxSurvivors][Story] " .. tostring(text))
end

local function virtualPosition(state)
    local x = tonumber(state.virtualX)
    local y = tonumber(state.virtualY)
    local z = tonumber(state.virtualZ) or 0
    if x == nil or y == nil then return nil end
    return x, y, z
end

-- Deterministic roll in [0, 100) for this survivor, phase, and purpose.
-- Same ledger state always yields the same outcome: no save/load desync.
local function rollFor(id, phase, purpose)
    return stableHash(tostring(id) .. ":" .. tostring(phase) .. ":" .. tostring(purpose)) % 100
end

local function dutyAllows(id)
    local persist = persistence()
    if persist == nil or persist.getSurvivorDuty == nil then return true end
    local ok, duty = pcall(persist.getSurvivorDuty, id)
    if not ok or type(duty) ~= "table" then return true end
    if duty.eventId ~= nil then return false end
    if duty.mode == "away" then return false end
    return true
end

local function socialAllows(id, state)
    local persist = persistence()
    if persist == nil then return false end
    local affiliation = persist.getSurvivorAffiliation ~= nil
        and persist.getSurvivorAffiliation(id) or nil
    local duty = persist.getSurvivorDuty ~= nil and persist.getSurvivorDuty(id) or nil
    if type(affiliation) == "table" and affiliation.kind == "player" then return false end
    if type(duty) ~= "table" or duty.mode == nil then return true end
    if duty.mode == "companion" or duty.mode == "away" or duty.eventId ~= nil then return false end
    if duty.mode == "base" then
        local activity = type(state) == "table" and tostring(state.activity or "") or ""
        return type(affiliation) == "table" and affiliation.kind == "faction"
            and (activity == "base_life" or activity == "sheltering")
    end
    return true
end

local function encounterDisposition(firstId, secondId)
    local persist = persistence()
    if persist == nil or persist.getSurvivorDisposition == nil then return nil end
    local ok, disposition = pcall(persist.getSurvivorDisposition, firstId, secondId)
    if not ok then return nil end
    disposition = tostring(disposition or "")
    if disposition == "neutral" or disposition == "hostile" then return disposition end
    return nil
end

function Stories.canEncounterPair(firstId, secondId)
    if type(firstId) ~= "string" or type(secondId) ~= "string" or firstId == secondId then
        return false
    end
    return encounterDisposition(firstId, secondId) ~= nil
end

local function nearbyStored(id, x, y, z)
    local persist = persistence()
    if persist == nil or persist.getActivatableSurvivorIds == nil then return {} end
    local ok, ids = pcall(persist.getActivatableSurvivorIds)
    if not ok or type(ids) ~= "table" then return {} end
    local found = {}
    local scanned = 0
    for _, otherId in ipairs(ids) do
        if scanned >= CANDIDATE_SCAN_CAP then break end
        scanned = scanned + 1
        if otherId ~= id and type(otherId) == "string" then
            local alive = persist.isSurvivorAlive == nil
                or (pcall(persist.isSurvivorAlive, otherId) and persist.isSurvivorAlive(otherId) ~= false)
            local available = false
            local other = nil
            if alive and persist.getUnloadedSurvivalState ~= nil then
                local okState, fetched = pcall(persist.getUnloadedSurvivalState, otherId)
                if okState then other = fetched end
                if okState and type(other) == "table" and other.status == "hibernated"
                    and other.pendingMaterialization ~= true and other.restMode ~= "sleep" then
                    available = true
                    if persist.getSurvivorDuty ~= nil then
                        local okDuty, duty = pcall(persist.getSurvivorDuty, otherId)
                        if okDuty and type(duty) == "table"
                            and (duty.mode == "away" or duty.eventId ~= nil) then
                            available = false
                        end
                    end
                end
            end
            if available and socialAllows(otherId, other)
                and Stories.canEncounterPair(id, otherId) then
                local ox, oy, oz = virtualPosition(other)
                if ox ~= nil and oz == z then
                    local dx, dy = ox - x, oy - y
                    if dx * dx + dy * dy <= MEET_RADIUS_TILES * MEET_RADIUS_TILES then
                        found[#found + 1] = otherId
                    end
                end
            end
        end
    end
    table.sort(found)
    return found
end

local function detour(state, phase, purpose, hours)
    local x, y, z = virtualPosition(state)
    if x == nil then return false end
    local distance = 2 + (stableHash(tostring(phase) .. ":" .. tostring(purpose) .. ":d") % (DETOUR_MAX_TILES - 1))
    local angle = (stableHash(tostring(phase) .. ":" .. tostring(purpose) .. ":a") % 360) * math.pi / 180
    state.virtualX = x + math.cos(angle) * distance
    state.virtualY = y + math.sin(angle) * distance
    state.virtualZ = z
    state.virtualAtHours = hours
    return true
end

local function meetingHostileChance(profile, otherProfile)
    profile = type(profile) == "table" and profile or {}
    otherProfile = type(otherProfile) == "table" and otherProfile or {}
    local aggression = ((tonumber(profile.aggression) or 35)
        + (tonumber(otherProfile.aggression) or 35)) / 2
    local hostileChance = clamp(5 + (aggression - 45) * 0.30, 3, 20)
    if profile.personality == "predatory" or otherProfile.personality == "predatory"
        or profile.personality == "gunner" or otherProfile.personality == "gunner" then
        hostileChance = clamp(hostileChance + 8, 8, 30)
    end
    return hostileChance
end

function Stories.meetingHostileChance(profile, otherProfile)
    return meetingHostileChance(profile, otherProfile)
end

local function meetOutcome(id, otherId, profile, otherProfile, hours, roll)
    local persist = persistence()
    local disposition = encounterDisposition(id, otherId)
    if disposition == nil then return nil, false end
    local record = nil
    if persist ~= nil and persist.getRelationship ~= nil then
        local ok, existing = pcall(persist.getRelationship, id, otherId)
        if ok then record = existing end
    end
    local firstMeeting = record == nil or (tonumber(record.meetings) or 0) == 0
    local hostileChance = meetingHostileChance(profile, otherProfile)
    if persist ~= nil and persist.recordEncounter ~= nil then
        pcall(persist.recordEncounter, id, otherId, {
            worldAgeHours = hours,
            began = firstMeeting,
            nearbyHours = 0.1,
            sharedRoam = 1,
        })
    end
    if disposition == "hostile" then
        if persist ~= nil and persist.setRelationshipDisposition ~= nil then
            pcall(persist.setRelationshipDisposition, id, otherId, "hostile", hours + 24)
        end
        return "hostile", firstMeeting
    end
    if roll < hostileChance then
        if persist ~= nil and persist.setRelationshipDisposition ~= nil then
            pcall(persist.setRelationshipDisposition, id, otherId, "hostile", hours + 24)
        end
        return "hostile", firstMeeting
    end
    return "friendly", firstMeeting
end

--- Record a pending meet intent on both ledgers. Either side materializing
-- near the other lets the loaded encounter engine prioritize the pair.
-- Kinds: rob (hostile intent), befriend (first friendly contact), greet
-- (repeat friendly contact), tail (follow without contact; resolved later).
local function pairPhaseToken(id, otherId, phase)
    local first, second = tostring(id), tostring(otherId)
    if second < first then first, second = second, first end
    return first .. "::" .. second .. "@" .. tostring(math.floor(tonumber(phase) or 0))
end

local function partnerStateFor(otherId)
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return nil end
    local ok, state = pcall(persist.getUnloadedSurvivalState, otherId)
    if not ok or type(state) ~= "table" or state.status ~= "hibernated"
        or state.pendingMaterialization == true or state.restMode == "sleep" then
        return nil
    end
    return state
end

local function pairAlreadyProcessed(id, state, otherId, otherState, phase)
    local token = pairPhaseToken(id, otherId, phase)
    return state.lastOffscreenMeetToken == token
        or (type(otherState) == "table" and otherState.lastOffscreenMeetToken == token)
end

local function writePendingMeet(id, state, otherId, otherState, kind, hours, phase)
    if kind ~= "rob" and kind ~= "befriend" and kind ~= "greet" and kind ~= "tail" then
        return false
    end
    local persist = persistence()
    if persist == nil or persist.setUnloadedSurvivalState == nil
        or type(state) ~= "table" or type(otherState) ~= "table" then
        return false
    end
    local atHours = tonumber(hours) or nowHours()
    local token = pairPhaseToken(id, otherId, phase)
    -- Save the freshly-read partner ledger first. The caller owns `state` and
    -- persists it after the simulation step; fetching and saving another copy
    -- of it here would let that stale working copy erase this intent.
    otherState.pendingMeet = { with = id, kind = kind, atHours = atHours, pairPhase = token }
    otherState.lastOffscreenMeetToken = token
    local okSave, saved = pcall(persist.setUnloadedSurvivalState, otherId, otherState)
    if not okSave or saved == false then return false end
    state.pendingMeet = { with = otherId, kind = kind, atHours = atHours, pairPhase = token }
    state.lastOffscreenMeetToken = token
    return true
end

--- Resolve the current far destination for a potential vehicle leg: the
-- active base return first, then the travel-group objective. Returns
-- targetX, targetY, targetZ or nil. Never invents destinations.
function Stories.rideTarget(id, state)
    if type(state.baseReturn) == "table"
        and tonumber(state.baseReturn.targetX) ~= nil
        and tonumber(state.baseReturn.targetY) ~= nil then
        return tonumber(state.baseReturn.targetX), tonumber(state.baseReturn.targetY),
            tonumber(state.baseReturn.targetZ) or tonumber(state.virtualZ) or 0
    end
    local persist = persistence()
    if persist == nil or persist.getTravelGroupFor == nil
        or persist.getTravelGroupObjective == nil then
        return nil
    end
    local okGroup, group = pcall(persist.getTravelGroupFor, id)
    if not okGroup or type(group) ~= "table" or group.id == nil then return nil end
    if tostring(group.leaderId or "") ~= tostring(id) then return nil end
    local okObjective, objective = pcall(persist.getTravelGroupObjective, group.id)
    if not okObjective or type(objective) ~= "table" then return nil end
    if objective.phase ~= "seeking" and objective.phase ~= "traveling" then return nil end
    if tonumber(objective.targetX) == nil or tonumber(objective.targetY) == nil then
        return nil
    end
    return tonumber(objective.targetX), tonumber(objective.targetY),
        tonumber(objective.targetZ) or tonumber(state.virtualZ) or 0
end

--- End a vehicle trip with a history line. Used on arrival, timeout,
-- base-return start, and materialization.
function Stories.endVehicleTrip(state, hours, outcome, detail)
    if type(state) ~= "table" or type(state.vehicleTrip) ~= "table" then return false end
    state.vehicleTrip = nil
    pushHistory(state, {
        kind = "ride", detail = tostring(detail or "the ride ended"), outcome = tostring(outcome or "done"),
    })
    return true
end

local STORYLETS = {}

-- A quiet moment: catch breath, check gear, keep going. Tiny fatigue relief
-- with explicit evidence; never touches hunger, thirst, or health.
STORYLETS.restful_moment = {
    activities = { sheltering = true, base_life = true, exploring = true },
    chance = function(activity) return activity == "exploring" and 10 or 14 end,
    resolve = function(id, state, profile, hours, phase)
        local relief = 0.02 + (stableHash(tostring(id) .. ":" .. tostring(phase) .. ":rest") % 4) / 100
        state.fatigue = clamp(state.fatigue - relief, 0, 1)
        pushHistory(state, { kind = "rest", detail = "caught breath off the road", outcome = "rested" })
        return "rested"
    end,
}

-- Something moved in the dark. Costs endurance; the courageous usually walk
-- away clean, the frightened sometimes do not. Injuries are small, explicit,
-- and never fatal on their own.
STORYLETS.close_call = {
    activities = { exploring = true, seeking_supplies = true, group_travel = true, group_objective = true },
    chance = function() return 22 end,
    resolve = function(id, state, profile, hours, phase)
        state.endurance = clamp(state.endurance - 0.03, 0, 1)
        local x, y, z = virtualPosition(state)
        local escape = clamp(55 + ((tonumber(profile.courage) or 42) - 50) * 0.8, 25, 90)
        if rollFor(id, phase, "escape") < escape then
            detour(state, phase, "escape", hours)
            pushHistory(state, { kind = "close_call", detail = "heard it coming, went still", outcome = "escaped" })
            return "escaped"
        end
        local injury = 1 + (stableHash(tostring(id) .. ":" .. tostring(phase) .. ":hurt") % 3)
        state.health = clamp(state.health - injury, 1, 100)
        if x ~= nil then
            pushScar(state, { x = x, y = y, z = z, kind = "injury", detail = "bloodied escape" })
        end
        pushHistory(state, { kind = "close_call", detail = "it got a piece before letting go", outcome = "hurt" })
        feed("id=" .. tostring(id) .. " hurt offscreen evidence=close_call")
        return "hurt"
    end,
}

-- Cross paths with another stored survivor. Meetings accumulate on the
-- shared relationship record; hostility flips disposition with a scar trace.
STORYLETS.fellow_traveler = {
    activities = { exploring = true, seeking_supplies = true, group_travel = true, group_objective = true },
    chance = function() return 30 end,
    resolve = function(id, state, profile, hours, phase)
        if not socialAllows(id, state) then return nil end
        local x, y, z = virtualPosition(state)
        if x == nil then return nil end
        local candidates = nearbyStored(id, x, y, z)
        if #candidates == 0 then return nil end
        local otherId = candidates[(stableHash(tostring(id) .. ":" .. tostring(phase) .. ":meet") % #candidates) + 1]
        local otherState = partnerStateFor(otherId)
        if otherState == nil or pairAlreadyProcessed(id, state, otherId, otherState, phase) then
            return nil
        end
        local otherProfile = profileFor(otherId)
        local outcome, first = meetOutcome(id, otherId, profile, otherProfile, hours,
            rollFor(id, phase, "meet:" .. tostring(otherId)))
        if outcome == nil then return nil end
        -- A pending meet lets the loaded encounter engine prioritize this
        -- pair when both materialize near each other (see
        -- KnoxSurvivorRelationships.pendingMeetOutcome). Robbery and ambush
        -- transfers still only happen loaded, never here.
        local kind = outcome == "hostile" and "rob" or (first and "befriend" or "greet")
        if not writePendingMeet(id, state, otherId, otherState, kind, hours, phase) then
            return nil
        end
        if outcome == "hostile" then
            detour(state, phase, "meet:away", hours)
            pushScar(state, { x = x, y = y, z = z, kind = "fight", with = otherId, detail = "turned hostile" })
            pushHistory(state, { kind = "meet", with = otherId, detail = "crossed paths, drew weapons", outcome = "hostile" })
            feed("id=" .. tostring(id) .. " met " .. tostring(otherId) .. " outcome=hostile")
            return "met_hostile"
        end
        detour(state, phase, "meet:on", hours)
        pushHistory(state, { kind = "meet", with = otherId, detail = "crossed paths, exchanged word", outcome = "friendly" })
        if first then
            feed("id=" .. tostring(id) .. " met " .. tostring(otherId) .. " outcome=friendly_first")
        end
        return "met_friendly"
    end,
}

-- Familiar ground steadies the nerves. Narrative flag only, plus a breath.
-- Places with scar traces pull twice as often: the ledger remembers.
STORYLETS.old_haunt = {
    activities = { exploring = true, sheltering = true },
    chance = function() return 8 end,
    resolve = function(id, state, profile, hours)
        state.fatigue = clamp(state.fatigue - 0.02, 0, 1)
        pushHistory(state, { kind = "haunt", detail = "walked ground that felt known", outcome = "steadied" })
        return "steadied"
    end,
    boostNearScars = true,
}

-- Bad weather off the road. Small endurance tax, explicit evidence.
STORYLETS.foul_weather = {
    activities = { exploring = true, seeking_supplies = true, group_travel = true, group_objective = true },
    chance = function() return 12 end,
    resolve = function(id, state, profile, hours)
        state.endurance = clamp(state.endurance - 0.04, 0, 1)
        pushHistory(state, { kind = "weather", detail = "pushed through bad weather", outcome = "weathered" })
        return "weathered"
    end,
}

-- A remembered cache that may matter later. Narrative flag only: no items,
-- no relief, no fabrication. Future systems may resolve it against the real
-- world; until then it weights recounts and later storylets.
STORYLETS.stash_memory = {
    activities = { exploring = true, seeking_supplies = true },
    chance = function() return 7 end,
    resolve = function(id, state, profile, hours)
        local x, y, z = virtualPosition(state)
        if x == nil then return nil end
        state.cacheMemory = { x = x, y = y, z = z, atHours = hours }
        pushHistory(state, { kind = "cache", detail = "marked a possible stash in memory", outcome = "remembered" })
        return "remembered"
    end,
}

-- Caught a ride: a virtual vehicle leg toward the current far destination.
-- TIS radar-blip style: no vehicle entity is claimed, no teleport happens;
-- the ledger simply advances at vehicle pace while the trip is active. The
-- trip dissolves the moment the survivor loads (real boarding is owned by
-- the loaded vehicle systems), on arrival, or after 24 hours.
STORYLETS.catch_ride = {
    activities = { group_travel = true, group_objective = true },
    chance = function() return 10 end,
    resolve = function(id, state, profile, hours)
        local x, y, z = virtualPosition(state)
        if x == nil then return nil end
        local tx, ty, tz = Stories.rideTarget(id, state)
        if tx == nil then return nil end
        local dx, dy = tx - x, ty - y
        if dx * dx + dy * dy < RIDE_MIN_DISTANCE_TILES * RIDE_MIN_DISTANCE_TILES then
            return nil
        end
        state.vehicleTrip = { targetX = tx, targetY = ty, targetZ = tz, atHours = hours }
        pushHistory(state, { kind = "ride", detail = "caught a ride toward the far goal", outcome = "riding" })
        feed("id=" .. tostring(id) .. " caught a ride")
        return "riding"
    end,
}

local STORYLET_ORDER = {
    "fellow_traveler", "close_call", "catch_ride", "foul_weather", "restful_moment",
    "old_haunt", "stash_memory",
}

local function activityChance(activity)
    if activity == "exploring" or activity == "group_travel" or activity == "group_objective" then
        return 38
    end
    if activity == "seeking_supplies" then return 36 end
    if activity == "sheltering" then return 14 end
    if activity == "base_life" then return 12 end
    return 10
end

local SCAR_RETURN_RADIUS_TILES = 30
local SCAR_MEMORY_RADIUS_TILES = 15

local function scarNear(state, radius)
    if type(state.scars) ~= "table" or #state.scars == 0 then return false end
    local x, y, z = virtualPosition(state)
    if x == nil then return false end
    for _, scar in ipairs(state.scars) do
        if type(scar) == "table" and tonumber(scar.x) ~= nil and tonumber(scar.z or z) == z then
            local dx, dy = tonumber(scar.x) - x, tonumber(scar.y) - y
            if dx * dx + dy * dy <= radius * radius then return true end
        end
    end
    return false
end

--- Resolve at most one storylet for a hibernated survivor's simulation step.
-- @param id string survivor id
-- @param state table mutable survival ledger (history/scars appended in place)
-- @param hours number current world age hours
-- @param elapsed number hours covered by this step
-- @return string|nil outcome code, or nil when nothing happened
function Stories.resolveFor(id, state, hours, elapsed)
    if rawget(_G, "KnoxOffscreenStoriesDisabled") == true then return nil end
    if type(id) ~= "string" or type(state) ~= "table" then return nil end
    if state.status ~= "hibernated" or state.pendingMaterialization == true then return nil end
    if (tonumber(state.health) or 0) <= 0 then return nil end
    if state.restMode == "sleep" then return nil end
    if not dutyAllows(id) then return nil end
    hours = tonumber(hours) or nowHours()
    elapsed = math.max(0, tonumber(elapsed) or 0)
    if elapsed <= 0 then return nil end
    local activity = tostring(state.activity or "sheltering")
    local phase = math.floor(hours / 6)
    -- Persist the attempt, not only a successful outcome. Repeated scheduler
    -- calls and save/reload in the same window must never reroll a storylet.
    if tonumber(state.lastStoryAttemptPhase) == phase then return nil end
    state.lastStoryAttemptPhase = phase
    if rollFor(id, phase, "any:" .. activity) >= activityChance(activity) then
        return nil
    end
    local profile = profileFor(id)
    local cursor = rollFor(id, phase, "pick")
    for _, key in ipairs(STORYLET_ORDER) do
        local storylet = STORYLETS[key]
        local allowed = storylet.activities[activity] == true
        if allowed then
            local chance = storylet.chance(activity)
            if storylet.boostNearScars == true and scarNear(state, SCAR_MEMORY_RADIUS_TILES) then
                chance = chance * 2
            end
            if cursor < chance then
                local ok, outcome = pcall(storylet.resolve, id, state, profile, hours, phase)
                if ok and outcome ~= nil then
                    return tostring(outcome)
                end
                return nil
            end
            cursor = cursor - chance
        end
    end
    return nil
end

function Stories.historyFor(id)
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return {} end
    local ok, state = pcall(persist.getUnloadedSurvivalState, id)
    if not ok or type(state) ~= "table" or type(state.history) ~= "table" then return {} end
    local copy = {}
    for index, entry in ipairs(state.history) do
        copy[index] = entry
    end
    return copy
end

--- Append a finalized loaded encounter to the existing survivor history.
-- The loaded relationship coordinator owns when an encounter is real; this
-- owner only stores the bounded fact. Missing ledgers are not synthesized.
function Stories.recordLoadedEncounter(id, otherId, outcome, hours)
    if type(id) ~= "string" or id == "" or type(otherId) ~= "string"
        or otherId == "" or id == otherId then
        return false, "invalid_identity"
    end
    local allowed = {
        friendly = true,
        joined = true,
        declined = true,
        parted = true,
        hostile = true,
    }
    if allowed[outcome] ~= true then return false, "invalid_outcome" end
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil
        or persist.setUnloadedSurvivalState == nil then
        return false, "history_unavailable"
    end
    local okRead, state = pcall(persist.getUnloadedSurvivalState, id)
    if not okRead or type(state) ~= "table" then
        return false, "canonical_history_missing"
    end
    local atHours = tonumber(hours) or nowHours()
    if type(state.history) == "table" then
        for _, entry in ipairs(state.history) do
            if type(entry) == "table" and entry.kind == "meet"
                and entry.with == otherId and entry.outcome == outcome
                and tonumber(entry.t) == atHours then
                return true, "already_recorded"
            end
        end
    end
    pushHistory(state, {
        kind = "meet",
        with = otherId,
        outcome = outcome,
        detail = "a loaded survivor encounter",
        t = atHours,
    })
    local okWrite, saved = pcall(persist.setUnloadedSurvivalState, id, state)
    if not okWrite or saved ~= true then return false, "history_write_failed" end
    return true, "recorded"
end

local function boundedText(value, maximum)
    if value == nil then return nil end
    local valueText = tostring(value):gsub("[%c]", " "):match("^%s*(.-)%s*$")
    if valueText == "" then return nil end
    maximum = math.max(1, tonumber(maximum) or 120)
    return #valueText > maximum and valueText:sub(1, maximum) or valueText
end

local function normalizeHistoryEntry(entry)
    if type(entry) ~= "table" then return nil end
    local kind = boundedText(entry.kind, 32)
    if kind == nil then return nil end
    return {
        kind = kind,
        outcome = boundedText(entry.outcome, 48),
        detail = boundedText(entry.detail, 160),
        with = boundedText(entry.with, 96),
        atHours = tonumber(entry.t),
    }
end

--- Read-only, newest-first survivor memory for UI and integrations. The
-- count and strings are bounded so malformed legacy data cannot grow a card
-- or expose arbitrary nested persistence state.
function Stories.recentHistoryFor(id, limit)
    local history = Stories.historyFor(id)
    local maximum = math.max(0, math.min(5, math.floor(tonumber(limit) or 3)))
    if maximum == 0 then return {} end
    local recent = {}
    for index = #history, 1, -1 do
        local entry = normalizeHistoryEntry(history[index])
        if entry ~= nil then recent[#recent + 1] = entry end
        if #recent >= maximum then break end
    end
    return recent
end

function Stories.scarsFor(id)
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return {} end
    local ok, state = pcall(persist.getUnloadedSurvivalState, id)
    if not ok or type(state) ~= "table" or type(state.scars) ~= "table" then return {} end
    local copy = {}
    for index, entry in ipairs(state.scars) do
        copy[index] = entry
    end
    return copy
end

--- Remove consumed scar traces after world resolution. Never fabricates.
function Stories.clearScars(id, keepNewerThanHours)
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return false end
    local ok, state = pcall(persist.getUnloadedSurvivalState, id)
    if not ok or type(state) ~= "table" or type(state.scars) ~= "table" then return false end
    local cutoff = tonumber(keepNewerThanHours) or 0
    local kept = {}
    for _, scar in ipairs(state.scars) do
        if tonumber(scar.t) ~= nil and tonumber(scar.t) > cutoff then
            kept[#kept + 1] = scar
        end
    end
    state.scars = kept
    if persist.setUnloadedSurvivalState ~= nil then
        pcall(persist.setUnloadedSurvivalState, id, state)
    end
    return true
end

--- Resolve queued scar traces against a materialized body. Places remember:
-- returning near a scar site appends history, announces fight sites on the
-- feed, and consumes the trace. Geometry (corpses, barricades, blood) is
-- deliberately NOT fabricated: only the engine or loaded survivors carrying
-- real items may change the world. Returns the count resolved.
function Stories.resolveScars(id, character, hours)
    if type(id) ~= "string" or character == nil then return 0 end
    local persist = persistence()
    if persist == nil or persist.getUnloadedSurvivalState == nil then return 0 end
    local ok, state = pcall(persist.getUnloadedSurvivalState, id)
    if not ok or type(state) ~= "table" or type(state.scars) ~= "table"
        or #state.scars == 0 then
        return 0
    end
    local okSquare, square = pcall(function() return character:getCurrentSquare() end)
    if not okSquare or square == nil or square.getX == nil then return 0 end
    local cx, cy, cz = tonumber(square:getX()), tonumber(square:getY()), tonumber(square:getZ()) or 0
    if cx == nil or cy == nil then return 0 end
    hours = tonumber(hours) or nowHours()
    local resolved, kept = 0, {}
    for _, scar in ipairs(state.scars) do
        local consumed = false
        if type(scar) == "table" and tonumber(scar.x) ~= nil
            and tonumber(scar.z or cz) == cz then
            local dx, dy = tonumber(scar.x) - cx, tonumber(scar.y) - cy
            if dx * dx + dy * dy <= SCAR_RETURN_RADIUS_TILES * SCAR_RETURN_RADIUS_TILES then
                consumed = true
                resolved = resolved + 1
                if scar.kind == "fight" then
                    pushHistory(state, {
                        kind = "scar", detail = "came back to where weapons were drawn",
                        with = scar.with, outcome = "returned",
                    })
                    feed("id=" .. tostring(id) .. " returned to a fight site")
                else
                    pushHistory(state, {
                        kind = "scar", detail = "came back to where blood was left",
                        outcome = "returned",
                    })
                end
            end
        end
        if not consumed then kept[#kept + 1] = scar end
    end
    state.scars = kept
    if persist.setUnloadedSurvivalState ~= nil then
        pcall(persist.setUnloadedSurvivalState, id, state)
    end
    return resolved
end

return Stories
