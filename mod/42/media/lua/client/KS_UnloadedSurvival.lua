local Simulation = rawget(_G, "KnoxUnloadedSurvival") or {}
_G.KnoxUnloadedSurvival = Simulation

-- Hibernated survivors are not hidden active characters.  This module advances a
-- small persisted survival ledger between body capture and reconstruction.  It
-- never creates supplies: food and water are removed from the encoded portable
-- inventory before the relief is recorded.
local MAX_STEP_HOURS = 6
local FOOD_TRIGGER = 0.60
local WATER_TRIGGER = 0.60
local FOOD_AFTER_MEAL = 0.22
local WATER_AFTER_DRINK = 0.22
local HUNGER_PER_HOUR = 0.026
local THIRST_PER_HOUR = 0.040
local FATIGUE_RECOVERY_PER_HOUR = 0.055
local ENDURANCE_RECOVERY_PER_HOUR = 0.090
local STARVATION_DAMAGE_PER_HOUR = 1.20
local DEHYDRATION_DAMAGE_PER_HOUR = 2.00
local TRAVEL_TILES_PER_HOUR = 1.25

local function clamp(value, low, high)
    return math.max(low, math.min(high, tonumber(value) or low))
end

local function nowHours()
    return getGameTime ~= nil and getGameTime() ~= nil
        and tonumber(getGameTime():getWorldAgeHours()) or 0
end

local function summaryCounts(summary)
    local counts = {}
    for typeName, amount in string.gmatch(tostring(summary or ""), "([^;=]+)=([0-9]+)") do
        counts[typeName] = math.max(0, math.floor(tonumber(amount) or 0))
    end
    return counts
end

local function classify(typeName)
    if InventoryItemFactory == nil or InventoryItemFactory.CreateItem == nil then
        return nil
    end
    local ok, item = pcall(InventoryItemFactory.CreateItem, typeName)
    if not ok or item == nil then
        return nil
    end
    local food = false
    local water = false
    pcall(function()
        food = item:IsFood() and item:getHungerChange() < 0
    end)
    pcall(function()
        local fluid = item:getFluidContainer()
        water = fluid ~= nil and fluid:getAmount() > 0
    end)
    return { food = food, water = water }
end

local function chooseSupply(summary, wanted)
    for typeName, amount in pairs(summaryCounts(summary)) do
        if amount > 0 then
            local item = classify(typeName)
            if item ~= nil and item[wanted] then
                return typeName
            end
        end
    end
    return nil
end

local function consumeStoredItem(id, typeName)
    local persistence = rawget(_G, "KnoxPersistence")
    local bridge = rawget(_G, "KnoxJavaBridge")
    if persistence == nil or bridge == nil or bridge.consumeNpcRecordItem == nil then
        return false, "record_mutator_unavailable"
    end
    local record = persistence.getRecord(id)
    if record == nil then
        return false, "record_unavailable"
    end
    local ok, updated = pcall(bridge.consumeNpcRecordItem, bridge, record, typeName)
    if not ok or type(updated) ~= "string" or updated == "" then
        return false, "item_not_present"
    end
    if not persistence.setRecord(id, updated) then
        return false, "record_save_failed"
    end
    local summaryOk, summary = pcall(bridge.getNpcRecordInventorySummary, bridge, updated)
    if summaryOk and type(summary) == "string" then
        persistence.setInventorySummary(id, summary, nowHours())
    end
    return true, typeName
end

local function ensureState(id, snapshot, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    local existing = persistence ~= nil and persistence.getUnloadedSurvivalState(id) or nil
    if existing ~= nil then
        return existing
    end
    return {
        hunger = clamp(snapshot and snapshot.hunger, 0, 1),
        thirst = clamp(snapshot and snapshot.thirst, 0, 1),
        fatigue = clamp(snapshot and snapshot.fatigue, 0, 1),
        endurance = clamp(snapshot and snapshot.endurance, 0, 1),
        health = clamp(snapshot and snapshot.health, 0, 100),
        bleedingParts = math.max(0, math.floor(tonumber(snapshot and snapshot.bleedingParts) or 0)),
        lastHours = hours,
        status = "stored",
        activity = "stored",
        activitySinceHours = hours,
    }
end

local function stableHash(value)
    local result = 5381
    for index = 1, #tostring(value or "") do
        result = (result * 33 + string.byte(tostring(value), index)) % 2147483647
    end
    return result
end

local function recordLocation(id)
    local persistence = rawget(_G, "KnoxPersistence")
    local bridge = rawget(_G, "KnoxJavaBridge")
    local record = persistence ~= nil and persistence.getRecord(id) or nil
    if bridge == nil or record == nil then return nil end
    local ok, x, y, z = pcall(function()
        return bridge:getTestNpcRecordX(record), bridge:getTestNpcRecordY(record),
            bridge:getTestNpcRecordZ(record)
    end)
    if not ok then return nil end
    return tonumber(x), tonumber(y), tonumber(z)
end

local function setActivity(state, activity, hours)
    if state.activity ~= activity then
        state.activity = activity
        state.activitySinceHours = hours
    end
end

local function advanceWorldActivity(id, state, elapsed, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then return end
    local duty = persistence.getSurvivorDuty ~= nil
        and persistence.getSurvivorDuty(id) or {}
    if duty.mode == "away" then
        -- Away-team simulation owns travel, risk, ETA, and mission results.
        -- Keep the last known destination in the durable ledger so a member
        -- can materialize there after the team resolves instead of snapping
        -- back to the stale departure square.
        local team = persistence.getAwayTeamForSurvivor ~= nil
            and persistence.getAwayTeamForSurvivor(id) or nil
        local destination = team ~= nil and team.destination or nil
        if destination ~= nil and tonumber(destination.x) ~= nil
            and tonumber(destination.y) ~= nil then
            state.virtualX = math.floor(tonumber(destination.x))
            state.virtualY = math.floor(tonumber(destination.y))
            state.virtualZ = math.floor(tonumber(destination.z) or 0)
            state.virtualAtHours = hours
        end
        setActivity(state, "away_mission", hours)
        return
    end
    local x, y, z = tonumber(state.virtualX), tonumber(state.virtualY), tonumber(state.virtualZ)
    if x == nil or y == nil or z == nil then
        x, y, z = recordLocation(id)
    end
    if x == nil then return end
    local returning = type(state.baseReturn) == "table" and state.baseReturn or nil
    if returning ~= nil and tonumber(returning.targetX) ~= nil
        and tonumber(returning.targetY) ~= nil then
        local targetX = tonumber(returning.targetX)
        local targetY = tonumber(returning.targetY)
        local targetZ = tonumber(returning.targetZ) or z
        local dx, dy = targetX - x, targetY - y
        local distance = math.sqrt(dx * dx + dy * dy)
        local travel = math.max(0, elapsed) * TRAVEL_TILES_PER_HOUR
        if distance <= math.max(0.01, travel) then
            x, y, z = targetX, targetY, targetZ
            state.baseReturn = nil
            setActivity(state, "base_life", hours)
        else
            x = x + dx / distance * travel
            y = y + dy / distance * travel
            z = targetZ
            setActivity(state, "returning_to_base", hours)
        end
        state.virtualX, state.virtualY, state.virtualZ = x, y, z
        state.virtualAtHours = hours
        return
    end
    if duty.mode == "base" and duty.baseId ~= nil then
        local base = persistence.getBase ~= nil and persistence.getBase(duty.baseId) or nil
        local area = base ~= nil and (base.territory or base.home) or nil
        if area ~= nil then
            -- A stored resident should not return to the exact old tile every
            -- time, or make a whole settlement reappear in one stack.  This is
            -- low-cost ambient base life rather than simulated pathfinding: each
            -- six-hour phase gives each identity one deterministic place inside
            -- its own saved territory.  Materialization still validates the
            -- real square before committing it to the persistent Java record.
            local minX = math.floor(tonumber(area.minX) or x)
            local minY = math.floor(tonumber(area.minY) or y)
            local width = math.max(1, math.floor(tonumber(area.width) or 1))
            local height = math.max(1, math.floor(tonumber(area.height) or 1))
            local phase = math.floor(hours / MAX_STEP_HOURS)
            local seed = stableHash(tostring(id) .. ":base:" .. tostring(phase))
            x = minX + (seed % width)
            y = minY + (math.floor(seed / width) % height)
            z = tonumber(area.z) or z
        end
        setActivity(state, "base_life", hours)
    elseif duty.mode == "companion" then
        -- Companions normally remain loaded. If streaming briefly stores one,
        -- preserve their exact last location for reliable reunion.
        setActivity(state, "waiting_for_leader", hours)
    else
        local group = persistence.getTravelGroupFor ~= nil
            and persistence.getTravelGroupFor(id) or nil
        local affiliation = persistence.getSurvivorAffiliation ~= nil
            and persistence.getSurvivorAffiliation(id) or {}
        local travelKey = group ~= nil and group.id
            or affiliation.factionId or id
        local phase = math.floor((tonumber(state.lastHours) or hours) / MAX_STEP_HOURS)
        local angle = (stableHash(tostring(travelKey) .. ":" .. tostring(phase)) % 628) / 100
        local distance = math.max(0, elapsed) * TRAVEL_TILES_PER_HOUR
        x = x + math.cos(angle) * distance
        y = y + math.sin(angle) * distance
        setActivity(state, group ~= nil and "group_travel" or "surviving", hours)
    end
    state.virtualX = x
    state.virtualY = y
    state.virtualZ = z
    state.virtualAtHours = hours
end

function Simulation.captureLoaded(id, snapshot, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or type(id) ~= "string" or snapshot == nil then
        return false
    end
    local state = ensureState(id, snapshot, tonumber(hours) or nowHours())
    state.hunger = clamp(snapshot.hunger, 0, 1)
    state.thirst = clamp(snapshot.thirst, 0, 1)
    state.fatigue = clamp(snapshot.fatigue, 0, 1)
    state.endurance = clamp(snapshot.endurance, 0, 1)
    state.health = clamp(snapshot.health, 0, 100)
    state.bleedingParts = math.max(0, math.floor(tonumber(snapshot.bleedingParts) or 0))
    state.lastHours = tonumber(hours) or nowHours()
    state.status = "loaded"
    return persistence.setUnloadedSurvivalState(id, state)
end

-- Starts a durable off-screen trip to an existing base. The caller is
-- responsible for capturing/removing the active shell first; this function
-- records only the virtual route and never creates or relocates a world body.
function Simulation.beginBaseReturn(id, base, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    local area = type(base) == "table" and (base.territory or base.home) or nil
    if persistence == nil or type(id) ~= "string" or area == nil
        or tonumber(area.minX) == nil or tonumber(area.minY) == nil then
        return false, "base_destination_unavailable"
    end
    local now = tonumber(hours) or nowHours()
    local state = ensureState(id, nil, now)
    -- captureActiveSurvivor has just written the current engine position into
    -- the record. Prefer that fresh location over any old virtual route.
    local x, y, z = recordLocation(id)
    if x == nil or y == nil or z == nil then
        x, y, z = tonumber(state.virtualX), tonumber(state.virtualY), tonumber(state.virtualZ)
    end
    if x == nil or y == nil then
        return false, "return_origin_unavailable"
    end
    local width = math.max(1, math.floor(tonumber(area.width) or 1))
    local height = math.max(1, math.floor(tonumber(area.height) or 1))
    state.virtualX, state.virtualY, state.virtualZ = x, y, tonumber(z) or 0
    state.virtualAtHours = now
    state.baseReturn = {
        baseId = tostring(base.id or ""),
        targetX = math.floor(tonumber(area.minX)) + math.floor((width - 1) / 2),
        targetY = math.floor(tonumber(area.minY)) + math.floor((height - 1) / 2),
        targetZ = tonumber(area.z) or tonumber(z) or 0,
        startedAtHours = now,
    }
    setActivity(state, "returning_to_base", now)
    persistence.setUnloadedSurvivalState(id, state)
    return true, "base_return_started"
end

local function advanceOne(id, state, hours)
    local elapsed = math.max(0, hours - (tonumber(state.lastHours) or hours))
    if elapsed <= 0 then
        return state, nil
    end
    state.hunger = clamp(state.hunger + HUNGER_PER_HOUR * elapsed, 0, 1)
    state.thirst = clamp(state.thirst + THIRST_PER_HOUR * elapsed, 0, 1)
    state.fatigue = clamp(state.fatigue - FATIGUE_RECOVERY_PER_HOUR * elapsed, 0, 1)
    state.endurance = clamp(state.endurance + ENDURANCE_RECOVERY_PER_HOUR * elapsed, 0, 1)
    advanceWorldActivity(id, state, elapsed, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    local summary = persistence ~= nil and persistence.getInventorySummary(id) or ""
    local events = {}
    if state.thirst >= WATER_TRIGGER then
        local water = chooseSupply(summary, "water")
        if water ~= nil then
            local consumed, evidence = consumeStoredItem(id, water)
            if consumed then
                state.thirst = WATER_AFTER_DRINK
                events[#events + 1] = "drank=" .. evidence
                summary = persistence.getInventorySummary(id)
            end
        end
    end
    if state.hunger >= FOOD_TRIGGER then
        local food = chooseSupply(summary, "food")
        if food ~= nil then
            local consumed, evidence = consumeStoredItem(id, food)
            if consumed then
                state.hunger = FOOD_AFTER_MEAL
                events[#events + 1] = "ate=" .. evidence
            end
        end
    end
    if state.hunger >= 0.95 then
        state.health = clamp(state.health - STARVATION_DAMAGE_PER_HOUR * elapsed, 0, 100)
        events[#events + 1] = "starving"
    end
    if state.thirst >= 0.95 then
        state.health = clamp(state.health - DEHYDRATION_DAMAGE_PER_HOUR * elapsed, 0, 100)
        events[#events + 1] = "dehydrated"
    end
    state.lastHours = hours
    state.status = state.health <= 0 and "dead" or "hibernated"
    return state, #events > 0 and table.concat(events, ",") or nil
end

function Simulation.advanceHibernated(id, hours)
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil or not persistence.isSurvivorAlive(id) or persistence.getRecord(id) == nil then
        return false, "not_hibernated"
    end
    local targetHours = tonumber(hours) or nowHours()
    local state = ensureState(id, nil, targetHours)
    local events = {}
    while (tonumber(state.lastHours) or targetHours) < targetHours do
        local stepHours = math.min(
            targetHours,
            (tonumber(state.lastHours) or targetHours) + MAX_STEP_HOURS
        )
        local nextState, event = advanceOne(id, state, stepHours)
        state = nextState
        if event ~= nil then
            events[#events + 1] = event
        end
        if state.status == "dead" then
            break
        end
    end
    persistence.setUnloadedSurvivalState(id, state)
    if state.status == "dead" then
        persistence.markSurvivorDead(id, targetHours, "unloaded_survival")
        return true, "died"
    end
    return true, #events > 0 and table.concat(events, ",") or "advanced"
end

function Simulation.advanceAll(activeIds, hours)
    local active = {}
    for _, id in ipairs(activeIds or {}) do
        active[id] = true
    end
    local persistence = rawget(_G, "KnoxPersistence")
    if persistence == nil then
        return 0, 0
    end
    local advanced, notable = 0, 0
    for _, id in ipairs(persistence.getActivatableSurvivorIds()) do
        if not active[id] and persistence.getRecord(id) ~= nil then
            -- Away teams own travel, risk, and mission results, but they do
            -- not suspend physiology.  Their durable ledger still advances
            -- hunger, thirst, fatigue, endurance, inventory consumption, and
            -- health while the mission is off-screen.
            local ok, result = Simulation.advanceHibernated(id, hours)
            if ok then
                advanced = advanced + 1
                if result ~= "advanced" then
                    notable = notable + 1
                    print("[KnoxSurvivors][Unloaded] id=" .. id .. " event=" .. tostring(result))
                end
            end
        end
    end
    return advanced, notable
end

function Simulation.applyToLoaded(id, character)
    local persistence = rawget(_G, "KnoxPersistence")
    local state = persistence ~= nil and persistence.getUnloadedSurvivalState(id) or nil
    if state == nil or character == nil then
        return false, "no_stored_state"
    end
    local ok, evidence = pcall(function()
        local stats = character:getStats()
        stats:set(CharacterStat.HUNGER, clamp(state.hunger, 0, 1))
        stats:set(CharacterStat.THIRST, clamp(state.thirst, 0, 1))
        stats:set(CharacterStat.FATIGUE, clamp(state.fatigue, 0, 1))
        stats:set(CharacterStat.ENDURANCE, clamp(state.endurance, 0, 1))
        local bodyDamage = character:getBodyDamage()
        -- BodyDamage has no setHealth() in Build 42.20.3.  The aggregate
        -- body-health setter is the supported counterpart to getHealth(); the
        -- old call was caught by pcall, so a survivor still spawned but every
        -- spawn produced a Lua error and skipped its unloaded-health restore.
        bodyDamage:setOverallBodyHealth(clamp(state.health, 0, 100))
    end)
    if ok then
        state.status = "loaded"
        state.lastHours = nowHours()
        persistence.setUnloadedSurvivalState(id, state)
        return true, "applied"
    end
    return false, tostring(evidence)
end

return Simulation
